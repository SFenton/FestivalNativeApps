package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.data.PublicationConnection
import com.festivalscoretracker.android.data.PublicationLiveConnection
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Receive-only protocol, authoritative reads, reconnect pacing and foreground cancellation. */
@OptIn(ExperimentalCoroutinesApi::class)
class PublicationLiveUpdatesTest {
    private class Socket : PublicationConnection {
        val messages = Channel<String>(Channel.UNLIMITED)
        var cancelled = false
        override suspend fun awaitOpen() = Unit
        override suspend fun receive(): String? = messages.receiveCatching().getOrThrow()
        override fun cancel() { cancelled = true; messages.cancel() }
    }

    @Test
    fun messagesAreHintsAndOtherReadsRePinTheOneConnection() = runTest {
        val publications = MutableStateFlow<Int?>(null)
        var server = 7
        var reads = 0
        val sockets = mutableListOf<Pair<Int, Socket>>()
        val errors = mutableListOf<Throwable>()
        val updates = PublicationLiveUpdates(
            publications,
            { reads++; server.also { publications.value = it } },
            { id -> Socket().also { sockets += id to it } },
            errors::add,
        )
        val job = backgroundScope.launch { updates.run() }
        runCurrent()
        assertEquals(2, reads)
        assertEquals(listOf(7), sockets.map { it.first })
        sockets.last().second.messages.send("""{"type":"shop_snapshot"}""")
        sockets.last().second.messages.send("""{"type":"sync_complete","accountId":"ignored"}""")
        sockets.last().second.messages.send("{broken")
        runCurrent()
        assertEquals(2, reads)
        assertEquals(1, errors.size)

        server = 8
        sockets.last().second.messages.send("""{"type":"publication_changed","publicationId":999999}""")
        runCurrent()
        assertEquals(8, publications.value)
        assertEquals(listOf(7, 8), sockets.map { it.first })
        assertTrue(sockets.first().second.cancelled)

        server = 9
        publications.value = 9
        runCurrent()
        assertEquals(listOf(7, 8, 9), sockets.map { it.first })
        assertTrue(sockets[1].second.cancelled)
        job.cancel()
        runCurrent()
        assertTrue(sockets.last().second.cancelled)
        advanceTimeBy(60_000)
        assertEquals(3, sockets.size)
    }

    @Test
    fun failuresBackOffFromOneSecondToThirtySeconds() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        val attempts = mutableListOf<Long>()
        val updates = PublicationLiveUpdates(
            publications, { 7 },
            { attempts += testScheduler.currentTime; throw IOException("synthetic connection failure") },
            {},
        )
        backgroundScope.launch { updates.run() }
        runCurrent()
        assertEquals(listOf(0L), attempts)
        for (gap in listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L)) {
            advanceTimeBy(gap - 1)
            assertEquals(attempts.last(), testScheduler.currentTime - gap + 1)
            advanceTimeBy(1)
            runCurrent()
            assertEquals(testScheduler.currentTime, attempts.last())
        }
    }

    @Test
    fun backgroundCancelsAnUpgradeAndResumeReadsMissedPublications() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        val opened = CompletableDeferred<Unit>()
        var cancelled = false
        var server = 7
        val ids = mutableListOf<Int>()
        var first = true
        val updates = PublicationLiveUpdates(
            publications, { server.also { publications.value = it } },
            { id ->
                ids += id
                if (first) {
                    first = false
                    object : PublicationConnection {
                        override suspend fun awaitOpen() = opened.await()
                        override suspend fun receive(): String? = error("not open")
                        override fun cancel() { cancelled = true }
                    }
                } else Socket()
            },
            { throw AssertionError(it) },
        )
        val job = backgroundScope.launch { updates.run() }
        runCurrent()
        job.cancel()
        runCurrent()
        assertTrue(cancelled)
        server = 8
        backgroundScope.launch { updates.run() }
        runCurrent()
        assertEquals(listOf(7, 8), ids)
        assertEquals(8, publications.value)
    }

    @Test
    fun overlappingForegroundOwnersCannotOpenTwoSockets() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        val sockets = mutableListOf<Socket>()
        val updates = PublicationLiveUpdates(publications, { 7 }, { Socket().also(sockets::add) }, {})
        val first = backgroundScope.launch { updates.run() }
        backgroundScope.launch { updates.run() }
        runCurrent()
        assertEquals(1, sockets.size)
        first.cancel()
        runCurrent()
        assertEquals(2, sockets.size)
        assertTrue(sockets.first().cancelled)
        assertFalse(sockets.last().cancelled)
    }

    @Test
    fun upgradeContainsOnlyThePublicationQueryAndNoHeaders() {
        val request = PublicationLiveConnection.request("https://example.invalid/old?token=discard#fragment", 8)
        assertEquals("https://example.invalid/api/ws?publicationId=8", request.url.toString())
        assertEquals(0, request.headers.size)
        for (origin in listOf("http://example.invalid", "https://localhost", "http://10.0.2.2", "https://user:secret@example.invalid")) {
            assertTrue(runCatching { PublicationLiveConnection.request(origin, 8) }.isFailure)
        }
        assertTrue(runCatching { PublicationLiveConnection.request("https://example.invalid", 0) }.isFailure)
    }
}
