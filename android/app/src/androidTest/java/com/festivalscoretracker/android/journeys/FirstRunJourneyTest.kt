package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Instant
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * First Run on a real device window (issue #139): the tour through the whole shell on whichever
 * FST AVD runs it, with ATF on every state, nothing across a separating hinge and the layout the
 * window calls for (`fst.first-run.layout.side-by-side` on short wide windows, otherwise stacked).
 * States: `new-slides-only` (a fresh store), `dismissed`, `hidden-all-seen` and `replay-all`
 * (`device.py test com.festivalscoretracker.android.journeys.FirstRunJourneyTest --avd …`).
 * `gated` and `waiting-not-ready` need controlled settings and timing, so they are covered by
 * the Robolectric `FirstRunStatesUiTest`.
 */
@RunWith(AndroidJUnit4::class)
class FirstRunJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }
    private val songsSlides = (FirstRunCatalog.slides(FirstRunPageKey.Songs, true) + FirstRunCatalog.slides(FirstRunPageKey.Songs, false)).distinctBy { it.id }

    private fun position(): String =
        rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    private fun assertLayoutFitsTheWindow() {
        val window = rule.activity.window.decorView
        val density = rule.activity.resources.displayMetrics.density
        val heightDp = window.height / density
        val widthDp = window.width / density
        assertTrue("one slide layout is tagged", h.exists("fst.first-run.layout.side-by-side") || h.exists("fst.first-run.layout.stacked"))
        if (h.exists("fst.first-run.layout.side-by-side")) assertTrue("side by side only on wide windows ($widthDp dp)", widthDp >= 480f)
        assertTrue("window $heightDp dp", heightDp > 0f)
        val next = rule.onNodeWithTag(if (h.exists("fst.first-run.next")) "fst.first-run.next" else "fst.first-run.done").fetchSemanticsNode().boundsInRoot
        val dialog = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode().boundsInRoot
        assertTrue("the footer action stays inside the dialog", next.bottom <= dialog.bottom && next.top >= dialog.top)
        h.assertNothingStraddles("fst.first-run.dialog")
    }

    /** `new-slides-only` from a fresh store, then `dismissed` with Close. */
    @Test
    fun newSlidesShowOnFirstVisitAndCloseDismisses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(firstRun = "on", stillBackground = true), transport)
        h.waitForTag("fst.first-run.dialog")
        assertTrue(position().startsWith("Slide 1 of "))
        assertLayoutFitsTheWindow()
        h.readingOrder("first-run-journey")
        h.tap("fst.first-run.next")
        rule.waitUntil(5_000) { position().startsWith("Slide 2 of ") }
        assertTrue("Back appears after the first slide", h.exists("fst.first-run.back"))
        assertLayoutFitsTheWindow()
        h.tap("fst.first-run.close")
        h.waitGone("fst.first-run.dialog")
        h.assertAccessible()
    }

    /** `hidden-all-seen` on launch, then `replay-all` from Settings' replay entry point. */
    @Test
    fun allSeenShowsNothingUntilReplay() {
        h.enableAccessibilityChecks()
        val debug = DebugLaunch(firstRun = "on", stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        runBlocking { container.firstRun.store.markSeen(songsSlides, Instant.now()) }
        rule.setContent { FestivalApp(container, debug) }
        h.waitForTag("fst.songs.list")
        rule.mainClock.advanceTimeBy(2_000)
        rule.waitForIdle()
        assertTrue("every slide seen: no tour", !h.exists("fst.first-run.dialog"))
        val replay = runBlocking { container.firstRun.beginReplay(FirstRunPageKey.Songs, compact = true) }
        assertTrue("replay claims the slot", replay != null)
        h.waitForTag("fst.first-run.dialog")
        assertEquals("Slide 1 of ${replay!!.slides.size}", position())
        assertLayoutFitsTheWindow()
        h.assertAccessible()
    }
}
