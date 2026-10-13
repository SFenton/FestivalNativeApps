package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.testing.FakeTransport
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Issue #616: the anonymous, receive-only `/api/ws` live socket (web `useAppWebSocket`). */
@OptIn(ExperimentalCoroutinesApi::class)
class PublicationLiveUpdatesTest {
    // region Messages and backoff

    @Test
    fun parsesOnlyPublicationChangedWithAPositiveIntegralId() {
        assertEquals(PublicationLiveMessage.PublicationChanged(8), PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":8}"""))
        assertEquals(PublicationLiveMessage.PublicationChanged(9), PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":9.0}"""))
        assertEquals(PublicationLiveMessage.PublicationChanged(null), PublicationLiveMessage.parse("""{"type":"publication_changed"}"""))
        assertEquals(PublicationLiveMessage.PublicationChanged(null), PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":"8"}"""))
        assertEquals(PublicationLiveMessage.PublicationChanged(null), PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":0}"""))
        assertEquals(PublicationLiveMessage.PublicationChanged(null), PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":8.5}"""))
        assertEquals(PublicationLiveMessage.Other, PublicationLiveMessage.parse("""{"type":"shop_snapshot","offers":[]}"""))
        assertEquals(PublicationLiveMessage.Other, PublicationLiveMessage.parse("""{"type":7}"""))
        assertEquals(PublicationLiveMessage.Other, PublicationLiveMessage.parse("""["publication_changed"]"""))
        assertEquals(PublicationLiveMessage.Other, PublicationLiveMessage.parse("not json"))
    }

    @Test
    fun backoffDoublesFromOneSecondToThirtyAndResets() {
        val backoff = PublicationLiveBackoff()
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L), List(7) { backoff.next() })
        backoff.reset()
        assertEquals(1_000L, backoff.next())
    }

    // endregion

    // region Loop

    /** Scripted socket: each connection replays the next script and records its URL. */
    private class ScriptedSocket(vararg scripts: Flow<PublicationSocketEvent>) : PublicationLiveSocket {
        private val remaining = ArrayDeque(scripts.toList())
        val urls = mutableListOf<String>()

        override fun connect(url: String): Flow<PublicationSocketEvent> {
            urls += url
            return remaining.removeFirstOrNull() ?: flow { throw IOException("offline") }
        }
    }

    private fun opened(vararg messages: String): Flow<PublicationSocketEvent> =
        flowOf(PublicationSocketEvent.Opened, *messages.map { PublicationSocketEvent.Message(it) }.toTypedArray())

    private val changed = """{"type":"publication_changed","publicationId":8}"""

    @Test
    fun publicationChangedReReadsAtOnceAndFailuresBackOff() = runTest {
        val generations = ArrayDeque(listOf(7, 8, 8, 8))
        val sleeps = mutableListOf<Long>()
        var refreshes = 0
        val socket = ScriptedSocket(
            // Round 1: snapshot then a change: the next round starts with no wait.
            opened("""{"type":"shop_snapshot"}""", changed),
            // Round 2: the server closes after opening: wait 1 s (backoff reset by the open).
            opened(),
        )
        // Rounds 3+: the connection fails: 2 s, then 4 s.
        val job = launch {
            PublicationLiveUpdates.run(
                refresh = { refreshes++; generations.removeFirstOrNull() ?: 8 },
                url = { "wss://fixture.test/api/ws?publicationId=$it" },
                socket = socket,
                sleep = { sleeps += it; if (sleeps.size == 3) throw CancellationException("done") },
            )
        }
        job.join()
        assertEquals(listOf(1_000L, 2_000L, 4_000L), sleeps)
        assertEquals(4, refreshes)
        assertEquals(
            listOf("wss://fixture.test/api/ws?publicationId=7", "wss://fixture.test/api/ws?publicationId=8", "wss://fixture.test/api/ws?publicationId=8", "wss://fixture.test/api/ws?publicationId=8"),
            socket.urls,
        )
    }

    @Test
    fun repeatedChangeForTheSameGenerationWaitsInsteadOfLooping() = runTest {
        val sleeps = mutableListOf<Long>()
        val socket = ScriptedSocket(opened(changed), opened(changed), opened(changed))
        val job = launch {
            PublicationLiveUpdates.run(
                refresh = { 8 },
                url = { "wss://fixture.test/api/ws?publicationId=$it" },
                socket = socket,
                sleep = { sleeps += it; if (sleeps.size == 2) throw CancellationException("done") },
            )
        }
        job.join()
        // Round 1 continues at once; rounds 2 and 3 repeat 8, so they wait and keep backing off.
        assertEquals(listOf(1_000L, 2_000L), sleeps)
        assertEquals(3, socket.urls.size)
    }

    @Test
    fun failedPublicationReadBacksOffWithoutConnecting() = runTest {
        val sleeps = mutableListOf<Long>()
        val socket = ScriptedSocket()
        val job = launch {
            PublicationLiveUpdates.run(
                refresh = { throw FestivalApiException.HttpStatus(503) },
                url = { "wss://fixture.test/api/ws?publicationId=$it" },
                socket = socket,
                sleep = { sleeps += it; if (sleeps.size == 3) throw CancellationException("done") },
            )
        }
        job.join()
        assertEquals(listOf(1_000L, 2_000L, 4_000L), sleeps)
        assertTrue(socket.urls.isEmpty())
    }

    @Test
    fun aClosedSocketWithoutMessagesIsNotAChange() = runTest {
        val sleeps = mutableListOf<Long>()
        val socket = ScriptedSocket(emptyFlow())
        val job = launch {
            PublicationLiveUpdates.run({ 7 }, { "wss://fixture.test/api/ws?publicationId=$it" }, socket, sleep = { sleeps += it; throw CancellationException("done") })
        }
        job.join()
        assertEquals(listOf(1_000L), sleeps)
    }

    // endregion

    // region URL

    @Test
    fun liveUrlIsWssOnThePublicOriginAndWsOnlyForLoopback() {
        val public = FestivalApi("https://api.example.test/base/", FakeTransport.standard())
        assertFalse(public.usesLoopbackOrigin)
        assertEquals("wss://api.example.test/api/ws?publicationId=7", public.liveUpdatesUrl(7))
        val loopback = FestivalApi("http://127.0.0.1:8765", FakeTransport.standard())
        assertTrue(loopback.usesLoopbackOrigin)
        assertEquals("ws://127.0.0.1:8765/api/ws?publicationId=12", loopback.liveUpdatesUrl(12))
        for (id in listOf(0, -1)) {
            try {
                public.liveUpdatesUrl(id)
                fail("expected InvalidResource for $id")
            } catch (_: FestivalApiException.InvalidResource) {
            }
        }
    }

    // endregion

    // region OkHttp socket

    @Test
    fun okHttpSocketSendsNoFramesNoKeyAndNoProfileHeader() = runBlocking {
        val server = MockWebServer()
        val serverOpened = java.util.concurrent.CountDownLatch(1)
        val serverClosed = java.util.concurrent.CountDownLatch(1)
        val received = mutableListOf<String>()
        var closeCode: Int? = null
        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send("""{"type":"shop_snapshot"}""")
                    webSocket.send("""{"type":"publication_changed","publicationId":8}""")
                    serverOpened.countDown()
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    synchronized(received) { received += text }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    synchronized(received) { closeCode = code }
                    webSocket.close(1000, null)
                    serverClosed.countDown()
                }
            }),
        )
        server.start()
        try {
            val client = OkHttpClient.Builder().build()
            val url = server.url("/api/ws?publicationId=7").toString().replaceFirst("http", "ws")
            val socket = OkHttpPublicationLiveSocket(client)
            val change = withTimeout(10_000) {
                socket.connect(url).first { it is PublicationSocketEvent.Message && PublicationLiveMessage.parse(it.text) is PublicationLiveMessage.PublicationChanged }
            }
            assertEquals(PublicationLiveMessage.PublicationChanged(8), PublicationLiveMessage.parse((change as PublicationSocketEvent.Message).text))
            val request = server.takeRequest(5, TimeUnit.SECONDS)!!
            assertEquals("/api/ws?publicationId=7", request.path)
            assertNull(request.getHeader("X-API-Key"))
            assertTrue(request.headers.names().none { it.contains("profile", ignoreCase = true) || it.contains("account", ignoreCase = true) })
            assertTrue(serverOpened.await(5, TimeUnit.SECONDS))
            // Collecting stopped at the change: the client closes with 1001 and sent no frame.
            assertTrue(serverClosed.await(5, TimeUnit.SECONDS))
            synchronized(received) {
                assertTrue(received.isEmpty())
                assertEquals(1001, closeCode)
            }
            client.dispatcher.executorService.shutdown()
        } finally {
            server.shutdown()
        }
    }

    // endregion
}
