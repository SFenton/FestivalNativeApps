package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoBars
import java.text.NumberFormat
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSuggestionTemplate
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoTiming
import com.festivalscoretracker.android.core.firstrun.FirstRunRotatingDemos
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemo
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.LocalFirstRunDemoCatalog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Issue #58: rotating first-run demos swap data on the web clock, only while the slide is active. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunRotatingDemoUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val catalog = FirstRunDemoCatalog(List(10) { Song("song-$it", "Demo Song $it", "Epic Games", albumArt = "$it.jpg") })

    /** One swap: interval plus fade out and fade in. */
    private val cycle = FirstRunDemoTiming.SWAP_INTERVAL_MS + 2L * FirstRunDemoTiming.FADE_MS + 50

    /** Texts of nodes tagged [tag]; a tag ending in `.` matches every tag with that prefix (per-song `fst.first-run.demo.song.<id>`). */
    private fun texts(tag: String): List<String> =
        rule.onAllNodes(SemanticsMatcher("tag $tag") { node -> node.config.getOrNull(SemanticsProperties.TestTag)?.let { if (tag.endsWith(".")) it.startsWith(tag) else it == tag } == true }, useUnmergedTree = true).fetchSemanticsNodes().map { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text }.orEmpty()
        }

    private fun show(id: String, active: () -> Boolean = { true }, reduceMotion: Boolean = false, demoCatalog: FirstRunDemoCatalog = catalog) {
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme(appReduceMotion = reduceMotion) {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides demoCatalog) { FirstRunDemo(id, active()) }
            }
        }
        rule.mainClock.advanceTimeByFrame()
    }

    @Test
    fun placeholdersHoldStillUntilTheCatalogueArrives() {
        show("songs-song-list", demoCatalog = FirstRunDemoCatalog())
        fun placeholders() = rule.onAllNodesWithTag("fst.first-run.demo.placeholder", useUnmergedTree = true).fetchSemanticsNodes().size
        assertEquals("no invented titles", emptyList<String>(), texts("fst.first-run.demo.song."))
        assertEquals("three rows of title + artist bars", 6, placeholders())
        rule.mainClock.advanceTimeBy(cycle * 2)
        assertEquals(6, placeholders())
        assertEquals(emptyList<String>(), texts("fst.first-run.demo.song."))
    }

    @Test
    fun songListSwapsOneRowEveryFiveSecondsWithAFade() {        show("songs-song-list")
        val before = texts("fst.first-run.demo.song.")
        // Two real song rows fit the 220 dp frame at phone width (web `useSlideHeight`).
        assertEquals(listOf("Demo Song 0", "Demo Song 1"), before)
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.SWAP_INTERVAL_MS - 500)
        assertEquals("no swap before the interval", before, texts("fst.first-run.demo.song."))
        rule.mainClock.advanceTimeBy(500L + FirstRunDemoTiming.FADE_MS / 2)
        assertEquals("still fading out the old row", before, texts("fst.first-run.demo.song."))
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.FADE_MS * 2L)
        val after = texts("fst.first-run.demo.song.")
        assertEquals(2, after.size)
        assertEquals(1, before.indices.count { before[it] != after[it] })
        assertEquals(2, after.toSet().size)
    }

    @Test
    fun inactiveSlideDoesNotRotateUntilItSettles() {
        var active by mutableStateOf(false)
        show("songs-song-list", active = { active })
        val before = texts("fst.first-run.demo.song.")
        rule.mainClock.advanceTimeBy(cycle * 3)
        assertEquals(before, texts("fst.first-run.demo.song."))
        rule.runOnIdle { active = true }
        rule.mainClock.advanceTimeByFrame()
        // Step the clock so the restarted ticker's launch is flushed before its delay is due.
        repeat(8) {
            rule.mainClock.advanceTimeBy(1_000)
            rule.waitForIdle()
        }
        assertNotEquals(before, texts("fst.first-run.demo.song."))
    }

    /** Issue #166: rotation runs only while the app is in the foreground (RESUMED). */
    @Test
    fun backgroundedAppHoldsStillUntilResumed() {
        val owner = TestLifecycle()
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalLifecycleOwner provides owner, LocalFirstRunDemoCatalog provides catalog) { FirstRunDemo("songs-song-list", true) }
            }
        }
        rule.mainClock.advanceTimeByFrame()
        rule.runOnIdle { owner.registry.currentState = Lifecycle.State.STARTED }
        val before = texts("fst.first-run.demo.song.")
        repeat(18) {
            rule.mainClock.advanceTimeBy(1_000)
            rule.waitForIdle()
        }
        assertEquals("no swaps while paused", before, texts("fst.first-run.demo.song."))
        rule.runOnIdle { owner.registry.currentState = Lifecycle.State.RESUMED }
        repeat(8) {
            rule.mainClock.advanceTimeBy(1_000)
            rule.waitForIdle()
        }
        assertNotEquals("swaps again once resumed", before, texts("fst.first-run.demo.song."))
    }

    /** Issue #166: leaving a slide mid-fade still lands the swap, then the slide holds still. */
    @Test
    fun leavingMidFadeCompletesTheSwapThenHoldsStill() {
        var active by mutableStateOf(true)
        show("songs-song-list", active = { active })
        val before = texts("fst.first-run.demo.song.")
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.SWAP_INTERVAL_MS + FirstRunDemoTiming.FADE_MS / 2L)
        assertEquals("mid fade-out, old rows still shown", before, texts("fst.first-run.demo.song."))
        rule.runOnIdle { active = false }
        repeat(3) {
            rule.mainClock.advanceTimeByFrame()
            rule.waitForIdle()
        }
        val landed = texts("fst.first-run.demo.song.")
        assertEquals(1, before.indices.count { before[it] != landed[it] })
        rule.mainClock.advanceTimeBy(cycle * 3)
        assertEquals("inactive slide holds still", landed, texts("fst.first-run.demo.song."))
    }

    @Test
    fun reduceMotionStillSwapsWithACrossFade() {
        show("songs-song-list", reduceMotion = true)
        val before = texts("fst.first-run.demo.song.")
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.SWAP_INTERVAL_MS + FirstRunDemoTiming.FADE_MS + 100L)
        val after = texts("fst.first-run.demo.song.")
        assertEquals(before.size, after.size)
        assertNotEquals(before, after)
    }

    @Test
    fun categoryCardCyclesTemplates() {
        show("suggestions-category-card")
        val titles = FirstRunDemoSuggestionTemplate.TEMPLATES.map { it.title }
        fun shown(title: String) = rule.onAllNodesWithText(title, useUnmergedTree = true).fetchSemanticsNodes().size
        assertEquals(1, shown(titles[0]))
        rule.mainClock.advanceTimeBy(cycle)
        assertEquals(1, shown(titles[1]))
        assertEquals(0, shown(titles[0]))
    }

    @Test
    fun experimentalMetricsMoveTheSelection() {
        show("leaderboards-experimental-metrics")
        fun selectedTop() = rule.onAllNodesWithTag("fst.first-run.demo.metric.selected", useUnmergedTree = true).fetchSemanticsNodes().single().boundsInRoot.top
        val first = selectedTop()
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.SWAP_INTERVAL_MS + 50)
        assertTrue(selectedTop() > first)
    }

    @Test
    fun barSelectMovesEveryTwoAndAHalfSeconds() {
        show("songinfo-bar-select")
        // The detail is the real Song Detail history row, which reads its values as one summary.
        fun shown(bar: Int) = rule.onAllNodes(hasTestTag("fst.first-run.demo.bar-detail.row") and hasContentDescription("score ${NumberFormat.getIntegerInstance().format(FirstRunDemoBars.BARS[bar].score)}", substring = true), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        assertTrue(shown(0))
        rule.mainClock.advanceTimeBy(FirstRunDemoTiming.BAR_SELECT_INTERVAL_MS + 2L * FirstRunDemoTiming.BAR_SELECT_FADE_MS + 50)
        assertTrue(shown(1))
        assertTrue(!shown(0))
    }

    @Test
    fun everyRotatingDemoRendersAndSurvivesSeveralSwaps() {
        var index by mutableStateOf(0)
        val ids = FirstRunRotatingDemos.IDS.toList()
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides catalog) { FirstRunDemo(ids[index], true) }
            }
        }
        ids.indices.forEach {
            rule.runOnIdle { index = it }
            repeat(18) {
                rule.mainClock.advanceTimeBy(1_000)
                rule.waitForIdle()
            }
        }
        rule.mainClock.advanceTimeByFrame()
    }

    @Test
    fun reduceMotionRendersEveryRotatingDemo() {
        var index by mutableStateOf(0)
        val ids = FirstRunRotatingDemos.IDS.toList()
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides FirstRunDemoCatalog()) { FirstRunDemo(ids[index], true) }
            }
        }
        ids.indices.forEach {
            rule.runOnIdle { index = it }
            repeat(12) {
                rule.mainClock.advanceTimeBy(1_000)
                rule.waitForIdle()
            }
        }
        rule.mainClock.advanceTimeByFrame()
    }

    /** Issues #67/#175: rival demos show the player's ahead/behind counts, never the shared-song count. */
    @Test
    fun rivalDemosShowAheadAndBehindWithoutTheSharedCount() {
        var id by mutableStateOf("compete-rivals")
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides catalog) { FirstRunDemo(id, true) }
            }
        }
        rule.mainClock.advanceTimeByFrame()
        fun shown(): List<String> =
            rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Text), useUnmergedTree = true).fetchSemanticsNodes().map { node ->
                node.config[SemanticsProperties.Text].joinToString("") { it.text }
            }
        val bareCount = Regex("""^[\d,]+ songs$""")
        // KeyDrifter leads 82 songs and trails 66; DrumSurge leads 58 and trails 84 (player's side: ahead = rival trails).
        assertTrue(shown().containsAll(listOf("66 ahead", "82 behind", "84 ahead", "58 behind")))
        listOf("compete-rivals", "rivals-overview", "rivals-instruments", "compete-hub").forEach { demo ->
            rule.runOnIdle { id = demo }
            rule.mainClock.advanceTimeByFrame()
            // Compete Hub opens on its rankings layout and swaps to the rivals one on the first tick.
            if (demo == "compete-hub") rule.mainClock.advanceTimeBy(cycle)
            val texts = shown()
            assertEquals("$demo counts", texts.count { it.endsWith(" ahead") }, texts.count { it.endsWith(" behind") })
            assertTrue("$demo shows ahead/behind", texts.any { it.endsWith(" ahead") })
            assertTrue("$demo hides the shared count: $texts", texts.none { bareCount.matches(it) || it.contains("shared", ignoreCase = true) })
        }
    }

    /** A lifecycle the test moves between RESUMED (foreground) and STARTED (backgrounded or covered). */
    private class TestLifecycle : LifecycleOwner {
        val registry: LifecycleRegistry = LifecycleRegistry.createUnsafe(this).apply { currentState = Lifecycle.State.RESUMED }
        override val lifecycle: Lifecycle get() = registry
    }
}
