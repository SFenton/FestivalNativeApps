package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.ui.common.FestivalLoadSwap
import com.festivalscoretracker.android.ui.common.LOAD_SWAP_SPINNER_TAG
import com.festivalscoretracker.android.ui.common.LoadSwap
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Shared load/reload swap (issue #71): content out → spinner → spinner out → content in. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class LoadSwapUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun count(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    private fun shows(text: String) = rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun spinner() = count(LOAD_SWAP_SPINNER_TAG) == 1

    /** `null` = loading. */
    private var data by mutableStateOf<String?>(null)
    private var reduce by mutableStateOf(false)
    private var boxSwap: LoadSwap<String?>? = null

    /** Stale content fading out: drawn from the old value but hidden from TalkBack. */
    private fun fadingOut(old: String) = boxSwap?.phase == LoadSwapPhase.ContentOut && boxSwap?.shown == old && count("row") == 0 && !spinner()

    private fun setBox() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduce)) {
                    FestivalLoadSwap(data, data != null, Modifier.fillMaxSize()) { swap, shown ->
                        boxSwap = swap
                        with(swap) { Text(shown.orEmpty(), Modifier.staggered(0).testTag("row")) }
                    }
                }
            }
        }
    }

    @Test
    fun firstLoadAndReloadRunTheWebSequence() {
        rule.mainClock.autoAdvance = false
        setBox()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(spinner() && count("row") == 0)
        data = "Page 1"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(200)
        // The spinner is still fading out; no half-built content.
        assertTrue(spinner() && count("row") == 0)
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(!spinner() && shows("Page 1"))

        // Reload (page change): the old page fades out, never shows under the spinner.
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(150)
        assertTrue("stale page fades out first", fadingOut("Page 1"))
        rule.mainClock.advanceTimeBy(400)
        assertTrue(spinner() && count("row") == 0)
        data = "Page 2"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(200)
        assertTrue(spinner() && count("row") == 0)
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(!spinner() && shows("Page 2") && !shows("Page 1"))
    }

    @Test
    fun dataArrivingDuringTheFadeOutStillShowsTheSpinner() {
        rule.mainClock.autoAdvance = false
        data = "Page 1"; Snapshot.sendApplyNotifications()
        setBox()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(shows("Page 1") && !spinner())
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(100)
        data = "Page 2"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(50)
        // The new page waits for the fade-out; the old one is still the one drawn.
        assertTrue(fadingOut("Page 1"))
        rule.mainClock.advanceTimeBy(250)
        assertTrue(spinner())
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(!spinner() && shows("Page 2"))
    }

    @Test
    fun aNewerReloadWhileTheSpinnerFadesKeepsTheSpinner() {
        rule.mainClock.autoAdvance = false
        setBox()
        rule.mainClock.advanceTimeByFrame()
        data = "Page 1"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(200)
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(spinner() && count("row") == 0)
        data = "Page 3"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(!spinner() && shows("Page 3"))
    }

    @Test
    fun reduceMotionSwapsWithoutFades() {
        rule.mainClock.autoAdvance = false
        reduce = true; Snapshot.sendApplyNotifications()
        data = "Page 1"; Snapshot.sendApplyNotifications()
        setBox()
        rule.mainClock.advanceTimeByFrame()
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeByFrame()
        rule.mainClock.advanceTimeByFrame()
        // No fade-out: straight to the spinner while loading.
        assertTrue(spinner() && !shows("Page 1"))
        data = "Page 2"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeByFrame()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(!spinner() && shows("Page 2"))
    }

    @Test
    fun instantDataForANewKeyStillFadesOutAndIn() {
        var key by mutableStateOf("a")
        var swap: LoadSwap<String>? = null
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                val state = rememberLoadSwap("rows for $key", ready = true, key = key)
                swap = state
                LazyColumn(Modifier.fillMaxSize()) {
                    item(key = "header") { Text("Header") }
                    if (state.showsSpinner) loadSwapSpinnerItem(state)
                    if (state.showsContent) item(key = "rows") { with(state) { Text(state.shown, Modifier.staggered(0).testTag("row")) } }
                }
            }
        }
        rule.mainClock.advanceTimeByFrame()
        assertTrue(shows("rows for a") && !spinner())
        key = "b"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(100)
        assertEquals(LoadSwapPhase.ContentOut, swap!!.phase)
        assertTrue("old rows draw while fading", shows("rows for a") && !shows("rows for b"))
        rule.mainClock.advanceTimeBy(300)
        assertTrue(spinner() && shows("Header"))
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(!spinner() && shows("rows for b"))
        assertEquals(LoadSwapPhase.ContentIn, swap!!.phase)
    }

    @Test
    fun sameKeyUpdatesApplyInPlace() {
        rule.mainClock.autoAdvance = false
        data = "Page 1"; Snapshot.sendApplyNotifications()
        setBox()
        rule.mainClock.advanceTimeByFrame()
        data = "Page 1 refreshed"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(shows("Page 1 refreshed") && !spinner())
    }

    // region Pinned content (load-transition R2, issue #190)

    private var pinnedKey by mutableStateOf<Any?>("Guitar")
    private var pinnedSwap: LoadSwap<String?>? = null

    /** A board: rows swapped by page, a pinned row beside them keyed by [pinnedKey] (or every reload when [keyed] is false). */
    private fun setBoard(keyed: Boolean = true) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduce)) {
                    val swap = if (keyed) rememberLoadSwap(data, data != null, pinnedKey = pinnedKey) else rememberLoadSwap(data, data != null)
                    pinnedSwap = swap
                    androidx.compose.foundation.layout.Column {
                        if (swap.showsContent) with(swap) { Text(swap.shown.orEmpty(), Modifier.staggered(0).testTag("row")) }
                        if (swap.showsSpinner) Text("spinner", Modifier.testTag(LOAD_SWAP_SPINNER_TAG))
                        with(swap) { Text("Your score", Modifier.pinnedStaggered(0).then(swap.pinnedContentModifier).testTag("pinned")) }
                    }
                }
            }
        }
    }

    private fun pinnedShows() = count("pinned") == 1

    @Test
    fun pinnedContentStaysInPlaceWhileOnlyThePageReloads() {
        rule.mainClock.autoAdvance = false
        setBoard()
        rule.mainClock.advanceTimeByFrame()
        // First load: hidden beside the spinner, then enters with the first rows (#295).
        assertTrue(spinner() && !pinnedShows() && pinnedSwap!!.pinnedStale)
        data = "Page 1"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_500)
        assertTrue(shows("Page 1") && pinnedShows() && pinnedSwap!!.pinnedEnters)

        // Page change: the rows swap; the pinned row stays readable and usable (web footer, #93).
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(100)
        assertTrue(pinnedShows() && !pinnedSwap!!.pinnedStale)
        rule.mainClock.advanceTimeBy(400)
        assertTrue(spinner() && pinnedShows())
        data = "Page 2"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_500)
        assertTrue(shows("Page 2") && pinnedShows())
        assertTrue("no re-entrance on a page-only swap", !pinnedSwap!!.pinnedEnters)

        // Pinned key change (instrument, metric, leeway): hidden beside the spinner, then re-enters.
        pinnedKey = "Bass"; data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(500)
        assertTrue(spinner() && !pinnedShows() && pinnedSwap!!.pinnedStale)
        data = "Bass page 1"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_500)
        assertTrue(shows("Bass page 1") && pinnedShows() && pinnedSwap!!.pinnedEnters && !pinnedSwap!!.pinnedStale)
    }

    @Test
    fun pinnedContentStaysUnderReduceMotionPaging() {
        rule.mainClock.autoAdvance = false
        reduce = true; data = "Page 1"; Snapshot.sendApplyNotifications()
        setBoard()
        rule.mainClock.advanceTimeByFrame()
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeByFrame()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(spinner() && pinnedShows())
        pinnedKey = "Bass"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeByFrame()
        assertTrue("a key change mid-load hides it", spinner() && !pinnedShows())
    }

    @Test
    fun unkeyedPinnedContentHidesOnEveryReload() {
        rule.mainClock.autoAdvance = false
        data = "Page 1"; Snapshot.sendApplyNotifications()
        setBoard(keyed = false)
        rule.mainClock.advanceTimeByFrame()
        assertTrue(pinnedShows() && !pinnedSwap!!.pinnedStale)
        data = null; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(500)
        assertTrue(spinner() && !pinnedShows() && pinnedSwap!!.pinnedStale)
        data = "Page 2"; Snapshot.sendApplyNotifications()
        rule.mainClock.advanceTimeBy(1_500)
        assertTrue(pinnedShows() && pinnedSwap!!.pinnedEnters)
    }

    // endregion
}
