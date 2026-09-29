package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.PopulationTiers
import com.festivalscoretracker.android.core.model.PopulationTiersSerializer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.PlayerRankTier
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.core.profile.PlayerValidScoreVariant
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.presentation.songs.effective
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import java.text.Collator
import java.time.OffsetDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Profile sort modes, Quick Links buckets, invalid-score fallback and Shop pulses (web parity). */
class SongsParityTest {
    private val sorter = SongCatalogSort(Collator.getInstance(Locale.US))
    private val lead = Instrument.Lead
    private val a = Fixtures.song("a", "Alpha", duration = 100).copy(maxScores = mapOf(lead.wireId to 100_000))
    private val b = Fixtures.song("b", "Beta", duration = 150).copy(maxScores = mapOf(lead.wireId to 200_000))
    private val c = Fixtures.song("c", "Gamma", duration = 400, lead = null)
    private val d = Fixtures.song("d", "Delta", duration = null)
    private val songs = listOf(a, b, c, d)
    private val details = mapOf(
        ("a" to lead) to SongScoreDetail(
            90_000, accuracy = 990_000.0, isFullCombo = true, stars = 6, season = 5, difficulty = 3.0, rank = 10, totalEntries = 1000,
            lastPlayedAt = "2026-09-27T00:00:00Z",
        ),
        ("b" to lead) to SongScoreDetail(
            150_000, accuracy = 950_000.0, isFullCombo = false, stars = 4, season = 3, difficulty = 1.0, rank = 500, totalEntries = 1000,
            lastPlayedAt = "2026-01-01T00:00:00Z",
        ),
        ("b" to Instrument.Bass) to SongScoreDetail(10, lastPlayedAt = "2026-09-28T00:00:00Z"),
    )
    private val lookup: (String, Instrument) -> SongScoreDetail? = { id, chart -> details[id to chart] }
    private val scores = SongSortScores(lead, listOf(lead, Instrument.Bass), lookup)
    private val now = OffsetDateTime.parse("2026-09-28T12:00:00Z").toInstant().toEpochMilli()

    private fun order(mode: SongSortMode, ascending: Boolean = true) = sorter.sorted(songs, mode, ascending, scores = scores).map { it.songId }

    // region Sorting

    @Test
    fun scoreModesSortScoredFirstAscendingLikeTheWeb() {
        assertEquals(listOf("a", "b", "d", "c"), order(SongSortMode.Score))
        assertEquals(listOf("c", "d", "b", "a"), order(SongSortMode.Score, ascending = false))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.HasFC))
        assertEquals(listOf("a", "b", "d", "c"), order(SongSortMode.Percentile))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.Percentage))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.Stars))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.Season))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.Difficulty))
    }

    @Test
    fun measuredModesKeepMeasurableSongsFirstInBothDirections() {
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.MaxDistance))
        assertEquals(listOf("a", "b", "c", "d"), order(SongSortMode.MaxDistance, ascending = false))
        assertEquals(listOf("b", "a", "d", "c"), order(SongSortMode.MaxScoreDiff))
        assertEquals(listOf("a", "b", "d", "c"), order(SongSortMode.Intensity))
        assertEquals(listOf("d", "b", "a", "c"), order(SongSortMode.Intensity, ascending = false))
        assertEquals(listOf("a", "b", "d", "c"), order(SongSortMode.LastPlayed))
        assertEquals(listOf("b", "a", "c", "d"), order(SongSortMode.LastPlayed, ascending = false))
        // Intensity works without scores when given a chart; Last Played without scores is title order.
        assertEquals(listOf("a", "b", "d", "c"), sorter.sorted(songs, SongSortMode.Intensity, true, chart = lead).map { it.songId })
        assertEquals(listOf("a", "b", "d", "c"), sorter.sorted(songs, SongSortMode.LastPlayed, true).map { it.songId })
    }

    @Test
    fun compareByModeTreatsMissingAndUnrankedScores() {
        val ranked = SongScoreDetail(1, rank = 1, totalEntries = 10)
        val unranked = SongScoreDetail(1)
        assertEquals(0, sorter.compareByMode(SongSortMode.Score, null, null))
        assertTrue(sorter.compareByMode(SongSortMode.Percentile, ranked, unranked) < 0)
        assertEquals(0, sorter.compareByMode(SongSortMode.Percentile, unranked, unranked))
        assertTrue(sorter.compareByMode(SongSortMode.Percentage, SongScoreDetail(1, 5.0, true), SongScoreDetail(1, 5.0, false)) > 0)
        assertEquals(0, sorter.compareByMode(SongSortMode.Title, ranked, unranked))
        assertEquals(Instrument.Bass, scores.latestPlayed("b")!!.first)
        assertNull(scores.latestPlayed("d"))
    }

    // endregion

    // region Pipeline

    @Test
    fun scoreSortsPauseWithoutTheirInputs() {
        val base = SongListInputs(songs, sort = SongSortMode.Score, hasPlayer = true, scores = lookup, nowEpochMillis = now)
        val noChart = SongListPipeline.run(base, sorter)
        assertEquals(SongSortMode.Title, noChart.effectiveSort)
        assertTrue(noChart.sortPaused!!.contains("needs a single-instrument filter"))

        val hasFc = base.copy(sort = SongSortMode.HasFC)
        val anonymous = SongListPipeline.run(hasFc.copy(hasPlayer = false), sorter)
        assertNull(anonymous.sortPaused)
        assertEquals(SongSortMode.Title, anonymous.effectiveSort)
        assertTrue(SongListPipeline.run(hasFc.copy(scores = null), sorter).sortPaused!!.contains("same update"))

        val live = SongListPipeline.run(hasFc, sorter)
        assertNull(live.sortPaused)
        assertEquals(SongSortMode.HasFC, live.effectiveSort)
        assertEquals(lead, live.sortChart)
        assertEquals(listOf("hasfc:no-fc", "hasfc:fc", "hasfc:no-score"), live.headers.map { it.id })
        assertEquals(listOf(0, 1, 2), live.headers.map { it.firstIndex })
        assertTrue(live.sections.isEmpty())
        assertEquals("Has FC Quick Links", SongQuickLinkBuckets.title(live.effectiveSort))

        val filtered = SongListPipeline.run(base.copy(filter = SongFilter(lead)), sorter)
        assertEquals(SongSortMode.Score, filtered.effectiveSort)
        assertEquals(listOf("a", "b", "d"), filtered.songs.map { it.songId })
        assertEquals(listOf("50k+", "150k+", "No Score"), filtered.headers.map { it.label })
    }

    @Test
    fun catalogueSortsGroupOrIndexWithoutScores() {
        val duration = SongListPipeline.run(SongListInputs(songs, sort = SongSortMode.Duration), sorter)
        assertEquals(listOf("Unknown Duration", "1–2 Minutes", "2–3 Minutes", "6–7 Minutes"), duration.headers.map { it.label })
        assertEquals("fst.songs.section.duration.1to2", duration.headers[1].testTag)
        assertEquals("1 to 2 minutes", duration.headers[1].quickLink.accessibleTitle)
        assertNull(duration.sortChart)
        val title = SongListPipeline.run(SongListInputs(songs), sorter)
        assertTrue(title.headers.isEmpty())
        assertEquals(4, title.sections.size)
        val intensity = SongListPipeline.run(SongListInputs(songs, sort = SongSortMode.Intensity, filter = SongFilter(lead)), sorter)
        assertNull(intensity.sortPaused)
        assertTrue(intensity.headers.isEmpty())
        // Last Played with a chart filter reads only that chart.
        val played = SongListPipeline.run(
            SongListInputs(songs, sort = SongSortMode.LastPlayed, filter = SongFilter(lead), hasPlayer = true, scores = lookup, nowEpochMillis = now),
            sorter,
        )
        assertEquals(listOf("lastplayed:year", "lastplayed:week", "lastplayed:never"), played.headers.map { it.id })
    }

    @Test
    fun groupingKeepsFirstSeenBucketOrder() {
        val offers = mapOf("a" to SongsFixtures.offer("a"), "c" to SongsFixtures.offer("c"))
        val (rows, headers) = SongQuickLinkBuckets.group(listOf(a, b, c), SongBucketContext(SongSortMode.Shop, null, offers))
        assertEquals(listOf(a, c, b), rows)
        assertEquals(listOf(0, 2), headers.map { it.firstIndex })
        assertTrue(SongQuickLinkBuckets.group(emptyList(), SongBucketContext(SongSortMode.Shop, null)).second.isEmpty())
    }

    @Test
    fun overThresholdFilterUsesRawOverThresholdScoresOnlyWhileFiltering() {
        val filter = SongPlayerScoreFilter(overThreshold = setOf(lead))
        val input = SongListInputs(
            songs, playerFilter = filter, hasPlayer = true, filterInvalidScores = true, scores = lookup,
            invalid = { id -> if (id == "a") mapOf(lead to InvalidScoreReason.OverThreshold) else emptyMap() },
        )
        assertEquals(listOf("a"), SongListPipeline.run(input, sorter).songs.map { it.songId })
        val off = SongListPipeline.run(input.copy(filterInvalidScores = false), sorter)
        assertEquals(4, off.songs.size)
        assertNull(off.scoreFilterPaused)
        assertFalse(off.filtersApplied)
    }

    // endregion

    // region Buckets

    private fun bucket(mode: SongSortMode, detail: SongScoreDetail?, song: Song = a): SongBucket =
        SongQuickLinkBuckets.bucket(song, SongBucketContext(mode, lead, scores = SongSortScores(lead, listOf(lead)) { _, _ -> detail }, nowEpochMillis = now))

    @Test
    fun scoreBucketsMatchTheWeb() {
        assertEquals("no-score", bucket(SongSortMode.Score, SongScoreDetail(0)).token)
        assertEquals(SongBucket("50000", "50k+", "50000 or more"), bucket(SongSortMode.Score, SongScoreDetail(75_000)))
        assertEquals("1.2M+", bucket(SongSortMode.Score, SongScoreDetail(1_250_000)).label)
        assertEquals("1M", SongQuickLinkBuckets.compact(1_000_000))
        assertEquals("999", SongQuickLinkBuckets.compact(999))
        listOf(1_000_000.0 to "100", 991_000.0 to "99", 985_000.0 to "98", 960_000.0 to "95", 920_000.0 to "90", 800_000.0 to "lt90").forEach { (acc, token) ->
            assertEquals(token, bucket(SongSortMode.Percentage, SongScoreDetail(1, acc)).token)
        }
        assertEquals("no-score", bucket(SongSortMode.Percentage, SongScoreDetail(1)).token)
        assertEquals(SongBucket("1", "1%", "Top 1%"), bucket(SongSortMode.Percentile, SongScoreDetail(1, rank = 1, totalEntries = 1000)))
        assertEquals("no-rank", bucket(SongSortMode.Percentile, SongScoreDetail(1)).token)
        assertEquals(SongBucket("1", "1★", "1 star"), bucket(SongSortMode.Stars, SongScoreDetail(1, stars = 1)))
        assertEquals("3 stars", bucket(SongSortMode.Stars, SongScoreDetail(1, stars = 3)).spoken)
        assertEquals("no-score", bucket(SongSortMode.Stars, SongScoreDetail(1, stars = 0)).token)
        assertEquals(SongBucket("s7", "S7", "Season 7"), bucket(SongSortMode.Season, SongScoreDetail(1, season = 7)))
        assertEquals("no-season", bucket(SongSortMode.Season, null).token)
        assertEquals("no-score", bucket(SongSortMode.Difficulty, SongScoreDetail(0)).token)
        assertEquals("unknown", bucket(SongSortMode.Difficulty, SongScoreDetail(1)).token)
        assertEquals("Hard", bucket(SongSortMode.Difficulty, SongScoreDetail(1, difficulty = 2.0)).label)
        assertEquals("5.0", bucket(SongSortMode.Difficulty, SongScoreDetail(1, difficulty = 5.0)).label)
        assertEquals("FC", bucket(SongSortMode.HasFC, SongScoreDetail(1, isFullCombo = true)).label)
        assertEquals("no-fc", bucket(SongSortMode.HasFC, SongScoreDetail(1)).token)
        assertEquals("no-score", bucket(SongSortMode.HasFC, null).token)
    }

    @Test
    fun maxScoreBucketsNeedAMaximum() {
        assertEquals("max-unavailable", bucket(SongSortMode.MaxDistance, SongScoreDetail(1), song = c).token)
        assertEquals("no-score", bucket(SongSortMode.MaxDistance, null).token)
        listOf(100_000L to "100", 99_500L to "99", 98_500L to "98", 96_000L to "95", 91_000L to "90", 50_000L to "lt90").forEach { (score, token) ->
            assertEquals(token, bucket(SongSortMode.MaxDistance, SongScoreDetail(score)).token)
        }
        assertEquals("max-unavailable", bucket(SongSortMode.MaxScoreDiff, SongScoreDetail(1), song = c).token)
        assertEquals("no-score", bucket(SongSortMode.MaxScoreDiff, null).token)
        listOf(100_000L to "max", 99_500L to "lt1k", 96_000L to "lt5k", 91_000L to "lt10k", 80_000L to "lt25k", 60_000L to "lt50k", 10_000L to "gte50k")
            .forEach { (score, token) -> assertEquals(token, bucket(SongSortMode.MaxScoreDiff, SongScoreDetail(score)).token) }
    }

    @Test
    fun catalogueAndLastPlayedBuckets() {
        fun played(raw: String?) = bucket(SongSortMode.LastPlayed, raw?.let { SongScoreDetail(1, lastPlayedAt = it) }).token
        assertEquals("today", played("2026-09-28T06:00:00Z"))
        assertEquals("week", played("2026-09-25T00:00:00Z"))
        assertEquals("month", played("2026-09-05T00:00:00Z"))
        assertEquals("year", played("2026-01-05T00:00:00Z"))
        assertEquals("older", played("2024-01-05T00:00:00Z"))
        assertEquals("older", played("not a date"))
        assertEquals("never", played(null))
        val context = SongBucketContext(SongSortMode.Year, null)
        assertEquals("2020s", SongQuickLinkBuckets.bucket(a, context).label)
        assertEquals("unknown", SongQuickLinkBuckets.bucket(a.copy(year = null), context).token)
        assertEquals(SongBucket("#", "#", "Numbers and symbols"), SongQuickLinkBuckets.bucket(a.copy(title = "99 Luftballons"), context.copy(mode = SongSortMode.Title)))
        assertEquals("z", SongQuickLinkBuckets.bucket(a.copy(artist = "Zed"), context.copy(mode = SongSortMode.Artist)).token)
        listOf(30 to "lt1", 90 to "1to2", 150 to "2to3", 599 to "9to10", 600 to "gt10", 0 to "unknown").forEach { (seconds, token) ->
            assertEquals(token, SongQuickLinkBuckets.bucket(a.copy(durationSeconds = seconds), context.copy(mode = SongSortMode.Duration)).token)
        }
        assertEquals(SongBucket("3", "4", "Difficulty 4 of 7"), bucket(SongSortMode.Intensity, null))
        assertEquals("unknown", bucket(SongSortMode.Intensity, null, song = c).token)
    }

    // endregion

    // region Invalid scores

    private fun raw(score: Int, minLeeway: Double? = null, variants: List<PlayerValidScoreVariant>? = null) =
        SongsFixtures.score("a", lead, score).copy(minLeeway = minLeeway, validScores = variants)

    private fun resolve(score: PlayerScore, song: Song? = a, over: Boolean = false) =
        InvalidScorePolicy.resolve(score, SongScoreDetail(score.score.toLong(), rank = score.rank, totalEntries = score.totalEntries), song, lead, 1.0, over)

    @Test
    fun precomputedVariantsSubstituteTheBestValidScore() {
        val tiered = a.copy(populationTiers = mapOf(lead.wireId to PopulationTiers(10, doubleArrayOf(0.5, 1.5), intArrayOf(12, 15))))
        val variant = PlayerValidScoreVariant(80_000, rawAccuracy = 950.0, isFullCombo = true, stars = 5, minLeeway = 0.5, rankTiers = listOf(PlayerRankTier(0.0, 5), PlayerRankTier(1.5, 3)))
        val fallback = resolve(raw(99_000, minLeeway = 2.0, variants = listOf(PlayerValidScoreVariant(95_000, minLeeway = 1.8), variant)), tiered)
        assertEquals(InvalidScoreReason.Fallback, fallback.reason)
        assertEquals(80_000L, fallback.detail!!.score)
        assertEquals(950_000.0, fallback.detail!!.accuracy!!, 0.0)
        assertEquals(true, fallback.detail!!.isFullCombo)
        assertEquals(5, fallback.detail!!.rank)
        assertEquals(12, fallback.detail!!.totalEntries)
        val none = resolve(raw(99_000, minLeeway = 2.0, variants = listOf(PlayerValidScoreVariant(95_000, minLeeway = 1.8))))
        assertEquals(InvalidScoreResolution(null, InvalidScoreReason.NoFallback), none)
        assertEquals(InvalidScoreReason.OverThreshold, resolve(raw(99_000, minLeeway = 2.0), over = true).reason)
        assertNull(resolve(raw(99_000, minLeeway = 0.5)).reason)
        // A variant without tiers keeps the raw rank and population.
        val bare = resolve(raw(99_000, minLeeway = 2.0, variants = listOf(PlayerValidScoreVariant(70_000, minLeeway = 0.0))))
        assertEquals(3, bare.detail!!.rank)
        assertEquals(1000, bare.detail!!.totalEntries)
    }

    @Test
    fun legacyFieldsAndThresholdsJudgeScoresWithoutPrecomputedLeeway() {
        assertEquals(101_000.0, InvalidScorePolicy.threshold(a, lead, 1.0)!!, 0.001)
        assertNull(InvalidScorePolicy.threshold(c, lead, 1.0))
        assertNull(resolve(raw(100_500)).reason)
        assertNull(resolve(raw(500_000), song = c).reason)
        val legacy = raw(102_000).copy(validScore = 99_000, validRank = 7, validStars = 5, validTotalEntries = 900, rawValidAccuracy = 990.0, validIsFullCombo = true)
        val substituted = resolve(legacy)
        assertEquals(InvalidScoreReason.Fallback, substituted.reason)
        assertEquals(SongScoreDetail(99_000, 990_000.0, true, 5, rank = 7, totalEntries = 900), substituted.detail!!.copy(season = null, difficulty = null, lastPlayedAt = null))
        assertEquals(0, resolve(raw(102_000).copy(validScore = 99_000)).detail!!.rank)
        assertEquals(InvalidScoreReason.NoFallback, resolve(raw(102_000)).reason)
        assertNull(InvalidScorePolicy.rankAt(null, 1.0))
        assertTrue(legacy.isWellFormed)
        assertFalse(legacy.copy(validStars = 9).isWellFormed)
    }

    @Test
    fun leaderboardSpotlightUsesTheEffectiveScore() {
        val variant = PlayerValidScoreVariant(80_000, rawAccuracy = 950.0, isFullCombo = false, stars = 5, minLeeway = 0.5, rankTiers = listOf(PlayerRankTier(0.0, 60)))
        val invalid = raw(99_000, minLeeway = 2.0, variants = listOf(variant))
        val shown = invalid.effective(a, lead, 1.0)!!
        assertEquals(80_000, shown.score)
        assertEquals(60, shown.rank)
        assertEquals(950_000.0, shown.accuracy!!, 0.001)
        assertEquals(false, shown.isFullCombo)
        val valid = raw(99_000, minLeeway = 0.5)
        assertTrue(valid.effective(a, lead, 1.0) === valid)
        assertNull(raw(99_000, minLeeway = 2.0).effective(a, lead, 1.0))
    }

    @Test
    fun populationTiersDecodeLenientlyAndPickTheLeewayTotal() {
        val json = """{"songId":"x","title":"X","artist":"Y","populationTiers":{
            "Solo_Guitar":{"bc":10,"t":[{"l":0.5,"t":12},{"l":1.0,"t":15}]},"Solo_Bass":null,"Solo_Drums":{"t":[1,2]},"Solo_Vocals":{"bc":1,"t":[{"l":2.0,"t":3},{"l":1.0,"t":4}]}}}"""
        val song = FestivalApi.JSON.decodeFromString(Song.serializer(), json)
        assertEquals(10, song.filteredPopulation(lead, 0.1))
        assertEquals(12, song.filteredPopulation(lead, 0.7))
        assertEquals(15, song.filteredPopulation(lead, 2.0))
        assertNull(song.filteredPopulation(Instrument.Bass, 1.0))
        assertNull(song.filteredPopulation(Instrument.Drums, 1.0))
        assertNull(song.filteredPopulation(Instrument.Vocals, 1.0))
        assertNull(song.filteredPopulation(Instrument.ProBass, 1.0))
        val encoded = FestivalApi.JSON.encodeToString(PopulationTiersSerializer, song.populationTiers!![lead.wireId]!!)
        assertEquals("""{"bc":10,"t":[{"l":0.5,"t":12},{"l":1.0,"t":15}]}""", encoded)
    }

    @Test
    fun warningsExplainEachVariantLikeTheWeb() {
        val one = InvalidScoreWarning.of("Song", mapOf(lead to InvalidScoreReason.Fallback), null)!!
        assertFalse(one.warning)
        assertEquals("Filtered Score", one.title)
        assertEquals(
            "Song has an invalid, filtered-out score on Lead. The Lead chip reflects the next valid score.\n\n" +
                "To see the absolute highest score you've achieved, toggle off 'Filter Invalid Scores' in App Settings. " +
                "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument.",
            one.message,
        )
        val filtered = InvalidScoreWarning.of("Song", mapOf(lead to InvalidScoreReason.Fallback, Instrument.Bass to InvalidScoreReason.NoFallback), lead)!!
        assertEquals(setOf(lead), filtered.reasons.keys)
        assertTrue(filtered.message.contains("We are showing the next valid score here."))
        assertTrue(filtered.message.endsWith("filter to 'Lead Over CHOpt Threshold' in the Filter modal."))
        val two = InvalidScoreWarning.of("Song", mapOf(Instrument.Bass to InvalidScoreReason.Fallback, lead to InvalidScoreReason.Fallback), null)!!
        assertTrue(two.message.startsWith("Song has an invalid, filtered-out score on Lead and Bass."))
        assertTrue(two.message.contains("The chips for these instruments reflect the next valid score."))
        assertTrue(two.message.contains("absolute highest scores"))
        val three = InvalidScoreWarning.of(
            "Song",
            mapOf(lead to InvalidScoreReason.NoFallback, Instrument.Bass to InvalidScoreReason.OverThreshold, Instrument.Drums to InvalidScoreReason.Fallback),
            null,
        )!!
        assertTrue(three.message.contains("on Lead, Bass, and Drums."))
        assertTrue(three.message.contains("Because there is no valid other score for Lead, the Lead icon chip is red here."))
        assertTrue(three.message.contains("The Bass score shown exceeds the CHOpt maximum."))
        val over = InvalidScoreWarning.of("Song", mapOf(lead to InvalidScoreReason.OverThreshold), null)!!
        assertTrue(over.warning)
        assertEquals("Song has a score on Lead that exceeds the CHOpt maximum. This is the highest unfiltered invalid score.", over.message)
        assertNull(InvalidScoreWarning.of("Song", mapOf(Instrument.Bass to InvalidScoreReason.Fallback), lead))
        assertNull(InvalidScoreWarning.of("Song", emptyMap(), null))
    }

    // endregion

    // region Filters and drafts

    @Test
    fun overThresholdChecksPersistAndApplyOnlyWhileFiltering() {
        val filter = SongPlayerScoreFilter(hasScores = setOf(Instrument.Bass), overThreshold = setOf(lead))
        assertEquals(filter, SongPlayerScoreFilter.decodeSaved(filter.encoded()))
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Bass)), SongPlayerScoreFilter.decodeSaved("""{"missingScores":[],"hasScores":["Solo_Bass"],"missingFCs":[],"hasFCs":[]}"""))
        assertNull(SongPlayerScoreFilter.decodeSaved("""{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":[],"overThreshold":["Nope"]}"""))
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Bass)), filter.effective(false))
        assertEquals(filter, filter.effective(true))
        assertTrue(SongPlayerScoreFilter(overThreshold = setOf(lead)).isActive)
        assertEquals(setOf(lead), filter.with(SongScoreFilterKind.OverThreshold, Instrument.Drums, false).charts(SongScoreFilterKind.OverThreshold))
        assertFalse(SongScoreFilterKind.OverThreshold in SongScoreFilterKind.offered(false))
        assertTrue(SongScoreFilterKind.OverThreshold in SongScoreFilterKind.offered(true))
        val over = SongPlayerScoreFilter(overThreshold = setOf(lead))
        val facts = mapOf("a" to ChartScoreFacts(10, false, overThreshold = true), "b" to ChartScoreFacts(10, false))
        assertEquals(listOf(a), over.filter(listOf(a, b), { id, _ -> facts[id] }, setOf(lead), null))
    }

    @Test
    fun sortDraftOffersModesByPlayerChartAndMetadata() {
        assertEquals(SongSortMode.entries.filter { it.group == SongSortGroup.Catalog }, SongSortDraft.modes(false, false))
        val player = SongSortDraft.modes(hideShop = true, hasPlayer = true)
        assertFalse(SongSortMode.Shop in player)
        assertTrue(SongSortMode.HasFC in player && SongSortMode.LastPlayed in player)
        assertTrue(SongSortDraft.chartModes(false, lead, MetadataField.entries.toSet()).isEmpty())
        assertTrue(SongSortDraft.chartModes(true, null, MetadataField.entries.toSet()).isEmpty())
        val noScore = SongSortDraft.chartModes(true, lead, MetadataField.entries.toSet() - MetadataField.Score)
        assertFalse(SongSortMode.Score in noScore)
        assertTrue(SongSortMode.MaxDistance in noScore && SongSortMode.MaxScoreDiff in noScore)
        assertEquals(SongSortMode.Title to true, SongSortDraft.normalized(SongSortMode.Score, false, null))
        assertEquals(SongSortMode.Score to false, SongSortDraft.normalized(SongSortMode.Score, false, lead))
        assertEquals(SongSortMode.HasFC to false, SongSortDraft.normalized(SongSortMode.HasFC, false, null))
        assertTrue(SongSortMode.LastPlayed.needsScores && !SongSortMode.Intensity.needsScores && SongSortMode.Intensity.needsChart)
        assertEquals(SongSortMode.Title, SongSortMode.fromStored("Nope"))
        assertEquals(SongSortMode.MaxScoreDiff, SongSortMode.fromStored("MaxScoreDiff"))
    }

    @Test
    fun metadataPriorityMovesVisibleFieldsOnly() {
        val visible = MetadataField.entries.toSet() - MetadataField.Percentage
        val draft = SongSortDraft(SongSortMode.Score, true)
        val moved = draft.move(visible, 1, -1)
        assertEquals(listOf(MetadataField.Percentile, MetadataField.Score), moved.metadataOrder.take(2))
        assertEquals(MetadataField.Percentage, moved.metadataOrder.last())
        assertTrue(moved.changed)
        assertEquals(draft.metadataOrder, draft.move(visible, 0, -1).metadataOrder)
        assertEquals(MetadataField.entries, moved.reset().metadataOrder)
        assertEquals(MetadataField.entries - MetadataField.Percentage, SongSortDraft.visiblePriority(MetadataField.entries, visible))
    }

    // endregion

    // region Rows

    private val settings = AppSettings(showInstrumentIcons = false)
    private val source = SongScoreSource(true, detail = lookup)

    @Test
    fun rowsLeadWithTheSortFieldAndShowLastPlayedOnlyWhenSortingByIt() {
        val score = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.Stars, locale = Locale.US).project(a)
        assertEquals(MetadataField.Stars, score.metadata.first().kind)
        assertFalse(score.metadata.any { it.kind == MetadataField.LastPlayed })
        val played = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.LastPlayed, locale = Locale.US).project(a)
        assertEquals(MetadataField.LastPlayed, played.metadata.first().kind)
        val priority = listOf(MetadataField.Season) + (MetadataField.entries - MetadataField.Season)
        val ordered = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.Title, priority, Locale.US).project(a)
        assertEquals(MetadataField.Season, ordered.metadata.first().kind)
        val visual = SongRowProjector(settings.copy(enableVisualOrder = true), SongFilter(lead), 15, null, source, SongSortMode.Title, priority, Locale.US).project(a)
        assertEquals(MetadataField.Score, visual.metadata.first().kind)
    }

    @Test
    fun unfilteredLastPlayedShowsTheMostRecentChart() {
        val chips = SongRowProjector(AppSettings(), SongFilter(), 15, null, source, SongSortMode.LastPlayed, locale = Locale.US).project(b)
        val expected = SongMetadataPolicy.lastPlayedText("2026-09-28T00:00:00Z", Locale.US)
        assertEquals(SongLastPlayed(Instrument.Bass, expected), chips.lastPlayed)
        assertFalse(chips.chips.isEmpty())
        assertTrue(chips.announcement.contains("$expected on Bass"))
        val pills = SongRowProjector(settings, SongFilter(), 15, null, source, SongSortMode.LastPlayed, locale = Locale.US).project(b)
        assertEquals(Instrument.Bass, pills.lastPlayed!!.chart)
        assertFalse(pills.metadata.any { it.kind == MetadataField.LastPlayed })
        assertNull(SongRowProjector(settings, SongFilter(), 15, null, source, SongSortMode.LastPlayed).project(d).lastPlayed)
        assertNull(SongRowProjector(settings.copy(visibleInstruments = setOf(Instrument.Drums)), SongFilter(), 15, null, source, SongSortMode.LastPlayed).project(b).lastPlayed)
    }

    @Test
    fun maxScoreSortsShowScoreOverMaximum() {
        val distance = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.MaxDistance, locale = Locale.US).project(a)
        assertEquals(SongMaxScorePill("90,000", "100,000", "90.0%", 90.0), distance.maxScore)
        assertFalse(distance.metadata.any { it.kind == MetadataField.Score })
        assertTrue(distance.announcement.contains("Score 90,000 of max 100,000, 90.0%"))
        val diff = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.MaxScoreDiff, locale = Locale.US).project(a)
        assertEquals("-10,000", diff.maxScore!!.metric)
        val over = SongRowProjector(settings, SongFilter(lead), 15, null, SongScoreSource(true, detail = { _, _ -> SongScoreDetail(120_000) }), SongSortMode.MaxScoreDiff, locale = Locale.US).project(a)
        assertEquals("+20,000", over.maxScore!!.metric)
        val noMax = SongRowProjector(settings, SongFilter(lead), 15, null, source, SongSortMode.MaxDistance, locale = Locale.US).project(a.copy(maxScores = null))
        assertEquals(SongMaxScorePill("90,000", null, "—", null), noMax.maxScore)
        assertEquals("Score 90,000, max score unavailable", noMax.maxScore!!.announcement)
    }

    @Test
    fun invalidScoresWarnAndExplainMissingFallbacks() {
        val invalid = SongScoreSource(
            true,
            detail = { id, chart -> if (id == "a" && chart == lead) null else lookup(id, chart) },
            invalid = { id -> if (id == "a") mapOf(lead to InvalidScoreReason.NoFallback, Instrument.Karaoke to InvalidScoreReason.Fallback) else emptyMap() },
        )
        val row = SongRowProjector(settings.copy(visibleInstruments = setOf(lead, Instrument.Bass)), SongFilter(lead), 15, null, invalid).project(a)
        assertEquals("No valid score", row.scoreState)
        assertEquals(setOf(lead), row.warning!!.reasons.keys)
        assertTrue(row.announcement.endsWith("Filtered score"))
        val chips = SongRowProjector(AppSettings(), SongFilter(), 15, null, invalid).project(a)
        assertEquals(SongInstrumentStatus.NoScore, chips.chips.first { it.instrument == lead }.status)
        assertEquals(setOf(lead, Instrument.Karaoke), chips.warning!!.reasons.keys)
        val warn = SongRowProjector(AppSettings(), SongFilter(), 15, null, SongScoreSource(true, detail = lookup, invalid = { mapOf(lead to InvalidScoreReason.OverThreshold) })).project(a)
        assertTrue(warn.announcement.endsWith("Score over the CHOpt maximum"))
        assertEquals(ChartScoreFacts(90_000, true, overThreshold = true), SongScoreSource(true, detail = lookup, invalid = { mapOf(lead to InvalidScoreReason.OverThreshold) }).facts!!("a", lead))
    }

    @Test
    fun shopPulsesGreenGoldAndRed() {
        assertEquals(ShopPulse.InShop, ShopPresentationPolicy.pulse(SongsFixtures.offer("a"), false, false))
        assertEquals(ShopPulse.New, ShopPresentationPolicy.pulse(SongsFixtures.offer("a", isNew = true), false, false))
        assertEquals(ShopPulse.LeavingTomorrow, ShopPresentationPolicy.pulse(SongsFixtures.offer("a", leaving = true, isNew = true), false, false))
        assertNull(ShopPresentationPolicy.pulse(SongsFixtures.offer("a"), true, false))
        assertNull(ShopPresentationPolicy.pulse(SongsFixtures.offer("a"), false, true))
        assertNull(ShopPresentationPolicy.pulse(null, false, false))
        val row = SongRowProjector(AppSettings(), SongFilter(), 15, mapOf("a" to SongsFixtures.offer("a")), SongScoreSource.NONE).project(a)
        assertEquals(ShopPulse.InShop, row.pulse)
        assertNull(row.highlight)
        assertTrue(row.announcement.contains("In the Item Shop"))
    }

    // endregion
}
