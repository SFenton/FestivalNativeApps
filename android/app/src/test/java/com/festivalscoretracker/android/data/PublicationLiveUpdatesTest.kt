package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.ByteString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The anonymous `/api/ws` live publication socket (#616; web `useAppWebSocket`, Apple #304). */
@OptIn(ExperimentalCoroutinesApi::class)
class PublicationLiveUpdatesTest {
    // region Messages

    @Test
    fun parseAcceptsOnlyPublicationChangedObjects() {
        assertEquals(
            PublicationLiveMessage.PublicationChanged(8),
            PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":8}"""),
        )
        assertEquals(PublicationLiveMessage.PublicationChanged(null), PublicationLiveMessage.parse("""{"type":"publication_changed"}"""))
        listOf("0", "-3", "1.5", "\"8\"", "null", "99999999999").forEach { id ->
            assertEquals(
                id,
                PublicationLiveMessage.PublicationChanged(null),
                PublicationLiveMessage.parse("""{"type":"publication_changed","publicationId":$id}"""),
            )
        }
        listOf(
            """{"type":"shop_snapshot","publicationId":8}""",
            """{"type":["publication_changed"]}""",
            """["publication_changed"]""",
            "publication_changed",
            "",
            "{",
        ).forEach { assertEquals(it, PublicationLiveMessage.Other, PublicationLiveMessage.parse(it)) }
    }

    @Test
    fun backoffDoublesFromOneToThirtySecondsAndResets() {
        val backoff = PublicationLiveBackoff()
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L), List(7) { backoff.next() })
        backoff.reset()
        assertEquals(1_000L, backoff.next())
    }

    // endregion

    // region URL and enablement

    @Test
    fun liveUrlIsWssForHttpsAndWsOnlyForLoopback() {
        assertEquals(
            "wss://festivalscoretracker.com/api/ws?publicationId=8",
            FestivalApi(FestivalApi.PUBLIC_ORIGIN, FakeTransport()).liveUpdatesUrl(8),
        )
        val loopback = FestivalApi("http://127.0.0.1:8080", FakeTransport())
        assertTrue(loopback.usesLoopbackOrigin)
        assertEquals("ws://127.0.0.1:8080/api/ws?publicationId=3", loopback.liveUpdatesUrl(3))
        assertFalse(FestivalApi("https://fixture.test", FakeTransport()).usesLoopbackOrigin)
        listOf(0, -1).forEach { id ->
            try {
                loopback.liveUpdatesUrl(id)
                fail("expected InvalidResource for $id")
            } catch (_: FestivalApiException.InvalidResource) {
            }
        }
    }

    @Test
    fun liveSocketRunsForThePublicServiceOnly() {
        assertTrue(PublicationLiveConnection.enabled(override = null, fixtureTransport = false, loopback = false))
        assertFalse(PublicationLiveConnection.enabled(override = null, fixtureTransport = false, loopback = true))
        assertTrue(PublicationLiveConnection.enabled(override = true, fixtureTransport = false, loopback = true))
        assertFalse(PublicationLiveConnection.enabled(override = false, fixtureTransport = false, loopback = false))
        // Instrumented tests' fixture transports never reach a network socket.
        assertFalse(PublicationLiveConnection.enabled(override = true, fixtureTransport = true, loopback = false))
        assertEquals(true, DebugLaunch.parse(mapOf("FST_LIVE_PUBLICATION_UPDATES" to "1")).liveUpdates)
        assertEquals(false, DebugLaunch.parse(mapOf("FST_LIVE_PUBLICATION_UPDATES" to "0")).liveUpdates)
        assertNull(DebugLaunch.parse(mapOf("FST_LIVE_PUBLICATION_UPDATES" to "yes")).liveUpdates)
        assertNull(DebugLaunch.NONE.liveUpdates)
    }

    // endregion

    // region Loop

    private class Stop : CancellationException("stop")

    @Test
    fun loopRereadsOnChangeAndBacksOffOtherwise() = runTest {
        val log = mutableListOf<String>()
        val refreshes = ArrayDeque(listOf<() -> Int>({ 7 }, { 8 }, { throw IOException("offline") }, { 8 }, { 8 }))
        val rounds = ArrayDeque<List<PublicationSocketEvent>>(
            listOf(
                // A shop snapshot is ignored; publication_changed re-reads at once.
                listOf(Opened, Message("""{"type":"shop_snapshot"}"""), Message(CHANGED_8), Message(CHANGED_8)),
                // The server closes an opened socket: reset, then wait 1 s.
                listOf(Opened),
                // (refresh failed: wait 2 s, no connect)
                // A change re-reads at once even without an open event.
                listOf(Message(CHANGED_8)),
                // The same generation changes again: wait (1 s after the reset) instead of looping.
                listOf(Opened, Message(CHANGED_8)),
            ),
        )
        try {
            PublicationLiveUpdates.run(
                refresh = {
                    log += "refresh"
                    refreshes.removeFirstOrNull()?.invoke() ?: throw Stop()
                },
                url = { "wss://fixture.test/api/ws?publicationId=$it" },
                connect = { url ->
                    log += "connect $url"
                    val events = rounds.removeFirst()
                    flow { events.forEach { emit(it) } }
                },
                sleep = { log += "sleep $it" },
            )
            fail("expected the loop to stop")
        } catch (_: Stop) {
        }
        assertEquals(
            listOf(
                "refresh", "connect wss://fixture.test/api/ws?publicationId=7",
                "refresh", "connect wss://fixture.test/api/ws?publicationId=8", "sleep 1000",
                "refresh", "sleep 2000",
                "refresh", "connect wss://fixture.test/api/ws?publicationId=8",
                "refresh", "connect wss://fixture.test/api/ws?publicationId=8", "sleep 1000",
                "refresh",
            ),
            log,
        )
    }

    @Test
    fun failedConnectionsBackOffUpToThirtySeconds() = runTest {
        val sleeps = mutableListOf<Long>()
        var connects = 0
        try {
            PublicationLiveUpdates.run(
                refresh = { 7 },
                url = { "wss://fixture.test/api/ws?publicationId=$it" },
                connect = {
                    connects++
                    if (connects > 7) throw Stop()
                    flow<PublicationSocketEvent> { throw IOException("refused") }
                },
                sleep = { sleeps += it },
            )
        } catch (_: Stop) {
        }
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L), sleeps)
    }

    // endregion

    // region OkHttp socket

    @Test
    fun okHttpSocketIsAnonymousAndReceiveOnly() = runBlocking {
        val server = MockWebServer().apply { start(java.net.InetAddress.getByName("127.0.0.1"), 0) }
        val received = Collections.synchronizedList(mutableListOf<String>())
        val closed = CountDownLatch(1)
        try {
            server.enqueue(
                MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        webSocket.send("""{"type":"shop_snapshot","offers":[]}""")
                        webSocket.send(CHANGED_8)
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        received += text
                    }

                    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                        received += bytes.hex()
                    }

                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                        webSocket.close(code, null)
                        closed.countDown()
                    }

                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                        closed.countDown()
                    }
                }),
            )
            val api = FestivalApi("http://127.0.0.1:${server.port}", OkHttpTransport())
            val socket = OkHttpPublicationLiveSocket(OkHttpTransport.defaultClient())
            val events = withTimeout(10_000) {
                socket.connect(api.liveUpdatesUrl(8))
                    .takeWhile { it != Message(CHANGED_8) }
                    .toList()
            }
            assertEquals(listOf(Opened, Message("""{"type":"shop_snapshot","offers":[]}""")), events)
            // Cancelling the collector closes the socket; the client never sent a frame.
            assertTrue(closed.await(10, TimeUnit.SECONDS))
            assertTrue(received.isEmpty())
            val request = server.takeRequest(5, TimeUnit.SECONDS)!!
            assertEquals("/api/ws?publicationId=8", request.path)
            assertNull(request.getHeader("X-API-Key"))
            val custom = request.headers.names().filter { it.startsWith("X-", ignoreCase = true) }
            assertTrue(custom.toString(), custom.isEmpty())
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun okHttpSocketReportsAFailedHandshake() = runBlocking {
        val server = MockWebServer().apply { start(java.net.InetAddress.getByName("127.0.0.1"), 0) }
        try {
            server.enqueue(MockResponse().setResponseCode(404))
            val socket = OkHttpPublicationLiveSocket(OkHttpClient())
            try {
                withTimeout(10_000) { socket.connect("ws://127.0.0.1:${server.port}/api/ws?publicationId=8").first() }
                fail("expected a failed handshake")
            } catch (_: IOException) {
            }
        } finally {
            server.shutdown()
        }
    }

    // endregion

    private companion object {
        const val CHANGED_8 = """{"type":"publication_changed","publicationId":8}"""
        val Opened = PublicationSocketEvent.Opened

        @Suppress("TestFunctionName")
        fun Message(text: String) = PublicationSocketEvent.Message(text)
    }
}
