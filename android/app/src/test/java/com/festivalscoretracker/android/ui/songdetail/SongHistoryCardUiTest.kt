package com.festivalscoretracker.android.ui.songdetail

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
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
        assertTrue(rule.onAllNodes(hasText("Accuracy (FC)")).fetchSemanticsNodes().isNotEmpty())
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
        assertFalse(rule.onAllNodes(hasText("Accuracy (FC)")).fetchSemanticsNodes().isNotEmpty())
        rule.onNodeWithTag("fst.song-detail.history.chart").assert(
            androidx.compose.ui.test.hasContentDescription("Lead score history: 3 scores", substring = true),
        )
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

    @Test
    fun axisHelpersRoundAndFormat() {
        assertEquals(1L, niceMax(0))
        assertEquals(1_000L, niceMax(900))
        assertEquals(60_000L, niceMax(52_000))
        assertEquals("12k", compactScore(12_345))
        assertEquals("999", compactScore(999))
    }
}
