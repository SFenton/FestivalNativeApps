package com.festivalscoretracker.android.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.takeWhile
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
import java.util.concurrent.TimeUnit
import kotlin.math.floor

// region Messages

/**
 * One server message on the public `/api/ws` socket, reduced to what the app acts on (Apple
 * `PublicationLiveMessage`, #304).
 *
 * The web's `useAppWebSocket.ts` holds one anonymous socket to `/api/ws?publicationId=N` and
 * re-reads `/api/publication` when the server sends `{"type":"publication_changed"}`.
 * Everything else (the `shop_snapshot` sent on connect, Shop rotation, account sync messages an
 * anonymous socket never receives) is ignored; the app keeps reading the Item Shop over HTTPS.
 */
sealed interface PublicationLiveMessage {
    /**
     * The service published a new generation.
     *
     * @property publicationId The generation the server named, or null when it named none.
     */
    data class PublicationChanged(val publicationId: Int?) : PublicationLiveMessage

    /** Any other or malformed message. */
    data object Other : PublicationLiveMessage

    companion object {
        /**
         * Decode one text frame without trusting its shape.
         *
         * @param text Frame text (JSON).
         * @return [PublicationChanged] for a `publication_changed` object, else [Other].
         */
        fun parse(text: String): PublicationLiveMessage {
            val json = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return Other
            val type = (json["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (type != "publication_changed") return Other
            val id = (json["publicationId"] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
                ?.takeIf { it > 0 && it == floor(it) && it <= Int.MAX_VALUE }?.toInt()
            return PublicationChanged(id)
        }
    }
}

// endregion

// region Backoff

/**
 * Reconnect delays matching the web socket: 1 s, doubling, at most 30 s; reset once a
 * connection opens (web `INITIAL_RETRY_MS`/`MAX_RETRY_MS`, Apple `PublicationLiveBackoff`).
 */
class PublicationLiveBackoff {
    private var nextDelay = INITIAL_MS

    /**
     * The delay before the next attempt, doubling the one after it.
     *
     * @return Milliseconds to wait.
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

// endregion

// region Socket

/** What a live socket reports to [PublicationLiveUpdates.run]. */
sealed interface PublicationSocketEvent {
    /** The WebSocket handshake completed. */
    data object Opened : PublicationSocketEvent

    /**
     * One text (or binary, decoded as UTF-8) frame.
     *
     * @property text Frame text.
     */
    data class Message(val text: String) : PublicationSocketEvent
}

/** Opens the public live socket; injectable so the loop is testable without a network. */
fun interface PublicationLiveSocket {
    /**
     * Connect and report events until the server closes (the flow completes) or the connection
     * fails (the flow throws). Cancelling the collector closes the socket.
     *
     * @param url The `wss://…/api/ws?publicationId=N` URL.
     * @return The connection's events.
     */
    fun connect(url: String): Flow<PublicationSocketEvent>
}

/**
 * The production socket on the app's shared, cache-less OkHttp client.
 *
 * It sends no frames and adds no headers: never an `X-API-Key`, never a selected-profile header
 * and never `subscribe_sync` (which binds a socket to an account). The service registers an
 * anonymous connection in memory only (`.agents/platforms/service-safety.md`, `/api/ws`).
 *
 * @param client Shared OkHttp client.
 */
class OkHttpPublicationLiveSocket(client: OkHttpClient) : PublicationLiveSocket {
    // A quiet socket is healthy: the shared client's read timeout must not drop it.
    private val client = client.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).build()

    override fun connect(url: String): Flow<PublicationSocketEvent> = callbackFlow {
        val socket = client.newWebSocket(
            Request.Builder().url(url).build(),
            object : WebSocketListener() {
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
            },
        )
        awaitClose { socket.close(GOING_AWAY, null) }
    }

    private companion object {
        const val NORMAL_CLOSURE = 1000
        const val GOING_AWAY = 1001
    }
}

// endregion

// region Loop

/** The live publication loop, like the web's `useAppWebSocket` (Apple `PublicationLiveUpdates`). */
object PublicationLiveUpdates {
    /**
     * Keep a live socket open until the calling coroutine is cancelled.
     *
     * Each round re-reads the publication ([refresh], which also lets the app observe a new
     * generation and so refresh every open page), then connects with that generation. A
     * `publication_changed` message starts the next round at once, so the app refreshes without
     * any user action. A closed or failed connection waits [PublicationLiveBackoff] first (reset
     * after a connection that opened). A second `publication_changed` for a generation that did
     * not advance also waits, without resetting the backoff, so a misbehaving server cannot cause
     * a tight loop.
     *
     * @param refresh Re-reads `/api/publication` and returns the observed generation.
     * @param url Builds the socket URL for a generation.
     * @param connect Opens the socket.
     * @param sleep Waits between attempts.
     */
    suspend fun run(
        refresh: suspend () -> Int,
        url: (Int) -> String,
        connect: (String) -> Flow<PublicationSocketEvent>,
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
                connect(url(current)).takeWhile { event ->
                    when (event) {
                        PublicationSocketEvent.Opened -> opened = true
                        is PublicationSocketEvent.Message ->
                            if (PublicationLiveMessage.parse(event.text) is PublicationLiveMessage.PublicationChanged) changed = true
                    }
                    !changed
                }.collect()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // A failed read or connection waits the backoff below.
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
 * The app's one live publication connection: [PublicationLiveUpdates] over [api] and [socket].
 * Run it only while the app is in the foreground (the shell does, under `STARTED`).
 *
 * @param api Keyless API client (its forced publication read adopts a new generation).
 * @param socket Socket factory.
 */
class PublicationLiveConnection(private val api: FestivalApi, private val socket: PublicationLiveSocket) {
    /** Keep the socket open until cancelled. */
    suspend fun run() {
        PublicationLiveUpdates.run(
            refresh = { api.publication(force = true).publicationId },
            url = api::liveUpdatesUrl,
            connect = socket::connect,
        )
    }

    companion object {
        /**
         * Whether the live socket runs for this process: on for the public service, off for a
         * fixture transport (tests never reach the network) and, unless explicitly asked for,
         * for a loopback fixture origin.
         *
         * @param override `FST_LIVE_PUBLICATION_UPDATES` (debug launches): true or false forces it.
         * @param fixtureTransport A transport override is installed (instrumented tests).
         * @param loopback The origin is a loopback fixture server.
         * @return Whether to connect.
         */
        fun enabled(override: Boolean?, fixtureTransport: Boolean, loopback: Boolean): Boolean = when {
            fixtureTransport -> false
            override != null -> override
            else -> !loopback
        }
    }
}

// endregion
