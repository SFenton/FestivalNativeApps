package com.festivalscoretracker.android.journeys

import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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
 * States: `new-slides-only` (a fresh store), `dismissed` (with Close, system Back and Esc, each
 * marking only the displayed slides seen), `hidden-all-seen` and `replay-all`
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

    /** The page title heads the dialog beside Close and names the pane (issues #24, #147). */
    private fun assertTitled(page: FirstRunPageKey) {
        val title = rule.onNodeWithTag("fst.first-run.title", useUnmergedTree = true).fetchSemanticsNode()
        assertEquals(listOf(page.label), title.config[SemanticsProperties.Text].map { it.text })
        assertTrue("the title is a heading", SemanticsProperties.Heading in title.config)
        val dialog = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode()
        assertEquals("Feature tour: ${page.label}", dialog.config[SemanticsProperties.PaneTitle])
        val close = rule.onNodeWithTag("fst.first-run.close").fetchSemanticsNode().boundsInRoot
        assertTrue("the title ends before Close", title.boundsInRoot.right <= close.left)
        assertTrue("Close stays inside the dialog", close.right <= dialog.boundsInRoot.right && close.top >= dialog.boundsInRoot.top)
    }

    /** `new-slides-only` from a fresh store, then `dismissed` with Close. */
    @Test
    fun newSlidesShowOnFirstVisitAndCloseDismisses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(firstRun = "on", stillBackground = true), transport)
        h.waitForTag("fst.first-run.dialog")
        assertTrue(position().startsWith("Slide 1 of "))
        assertTitled(FirstRunPageKey.Songs)
        assertLayoutFitsTheWindow()
        h.readingOrder("first-run-journey")
        val firstNext = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        h.tap("fst.first-run.next")
        rule.waitUntil(5_000) { position().startsWith("Slide 2 of ") }
        assertTrue("Back appears after the first slide", h.exists("fst.first-run.back"))
        // Material 3 dialog actions (issues #25, #148): Back, then Next, which never moves.
        val back = rule.onNodeWithTag("fst.first-run.back").fetchSemanticsNode().boundsInRoot
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        assertTrue("Back comes before Next", back.right <= next.left)
        assertEquals("Next keeps its place on slide 2", firstNext, next)
        assertLayoutFitsTheWindow()
        h.tap("fst.first-run.close")
        h.waitGone("fst.first-run.dialog")
        h.assertAccessible()
    }

    /** `dismissed` with system Back on slide 2: only the tour closes and the two displayed slides are seen (issue #152). */
    @Test
    fun systemBackDismissesAndMarksTheDisplayedSlidesSeen() = dismissWithKey(KeyEvent.KEYCODE_BACK, slides = 2)

    /** `dismissed` with Esc (hardware keyboard) on slide 3, like Back (issue #152). */
    @Test
    fun escapeDismissesAndMarksTheDisplayedSlidesSeen() = dismissWithKey(KeyEvent.KEYCODE_ESCAPE, slides = 3)

    /**
     * Opens the first-visit Songs tour, pages to [slides], dismisses it with [keyCode] and checks
     * the tour is gone, the page underneath stays, and exactly the displayed slides are seen.
     */
    private fun dismissWithKey(keyCode: Int, slides: Int) {
        val debug = DebugLaunch(firstRun = "on", stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = MemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        h.waitForTag("fst.first-run.dialog")
        val displayed = container.firstRun.active.value!!.slides.take(slides).map { it.id }.toSet()
        repeat(slides - 1) { page ->
            h.tap("fst.first-run.next")
            rule.waitUntil(5_000) { position().startsWith("Slide ${page + 2} of ") }
        }
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(keyCode)
        h.waitGone("fst.first-run.dialog")
        rule.waitUntil(5_000) { container.firstRun.active.value == null }
        assertTrue("the key closed only the tour", h.exists("fst.songs.list"))
        val seen = runBlocking { container.firstRun.store.load().keys }
        assertEquals(displayed, seen)
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
        assertTitled(FirstRunPageKey.Songs)
        assertLayoutFitsTheWindow()
        h.assertAccessible()
    }
}
