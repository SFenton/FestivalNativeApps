package com.festivalscoretracker.android.ui.background

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.BackgroundController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** [SongCoverBackdrop]: song-scoped pages show their static cover while composed (pattern `song-leaderboard-header` R4, issue #317). */
@RunWith(AndroidJUnit4::class)
class SongCoverBackdropTest {
    @get:Rule
    val rule = createComposeRule()

    private val controller = BackgroundController(
        loadCatalog = { CatalogPayload(SongsResponse(0, null, emptyList()), 1) },
        artworkUrl = { raw -> raw?.let { "https://art.invalid/$it" } },
    )

    @Test
    fun pushesTheCoverWhileComposedAndFollowsArtChanges() {
        var shown by mutableStateOf(true)
        var art by mutableStateOf<String?>(null)
        rule.setContent { if (shown) SongCoverBackdrop(controller, art) }
        rule.waitForIdle()
        // Still loading (no art): the carousel stays.
        assertNull(controller.focus.value)
        art = "one.jpg"
        rule.waitForIdle()
        assertEquals("https://art.invalid/one.jpg", controller.focus.value)
        art = "two.jpg"
        rule.waitForIdle()
        assertEquals("https://art.invalid/two.jpg", controller.focus.value)
        shown = false
        rule.waitForIdle()
        assertNull(controller.focus.value)
    }

    @Test
    fun aPushedPageKeepsItsCoverWhenThePreviousPageLeaves() {
        // Song Detail → leaderboard: the new page pushes before the old one disposes.
        var detail by mutableStateOf(true)
        var board by mutableStateOf(false)
        rule.setContent {
            if (detail) SongCoverBackdrop(controller, "song.jpg")
            if (board) SongCoverBackdrop(controller, "song.jpg")
        }
        rule.waitForIdle()
        board = true
        rule.waitForIdle()
        detail = false
        rule.waitForIdle()
        assertEquals("https://art.invalid/song.jpg", controller.focus.value)
    }

    @Test
    fun noControllerIsANoOp() {
        rule.setContent { SongCoverBackdrop(null, "song.jpg") }
        rule.waitForIdle()
        assertNull(controller.focus.value)
    }
}
