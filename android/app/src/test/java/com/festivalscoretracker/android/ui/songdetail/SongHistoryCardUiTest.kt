package com.festivalscoretracker.android.ui.songdetail

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Modifier
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
import com.festivalscoretracker.android.core.shell.GraphListPhase
import com.festivalscoretracker.android.ui.common.GraphListPhaseKey
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
    private fun rows(chart: String, count: Int, goldLast: Boolean = false, baseScore: Long = 50_000L) = (1..count).map { day ->
        val gold = goldLast && day == count
        ScoreHistoryEntry(
            songId = "s-alpha",
            instrument = chart,
            newScore = baseScore + day * 1_000,
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

    private val cardWidth = mutableIntStateOf(0)

    /**
     * Shows three Lead rows in a card exactly [width] wide at [fontScale] (a split pane or
     * hinge half narrower than the window); later calls only resize the card.
     */
    private fun showAt(width: Int, fontScale: Float = 1f, baseScore: Long = 50_000L) {
        val first = cardWidth.intValue == 0
        cardWidth.intValue = width
        if (first) {
            rule.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    FestivalTheme {
                        Box(Modifier.width(cardWidth.intValue.dp)) {
                            SongHistoryCard(rows("Solo_Guitar", 3, baseScore = baseScore), visible = Instrument.entries.toSet(), keyboard = false, initialInstrument = null, onViewAll = {})
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun listSeasons() = (0 until 3).count { description("fst.song-detail.history.top.$it").contains("Season 9") }

    private fun tapLastBar() {
        rule.onNodeWithTag("fst.song-detail.history.chart").performTouchInput { click(centerRight.copy(x = width - 60.dp.toPx())) }
        rule.waitForIdle()
    }

    @Test
    @Config(qualifiers = "w900dp-h900dp-xxhdpi")
    fun theRowsOwnWidthDecidesTheSeasonAtTheBreakpoint() {
        // Issue #170: the rule follows the rows' width, not the 900 dp window: 519 hides, 520 shows.
        showAt(519)
        assertEquals(0, listSeasons())
        tapLastBar()
        assertTrue(description("fst.song-detail.history.detail").contains("Season 9"))
        showAt(520)
        assertEquals(3, listSeasons())
    }

    @Test
    @Config(qualifiers = "w900dp-h900dp-xxhdpi")
    fun largeTextKeepsTheWidthRuleInTheStackedRows() {
        // At 200% the rows stack (issue #102); the season still follows the 520 dp rule.
        showAt(411, fontScale = 2f)
        assertEquals(0, listSeasons())
        tapLastBar()
        assertTrue(description("fst.song-detail.history.detail").contains("Season 9"))
        showAt(600, fontScale = 2f)
        assertEquals(3, listSeasons())
    }

    @Test
    @Config(qualifiers = "w900dp-h900dp-xxhdpi")
    fun largeTextWithLongScoresKeepsTheSeasonFrom520() {
        // Issue #170 review: 200% text and seven-digit scores at the 520 dp boundary still show every season.
        showAt(519, fontScale = 2f, baseScore = 1_234_000L)
        assertEquals(0, listSeasons())
        for (width in listOf(520, 600)) {
            showAt(width)
            assertEquals("season at $width dp", 3, listSeasons())
            assertTrue(description("fst.song-detail.history.top.0").contains("1,23"))
        }
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
        // The best scores end on the last choice too (Drums' three rows, settled).
        rule.mainClock.advanceTimeBy(500)
        assertEquals(GraphListPhase.Idle, listPhase())
        assertTrue(exists("fst.song-detail.history.top.2"))
        assertFalse(exists("fst.song-detail.history.top.3"))
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

    private fun listPhase() = rule.onNodeWithTag("fst.song-detail.history.top").fetchSemanticsNode().config[GraphListPhaseKey]

    @Test
    fun theBestScoresListRunsTheWebGraphCardSequence() {
        // Issue #169 (web useListAnimation): Lead's five rows fade out (200 + 4 × 40 = 360 ms), the
        // list eases to Bass's height (300 ms) with the rows hidden, then Bass's two rows fade in
        // (300 + 60 = 360 ms). View All follows the selection at once, as on the web.
        show(mixed)
        rule.waitForIdle()
        val lead = topHeight()
        assertTrue(exists("fst.song-detail.history.view-all"))
        assertEquals(GraphListPhase.Idle, listPhase())
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Bass").performClick()
        untilSelected("Solo_Bass")
        rule.mainClock.advanceTimeBy(100)
        // Old rows fading out at the old height; View All already gone with Lead's selection.
        assertEquals(GraphListPhase.Out, listPhase())
        assertTrue(exists("fst.song-detail.history.top.4"))
        assertFalse(exists("fst.song-detail.history.view-all"))
        assertEquals(lead, topHeight())
        rule.mainClock.advanceTimeBy(150)
        assertEquals(GraphListPhase.Out, listPhase())
        assertEquals(lead, topHeight())
        // Resize: Bass's rows are in place but hidden while the list eases to the shorter height.
        rule.mainClock.advanceTimeBy(200)
        assertEquals(GraphListPhase.Resize, listPhase())
        assertTrue(exists("fst.song-detail.history.top.1"))
        assertFalse(exists("fst.song-detail.history.top.2"))
        val easing = topHeight()
        // In: the new rows fade in at the new height.
        rule.mainClock.advanceTimeBy(350)
        assertEquals(GraphListPhase.In, listPhase())
        val bass = topHeight()
        assertTrue("easing $easing between $bass and $lead", easing < lead && easing > bass)
        rule.mainClock.advanceTimeBy(500)
        assertEquals(GraphListPhase.Idle, listPhase())
        assertEquals(bass, topHeight())
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun viewAllFollowsTheSelectionAndOpensIt() {
        show(mixed, initial = Instrument.Bass)
        rule.waitForIdle()
        assertFalse(exists("fst.song-detail.history.view-all"))
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.song-detail.history.instrument.Solo_Guitar").performClick()
        untilSelected("Solo_Guitar")
        rule.mainClock.advanceTimeBy(50)
        // Lead has eight scores: View All shows at once while Bass's rows are still fading out.
        assertTrue(exists("fst.song-detail.history.view-all"))
        assertFalse(exists("fst.song-detail.history.top.2"))
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        assertTrue(exists("fst.song-detail.history.top.4"))
        rule.onNodeWithTag("fst.song-detail.history.view-all").performClick()
        assertEquals(Instrument.Lead, viewAll)
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
        assertEquals(GraphListPhase.Idle, listPhase())
        assertFalse(exists("fst.song-detail.history.top.2"))
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

    /** Horizontal runs (left, right, px in the row) and vertical extent of the date row's text ink. */
    private class DateInk(val runs: List<IntRange>, val top: Int, val bottom: Int)

    /** Draws the window and finds the muted date text in [row] (window px), from the plot's bottom [plotBottom]. */
    private fun dateInk(row: androidx.compose.ui.geometry.Rect, plotBottom: Float): DateInk {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        // Textmuted 0x8899AA; anti-aliased edges fall outside the tolerance, which keeps the runs symmetric.
        fun ink(x: Int, y: Int): Boolean {
            val p = bitmap.getPixel(x, y)
            return kotlin.math.abs(((p shr 16) and 0xFF) - 0x88) + kotlin.math.abs(((p shr 8) and 0xFF) - 0x99) + kotlin.math.abs((p and 0xFF) - 0xAA) < 60
        }
        // Scan from the plot's bottom edge to past the row (short of the legend), so text drawn
        // past (or cut at) the row's edges shows.
        val left = row.left.toInt()
        val top = plotBottom.toInt()
        val bottom = (row.bottom + 12).toInt().coerceAtMost(bitmap.height)
        val columns = (left until row.right.toInt()).filter { x -> (top until bottom).any { y -> ink(x, y) } }
        val rows = (top until bottom).filter { y -> (left until row.right.toInt()).any { x -> ink(x, y) } }
        val runs = mutableListOf<IntRange>()
        columns.forEach { x ->
            val last = runs.lastOrNull()
            // Glyphs of one date are a few px apart; two shown dates are at least 8 dp (24 px).
            if (last != null && x - last.last <= 16) runs[runs.lastIndex] = last.first..x else runs += x..x
        }
        return DateInk(runs.map { (it.first - left)..(it.last - left) }, rows.firstOrNull() ?: -1, rows.lastOrNull() ?: -1)
    }

    @Test
    fun largeTextDatesStayWholeAndCentredUnderTheirBars() {
        // #314 review: at 200% the dates outgrew a fixed 18 dp canvas band and were cut off.
        // The date row now grows with the text, and each date stays centred under its bar.
        // A 411 dp card fits all three bars on one page.
        showAt(411, fontScale = 2f)
        val chart = rule.onNodeWithTag("fst.song-detail.history.chart").fetchSemanticsNode().boundsInWindow
        val row = rule.onNodeWithTag("fst.song-detail.history.dates").fetchSemanticsNode().boundsInWindow
        assertTrue("dates sit under the plot", row.top >= chart.bottom)
        assertEquals(chart.left, row.left, 0.5f)
        assertEquals(chart.width, row.width, 0.5f)
        val ink = dateInk(row, chart.bottom)
        // 10 sp at 200% on xxhdpi: 60 px type, so digits are well over 30 px tall.
        assertTrue("date glyphs are ${ink.bottom - ink.top + 1} px tall", ink.bottom - ink.top + 1 >= 30)
        assertTrue("dates start inside the row (${ink.top} vs ${row.top})", ink.top > row.top)
        assertTrue("dates end inside the row (${ink.bottom} vs ${row.bottom})", ink.bottom < row.bottom - 1)
        // Three bars, three whole dates: none reaches the row's ends.
        assertEquals("runs ${ink.runs} in ${row.width}", 3, ink.runs.size)
        assertTrue(ink.runs.first().first > 0 && ink.runs.last().last < row.width.toInt() - 1)
        val axis = 40 * 3f
        val slot = (row.width - 2 * axis) / 3
        ink.runs.forEachIndexed { i, run ->
            val bar = axis + slot * (i + 0.5f)
            val centre = (run.first + run.last) / 2f
            // Within glyph side bearings (4 dp).
            assertEquals("date $i centre", bar, centre, 12f)
        }
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
