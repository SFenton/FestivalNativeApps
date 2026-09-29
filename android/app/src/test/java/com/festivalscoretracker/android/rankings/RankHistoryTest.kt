package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.RankHistoryPlot
import com.festivalscoretracker.android.core.profile.RankHistoryWindow
import com.festivalscoretracker.android.core.rankings.RankHistoryChart
import com.festivalscoretracker.android.core.rankings.RankHistoryRow
import com.festivalscoretracker.android.core.rankings.RankHistoryResponse
import com.festivalscoretracker.android.core.rankings.RankHistorySnapshot
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.rankings.RankingsEndpoints
import com.festivalscoretracker.android.data.rankings.rankHistory
import com.festivalscoretracker.android.testing.FakeTransport
import java.time.LocalDate
import java.util.Locale
import kotlinx.coroutines.test.runTest
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Leaderboards rank-history wire model, chart geometry and read (web `RankHistoryChart`). */
class RankHistoryTest {
    private val today = LocalDate.parse("2026-09-27")

    private fun snapshot(day: String, rank: Int, score: Long? = 1_000L) = RankHistorySnapshot(
        snapshotDate = day,
        adjustedSkillRank = rank + 1,
        weightedRank = rank + 2,
        fcRateRank = rank + 3,
        totalScoreRank = rank,
        maxScorePercentRank = rank + 4,
        adjustedSkillRating = 0.2,
        weightedRating = 0.3,
        fcRate = 0.425,
        totalScore = score,
        maxScorePercent = 0.95,
        rawSkillRating = 0.02,
        rawWeightedRating = null,
        rawMaxScorePercent = 0.96,
    )

    @Test
    fun snapshotsPickTheMetricsRankAndValue() {
        val row = snapshot("2026-09-20", 10)
        assertEquals(listOf(10, 11, 12, 13, 14), RankingMetric.entries.map(row::rank))
        // Raw percentiles win over the Bayesian value (web `getValueField`).
        assertEquals(0.02, row.value(RankingMetric.Adjusted), 0.0)
        assertEquals(0.3, row.value(RankingMetric.Weighted), 0.0)
        assertEquals(0.425, row.value(RankingMetric.FcRate), 0.0)
        assertEquals(1_000.0, row.value(RankingMetric.TotalScore), 0.0)
        assertEquals(0.96, row.value(RankingMetric.MaxScore), 0.0)
        assertEquals(0.0, RankHistorySnapshot("2026-09-20").value(RankingMetric.Weighted), 0.0)
        assertEquals(0.0, RankHistorySnapshot("2026-09-20").value(RankingMetric.TotalScore), 0.0)
        assertNull(RankHistorySnapshot("20-09-2026").date)
        assertNull(RankHistorySnapshot("2026-13-40").date)
    }

    @Test
    fun gapsCarryForwardThroughToday() {
        val points = RankHistoryChart.points(listOf(snapshot("2026-09-24", 5), snapshot("2026-09-22", 7), snapshot("bad", 1)), RankingMetric.TotalScore, today)
        assertEquals((22..27).map { LocalDate.parse("2026-09-$it") }, points.map { it.date })
        assertEquals(listOf(7, 7, 5, 5, 5, 5), points.map { it.rank })
        assertEquals(listOf(false, true, false, true, true, true), points.map { it.synthetic })
        assertTrue(RankHistoryChart.points(emptyList(), RankingMetric.TotalScore, today).isEmpty())
    }

    @Test
    fun valueTextFollowsTheWeb() {
        assertEquals("43%", RankHistoryChart.valueText(0.43, RankingMetric.FcRate, Locale.US))
        assertEquals("42.5%", RankHistoryChart.valueText(0.425, RankingMetric.MaxScore, Locale.US))
        assertEquals("1,234,567", RankHistoryChart.valueText(1_234_567.0, RankingMetric.TotalScore, Locale.US))
        assertEquals("Top 2%", RankHistoryChart.valueText(0.02, RankingMetric.Adjusted, Locale.US))
    }

    @Test
    fun chartFeedsTheSharedWindowAndPlot() {
        val chart = RankHistoryChart.build(listOf(snapshot("2026-09-23", 12, 2_000), snapshot("2026-09-25", 8, 4_000)), RankingMetric.TotalScore, today, Locale.US)!!
        assertEquals(5, chart.points.size)
        assertEquals(listOf(12, 12, 8, 8, 8), chart.snapshots.map { it.totalScoreRank })
        assertEquals(listOf(2_000L, 2_000L, 4_000L, 4_000L, 4_000L), chart.snapshots.map { it.totalScore })
        assertEquals(RankHistoryChart.RECENT_ROWS, chart.rows.size)
        assertEquals(RankHistoryRow("Sep 27, 2026", "#8", "4,000", latest = true), chart.rows.first())
        assertEquals("Total Score rank over 5 days. Latest #8, up 4 places.", chart.summary)
        assertEquals(0, chart.totalAccounts)
        // A narrow window of three bars ending at the newest day, then paged back.
        val window = RankHistoryWindow(chart.snapshots, maxBars = 3)
        // Recharts nice ticks from zero (tickCount 5).
        assertEquals(listOf("4K", "3K", "2K", "1K", "0"), chart.valueTicks(window, Locale.US).map { it.label })
        assertTrue(chart.windowDescription(window, Locale.US).startsWith("Rank history chart, Sep 25, 2026 to Sep 27, 2026. Sep 25, 2026: #8."))
        val plot = RankHistoryPlot.build(window, chart.totalAccounts)
        assertEquals(3, plot.bars.size)
        assertNull(chart.detail(window, Locale.US))
        val tapped = window.toggle(0)
        assertEquals(RankHistoryRow("Sep 25, 2026", "#8", "4,000", latest = false), chart.detail(tapped, Locale.US))
        assertEquals("#12", chart.detail(tapped.backPage(), Locale.US)!!.rank)
        val down = RankHistoryChart.build(listOf(snapshot("2026-09-26", 3), snapshot("2026-09-27", 9)), RankingMetric.TotalScore, today, Locale.US)!!
        assertTrue(down.summary.endsWith("down 6 places."))
        val flat = RankHistoryChart.build(listOf(snapshot("2026-09-27", 3, score = null)), RankingMetric.TotalScore, today, Locale.US)!!
        assertTrue(flat.summary.endsWith("unchanged."))
        assertTrue(flat.valueTicks(RankHistoryWindow(flat.snapshots, 5)).isEmpty())
        assertEquals(1, flat.rows.size)
    }

    @Test
    fun fractionalMetricsAreScaledForThePlotAndLabelledAsPercents() {
        val fc = RankHistoryChart.build(listOf(snapshot("2026-09-27", 3)), RankingMetric.FcRate, today, Locale.US)!!
        assertEquals(6, fc.snapshots.single().totalScoreRank)
        assertEquals(425_000L, fc.snapshots.single().totalScore)
        // 0.43 rounds up to a 0.6 axis in 0.15 steps (web getNiceTickValues).
        assertEquals("60%", fc.valueTicks(RankHistoryWindow(fc.snapshots, 5), Locale.US).first().label)
        assertEquals("42.5%", fc.rows.single().value)
        assertEquals("0.02", RankHistoryChart.axisText(0.02, RankingMetric.Adjusted, Locale.US))
        assertEquals("1.2M", RankHistoryChart.axisText(1_234_567.0, RankingMetric.TotalScore, Locale.US))
        val counted = RankHistoryChart.build(listOf(snapshot("2026-09-27", 3).copy(rankedAccountCount = 500)), RankingMetric.TotalScore, today, Locale.US)!!
        assertEquals(500, counted.totalAccounts)
    }

    @Test
    fun chartIsEmptyWithoutARankForTheMetric() {
        assertNull(RankHistoryChart.build(emptyList(), RankingMetric.TotalScore, today))
        assertNull(RankHistoryChart.build(listOf(RankHistorySnapshot("2026-09-27")), RankingMetric.FcRate, today))
    }

    @Test
    fun responsesAreValidated() {
        val good = RankHistoryResponse("Solo_Guitar", RankingsFixtures.SELECTED.uppercase(), listOf(snapshot("2026-09-20", 1)))
        good.validate(Instrument.Lead, RankingsFixtures.SELECTED)
        listOf(
            good.copy(instrument = "Solo_Bass"),
            good.copy(accountId = "other"),
            good.copy(history = listOf(snapshot("nope", 1))),
            good.copy(history = listOf(snapshot("2026-09-20", -1))),
            good.copy(history = listOf(snapshot("2026-09-20", 1), snapshot("2026-09-20", 2))),
        ).forEach { bad ->
            assertThrows(FestivalApiException.InvalidResponse::class.java) { bad.validate(Instrument.Lead, RankingsFixtures.SELECTED) }
        }
    }

    @Test
    fun historyReadIsExactAndValidated() = runTest {
        val base = "https://fixture.test".toHttpUrl()
        assertEquals(
            "https://fixture.test/api/rankings/Solo_Guitar/${RankingsFixtures.SELECTED}/history?days=30",
            RankingsEndpoints.rankHistory(Instrument.Lead, RankingsFixtures.SELECTED, 30).url(base),
        )
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.rankHistory(Instrument.Lead, "bad id", 30) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.rankHistory(Instrument.Lead, RankingsFixtures.SELECTED, 0) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { RankingsEndpoints.rankHistory(Instrument.Lead, RankingsFixtures.SELECTED, 366) }
        val transport = RankingsFixtures.install(FakeTransport.standard(), unranked = setOf("Solo_Bass"))
        val api = FestivalApi("https://fixture.test", transport)
        assertEquals(3, api.rankHistory(Instrument.Lead, RankingsFixtures.SELECTED, 30).history.size)
        assertTrue(api.rankHistory(Instrument.Bass, RankingsFixtures.SELECTED, 30).history.isEmpty())
        assertTrue(transport.requests.none { it.headers.keys.any { key -> key.startsWith("x-fst-selected", ignoreCase = true) } })
    }
}
