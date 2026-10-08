package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.withKeyDown
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FirstRunCarouselDialog
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.LocalFirstRunDemoCatalog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Hardware keyboard in every First Run demo (issue #420). The demos are decorative pictures that
 * reuse real clickable rows, buttons and chips, so `DemoIllustration` keeps them out of keyboard
 * focus without blocking traversal past them. For each of the 42 slides, opened alone as a fresh
 * dialog, Tab from Close reaches Done and Shift+Tab walks back to Close without ever stopping
 * inside the demo or leaving focus nowhere. The first Tab from a touch-mode window (nothing
 * focused) needs a real `ViewRootImpl`, so the `@DeviceCi` journey
 * `journeys/FirstRunDemoSongsJourneyTest` covers it.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunDemoKeyboardUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val slides: List<FirstRunSlide> =
        FirstRunPageKey.entries.flatMap { page -> FirstRunCatalog.slides(page, true) }.distinctBy { it.id }

    private val catalog = FirstRunDemoCatalog(
        listOf(
            Fixtures.song("demo-1", "Neon Overture", artist = "Epic Games").copy(albumArt = "one.jpg"),
            Fixtures.song("demo-2", "Crowd Surfer", artist = "Epic Games").copy(albumArt = "two.jpg"),
            Fixtures.song("demo-3", "Lighthouse Static", artist = "Harbor Kids").copy(albumArt = "three.jpg"),
        ),
        artworkUrl = { null },
    )

    private var carousel by mutableStateOf<FirstRunCarousel?>(null)

    private var nextId = 1L

    private var started = false

    /** Advances the paused clock past entrance animations (rotating demos never idle). */
    private fun settle() {
        rule.mainClock.advanceTimeBy(1_500)
        rule.waitForIdle()
    }

    /** Opens [slide] alone in a fresh dialog (a new key replaces the previous dialog's window). */
    private fun open(slide: FirstRunSlide) {
        carousel = FirstRunCarousel(nextId++, FirstRunPageKey.Songs, listOf(slide), isReplay = false)
        if (!started) {
            started = true
            rule.mainClock.autoAdvance = false
            rule.setContent {
                FestivalTheme {
                    CompositionLocalProvider(LocalFirstRunDemoCatalog provides catalog) {
                        carousel?.let { shown -> key(shown.id) { FirstRunCarouselDialog(shown) { } } }
                    }
                }
            }
        }
        repeat(10) {
            settle()
            if (rule.onAllNodes(hasTestTag("fst.first-run.slide.${slide.id}"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()) return
        }
        throw AssertionError("${slide.id}: the dialog never opened")
    }

    private fun focused(): List<SemanticsNode> = rule.onAllNodes(isFocused(), useUnmergedTree = true).fetchSemanticsNodes()

    private fun SemanticsNode.tag(): String = config.getOrNull(SemanticsProperties.TestTag)
        ?: config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
        ?: config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
        ?: "<node $id>"

    /**
     * Presses Tab (or Shift+Tab when [backward]) until [target] has focus.
     *
     * @return The focus stops, in order.
     */
    private fun tabTo(slide: FirstRunSlide, target: String, backward: Boolean, stops: MutableList<String> = mutableListOf()): List<String> {
        val key = if (backward) "Shift+Tab" else "Tab"
        for (step in 0 until 8) {
            rule.onNodeWithTag("fst.first-run.dialog").performKeyInput {
                if (backward) withKeyDown(Key.ShiftLeft) { pressKey(Key.Tab) } else pressKey(Key.Tab)
            }
            settle()
            val inDemo = rule.onAllNodes(isFocused() and hasAnyAncestor(hasTestTag("fst.first-run.demo")), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("${slide.id}: $key ${step + 1} after $stops focused a hidden demo node: ${inDemo.map { it.tag() }}", inDemo.isEmpty())
            val now = rule.onAllNodes(isFocused() and hasAnyAncestor(hasTestTag("fst.first-run.dialog")), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("${slide.id}: $key ${step + 1} after $stops left keyboard focus nowhere in the dialog", now.isNotEmpty())
            stops += now.first().tag()
            if (stops.last() == target) break
        }
        assertEquals("${slide.id}: $key reaches $target (stops $stops)", target, stops.last())
        return stops
    }

    /**
     * Every slide: Tab from Close (where a fresh dialog's focus starts here) reaches Done, then
     * Shift+Tab walks back to Close, both past the demo without stopping in it.
     */
    @Test
    fun tabAndShiftTabStepOverEveryDemo() {
        slides.forEach { slide ->
            open(slide)
            if (focused().isEmpty()) rule.onNodeWithTag("fst.first-run.close").performSemanticsAction(SemanticsActions.RequestFocus)
            settle()
            assertEquals("${slide.id}: focus starts on Close", listOf("fst.first-run.close"), focused().map { it.tag() })
            val forward = tabTo(slide, "fst.first-run.done", backward = false)
            val backward = tabTo(slide, "fst.first-run.close", backward = true)
            println("FST_A11Y ${slide.id} Tab: $forward Shift+Tab: $backward")
        }
    }
}
