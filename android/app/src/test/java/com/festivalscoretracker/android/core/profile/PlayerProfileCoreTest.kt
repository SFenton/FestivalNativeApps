package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.PopulationTiers
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerProfileCoreTest {
    private fun decode(json: String) = FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), json)

    // region Wire

    @Test
    fun instrumentCodesDecodeSingleCanonicalBits() {
        Instrument.entries.forEach { assertEquals(it, PlayerInstrumentCode.parse(PlayerInstrumentCode.encode(it))) }
        assertEquals("01", PlayerInstrumentCode.encode(Instrument.Lead))
        assertEquals("100", PlayerInstrumentCode.encode(Instrument.ProDrums))
        listOf(null, "1", "03", "0x1", "zz", "200", "0001", "00", "1FF", "0A").forEach { assertNull(it, PlayerInstrumentCode.parse(it)) }
    }

    @Test
    fun profileDecodesScalesAndValidates() {
        val profile = decode(ProfileFixtures.profile())
        assertEquals(PlayerProfileState.Available, profile.validate(Fixtures.ACCOUNT_A))
        val first = profile.scores.first()
        assertEquals(1_000_000.0, first.accuracy!!, 0.0)
        assertNull(first.percentile)
        assertEquals(Instrument.Lead, first.instrument)
        val index = profile.scoreIndex()
        assertEquals(setOf(Instrument.Lead, Instrument.Bass), index["s-alpha"]!!.keys)
        assertEquals(PlayerProfileState.Available, profile.validate(Fixtures.ACCOUNT_A.uppercase()))
    }

    @Test
    fun syncingEnvelopeAndCorruptProfilesAreDistinguished() {
        assertEquals(PlayerProfileState.Syncing, decode(ProfileFixtures.syncing()).validate(Fixtures.ACCOUNT_A))
        val corrupt = listOf(
            ProfileFixtures.profile(account = Fixtures.ACCOUNT_B),
            """{"accountId":"${Fixtures.ACCOUNT_A}","totalScores":2,"scores":[]}""",
            ProfileFixtures.profile(rows = listOf(ProfileFixtures.score("a"), ProfileFixtures.score("a"))),
            ProfileFixtures.profile(rows = listOf(ProfileFixtures.score("a", code = "03"))),
            ProfileFixtures.profile(rows = listOf(ProfileFixtures.score("a", stars = 7))),
            ProfileFixtures.profile(rows = listOf(ProfileFixtures.score("a", acc = 1001))),
            """{"accountId":"${Fixtures.ACCOUNT_A}","status":"syncing","notYetPublished":false,"totalScores":0,"scores":[]}""",
            """{"accountId":"${Fixtures.ACCOUNT_A}","status":"other","totalScores":0,"scores":[]}""",
            """{"accountId":"${Fixtures.ACCOUNT_A}","displayName":" x","totalScores":0,"scores":[]}""",
        )
        corrupt.forEach { json -> assertThrows(json, FestivalApiException.InvalidResponse::class.java) { decode(json).validate(Fixtures.ACCOUNT_A) } }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { decode(ProfileFixtures.profile()).validate("bad id") }
    }

    @Test
    fun normalizedTrimsAndDropsBlankNames() {
        assertEquals("Name", PlayerProfileResponse(displayName = "  Name ").normalized().displayName)
        assertNull(PlayerProfileResponse(displayName = "   ").normalized().displayName)
        assertEquals("a‮b", PlayerProfileResponse(displayName = "a‮b").normalized().displayName)
        assertNull(PlayerProfileResponse().normalized().displayName)
        assertTrue(ProfileText.containsUnsafe("a\u0007"))
        assertFalse(ProfileText.containsUnsafe("Plain name"))
    }

    @Test
    fun variantsValidateRanges() {
        assertTrue(PlayerValidScoreVariant(score = 1, rawAccuracy = 99.0, stars = 6, rankTiers = listOf(PlayerRankTier(0.5, 3))).isWellFormed)
        assertEquals(99_000.0, PlayerValidScoreVariant(rawAccuracy = 99.0).accuracy!!, 0.0)
        assertFalse(PlayerValidScoreVariant(score = -1).isWellFormed)
        assertFalse(PlayerValidScoreVariant(rankTiers = listOf(PlayerRankTier(Double.NaN, 1))).isWellFormed)
        assertFalse(PlayerScore(songId = "a", instrumentCode = "01", validScores = listOf(PlayerValidScoreVariant(stars = 9))).isWellFormed)
        assertFalse(PlayerScore(songId = "a", instrumentCode = "01", rawPercentile = 101.0).isWellFormed)
        assertFalse(PlayerScore(songId = "a", instrumentCode = "01", difficulty = -1.0).isWellFormed)
        assertEquals(12_000.0, PlayerScore(rawValidAccuracy = 12.0).validAccuracy!!, 0.0)
    }

    @Test
    fun payloadSelectabilityNeedsAHeaderMatchingTheCurrentGeneration() {
        val profile = decode(ProfileFixtures.profile())
        assertTrue(PlayerProfilePayload(profile, PlayerProfileState.Available, 7, 7).isSelectable(7))
        assertFalse(PlayerProfilePayload(profile, PlayerProfileState.Available, null, 7).isSelectable(7))
        assertFalse(PlayerProfilePayload(profile, PlayerProfileState.Available, 7, 7).isSelectable(8))
        assertFalse(PlayerProfilePayload(profile, PlayerProfileState.Syncing, 7, 7).isSelectable(7))
        assertTrue(PlayerProfilePayload(profile, PlayerProfileState.Available, 7, 7).belongsTo(Fixtures.ACCOUNT_A.uppercase()))
    }

    // endregion

    // region Statistics

    @Test
    fun statisticsMirrorTheWebAggregates() {
        val profile = decode(ProfileFixtures.profile())
        val overall = PlayerStatistics.overall(profile, setOf(Instrument.Lead, Instrument.Bass))
        assertEquals(3, overall.songsPlayed)
        assertEquals(1, overall.fullComboCount)
        assertEquals(25.0, overall.fullComboPercent, 0.0)
        assertEquals(1, overall.goldStarCount)
        assertEquals(1, overall.fiveStarCount)
        assertEquals(850_000.0, overall.averageAccuracy!!, 0.001)
        assertEquals(1, overall.bestRank)
        assertEquals("s-alpha", overall.bestRankSongId)
        assertEquals(Instrument.Lead, overall.bestRankInstrument)
        val lead = PlayerStatistics.forInstrument(profile, Instrument.Lead)
        assertEquals(3, lead.songsPlayed)
        assertEquals(33.3, lead.fullComboPercent, 0.0)
        val empty = PlayerStatistics.forInstrument(profile, Instrument.Drums)
        assertEquals(0, empty.songsPlayed)
        assertNull(empty.averageAccuracy)
        assertNull(empty.bestRank)
        assertEquals(0, PlayerStatistics.overall(profile, emptySet()).songsPlayed)
    }

    @Test
    fun percentileBucketsPlaceEachRowInItsFirstBand() {
        val profile = decode(ProfileFixtures.profile())
        val lead = PlayerStatistics.percentileBuckets(profile, Instrument.Lead)
        assertEquals(listOf(PlayerPercentileBucket(1, 1), PlayerPercentileBucket(15, 1), PlayerPercentileBucket(80, 1)), lead)
        assertTrue(lead.first().isTopFive)
        assertEquals("Top 15%", lead[1].label)
        assertEquals(listOf(PlayerPercentileBucket(90, 1)), PlayerStatistics.percentileBuckets(profile, Instrument.Bass))
        val bars = PercentileBar.build(lead)
        assertEquals(1f, bars.first().fraction)
        assertTrue(bars.first().gold)
        assertEquals("Top 1%: 1 song", bars.first().announcement)
        assertEquals("Top 5%: 2 songs", PercentileBar("Top 5%", 2, 1f, true).announcement)
        assertTrue(PercentileBar.build(emptyList()).isEmpty())
    }

    @Test
    fun filteredProfileUsesWebFilterPlayerScoresForAnyPlayer() {
        val lead = Instrument.Lead
        val song = { id: String -> Song(id, id, "A", maxScores = mapOf(lead.wireId to 100_000)) }
        val songs = mapOf(
            "valid" to song("valid"),
            "variant" to song("variant").copy(
                populationTiers = mapOf(lead.wireId to PopulationTiers(400, doubleArrayOf(0.5), intArrayOf(450))),
            ),
            "legacy" to song("legacy"),
            "dropped" to song("dropped"),
            "variantNoMl" to song("variantNoMl"),
        )
        val code = PlayerInstrumentCode.encode(lead)
        val rows = listOf(
            PlayerScore("valid", code, 99_000, rank = 40, totalEntries = 500, minLeeway = 0.2),
            // `ml` over the leeway: the first variant at the leeway, its filtered rank and the catalogue's filtered population.
            PlayerScore(
                "variant", code, 105_000, rawAccuracy = 100.0, isFullCombo = true, stars = 6, rank = 1, totalEntries = 500, minLeeway = 5.0,
                validScores = listOf(
                    PlayerValidScoreVariant(103_000, minLeeway = 3.0, rankTiers = listOf(PlayerRankTier(3.0, 2))),
                    PlayerValidScoreVariant(100_500, rawAccuracy = 98.0, isFullCombo = false, stars = 5, minLeeway = 0.5, rankTiers = listOf(PlayerRankTier(0.5, 9), PlayerRankTier(1.0, 7))),
                ),
            ),
            // No `ml`: the CHOpt ceiling decides and the legacy fields replace it.
            PlayerScore("legacy", code, 120_000, rank = 2, totalEntries = 500, validScore = 99_500, validRank = 30, validTotalEntries = 480),
            // `ml` over the leeway with no variant: dropped (web omits it).
            PlayerScore("dropped", code, 110_000, rank = 3, totalEntries = 500, minLeeway = 9.0),
            // No `ml`, over the ceiling, no legacy fallback: a `vs` array is ignored (R4), so it is dropped.
            PlayerScore("variantNoMl", code, 130_000, rank = 4, totalEntries = 500, validScores = listOf(PlayerValidScoreVariant(90_000))),
        )
        val profile = PlayerProfileResponse(Fixtures.ACCOUNT_A, "Viewed", rows.size, rows)

        assertTrue(PlayerStatistics.filtered(profile, songs, null) === profile)
        val filtered = PlayerStatistics.filtered(profile, songs, 1.0)
        assertEquals(listOf("valid", "variant", "legacy"), filtered.scores.map { it.songId })
        assertEquals(3, filtered.totalScores)
        assertTrue(filtered.scores[0] === rows[0])
        with(filtered.scores[1]) {
            assertEquals(100_500, score)
            assertEquals(7, rank)
            assertEquals(450, totalEntries)
            assertEquals(98_000.0, accuracy!!, 0.0)
            assertEquals(false, isFullCombo)
            assertEquals(5, stars)
        }
        with(filtered.scores[2]) {
            assertEquals(99_500, score)
            assertEquals(30, rank)
            assertEquals(480, totalEntries)
        }
        // Best Rank and percentiles come from the effective scores, not the raw rank 1.
        val stats = PlayerStatistics.forInstrument(filtered, lead)
        assertEquals(3, stats.songsPlayed)
        assertEquals(7, stats.bestRank)
        assertEquals("variant", stats.bestRankSongId)
        assertEquals(1, PlayerStatistics.forInstrument(profile, lead).bestRank)
        assertEquals(listOf(PlayerPercentileBucket(2, 1), PlayerPercentileBucket(10, 2)), PlayerStatistics.percentileBuckets(filtered, lead))
        // A leeway that accepts every `ml` score keeps them raw; without `ml` the legacy row still exceeds its ceiling.
        val wide = PlayerStatistics.filtered(profile, songs, 10.0)
        assertEquals(listOf("valid", "variant", "legacy", "dropped"), wide.scores.map { it.songId })
        assertTrue(wide.scores[1] === rows[1] && wide.scores[3] === rows[3])
        assertEquals(99_500, wide.scores[2].score)
    }

    @Test
    fun overThresholdCountUsesTheUnroundedCeilingNotMinLeeway() {
        val lead = Instrument.Lead
        val songs = mapOf("a" to Song("a", "A", "B", maxScores = mapOf(lead.wireId to 100_000)))
        val code = PlayerInstrumentCode.encode(lead)
        // 101,040 is over the 101,000 ceiling at 1.0 even though the service rounds its `ml` to 1.0 (R8).
        val profile = PlayerProfileResponse(Fixtures.ACCOUNT_A, null, 1, listOf(PlayerScore("a", code, 101_040, minLeeway = 1.0)))
        assertEquals(1, PlayerStatistics.overThresholdCount(profile, lead, songs, 1.0))
        assertEquals(0, PlayerStatistics.overThresholdCount(profile, lead, songs, 1.1))
    }

    // endregion

    // region Rankings and charts

    @Test
    fun rankingValidatesAndFormats() {
        val ranking = FestivalApi.JSON.decodeFromString(PlayerInstrumentRanking.serializer(), ProfileFixtures.ranking(rank = 20, total = 500))
        ranking.validate(Instrument.Lead, Fixtures.ACCOUNT_A)
        assertEquals(0.04, ranking.totalScorePercentile!!, 1e-9)
        assertTrue(ranking.isTopFive)
        assertThrows(FestivalApiException.InvalidResponse::class.java) { ranking.validate(Instrument.Lead, Fixtures.ACCOUNT_B) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { ranking.copy(instrument = "Solo_Bass").validate(Instrument.Lead, Fixtures.ACCOUNT_A) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { ranking.copy(totalRankedAccounts = -1).validate(Instrument.Lead, Fixtures.ACCOUNT_A) }
        assertNull(ranking.copy(totalScoreRank = 0).totalScorePercentile)
        assertFalse(ranking.copy(totalScoreRank = 0).isTopFive)
        assertEquals("Top 4%", ProfileFormatting.topPercent(0.04, Locale.US))
        assertEquals("Top 0.50%", ProfileFormatting.topPercent(0.005, Locale.US))
        assertEquals("Top 0.01%", ProfileFormatting.topPercent(0.0, Locale.US))
        assertEquals("N/A", ProfileFormatting.topPercent(Double.NaN, Locale.US))
        assertEquals("#1,234", ProfileFormatting.rank(1234, Locale.US))
        assertEquals("40.5", ProfileFormatting.percent(40.5, Locale.US))
        assertEquals("40", ProfileFormatting.percent(40.0, Locale.US))
    }

    @Test
    fun rankHistoryValidatesAndBuildsAChart() {
        val history = FestivalApi.JSON.decodeFromString(PlayerRankHistory.serializer(), ProfileFixtures.rankHistory())
        history.validate(Instrument.Lead, Fixtures.ACCOUNT_A)
        val ranked = history.rankedChronological
        assertEquals(listOf("2026-09-01", "2026-09-03", "2026-09-04"), ranked.map { it.snapshotDate })
        assertThrows(FestivalApiException.InvalidResponse::class.java) { history.validate(Instrument.Bass, Fixtures.ACCOUNT_A) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) {
            history.copy(history = history.history + history.history.first()).validate(Instrument.Lead, Fixtures.ACCOUNT_A)
        }
        assertThrows(FestivalApiException.InvalidResponse::class.java) {
            history.copy(history = listOf(PlayerRankHistorySnapshot("2026-13-01", totalScoreRank = 1))).validate(Instrument.Lead, Fixtures.ACCOUNT_A)
        }
        assertNull(PlayerRankHistorySnapshot("bad").date)

        val chart = RankHistoryChartModel.build(ranked, Locale.US)!!
        assertEquals("#8 of 500", chart.headline)
        assertEquals("Total Score 1,234,567", chart.totalScoreLine)
        assertEquals("Sep 1", chart.startLabel)
        assertEquals("Sep 4", chart.endLabel)
        assertEquals("3 daily snapshots. Latest rank 8, up 12 places.", chart.summary)
        assertEquals(0f, chart.rankLine.first().x)
        assertTrue(chart.rankLine.last().highlight)
        assertTrue(chart.rankLine.last().y < chart.rankLine.first().y)
        assertEquals("#6", chart.rankTicks.first().label)
        assertEquals(3, chart.scoreBars.size)
        assertEquals(1f, chart.scoreBars.last().height)
        assertNull(RankHistoryChartModel.build(emptyList()))

        val single = RankHistoryChartModel.build(listOf(PlayerRankHistorySnapshot("2026-09-01", totalScoreRank = 3)), Locale.US)!!
        assertEquals(0.5f, single.rankLine.single().x)
        assertTrue(single.scoreBars.isEmpty())
        assertNull(single.totalScoreLine)
        assertEquals("#3", single.headline)
        assertEquals("1 daily snapshot. Latest rank 3, unchanged.", single.summary)
        assertEquals("down 5 places", RankHistoryChartModel.rankTrend(listOf(PlayerRankHistorySnapshot(totalScoreRank = 1), PlayerRankHistorySnapshot(totalScoreRank = 6)), Locale.US).substringAfter(", ").trimEnd('.'))
        assertEquals("No snapshots", RankHistoryChartModel.rankTrend(emptyList()))
        // A constant rank is a single-valued web domain: one tick, the line through the middle.
        assertEquals(0.5f, single.rankLine.single().y)
        assertEquals(listOf("#3"), single.rankTicks.map { it.label })
    }

    // endregion

    // region Score history

    @Test
    fun historyFiltersSortsAndHighlightsTheBest() {
        val response = FestivalApi.JSON.decodeFromString(PlayerHistoryResponse.serializer(), ProfileFixtures.history())
        response.validate(Fixtures.ACCOUNT_A)
        assertThrows(FestivalApiException.InvalidResponse::class.java) { response.copy(count = 9).validate(Fixtures.ACCOUNT_A) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { response.validate(Fixtures.ACCOUNT_B) }
        val rows = PlayerHistoryPayload(response, PlayerHistoryState.Available).entries("s-alpha", Instrument.Lead)
        assertEquals(2, rows.size)
        assertEquals("2024-01-01T00:00:00Z", rows[1].dateKey)
        assertNotNull(rows[1].displayDate)
        assertNull(ScoreHistoryEntry(changedAt = "nope").displayDate)
        assertNotNull(ScoreHistoryEntry(changedAt = "2024-01-01T00:00:00+02:00").displayDate)

        val byScore = PlayerScoreHistorySort.sorted(rows, PlayerScoreSortMode.Score, ascending = false)
        assertEquals(850_000L, byScore.first().newScore)
        assertEquals(0, PlayerScoreHistorySort.highScoreIndex(byScore))
        val ascending = PlayerScoreHistorySort.sorted(rows, PlayerScoreSortMode.Date, ascending = true)
        assertEquals(700_000L, ascending.first().newScore)
        assertEquals(1, PlayerScoreHistorySort.highScoreIndex(ascending))
        assertEquals(39, PlayerScoreHistorySort.sorted(rows, PlayerScoreSortMode.Season, true).first().season)
        val tie = listOf(
            ScoreHistoryEntry(newScore = 5, accuracy = 1.0, isFullCombo = true, changedAt = "b"),
            ScoreHistoryEntry(newScore = 5, accuracy = 1.0, isFullCombo = false, changedAt = "a"),
            ScoreHistoryEntry(newScore = 6, accuracy = 1.0, isFullCombo = false, changedAt = "c"),
        )
        assertEquals(listOf("a", "c", "b"), PlayerScoreHistorySort.sorted(tie, PlayerScoreSortMode.Accuracy, true).map { it.changedAt })
        assertNull(PlayerScoreHistorySort.highScoreIndex(emptyList()))
        assertEquals("Accuracy", PlayerScoreSortMode.Accuracy.label)
    }

    @Test
    fun scoreHistoryChartNeedsTwoDatedRows() {
        val response = FestivalApi.JSON.decodeFromString(PlayerHistoryResponse.serializer(), ProfileFixtures.history())
        val rows = response.history.filter { it.instrument == "Solo_Guitar" }
        val chart = ScoreHistoryChartModel.build(rows, ZoneOffset.UTC, Locale.US)!!
        assertEquals(2, chart.points.size)
        assertEquals(0f, chart.points.first().x)
        assertEquals(1f, chart.points.last().x)
        assertTrue(chart.points.last().highlight)
        assertEquals("Jan 1, 2024", chart.startLabel)
        assertEquals("Jan 5, 2024", chart.endLabel)
        assertEquals(3, chart.ticks.size)
        assertTrue(chart.summary.startsWith("2 score changes from Jan 1, 2024 to Jan 5, 2024. Best 850,000"))
        assertNull(ScoreHistoryChartModel.build(rows.take(1)))
    }

    // endregion
}
