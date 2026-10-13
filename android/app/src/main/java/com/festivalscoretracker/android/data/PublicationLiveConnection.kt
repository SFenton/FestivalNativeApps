package com.festivalscoretracker.android.data

import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

// region Receive-only publication connection

/** An anonymous socket with no application-message send API. */
interface PublicationConnection {
    /** Wait for the upgrade; throws when the connection fails. */
    suspend fun awaitOpen()

    /** Read the next text message, or null when the server closes normally. */
    suspend fun receive(): String?

    /** Cancel the handshake or connection and release its resources. */
    fun cancel()
}

/**
 * Creates only the allowlisted anonymous `/api/ws?publicationId=N` connection.
 * No headers, account identifiers, subscriptions or application messages are sent.
 *
 * @property client The app's cache-less HTTP client.
 */
class PublicationLiveConnection(private val client: OkHttpClient) {
    /**
     * Open a receive-only socket at the validated API origin.
     *
     * @param origin FestivalApi's validated origin.
     * @param publicationId Latest observed generation.
     * @return Cancellable connection.
     */
    fun open(origin: String, publicationId: Int): PublicationConnection {
        val opened = CompletableDeferred<Unit>()
        val messages = Channel<String>(Channel.BUFFERED)
        val socket = client.newWebSocket(request(origin, publicationId), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                opened.complete(Unit)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (!messages.trySend(text).isSuccess) {
                    messages.close(IOException("Publication message queue exceeded"))
                    webSocket.cancel()
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, null)
                messages.close()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                opened.completeExceptionally(t)
                messages.close(t)
                response?.close()
            }
        })
        return object : PublicationConnection {
            override suspend fun awaitOpen() = opened.await()
            override suspend fun receive(): String? = messages.receiveCatching().getOrThrow()
            override fun cancel() {
                socket.cancel()
                opened.cancel()
                messages.cancel()
            }
        }
    }

    companion object {
        /**
         * Build the upgrade request, refusing credentials and fixture origins.
         *
         * @param origin Public HTTPS API origin.
         * @param publicationId Positive observed publication.
         * @return Anonymous request with only the publication query.
         */
        internal fun request(origin: String, publicationId: Int): Request {
            val base = origin.toHttpUrl()
            require(base.scheme == "https" && base.host !in FestivalApi.LOOPBACK_HOSTS)
            require(base.username.isEmpty() && base.password.isEmpty())
            require(publicationId > 0)
            val url = base.newBuilder().encodedPath("/api/ws").query(null).fragment(null)
                .addQueryParameter("publicationId", publicationId.toString()).build()
            return Request.Builder().url(url).build()
        }
    }
}

// endregion
