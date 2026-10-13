package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.testing.Fixtures
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** Decorative cover pools follow the current generation, never a cancelled older read. */
@OptIn(ExperimentalCoroutinesApi::class)
class BackgroundPublicationTest {
    @Test
    fun aNewerPublicationCancelsTheOlderCoverPoolLoad() = runTest {
        val publications = MutableStateFlow<Int?>(7)
        val held = CompletableDeferred<Unit>()
        val controller = BackgroundController(
            loadCatalog = {
                val id = publications.value!!
                if (id == 8) held.await()
                CatalogPayload(SongsResponse(1, 15, listOf(Fixtures.song("song", "Song").copy(albumArt = "cover-$id"))), id)
            },
            artworkUrl = { it },
            publications = publications,
        )
        controller.start(backgroundScope)
        runCurrent()
        assertEquals(listOf("cover-7"), controller.covers.value)
        publications.value = 8
        runCurrent()
        assertEquals(emptyList<String>(), controller.covers.value)
        publications.value = 9
        runCurrent()
        held.complete(Unit)
        runCurrent()
        assertEquals(listOf("cover-9"), controller.covers.value)
    }
}
