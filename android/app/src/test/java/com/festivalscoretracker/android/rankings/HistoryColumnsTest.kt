package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.bands.BandDetailProjection
import com.festivalscoretracker.android.core.bands.BandRankHistoryEntry
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.profile.PlayerRankHistorySnapshot
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.rankings.HistoryColumnPlan
import com.festivalscoretracker.android.core.rankings.HistoryRowLayout
import com.festivalscoretracker.android.core.rankings.RankHistoryChart
import com.festivalscoretracker.android.core.rankings.RankHistorySnapshot
import com.festivalscoretracker.android.core.rankings.RankingMetric
import java.time.LocalDate
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Rank-history rows measure their rank and value columns from every chart day, not only the
 * listed rows (web "stable column widths derived from ALL chart history points"), and fall back
 * to stacking only when the widest date no longer fits (`leaderboard-row` R1, issue #594).
 */
class HistoryColumnsTest {
    @Test
    fun leaderboardsColumnTextsCoverEveryDayNotOnlyTheFiveRows() {
        val today = LocalDate.parse("2026-09-30")
        val history = listOf(
            RankHistorySnapshot("2026-09-20", totalScoreRank = 12_345, totalScore = 98_765_432),
            RankHistorySnapshot("2026-09-24", totalScoreRank = 7, totalScore = 1_234),
        )
        val chart = RankHistoryChart.build(history, RankingMetric.TotalScore, today, Locale.US)!!
        val texts = chart.columnTexts(Locale.US)
        assertEquals(chart.points.size, texts.ranks.size)
        assertEquals(RankHistoryChart.RECENT_ROWS, chart.rows.size)
        // The widest rank and value only occur in days older than the five listed rows.
        assertTrue(chart.rows.none { it.rank == "#12,345" })
        assertTrue("#12,345" in texts.ranks && "98,765,432" in texts.values)
        assertEquals(texts.dates.size, texts.values.size)
        assertTrue(chart.rows.all { it.date in texts.dates && it.rank in texts.ranks && it.value in texts.values })
    }

    @Test
    fun profileColumnTextsCoverEverySnapshotAndShowADashWithoutAScore() {
        val snapshots = listOf(
            PlayerRankHistorySnapshot(snapshotDate = "2026-09-01", totalScoreRank = 1_234, totalScore = 12_345_678),
            PlayerRankHistorySnapshot(snapshotDate = "2026-09-02", totalScoreRank = 9, totalScore = null),
        )
        val model = RankHistoryChartModel.build(snapshots, Locale.US)!!
        val texts = model.columnTexts(Locale.US)
        assertEquals(listOf("#1,234", "#9"), texts.ranks)
        assertEquals(listOf("12,345,678", "—"), texts.values)
        assertEquals(2, texts.dates.size)
    }

    @Test
    fun bandColumnTextsCoverEveryRankedSnapshotBeyondTheListedRows() {
        val history = (1..15).map { BandRankHistoryEntry(snapshotDate = "2024-02-%02d".format(it), totalScoreRank = if (it == 1) 10_000 else it, totalScore = it * 1_000L) }
        val ranked = BandDetailProjection.ranked(history, BandRankingMetric.TotalScore)
        val rows = BandDetailProjection.recentRows(ranked, BandRankingMetric.TotalScore, Locale.US)
        val texts = BandDetailProjection.columnTexts(ranked, BandRankingMetric.TotalScore, Locale.US)
        assertEquals(BandDetailProjection.RECENT_ROWS, rows.size)
        assertEquals(15, texts.ranks.size)
        assertTrue(rows.none { it.rankText == "#10,000" })
        assertTrue("#10,000" in texts.ranks)
        assertTrue(rows.all { it.rankText in texts.ranks && it.valueText in texts.values && it.dateText in texts.dates })
    }

    @Test
    fun rowsStayOnOneLineWhileTheWidestDateFitsBesideTheColumns() {
        val plan = HistoryColumnPlan(dateWidth = 90f, rankWidth = 60f, valueWidth = 80f, gap = 12f)
        // 90 + 12 + 60 + 12 + 80 = 254.
        assertEquals(HistoryRowLayout.Line, plan.layoutFor(254f))
        assertEquals(HistoryRowLayout.DateAbove, plan.layoutFor(253.9f))
        // 60 + 12 + 80 = 152.
        assertEquals(HistoryRowLayout.DateAbove, plan.layoutFor(152f))
        assertEquals(HistoryRowLayout.Lines, plan.layoutFor(151f))
    }

    @Test
    fun anUnmeasuredRowUsesOneLine() {
        val plan = HistoryColumnPlan(dateWidth = 900f, rankWidth = 600f, valueWidth = 800f, gap = 12f)
        assertEquals(HistoryRowLayout.Line, plan.layoutFor(Float.NaN))
        assertEquals(HistoryRowLayout.Line, plan.layoutFor(0f))
        assertEquals(HistoryRowLayout.Line, plan.layoutFor(Float.POSITIVE_INFINITY))
    }
}
