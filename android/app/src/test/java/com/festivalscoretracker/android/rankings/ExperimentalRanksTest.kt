package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Settings → Experimental Ranks gate (#541, `experimental-ranks` R1/R2): web
 * `getEnabledRankingMetrics`, `coerceRankingMetric` and `coerceBandRankingMetric`.
 */
class ExperimentalRanksTest {
    @Test
    fun playerMetricsOfferOnlyTotalScoreWhileOff() {
        assertEquals(listOf(RankingMetric.TotalScore), RankingMetric.enabled(experimentalRanks = false))
        assertEquals(RankingMetric.entries.toList(), RankingMetric.enabled(experimentalRanks = true))
        assertFalse(RankingMetric.TotalScore.isExperimental)
        assertTrue(RankingMetric.entries.drop(1).all { it.isExperimental })
    }

    @Test
    fun savedOrRoutedPlayerMetricsFallBackToTotalScoreWhileOff() {
        RankingMetric.entries.forEach { metric ->
            assertEquals(RankingMetric.TotalScore, RankingMetric.coerce(metric, experimentalRanks = false))
            assertEquals(metric, RankingMetric.coerce(metric, experimentalRanks = true))
            assertEquals(RankingMetric.TotalScore, RankingMetric.coerce(metric.wireId, experimentalRanks = false))
            assertEquals(metric, RankingMetric.coerce(metric.wireId, experimentalRanks = true))
        }
        assertEquals(RankingMetric.TotalScore, RankingMetric.coerce(null as RankingMetric?, experimentalRanks = true))
        assertEquals(RankingMetric.TotalScore, RankingMetric.coerce("bogus", experimentalRanks = true))
        assertEquals(RankingMetric.TotalScore, RankingMetric.coerce(null as String?, experimentalRanks = false))
    }

    @Test
    fun bandMetricsAreNarrowedAndGated() {
        assertEquals(listOf(BandRankingMetric.TotalScore), BandRankingMetric.enabled(experimentalRanks = false))
        assertEquals(
            listOf(BandRankingMetric.TotalScore, BandRankingMetric.Adjusted, BandRankingMetric.Weighted, BandRankingMetric.FcRate),
            BandRankingMetric.enabled(experimentalRanks = true),
        )
        BandRankingMetric.entries.forEach { metric ->
            assertEquals(BandRankingMetric.TotalScore, BandRankingMetric.coerce(metric, experimentalRanks = false))
            assertEquals(metric, BandRankingMetric.coerce(metric, experimentalRanks = true))
        }
        assertEquals(BandRankingMetric.TotalScore, BandRankingMetric.coerce(null, experimentalRanks = true))
    }

    @Test
    fun rivalLeaderboardScopesFallBackToTotalScoreWhileOff() {
        RivalRankMetric.entries.forEach { metric ->
            val expected = if (metric == RivalRankMetric.TotalScore) metric else RivalRankMetric.TotalScore
            assertEquals(expected, metric.gated(experimentalRanks = false))
            assertEquals(metric, metric.gated(experimentalRanks = true))
        }
        val weighted = RivalScope.Leaderboard(Instrument.Lead, RivalRankMetric.Weighted)
        assertEquals(RivalScope.Leaderboard(Instrument.Lead), RivalScopes.gated(weighted, experimentalRanks = false))
        assertEquals(weighted, RivalScopes.gated(weighted, experimentalRanks = true))
        val combo = RivalScope.Combo("03")
        assertEquals(combo, RivalScopes.gated(combo, experimentalRanks = false))
    }
}
