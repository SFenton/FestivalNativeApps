package com.festivalscoretracker.android.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.onEach
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

// region Live publication updates (issue #616)

/**
 * One server message on the public `/api/ws` socket, reduced to what the app acts on
 * (Apple `PublicationLiveMessage`, #304).
 *
 * The web's `useAppWebSocket.ts` holds one anonymous socket to `/api/ws?publicationId=N`
 * and re-reads `/api/publication` when the server sends `{"type":"publication_changed"}`.
 * Everything else (the `shop_snapshot` sent on connect, Shop rotation, account sync
 * messages an anonymous socket never receives) is ignored: the app keeps reading the Item
 * Shop over HTTPS.
 */
sealed interface PublicationLiveMessage {
    /**
     * The service published a new generation.
     *
     * @property publicationId Positive generation when the server sent one.
     */
    data class PublicationChanged(val publicationId: Int?) : PublicationLiveMessage

    /** Any other or malformed message. */
    data object Other : PublicationLiveMessage

    companion object {
        /**
         * Decode one text frame without trusting its shape.
         *
         * @param text Frame text (UTF-8 JSON).
         * @return [PublicationChanged] for a `publication_changed` object, else [Other].
         */
        fun parse(text: String): PublicationLiveMessage {
            val root = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return Other
            val type = root["type"] as? JsonPrimitive
            if (type == null || !type.isString || type.content != "publication_changed") return Other
            val raw = (root["publicationId"] as? JsonPrimitive)?.takeUnless { it.isString }
            val id = raw?.content?.toIntOrNull() ?: raw?.doubleOrNull?.takeIf { it % 1.0 == 0.0 && it <= Int.MAX_VALUE }?.toInt()
            return PublicationChanged(id?.takeIf { it > 0 })
        }
    }
}

/**
 * Reconnect delays matching the web socket: 1 s, doubling, at most 30 s; reset once a
 * connection opens (web `useAppWebSocket` `RECONNECT_BASE_MS`/`RECONNECT_MAX_MS`).
 */
class PublicationLiveBackoff {
    private var nextDelay = INITIAL_MS

    /**
     * The delay before the next attempt, doubling the one after it.
     *
     * @return Delay in milliseconds.
     */
    fun next(): Long {
        val delay = nextDelay
        nextDelay = (nextDelay * 2).coerceAtMost(MAXIMUM_MS)
        return delay
    }

    /** A connection opened: the next failure retries after the initial delay again. */
    fun reset() {
        nextDelay = INITIAL_MS
    }

    companion object {
        /** First reconnect delay. */
        const val INITIAL_MS = 1_000L

        /** Longest reconnect delay. */
        const val MAXIMUM_MS = 30_000L
    }
}

/** What a live socket reports to [PublicationLiveUpdates.run]. */
sealed interface PublicationSocketEvent {
    /** The WebSocket handshake completed. */
    data object Opened : PublicationSocketEvent

    /**
     * One text (or UTF-8 binary) frame.
     *
     * @property text Frame text.
     */
    data class Message(val text: String) : PublicationSocketEvent
}

/** Opens the public live socket; injectable so the loop is testable without a network. */
fun interface PublicationLiveSocket {
    /**
     * Connect and report events until the server closes (flow completes) or the connection
     * fails (flow throws). Cancelling the collector closes the socket.
     *
     * @param url The `wss://…/api/ws?publicationId=N` URL.
     * @return The connection's events.
     */
    fun connect(url: String): Flow<PublicationSocketEvent>
}

/**
 * The production socket on the shared cache-less OkHttp client (no cookie jar).
 *
 * It sends no frames and no custom headers: never an `X-API-Key`, never a selected-profile
 * header and never `subscribe_sync` (which binds a socket to an account). The service
 * registers an anonymous connection in memory only (`.agents/platforms/service-safety.md`,
 * `/api/ws`). OkHttp drops the read timeout once the socket is upgraded, and answers server
 * pings itself; no client pings are scheduled.
 *
 * @param client Shared OkHttp client.
 */
class OkHttpPublicationLiveSocket(private val client: OkHttpClient) : PublicationLiveSocket {
    override fun connect(url: String): Flow<PublicationSocketEvent> = callbackFlow {
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                trySend(PublicationSocketEvent.Opened)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                trySend(PublicationSocketEvent.Message(text))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                trySend(PublicationSocketEvent.Message(bytes.utf8()))
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(NORMAL_CLOSURE, null)
                channel.close()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                channel.close()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                channel.close(t)
            }
        }
        val socket = client.newWebSocket(Request.Builder().url(url).build(), listener)
        awaitClose { if (!socket.close(GOING_AWAY, null)) socket.cancel() }
    }

    private companion object {
        /** RFC 6455 normal closure. */
        const val NORMAL_CLOSURE = 1000

        /** RFC 6455 "going away": the app left the foreground or the round ended. */
        const val GOING_AWAY = 1001
    }
}

/** The live publication loop, like the web's `useAppWebSocket` (Apple `PublicationLiveUpdates`). */
object PublicationLiveUpdates {
    /**
     * Keep a live socket open until the calling coroutine is cancelled.
     *
     * Each round re-reads the publication ([refresh], which also lets the app observe a new
     * generation through [FestivalApi.publicationChanges]), then connects with that
     * generation. A `publication_changed` message starts the next round at once, so pages
     * refresh without any user action. A closed or failed connection waits
     * [PublicationLiveBackoff] first (reset after a connection that opened). A second
     * `publication_changed` for a generation that did not advance also waits, without
     * resetting the backoff, so a misbehaving server cannot cause a tight loop.
     *
     * @param refresh Re-reads `/api/publication` and returns the observed generation.
     * @param url Builds the socket URL for a generation.
     * @param socket Opens the socket.
     * @param sleep Waits between attempts.
     */
    suspend fun run(
        refresh: suspend () -> Int,
        url: (Int) -> String,
        socket: PublicationLiveSocket,
        sleep: suspend (Long) -> Unit = { delay(it) },
    ) {
        val backoff = PublicationLiveBackoff()
        var lastChanged: Int? = null
        while (true) {
            currentCoroutineContext().ensureActive()
            var publicationId: Int? = null
            var opened = false
            var changed = false
            try {
                val current = refresh()
                publicationId = current
                currentCoroutineContext().ensureActive()
                changed = socket.connect(url(current))
                    .onEach { if (it is PublicationSocketEvent.Opened) opened = true }
                    .firstOrNull { it is PublicationSocketEvent.Message && PublicationLiveMessage.parse(it.text) is PublicationLiveMessage.PublicationChanged } != null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Failed refresh or connection: retry after the backoff.
            }
            currentCoroutineContext().ensureActive()
            val repeated = changed && publicationId != null && lastChanged == publicationId
            lastChanged = if (changed) publicationId else null
            if (changed && !repeated) {
                backoff.reset()
                continue
            }
            if (opened && !repeated) backoff.reset()
            sleep(backoff.next())
        }
    }
}

/**
 * The app's live publication connection (Apple `PublicationLiveConnection`): runs
 * [PublicationLiveUpdates] against [api] while the app is in the foreground.
 *
 * @param api Keyless API client (public HTTPS origin).
 * @param socket Socket factory.
 */
class PublicationLiveConnection(private val api: FestivalApi, private val socket: PublicationLiveSocket) {
    /** Keep the socket open until cancelled (the caller ties this to the foreground lifecycle). */
    suspend fun run() {
        PublicationLiveUpdates.run(
            refresh = { api.publication(force = true).publicationId },
            url = api::liveUpdatesUrl,
            socket = socket,
        )
    }
}

// endregion
