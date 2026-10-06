package com.festivalscoretracker.android.ui.leaderboards

import androidx.activity.ComponentActivity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issue #90: every leaderboard row (rankings, band rankings, song boards and previews, the
 * selected player's row, the loading skeleton and the spotlight placeholder) is the web's
 * 48 dp `entryRow`, so rows match across pages and don't jump when data arrives; large
 * text still grows rows.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LeaderboardRowHeightUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val ranking = AccountRankingEntry(accountId = "b".repeat(32), displayName = "Synthetic Player", songsPlayed = 39, totalChartedSongs = 50, totalScore = 89_000_000, totalScoreRank = 1)
    private val band = BandRankingEntry(teamKey = "synthetic-team", songsPlayed = 12, totalChartedSongs = 50, totalScore = 9_000_000, totalScoreRank = 3)
    private val score = LeaderboardEntry(accountId = "a".repeat(32), displayName = "Synthetic Player", score = 99_900, rank = 12, accuracy = 980_000.0)

    private fun show(fontScale: Float = 1f, content: @Composable () -> Unit) {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    Column(Modifier.width(360.dp).verticalScroll(rememberScrollState())) { content() }
                }
            }
        }
    }

    /** Wraps [content] in a tagged column so its measured height includes the row's own padding. */
    @Composable
    private fun Tagged(tag: String, content: @Composable () -> Unit) = Column(Modifier.testTag(tag)) { content() }

    private fun height(tag: String): Dp = rule.onNodeWithTag(tag, useUnmergedTree = true).getUnclippedBoundsInRoot().height

    private fun assertRowHeight(tag: String) = assertEquals(tag, LEADERBOARD_ROW_MIN_HEIGHT.value, height(tag).value, 0.5f)

    @Test
    fun everyRowSharesTheWebEntryRowHeight() {
        show {
            Tagged("ranking") { AccountRankingRow(ranking, RankingMetric.TotalScore, isSelected = false, route = null, onOpen = {}) }
            Tagged("ranking-selected") { AccountRankingRow(ranking, RankingMetric.TotalScore, isSelected = true, route = null, onOpen = {}) }
            Tagged("band") { BandRankingRow(band, BandRankingMetric.TotalScore, isSelected = true, route = null, onOpen = {}) }
            Tagged("score") { ScoreRow(score, navigable = true) }
            Tagged("score-selected") { ScoreRow(score, isSelected = true, navigable = true) }
            Tagged("spotlight-loading") { SpotlightLoadingRow("loading") }
        }
        listOf("ranking", "ranking-selected", "band", "score", "score-selected", "spotlight-loading").forEach(::assertRowHeight)
    }

    @Test
    fun skeletonFillsTheSameBlockAsLoadedRows() {
        val rows = 5
        show {
            Tagged("skeleton") { RankingsSkeletonRows(rows) }
            Tagged("loaded") {
                Column(verticalArrangement = Arrangement.spacedBy(LEADERBOARD_ROW_GAP)) {
                    repeat(rows) { AccountRankingRow(ranking, RankingMetric.TotalScore, isSelected = false, route = null, onOpen = {}, tag = "row$it") }
                }
            }
        }
        val expected = LEADERBOARD_ROW_MIN_HEIGHT * rows + LEADERBOARD_ROW_GAP * (rows - 1)
        assertEquals(expected.value, height("loaded").value, 0.5f)
        assertEquals(expected.value, height("skeleton").value, 0.5f)
    }

    /**
     * Issue #188: at font scale 2.0 ranking rows stack (rank and name, then rating, the
     * Bayesian value for percentile metrics, and songs), so the overview skeleton takes the
     * stacked shape too and the card does not jump when one-line names arrive.
     */
    @Test
    fun largeTextSkeletonMatchesStackedRows() {
        val rows = 5
        val short = ranking.copy(displayName = "Player", adjustedSkillRating = 0.0123, adjustedSkillRank = 1)
        show(fontScale = 2f) {
            Tagged("skeleton") { RankingsSkeletonRows(rows) }
            Tagged("loaded") {
                Column(verticalArrangement = Arrangement.spacedBy(LEADERBOARD_ROW_GAP)) {
                    repeat(rows) { AccountRankingRow(short, RankingMetric.TotalScore, isSelected = false, route = null, onOpen = {}, tag = "row$it") }
                }
            }
            Tagged("skeleton-percentile") { RankingsSkeletonRows(rows, bayesian = true) }
            Tagged("loaded-percentile") {
                Column(verticalArrangement = Arrangement.spacedBy(LEADERBOARD_ROW_GAP)) {
                    repeat(rows) { AccountRankingRow(short, RankingMetric.Adjusted, isSelected = it == 0, route = null, onOpen = {}, tag = "p$it") }
                }
            }
        }
        assertTrue(height("loaded") > LEADERBOARD_ROW_MIN_HEIGHT * rows)
        assertTrue(height("loaded-percentile") > height("loaded"))
        assertEquals(height("loaded").value, height("skeleton").value, 0.5f)
        assertEquals(height("loaded-percentile").value, height("skeleton-percentile").value, 0.5f)
    }

    /**
     * Issue #188: Adjusted and Weighted rows add a small Bayesian line under the rating;
     * the two-line rating still fits the 48 dp row, as does its skeleton.
     */
    @Test
    fun percentileRowsKeepTheEntryRowHeight() {
        val rated = ranking.copy(adjustedSkillRating = 0.0123, adjustedSkillRank = 1, weightedRating = 0.0456, weightedRank = 1)
        val ratedBand = band.copy(adjustedSkillRating = 0.0123, adjustedSkillRank = 2)
        show {
            Tagged("adjusted") { AccountRankingRow(rated, RankingMetric.Adjusted, isSelected = false, route = null, onOpen = {}) }
            Tagged("weighted") { AccountRankingRow(rated, RankingMetric.Weighted, isSelected = true, route = null, onOpen = {}) }
            Tagged("band-adjusted") { BandRankingRow(ratedBand, BandRankingMetric.Adjusted, isSelected = false, route = null, onOpen = {}) }
            Tagged("skeleton") { RankingsSkeletonRows(1, bayesian = true) }
        }
        listOf("adjusted", "weighted", "band-adjusted", "skeleton").forEach(::assertRowHeight)
    }

    @Test
    fun largeTextStillGrowsRows() {
        show(fontScale = 2f) {
            Tagged("ranking") { AccountRankingRow(ranking, RankingMetric.TotalScore, isSelected = true, route = null, onOpen = {}) }
            Tagged("score") { ScoreRow(score, navigable = true) }
        }
        assertTrue(height("ranking") > LEADERBOARD_ROW_MIN_HEIGHT)
        assertTrue(height("score") > LEADERBOARD_ROW_MIN_HEIGHT)
    }

    /**
     * Issue #149: stacked (font 2.0) ranking rows keep the section's rank width, so a short
     * rank (#9) and a long one (#1,234) indent their names alike.
     */
    @Test
    fun largeTextRankingNamesLineUpWhateverTheRankWidth() {
        val short = ranking.copy(totalScoreRank = 9)
        val long = ranking.copy(accountId = "c".repeat(32), totalScoreRank = 1_234)
        show(fontScale = 2f) {
            CompositionLocalProvider(LocalRankingColumns provides rememberAccountColumns(listOf(short, long), RankingMetric.TotalScore)) {
                AccountRankingRow(short, RankingMetric.TotalScore, isSelected = false, route = null, onOpen = {}, tag = "short")
                AccountRankingRow(long, RankingMetric.TotalScore, isSelected = false, route = null, onOpen = {}, tag = "long")
            }
        }
        rule.waitForIdle()
        assertEquals(nameStart("short"), nameStart("long"))
    }

    /** Leftmost bright pixel of a stacked row's first (name) line, drawn in software. */
    private fun nameStart(tag: String): Int {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        val b = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        // The name line sits above the vertically centred rank.
        val top = b.top.toInt() + 2
        val bottom = (b.top + b.height / 4).toInt()
        for (x in b.left.toInt() until b.right.toInt()) for (y in top until bottom) {
            val p = whole.getPixel(x, y)
            if (((p shr 16) and 0xFF) > 180 && ((p shr 8) and 0xFF) > 180 && (p and 0xFF) > 180) return x
        }
        error("no name pixels in $tag")
    }
}
