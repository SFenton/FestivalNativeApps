package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.testing.Fixtures
import java.io.IOException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertSame
import org.junit.Test

/** Catalogue recovery without restarting the shared backdrop (issue #623). */
@OptIn(ExperimentalCoroutinesApi::class)
class BackgroundRecoveryTest {
    @Test
    fun failedFirstCatalogueReadRecoversWithoutRestarting() = runTest {
        var reads = 0
        val controller = BackgroundController(
            loadCatalog = {
                reads++
                if (reads == 1) throw IOException("Synthetic catalogue outage")
                CatalogPayload(SongsResponse(1, null, listOf(Fixtures.song("a", "A").copy(albumArt = "a.jpg"))), 7)
            },
            artworkUrl = { it?.let { raw -> "https://art.invalid/$raw" } },
        )
        controller.start(backgroundScope)
        runCurrent()
        assertTrue(controller.covers.value.isEmpty())
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(listOf("https://art.invalid/a.jpg"), controller.covers.value)
        assertEquals(2, reads)
    }

    @Test
    fun retryAfterIsHonouredAndCancellationStopsRetries() = runTest {
        var reads = 0
        val failures = mutableListOf<Exception>()
        val controller = BackgroundController(
            loadCatalog = {
                reads++
                throw FestivalApiException.PublicReadFrozen("scrape", "3")
            },
            artworkUrl = { it },
            backoff = ServiceRetryBackoff { testScheduler.currentTime },
            onFailure = failures::add,
        )
        val job = controller.start(backgroundScope)
        assertSame(job, controller.start(backgroundScope))
        runCurrent()
        advanceTimeBy(2_999)
        runCurrent()
        assertEquals(1, reads)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, reads)
        assertEquals(2, failures.size)
        job.cancel()
        advanceTimeBy(300_000)
        runCurrent()
        assertEquals(2, reads)
    }

    @Test
    fun newerPublicationClearsArtAndRecoversEvenWithTheSameCoverUrls() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        var fail = false
        var reads = 0
        var clears = 0
        val controller = BackgroundController(
            loadCatalog = {
                reads++
                if (fail) throw IOException("Synthetic outage")
                CatalogPayload(SongsResponse(1, null, listOf(Fixtures.song("a", "A").copy(albumArt = "a.jpg"))), publications.value!!)
            },
            artworkUrl = { it },
            publications = publications,
            onPublicationChanged = { clears++ },
        )
        val job = controller.start(backgroundScope)
        runCurrent()
        val before = controller.covers.value
        assertEquals(listOf("a.jpg"), before)
        publications.value = 7
        runCurrent()
        assertSame(before, controller.covers.value)
        assertEquals(1, reads)
        fail = true
        publications.value = 8
        runCurrent()
        assertTrue(controller.covers.value.isEmpty())
        assertEquals(8, controller.publication.value)
        assertEquals(2, clears)
        fail = false
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(listOf("a.jpg"), controller.covers.value)
        assertEquals(3, reads)
        job.cancel()
        controller.start(backgroundScope)
        runCurrent()
        assertEquals("resuming does not reload a successful pool", 3, reads)
    }

    @Test
    fun aNewerPublicationCancelsAnOlderReadAndKeepsTheNewestPool() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        val old = CompletableDeferred<CatalogPayload>()
        val controller = BackgroundController(
            loadCatalog = {
                if (publications.value == 7) old.await()
                else CatalogPayload(SongsResponse(1, null, listOf(Fixtures.song("b", "B").copy(albumArt = "b.jpg"))), 8)
            },
            artworkUrl = { it },
            publications = publications,
        )
        controller.start(backgroundScope)
        runCurrent()
        publications.value = 8
        runCurrent()
        old.complete(CatalogPayload(SongsResponse(0, null, emptyList()), 7))
        runCurrent()
        assertEquals(listOf("b.jpg"), controller.covers.value)
        assertEquals(8, controller.publication.value)
    }
}
