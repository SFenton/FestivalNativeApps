package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunGate
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FirstRunHost
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Every reachable First Run state through the shell seam ([FirstRunHost] + a real
 * [FirstRunCenter] over an in-memory seen store), named as in `.agents/controls/first-run/spec.md`:
 * `hidden-all-seen`, `new-slides-only`, `gated`, `waiting-not-ready`, `replay-all`, `dismissed`.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunStatesUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val now = Instant.ofEpochSecond(1_700_000_000)
    private val songs = FirstRunCatalog.slides(FirstRunPageKey.Songs, true)
    private val anonymousSlides = songs.filter { it.gate != FirstRunGate.HasPlayer }
    private val player = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))

    private fun center(seen: List<String> = emptyList()): FirstRunCenter {
        val store = FirstRunSeenStore(MemoryBlobStore())
        runBlocking { store.markSeen(songs.filter { it.id in seen }, now) }
        return FirstRunCenter(store, FirstRunMode.Normal) { now }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun settle() {
        rule.mainClock.advanceTimeBy(1_000)
        rule.waitForIdle()
    }

    private fun awaitDialog() = rule.waitUntil(5_000) { exists("fst.first-run.dialog") }

    private fun position(): String =
        rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    @Test
    fun hiddenAllSeenShowsNothing() {
        val center = center(seen = anonymousSlides.map { it.id })
        rule.setContent { FestivalTheme { FirstRunHost(center, FirstRunPageKey.Songs, AppSettings(), compact = true, blocked = false) } }
        settle()
        assertTrue(!exists("fst.first-run.dialog"))
        assertNull(center.active.value)
    }

    @Test
    fun newSlidesOnlyStartsAtTheFirstUnseenSlide() {
        val center = center(seen = listOf("songs-song-list", "songs-sort"))
        rule.setContent { FestivalTheme { FirstRunHost(center, FirstRunPageKey.Songs, AppSettings(), compact = true, blocked = false) } }
        settle()
        awaitDialog()
        assertTrue(exists("fst.first-run.slide.songs-navigation"))
        assertTrue(!exists("fst.first-run.slide.songs-song-list"))
        assertEquals("Slide 1 of ${anonymousSlides.size - 2}", position())
    }

    @Test
    fun gatedSlidesAppearOnlyOnceTheirGatePasses() {
        val center = center(seen = anonymousSlides.map { it.id })
        var settings by mutableStateOf(AppSettings())
        rule.setContent { FestivalTheme { FirstRunHost(center, FirstRunPageKey.Songs, settings, compact = true, blocked = false) } }
        settle()
        assertTrue("player-gated slides stay hidden without a player", !exists("fst.first-run.dialog"))
        settings = player
        settle()
        awaitDialog()
        assertTrue(exists("fst.first-run.slide.songs-filter"))
        assertEquals("Slide 1 of ${songs.count { it.gate == FirstRunGate.HasPlayer }}", position())
    }

    @Test
    fun waitingNotReadyHoldsUntilAPageIsVisibleAndUnblocked() {
        val center = center()
        var page by mutableStateOf<FirstRunPageKey?>(null)
        var blocked by mutableStateOf(false)
        rule.setContent { FestivalTheme { FirstRunHost(center, page, AppSettings(), compact = true, blocked = blocked) } }
        settle()
        assertTrue("no page yet", !exists("fst.first-run.dialog"))
        blocked = true
        page = FirstRunPageKey.Songs
        settle()
        assertTrue("another modal owns the screen", !exists("fst.first-run.dialog"))
        blocked = false
        settle()
        awaitDialog()
        assertEquals("Slide 1 of ${anonymousSlides.size}", position())
    }

    @Test
    fun replayAllShowsEverySlideIgnoringGatesAndSeenState() {
        val center = center(seen = songs.map { it.id })
        rule.setContent { FestivalTheme { FirstRunHost(center, FirstRunPageKey.Songs, AppSettings(), compact = true, blocked = false) } }
        settle()
        assertTrue(!exists("fst.first-run.dialog"))
        val replay = runBlocking { center.beginReplay(FirstRunPageKey.Songs, compact = true) }!!
        assertTrue(replay.isReplay)
        awaitDialog()
        assertEquals("Slide 1 of ${songs.size}", position())
    }

    @Test
    fun dismissedMarksOnlyDisplayedSlidesAndFreesTheSlot() {
        val center = center()
        rule.setContent { FestivalTheme { FirstRunHost(center, FirstRunPageKey.Songs, AppSettings(), compact = true, blocked = false) } }
        settle()
        awaitDialog()
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("fst.first-run.close").performClick()
        rule.waitUntil(5_000) { center.active.value == null }
        rule.waitForIdle()
        assertTrue(!exists("fst.first-run.dialog"))
        assertEquals(anonymousSlides.take(2).map { it.id }.toSet(), runBlocking { center.store.load().keys })
    }
}

/** Slide layouts: stacked on tall windows, side by side (dots in the footer) on short wide ones. */
@RunWith(AndroidJUnit4::class)
class FirstRunSlideLayoutUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = FirstRunCatalog.slides(FirstRunPageKey.Songs, false)

    private fun show() {
        val carousel = com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel(1, FirstRunPageKey.Songs, songs.take(3), isReplay = false)
        rule.setContent { FestivalTheme { com.festivalscoretracker.android.ui.firstrun.FirstRunCarouselDialog(carousel) { } } }
        rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    @Test
    @Config(qualifiers = "w891dp-h411dp-land")
    fun landscapePhoneShowsTheSlideSideBySideWithEverythingInView() {
        show()
        assertTrue(exists("fst.first-run.layout.side-by-side"))
        rule.onNodeWithTag("fst.first-run.demo", useUnmergedTree = true).assertIsDisplayed()
        val dialog = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode().boundsInRoot
        val dots = rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        assertTrue("dots share the footer row with Next", dots.center.y in next.top..next.bottom && dots.right <= next.left)
        val title = rule.onAllNodesWithTag("fst.first-run.slide.songs-song-list", useUnmergedTree = true).fetchSemanticsNodes().single().boundsInRoot
        assertTrue("slide sits inside the dialog above the footer", title.top >= dialog.top && title.bottom <= next.top)
        val demo = rule.onNodeWithTag("fst.first-run.demo", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("demo fits inside the dialog", demo.bottom <= next.top)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land")
    fun sideBySideTitleIsAVisibleHeading() {
        show()
        rule.onNodeWithTag("fst.first-run.pager").assertIsDisplayed()
        val heading = rule.onAllNodes(
            androidx.compose.ui.test.SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading),
            useUnmergedTree = true,
        ).fetchSemanticsNodes()
        assertTrue(heading.any { it.config.getOrElse(SemanticsProperties.Text) { emptyList() }.any { t -> t.text == "Song List" } })
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp")
    fun tallWindowStacksTheSlide() {
        show()
        assertTrue(exists("fst.first-run.layout.stacked"))
        val dots = rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        assertTrue("dots sit above the footer", dots.bottom <= next.top)
    }
}

/**
 * Half-open foldables: the tour stays on one side of a separating hinge (M3 "Never place
 * interactive content or critical information across the hinge area") and a tap on the other
 * side still dismisses it.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w841dp-h900dp")
class FirstRunHingeUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = FirstRunCatalog.slides(FirstRunPageKey.Songs, false)

    private fun show(hingeDp: Pair<Float, Float>, vertical: Boolean = true, separating: Boolean = true, onComplete: () -> Unit = {}): androidx.compose.ui.geometry.Rect {
        val carousel = com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel(1, FirstRunPageKey.Songs, songs.take(3), isReplay = false)
        var hinge = androidx.compose.ui.geometry.Rect.Zero
        rule.setContent {
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            hinge = if (vertical) {
                androidx.compose.ui.geometry.Rect(hingeDp.first * density, 0f, hingeDp.second * density, 900 * density)
            } else {
                androidx.compose.ui.geometry.Rect(0f, hingeDp.first * density, 841 * density, hingeDp.second * density)
            }
            val posture = androidx.compose.material3.adaptive.Posture(
                isTabletop = !vertical,
                hingeList = listOf(androidx.compose.material3.adaptive.HingeInfo(hinge, isFlat = !separating, isVertical = vertical, isSeparating = separating, isOccluding = false)),
            )
            androidx.compose.runtime.CompositionLocalProvider(com.festivalscoretracker.android.ui.common.LocalShellPosture provides posture) {
                FestivalTheme { com.festivalscoretracker.android.ui.firstrun.FirstRunCarouselDialog(carousel) { onComplete() } }
            }
        }
        rule.waitForIdle()
        return hinge
    }

    private fun dialogBounds() = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode().boundsInRoot

    @Test
    fun bookPostureKeepsTheTourOnTheWiderSide() {
        val hinge = show(400f to 410f)
        val dialog = dialogBounds()
        assertTrue("dialog $dialog clears hinge $hinge", dialog.left >= hinge.right)
    }

    @Test
    fun tabletopPostureKeepsTheTourBelowTheHinge() {
        val hinge = show(300f to 310f, vertical = false)
        val dialog = dialogBounds()
        assertTrue("dialog $dialog clears hinge $hinge", dialog.top >= hinge.bottom)
    }

    @Test
    fun flatFoldKeepsTheCentredTour() {
        val hinge = show(415f to 425f, separating = false)
        val dialog = dialogBounds()
        assertTrue("an unfolded device keeps the centred dialog", dialog.left < hinge.left && dialog.right > hinge.right)
    }

    @Test
    fun tapOnTheOtherSideOfTheHingeDismisses() {
        var completed = 0
        val hinge = show(400f to 410f) { completed++ }
        val dialog = dialogBounds()
        rule.onAllNodes(androidx.compose.ui.test.isRoot()).let { roots ->
            val last = roots.fetchSemanticsNodes().size - 1
            roots[last].performTouchInput { click(androidx.compose.ui.geometry.Offset(dialog.left + 40f, dialog.top + 40f)) }
            rule.waitForIdle()
            assertEquals("a tap on the surface keeps the tour", 0, completed)
            roots[last].performTouchInput { click(androidx.compose.ui.geometry.Offset(hinge.left / 2f, dialog.center.y)) }
        }
        rule.waitForIdle()
        assertEquals(1, completed)
    }
}

/** Pure sizing rules behind the slide layouts. */
class FirstRunSlideLayoutPolicyTest {
    private val layout = com.festivalscoretracker.android.ui.firstrun.FirstRunSlideLayout

    @Test
    fun sideBySideOnlyForShortWideContent() {
        assertTrue(layout.sideBySide(widthDp = 560f, heightDp = 220f))
        assertTrue(!layout.sideBySide(widthDp = 560f, heightDp = layout.SHORT_HEIGHT_DP))
        assertTrue("narrow short windows keep the scrolling stacked slide", !layout.sideBySide(widthDp = 379f, heightDp = 220f))
        assertTrue(layout.sideBySide(widthDp = layout.SIDE_BY_SIDE_MIN_WIDTH_DP, heightDp = 300f))
    }

    @Test
    fun demoScalesDownToFitButNeverUpOrBelowTheFloor() {
        assertEquals(1f, layout.demoScale(available = 400f, design = 220f))
        assertEquals(1f, layout.demoScale(available = 220f, design = 220f))
        assertEquals(0.5f, layout.demoScale(available = 110f, design = 220f), 0.0001f)
        assertEquals(layout.MIN_DEMO_SCALE, layout.demoScale(available = 10f, design = 220f))
        assertEquals(1f, layout.demoScale(available = 10f, design = 0f))
    }
}
