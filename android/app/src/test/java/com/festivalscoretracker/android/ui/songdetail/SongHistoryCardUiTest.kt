package com.festivalscoretracker.android.ui.songdetail

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The song page's Score History card: selector, bar selection, paging, top five and View All. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongHistoryCardUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /**
     * Synthetic history rows, one per day in January 2026.
     *
     * @param chart Wire chart.
     * @param count Rows.
     * @param goldLast The last row is a 100% full combo.
     */
    private fun rows(chart: String, count: Int, goldLast: Boolean = false) = (1..count).map { day ->
        val gold = goldLast && day == count
        ScoreHistoryEntry(
            songId = "s-alpha",
            instrument = chart,
            newScore = 50_000L + day * 1_000,
            accuracy = if (gold) 1_000_000.0 else 900_000.0 + day * 1_000,
            isFullCombo = gold,
            season = 9,
            scoreAchievedAt = "2026-01-%02dT12:00:00Z".format(day),
            changedAt = "2026-01-%02dT12:00:00Z".format(day),
        )
    }

    private var viewAll: Instrument? = null

    private fun show(entries: List<ScoreHistoryEntry>, initial: Instrument? = null) {
        rule.setContent {
            FestivalTheme {
                SongHistoryCard(
                    entries = entries,
                    visible = Instrument.entries.toSet(),
                    keyboard = false,
                    initialInstrument = initial,
                    onViewAll = { viewAll = it },
                )
            }
        }
    }

    /** Force a frame so the chart canvas and legend swatches actually draw. */
    private fun draw() {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
    }

    private fun exists(tag: String) = rule.onAllNodes(androidx.compose.ui.test.hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun longHistoryPagesSelectsBarsAndOpensViewAll() {
        show(rows("Solo_Guitar", 30, goldLast = true))
        // Thirty bars don't fit a phone card: the pager starts on the newest page.
        rule.onNodeWithTag("fst.song-detail.history.pager").assertExists()
        rule.onNodeWithContentDescription("Forward one page").assertIsNotEnabled()
        rule.onNodeWithContentDescription("Back one page").assertIsEnabled()
        draw()
        // Tap the last bar: its detail row appears (selected stroke drawn); tapping it again clears it.
        rule.onNodeWithTag("fst.song-detail.history.chart").performTouchInput { click(centerRight.copy(x = width - 44.dp.toPx())) }
        rule.waitForIdle()
        assertTrue(exists("fst.song-detail.history.detail"))
        draw()
        rule.onNodeWithTag("fst.song-detail.history.chart").performTouchInput { click(centerRight.copy(x = width - 44.dp.toPx())) }
        rule.waitForIdle()
        assertFalse(exists("fst.song-detail.history.detail"))
        // A tap on the axis gutter does nothing.
        rule.onNodeWithTag("fst.song-detail.history.chart").performTouchInput { click(centerLeft.copy(x = 4f)) }
        rule.waitForIdle()
        assertFalse(exists("fst.song-detail.history.detail"))
        // Page and step back, then forward again.
        rule.onNodeWithContentDescription("Back one page").performClick()
        rule.onNodeWithContentDescription("Back one entry").performClick()
        rule.onNodeWithContentDescription("Forward one entry").assertIsEnabled().performClick()
        rule.onNodeWithContentDescription("Forward one page").performClick()
        rule.waitForIdle()
        // Five best scores, best highlighted; more than five → View All Scores.
        (0 until 5).forEach { assertTrue(exists("fst.song-detail.history.top.$it")) }
        assertFalse(exists("fst.song-detail.history.top.5"))
        assertTrue(rule.onAllNodes(hasContentDescription("best score", substring = true)).fetchSemanticsNodes().size == 1)
        rule.onNodeWithTag("fst.song-detail.history.view-all").performClick()
        assertEquals(Instrument.Lead, viewAll)
    }

    @Test
    fun shortHistoryHasNoPagerOrViewAllAndSwitchesCharts() {
        show(rows("Solo_Guitar", 3) + rows("Solo_Bass", 2, goldLast = true), initial = Instrument.Bass)
        assertFalse(exists("fst.song-detail.history.pager"))
        assertFalse(exists("fst.song-detail.history.view-all"))
        // The route focus preselects Bass (two rows).
        assertTrue(exists("fst.song-detail.history.top.1"))
        assertFalse(exists("fst.song-detail.history.top.2"))
        draw()
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Guitar").performClick()
        rule.waitForIdle()
        draw()
        assertTrue(exists("fst.song-detail.history.top.2"))
        rule.onNodeWithTag("fst.song-detail.history.chart").assert(
            androidx.compose.ui.test.hasContentDescription("Lead score history: 3 scores", substring = true),
        )
    }

    private fun description(tag: String) =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString()

    @Test
    fun narrowListRowsHideTheSeasonButTheTappedBarDetailShowsIt() {
        // Issue #62: a 411 dp phone is narrower than the web's 520 breakpoint.
        show(rows("Solo_Guitar", 3))
        (0 until 3).forEach { assertFalse(description("fst.song-detail.history.top.$it").contains("Season")) }
        rule.onNodeWithTag("fst.song-detail.history.chart").performTouchInput { click(centerRight.copy(x = width - 60.dp.toPx())) }
        rule.waitForIdle()
        assertTrue(description("fst.song-detail.history.detail").contains("Season 9"))
    }

    @Test
    @Config(qualifiers = "w700dp-h900dp-xxhdpi")
    fun wideListRowsShowTheSeason() {
        show(rows("Solo_Guitar", 3))
        (0 until 3).forEach { assertTrue(description("fst.song-detail.history.top.$it").contains("Season 9")) }
    }

    /** Advance the paused clock until the selector shows [wireId] selected (the click has landed). */
    private fun untilSelected(wireId: String) = rule.mainClock.advanceTimeUntil(timeoutMillis = 2_000) {
        rule.onNodeWithTag("fst.song-detail.history.instrument.$wireId").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Selected) == true
    }

    private fun cardHeight() = rule.onNodeWithTag("fst.song-detail.history.card").getBoundsInRoot().height

    private fun chartSays(text: String) =
        rule.onNodeWithTag("fst.song-detail.history.chart").assert(hasContentDescription(text, substring = true))

    /** Lead pages on a phone (8 > 3 bars), Bass and Drums don't. */
    private val mixed get() = rows("Solo_Guitar", 8) + rows("Solo_Bass", 2) + rows("Solo_Drums", 3, goldLast = true)

    @Test
    fun switchingChartFadesOutSwapsAndFadesInWithoutResizingTheCard() {
        show(mixed)
        rule.waitForIdle()
        val before = cardHeight()
        rule.onNodeWithTag("fst.song-detail.history.pager").assertExists()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        // The selector follows the choice at once; the graph is still fading the old chart out.
        untilSelected("Solo_Bass")
        rule.mainClock.advanceTimeBy(80)
        // Still fading the old chart out, at the same size.
        chartSays("Lead score history")
        assertEquals(before, cardHeight())
        rule.mainClock.advanceTimeBy(200)
        // Swapped and fading in: the pager is gone but its row is still reserved.
        chartSays("Bass score history: 2 scores")
        assertFalse(exists("fst.song-detail.history.pager"))
        assertTrue(exists("fst.song-detail.history.pager-slot"))
        assertEquals(before, cardHeight())
        rule.mainClock.advanceTimeBy(1_000)
        assertEquals(before, cardHeight())
        assertFalse(exists("fst.song-detail.history.top.2"))
        // The reserved slot is silent for TalkBack.
        assertTrue(rule.onAllNodes(hasContentDescription("Back one page")).fetchSemanticsNodes().isEmpty())
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun rapidSwitchesCancelEarlierSwapsAndEndOnTheLastChoice() {
        show(mixed)
        rule.waitForIdle()
        val before = cardHeight()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        rule.mainClock.advanceTimeBy(60)
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Drums").performClick()
        rule.mainClock.advanceTimeBy(60)
        // Back to the shown chart: it just fades back in.
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Guitar").performClick()
        rule.mainClock.advanceTimeBy(1_000)
        chartSays("Lead score history: 8 scores")
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        rule.mainClock.advanceTimeBy(60)
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Drums").performClick()
        rule.mainClock.advanceTimeBy(1_000)
        chartSays("Drums score history: 3 scores")
        assertEquals(before, cardHeight())
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun reducedMotionSwapsAtOnce() {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                SongHistoryCard(mixed, visible = Instrument.entries.toSet(), keyboard = false, initialInstrument = null, onViewAll = {})
            }
        }
        rule.waitForIdle()
        val before = cardHeight()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        // Well inside the 150 ms fade-out: with reduced motion the new chart is already shown.
        untilSelected("Solo_Bass")
        rule.mainClock.advanceTimeBy(50)
        chartSays("Bass score history: 2 scores")
        assertEquals(before, cardHeight())
        rule.mainClock.autoAdvance = true
    }

    private fun topHeight() = rule.onNodeWithTag("fst.song-detail.history.top").getBoundsInRoot().height

    @Test
    fun theBestScoresListEasesToItsNewHeightSoContentBelowDoesNotSnap() {
        // Issue #169: Lead (five rows + View All) → Bass (two rows) moved the cards below at once.
        show(mixed)
        rule.waitForIdle()
        val lead = topHeight()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        untilSelected("Solo_Bass")
        // Fading out: the old list keeps its height.
        rule.mainClock.advanceTimeBy(80)
        assertEquals(lead, topHeight())
        // Swapped and fading in: the list is on its way to the shorter height, not there yet.
        rule.mainClock.advanceTimeBy(200)
        val easing = topHeight()
        assertFalse(exists("fst.song-detail.history.view-all"))
        rule.mainClock.advanceTimeBy(1_000)
        val bass = topHeight()
        assertTrue("easing $easing between $bass and $lead", easing < lead && easing > bass)
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun reducedMotionResizesTheBestScoresListAtOnce() {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                SongHistoryCard(mixed, visible = Instrument.entries.toSet(), keyboard = false, initialInstrument = null, onViewAll = {})
            }
        }
        rule.waitForIdle()
        val lead = topHeight()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        untilSelected("Solo_Bass")
        rule.mainClock.advanceTimeBy(50)
        val swapped = topHeight()
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(swapped < lead)
        assertEquals(swapped, topHeight())
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun hiddenWithoutVisibleHistory() {
        rule.setContent {
            FestivalTheme {
                SongHistoryCard(rows("Solo_Drums", 2), visible = setOf(Instrument.Lead), keyboard = false, initialInstrument = null, onViewAll = {})
            }
        }
        assertFalse(exists("fst.song-detail.history"))
    }

    /** Shows the card at [fontScale] and returns the best (top) row's height in dp. */
    private fun topRowHeightAt(fontScale: Float): Float {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                FestivalTheme {
                    SongHistoryCard(rows("Solo_Guitar", 3, goldLast = true), visible = Instrument.entries.toSet(), keyboard = false, initialInstrument = null, onViewAll = {})
                }
            }
        }
        rule.waitForIdle()
        return rule.onNodeWithTag("fst.song-detail.history.top.0").getBoundsInRoot().height.value
    }

    @Test
    fun largeTextStacksTheTopRowsInsteadOfClippingTheDateOrWrappingTheAccuracy() {
        // Issue #102: at 200% on a phone the one-line row cut the date to "Jan 3," and wrapped "100%" to "100 / %".
        val height = topRowHeightAt(2f)
        // Stacked: the date line (bodyLarge, 48 dp at 200%) over the score/accuracy line, plus padding.
        assertTrue("stacked row is $height dp", height >= 100f)
        assertTrue(description("fst.song-detail.history.top.0").contains("accuracy 100%, full combo, best score"))
    }

    @Test
    fun defaultTextKeepsTheTopRowsOnOneLine() {
        val height = topRowHeightAt(1f)
        assertTrue("one-line row is $height dp", height < 60f)
    }

    @Test
    fun axisHelpersRoundAndFormat() {
        assertEquals(1L, niceMax(0))
        assertEquals(1_000L, niceMax(900))
        assertEquals(60_000L, niceMax(52_000))
        assertEquals("12k", compactScore(12_345))
        assertEquals("999", compactScore(999))
    }
}
