package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingsResponse
import com.festivalscoretracker.android.core.rankings.LeaderboardsLayoutPolicy
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rankings.RankingSpotlightPlacement
import com.festivalscoretracker.android.core.rankings.RankingSpotlightSource
import com.festivalscoretracker.android.core.rankings.RankingsResponse
import com.festivalscoretracker.android.core.rankings.SongScoreSpotlight
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.core.rankings.asRankingMetric
import com.festivalscoretracker.android.data.FestivalApi
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class RankingsCoreTest {
    private fun entry(rank: Int, anonymous: Boolean = false) =
        FestivalApi.JSON.decodeFromString(AccountRankingEntry.serializer(), RankingsFixtures.accountRow(rank, anonymous))

    private fun band(rank: Int, withSelected: Boolean = false) =
        FestivalApi.JSON.decodeFromString(BandRankingEntry.serializer(), RankingsFixtures.bandRow("Band_Duets", rank, withSelected))

    // region Metrics

    @Test
    fun metricsParseLabelAndNarrowForBands() {
        assertEquals(RankingMetric.TotalScore, RankingMetric.DEFAULT)
        assertEquals(listOf("Total Score", "Adjusted", "Weighted", "FC Rate", "Max Score"), RankingMetric.entries.map { it.label })
        assertEquals(RankingMetric.FcRate, RankingMetric.fromWireId("fcrate"))
        assertNull(RankingMetric.fromWireId("bogus"))
        assertTrue(RankingMetric.Adjusted.isPercentile && RankingMetric.Weighted.isPercentile)
        assertFalse(RankingMetric.TotalScore.isPercentile)
        assertEquals(BandRankingMetric.TotalScore, RankingMetric.MaxScore.bandMetric)
        assertEquals(BandRankingMetric.Weighted, RankingMetric.Weighted.bandMetric)
        BandRankingMetric.entries.forEach { assertEquals(it.wireId, it.asRankingMetric.wireId) }
    }

    // endregion

    // region Account rows

    @Test
    fun accountRowDispatchesEveryMetric() {
        val row = entry(7)
        RankingMetric.entries.forEach { assertEquals(7, row.rank(it)) }
        assertEquals(0.007, row.ratingValue(RankingMetric.Adjusted), 1e-9)
        assertEquals(7 / 900.0, row.ratingValue(RankingMetric.Weighted), 1e-9)
        assertEquals(118 / 250.0, row.ratingValue(RankingMetric.FcRate), 1e-9)
        assertEquals(49_993_000.0, row.ratingValue(RankingMetric.TotalScore), 0.0)
        assertEquals(0.983, row.ratingValue(RankingMetric.MaxScore), 1e-9)
        assertEquals(1.43, row.bayesianValue(RankingMetric.Adjusted)!!, 1e-9)
        assertEquals(1.13, row.bayesianValue(RankingMetric.Weighted)!!, 1e-9)
        assertNull(row.bayesianValue(RankingMetric.TotalScore))
        assertEquals("118 / 250", row.songsLabel(RankingMetric.FcRate))
        assertEquals("193 / 250", row.songsLabel(RankingMetric.TotalScore))
        assertEquals("Synthetic Player 7", row.name)
        assertTrue(row.hasProfile)
        assertEquals(row.accountId, row.key)
        // Weighted falls back to weightedRating without a raw value; FC Rate is 0 without charted songs.
        assertEquals(0.4, AccountRankingEntry(weightedRating = 0.4).ratingValue(RankingMetric.Weighted), 0.0)
        assertEquals(0.0, AccountRankingEntry(fullComboCount = 3).ratingValue(RankingMetric.FcRate), 0.0)
    }

    @Test
    fun anonymousRowsDecodeAsUnknownUserWithUniqueKeys() {
        val anonymous = entry(3, anonymous = true)
        assertEquals("", anonymous.accountId)
        assertEquals(AccountRankingEntry.UNKNOWN_USER, anonymous.name)
        assertFalse(anonymous.hasProfile)
        assertEquals("anonymous-3-3-3", anonymous.key)
        assertFalse(AccountRankingEntry(accountId = "bad/id").hasProfile)
        assertEquals(AccountRankingEntry.UNKNOWN_USER, AccountRankingEntry(displayName = "  ").name)
    }

    @Test
    fun rankingsResponseValidatesAndCountsPages() {
        val page = FestivalApi.JSON.decodeFromString(RankingsResponse.serializer(), RankingsFixtures.rankings("Solo_Guitar", "totalscore", 1, 25))
        page.validate(Instrument.Lead)
        assertEquals(3, page.pageCount)
        assertEquals(25, page.entries.size)
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.validate(Instrument.Bass) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.copy(page = 0).validate(Instrument.Lead) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.copy(pageSize = 2).validate(Instrument.Lead) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.copy(totalAccounts = -1).validate(Instrument.Lead) }
        assertEquals(1, page.copy(totalAccounts = 0).pageCount)
        assertEquals(5, RankingPaging.pageCount(5, 0))
    }

    @Test
    fun playerRankingAcceptsBlankInstrumentButNotMismatches() {
        val row = entry(RankingsFixtures.SELECTED_RANK)
        PlayerInstrumentRanking(row, "", 60).validate(Instrument.Lead, RankingsFixtures.SELECTED.uppercase())
        PlayerInstrumentRanking(row, "Solo_Guitar", 60).validate(Instrument.Lead, RankingsFixtures.SELECTED)
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { PlayerInstrumentRanking(row, "Solo_Bass", 60).validate(Instrument.Lead, RankingsFixtures.SELECTED) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { PlayerInstrumentRanking(row, "", 60).validate(Instrument.Lead, RankingsFixtures.accountId(1)) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { PlayerInstrumentRanking(row, "", -1).validate(Instrument.Lead, RankingsFixtures.SELECTED) }
    }

    // endregion

    // region Band rows

    @Test
    fun bandRowsFormatRosterAndDispatchMetrics() {
        val row = band(2, withSelected = true)
        BandRankingMetric.entries.forEach { assertEquals(2, row.rank(it)) }
        assertEquals("Member 2A + Unknown User", row.membersLabel)
        assertTrue(row.hasDetail)
        assertTrue(row.includes(RankingsFixtures.SELECTED.uppercase()))
        assertFalse(row.includes(null))
        assertFalse(band(3).includes(RankingsFixtures.SELECTED))
        assertEquals(0.004, row.ratingValue(BandRankingMetric.Adjusted), 1e-9)
        assertEquals(0.9, row.ratingValue(BandRankingMetric.Weighted), 1e-9)
        assertEquals(10 / 250.0, row.ratingValue(BandRankingMetric.FcRate), 1e-9)
        assertEquals(8_999_999_998.0, row.ratingValue(BandRankingMetric.TotalScore), 0.0)
        assertEquals(1.08, row.bayesianValue(BandRankingMetric.Adjusted)!!, 1e-9)
        assertEquals(0.9, row.bayesianValue(BandRankingMetric.Weighted)!!, 1e-9)
        assertNull(row.bayesianValue(BandRankingMetric.FcRate))
        assertEquals("10 / 250", row.songsLabel(BandRankingMetric.FcRate))
        assertEquals("88 / 250", row.songsLabel(BandRankingMetric.TotalScore))
        assertEquals(row.teamKey, row.key)
        assertFalse(BandRankingEntry(bandId = "x", teamKey = "").hasDetail)
        assertFalse(BandRankingEntry(bandId = "a/b", teamKey = "abc").hasDetail)
        assertEquals("band-4-5-6", BandRankingEntry(totalScoreRank = 4, adjustedSkillRank = 5, weightedRank = 6).key)
        assertEquals(0.0, BandRankingEntry().ratingValue(BandRankingMetric.FcRate), 0.0)
    }

    @Test
    fun bandResponseValidates() {
        val page = FestivalApi.JSON.decodeFromString(BandRankingsResponse.serializer(), RankingsFixtures.bandRankings("Band_Trios", "adjusted", 2, 25))
        page.validate(BandType.Trios)
        assertEquals(5, page.entries.size)
        assertEquals(2, page.pageCount)
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.validate(BandType.Quad) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { page.copy(totalTeams = -2).validate(BandType.Trios) }
    }

    // endregion

    // region Formatting

    @Test
    fun ratingFormatsMatchTheWeb() {
        assertEquals("Top 3%", RankingFormatting.rating(0.03, RankingMetric.Adjusted))
        assertEquals("Top 0.03%", RankingFormatting.percentile(0.0003))
        assertEquals("Top 0.01%", RankingFormatting.percentile(0.0))
        assertEquals("Top 100%", RankingFormatting.percentile(3.0))
        // Banker's rounding, like formatPercentileTopExact.
        assertEquals("Top 12%", RankingFormatting.percentile(0.125))
        assertEquals("Top 38%", RankingFormatting.percentile(0.375))
        assertEquals("N/A", RankingFormatting.percentile(Double.NaN))
        assertEquals("97.3%", RankingFormatting.rating(0.9734, RankingMetric.FcRate))
        assertEquals("50.0%", RankingFormatting.rating(0.5, RankingMetric.MaxScore))
        assertEquals("N/A", RankingFormatting.percentage(Double.POSITIVE_INFINITY))
        assertEquals("12,345,678", RankingFormatting.rating(12_345_678.0, RankingMetric.TotalScore, Locale.US))
        assertEquals("N/A", RankingFormatting.wholeNumber(Double.NaN))
        assertEquals("0.0123", RankingFormatting.bayesian(0.0123))
        assertEquals("0.05", RankingFormatting.bayesian(0.05))
        assertEquals("0.0", RankingFormatting.bayesian(0.0))
        assertEquals("0.46", RankingFormatting.bayesian(0.456))
        assertEquals("1.5", RankingFormatting.bayesian(1.46))
        assertEquals("N/A", RankingFormatting.bayesian(Double.NaN))
    }

    @Test
    fun labelsOrdinalsAndDescriptions() {
        assertEquals("#1,234", RankingFormatting.rankLabel(1234, Locale.US))
        val ordinals = listOf(1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 112, 1234).map { RankingFormatting.ordinal(it, Locale.US) }
        assertEquals(listOf("1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "112th", "1,234th"), ordinals)
        assertEquals("869,000 ranked players", RankingFormatting.population(869_000, "player", Locale.US))
        assertEquals("1 ranked band", RankingFormatting.population(1, "band", Locale.US))
        assertEquals("Your rank, #2. Ann. Top 3%. 1 / 2 songs.", RankingFormatting.rowDescription(2, "Ann", "Top 3%", "1 / 2", true, Locale.US))
        assertEquals("#5. Bo. 10. 1 / 2 songs.", RankingFormatting.rowDescription(5, "Bo", "10", "1 / 2", false, Locale.US))
    }

    // endregion

    // region Spotlight

    @Test
    fun spotlightPlacementCoversEveryState() {
        val top = (1..10).map { entry(it) }
        val own = entry(RankingsFixtures.SELECTED_RANK)
        val selected = RankingsFixtures.SELECTED
        assertEquals(RankingSpotlightPlacement.None, RankingSpotlight.placement(null, top, RankingSpotlightSource.NotLoaded))
        assertEquals(RankingSpotlightPlacement.None, RankingSpotlight.placement(" ", top, RankingSpotlightSource.NotLoaded))
        assertEquals(RankingSpotlightPlacement.Inline, RankingSpotlight.placement(top[3].accountId.uppercase(), top, RankingSpotlightSource.NotLoaded))
        assertEquals(RankingSpotlightPlacement.Pending, RankingSpotlight.placement(selected, top, RankingSpotlightSource.NotLoaded))
        assertEquals(RankingSpotlightPlacement.Unranked, RankingSpotlight.placement(selected, top, RankingSpotlightSource.Unranked))
        assertEquals(RankingSpotlightPlacement.Footer(own), RankingSpotlight.placement(selected, top, RankingSpotlightSource.Available(own)))
        // A stale row for another account never shows as the selected player's.
        assertEquals(RankingSpotlightPlacement.Pending, RankingSpotlight.placement(selected, top, RankingSpotlightSource.Available(top[0])))
        assertFalse(RankingSpotlight.isSelected(null, ""))
        assertFalse(RankingSpotlight.isSelected(selected, ""))
    }

    // endregion

    // region Navigation and layout

    @Test
    fun rowRoutesFollowTheWeb() {
        val selected = RankingsFixtures.SELECTED
        assertEquals(StatisticsRoute, RankingNavigation.playerRoute(selected.uppercase(), "Me", selected))
        assertEquals(PlayerRoute(RankingsFixtures.accountId(1), "Them"), RankingNavigation.playerRoute(RankingsFixtures.accountId(1), "Them", selected))
        assertEquals(PlayerRoute(RankingsFixtures.accountId(1), null), RankingNavigation.playerRoute(RankingsFixtures.accountId(1), " ", null))
        assertNull(RankingNavigation.playerRoute("", null, selected))
        val row = band(4)
        assertEquals(BandRoute(row.bandId, null, "Band_Quad", row.teamKey), RankingNavigation.bandRoute(row, BandType.Quad))
        assertNull(RankingNavigation.bandRoute(BandRankingEntry(), BandType.Quad))
    }

    @Test
    fun rowActionLabelsNameTheDestination() {
        assertEquals("Open profile", RankingNavigation.actionLabel(PlayerRoute(RankingsFixtures.accountId(1), "Them")))
        assertEquals("Open your statistics", RankingNavigation.actionLabel(StatisticsRoute))
        assertEquals("Open your page of the full leaderboard", RankingNavigation.actionLabel(SongLeaderboardRoute("s-alpha", "Solo_Guitar", 3)))
    }

    @Test
    fun songFooterProjectsOnlySamePublicationScoresOffThePage() {
        val player = SelectedPlayer(RankingsFixtures.SELECTED, "Me")
        val score = FestivalApi.JSON.decodeFromString(PlayerScore.serializer(), ProfileFixtures.score("s-alpha", rank = 30, acc = 990, fc = true))
        val other = LeaderboardEntry(accountId = RankingsFixtures.accountId(1), score = 1, rank = 1)
        val footer = SongScoreSpotlight.footer(player, score, 7, 7, listOf(other))!!
        assertEquals(RankingsFixtures.SELECTED, footer.accountId)
        assertEquals("Me", footer.displayName)
        assertEquals(30, footer.rank)
        assertEquals(990_000.0, footer.accuracy!!, 0.0)
        assertEquals(true, footer.isFullCombo)
        assertNull(SongScoreSpotlight.footer(player, score, 8, 7, listOf(other)))
        assertNull(SongScoreSpotlight.footer(player, score, null, 7, listOf(other)))
        assertNull(SongScoreSpotlight.footer(player, score, 7, 7, listOf(other.copy(accountId = RankingsFixtures.SELECTED.uppercase()))))
        assertNull(SongScoreSpotlight.footer(null, score, 7, 7, emptyList()))
        assertNull(SongScoreSpotlight.footer(player, null, 7, 7, emptyList()))
        assertEquals(0, SongScoreSpotlight.footer(player, score.copy(rank = null), 7, 7, emptyList())!!.rank)
    }

    @Test
    fun layoutPolicyAdaptsToWidthAndHinge() {
        assertEquals(1, LeaderboardsLayoutPolicy.columns(411))
        assertEquals(1, LeaderboardsLayoutPolicy.columns(640))
        assertEquals(2, LeaderboardsLayoutPolicy.columns(761))
        assertEquals(2, LeaderboardsLayoutPolicy.columns(1000))
        assertEquals(3, LeaderboardsLayoutPolicy.columns(1200))
        assertEquals(4, LeaderboardsLayoutPolicy.columns(2400))
        assertEquals(2, LeaderboardsLayoutPolicy.columns(500, separatingHinge = true))
        assertEquals(1, LeaderboardsLayoutPolicy.columns(100))
        assertFalse(LeaderboardsLayoutPolicy.showsSupportingPane(600))
        assertTrue(LeaderboardsLayoutPolicy.showsSupportingPane(840))
        assertTrue(LeaderboardsLayoutPolicy.showsSupportingPane(600, separatingHinge = true))
    }

    // endregion
}
