package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.data.PublicationConnection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// region Live publication updates

/**
 * One foreground receive loop, matching web useAppWebSocket's 1–30 second backoff.
 * Messages are hints only: the public publication read remains authoritative.
 *
 * @property publications The API's current generation.
 * @property readPublication Forced, keyless publication read.
 * @property connect Anonymous receive-only connection factory.
 * @property reportFailure Reports recoverable connection/read/protocol errors without payloads.
 */
class PublicationLiveUpdates(
    private val publications: StateFlow<Int?>,
    private val readPublication: suspend () -> Int,
    private val connect: (Int) -> PublicationConnection,
    private val reportFailure: (Throwable) -> Unit,
) {
    private val mutex = Mutex()

    /** Run until the foreground lifecycle cancels this job; every connection is released. */
    suspend fun run() = mutex.withLock { receiveLoop() }

    /** Receive publication hints and retry until the foreground owner cancels. */
    private suspend fun receiveLoop() {
        var backoff = RECONNECT_BASE_MS
        while (currentCoroutineContext().isActive) {
            var connection: PublicationConnection? = null
            try {
                val id = readPublication()
                connection = connect(id)
                connection.awaitOpen()
                backoff = RECONNECT_BASE_MS
                if (readPublication() != id) continue
                coroutineScope {
                    val changed = async { publications.first { it != null && it != id } }
                    try {
                        while (isActive) {
                            val message = async { connection.receive() }
                            val text = try {
                                select<String?> {
                                    changed.onAwait { null }
                                    message.onAwait { it }
                                }
                            } finally {
                                message.cancel()
                            } ?: break
                            val payload = try {
                                Json.parseToJsonElement(text) as? JsonObject
                            } catch (error: SerializationException) {
                                reportFailure(error)
                                null
                            }
                            if (payload?.get("type")?.let { it is kotlinx.serialization.json.JsonPrimitive && it.jsonPrimitive.content == "publication_changed" } == true) {
                                readPublication()
                                break
                            }
                        }
                    } finally {
                        changed.cancel()
                    }
                }
                if (publications.value != id) continue
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                reportFailure(error)
            } finally {
                connection?.cancel()
            }
            delay(backoff)
            backoff = (backoff * 2).coerceAtMost(RECONNECT_MAX_MS)
        }
    }

    companion object {
        /** Web useAppWebSocket reconnect base. */
        const val RECONNECT_BASE_MS = 1_000L

        /** Web useAppWebSocket reconnect ceiling. */
        const val RECONNECT_MAX_MS = 30_000L
    }
}

// endregion
