package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.data.FestivalApi
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Behavior tests for the Suggestions core beyond the Apple parity fixture. */
class SuggestionCoreTest {
    // region Fixtures

    private fun song(id: String, title: String = "Track $id", artist: String = "Artist $id", year: Int? = 1985, maxLead: Int? = null) = Song(
        songId = id,
        title = title,
        artist = artist,
        year = year,
        difficulty = SongDifficulty(guitar = 2.0, bass = 2.0, drums = 2.0, vocals = 2.0, proGuitar = 2.0, proBass = 2.0, proDrums = 2.0, proCymbals = 2.0, proVocals = 2.0),
        maxScores = maxLead?.let { mapOf(Instrument.Lead.wireId to it) },
    )

    private fun category(key: String, instrument: Instrument? = null, songs: List<SuggestionSongItem> = listOf(SuggestionSongItem(song("a"))), type: SuggestionCategoryType = SuggestionCategoryType.NearFC) =
        SuggestionCategory(key, "Title", "Description", type, instrument, songs)

    /** Scripted RNG: always the same double. */
    private class ConstantRng(private val value: Double) : SuggestionRng {
        override fun nextDouble() = value
        override fun nextInt(maxExclusive: Int) = if (maxExclusive <= 0) 0 else (value * maxExclusive).toInt()
    }

    // endregion

    // region Models

    @Test
    fun rngGuardsNonPositiveBoundsAndStaysInRange() {
        val rng = SeededSuggestionRng(4_294_967_295L)
        assertEquals(0, rng.nextInt(0))
        assertEquals(0, rng.nextInt(-3))
        repeat(200) { assertTrue(rng.nextDouble() in 0.0..<1.0) }
        repeat(200) { assertTrue(rng.nextInt(7) in 0..6) }
    }

    @Test
    fun categoryTypesRoundTripTheirAppleKeys() {
        SuggestionCategoryType.entries.forEach { assertSame(it, SuggestionCategoryType.fromKey(it.key)) }
        assertNull(SuggestionCategoryType.fromKey("leaderboardRivals"))
        assertEquals(13, SuggestionCategoryType.entries.size)
    }

    @Test
    fun rowIdentityIncludesTheChartOnlyWhenPresent() {
        assertEquals("a", SuggestionSongItem(song("a")).id)
        assertEquals("a|Solo_Drums", SuggestionSongItem(song("a"), Instrument.Drums).id)
    }

    @Test
    fun seasonFallsBackToTheHighestScoredSeason() {
        val scores = mapOf("a" to mapOf(Instrument.Lead to SuggestionScore(1, season = 4), Instrument.Bass to SuggestionScore(1, season = null)), "b" to mapOf(Instrument.Drums to SuggestionScore(1, season = 9)))
        assertEquals(12, SuggestionSeason.effective(12, scores))
        assertEquals(9, SuggestionSeason.effective(null, scores))
        assertEquals(9, SuggestionSeason.effective(0, scores))
        assertEquals(0, SuggestionSeason.effective(null, emptyMap()))
    }

    // endregion

    // region Rival index

    private fun entry(id: String, name: String?, vararg samples: RivalsAllSample) =
        RivalsAllEntry(id, name, null, samples.size, 1, 2, 3.5, samples = samples.toList())

    @Test
    fun rivalIndexDedupsLimitsAndSkipsMalformedSamples() {
        val response = RivalsAllResponse(
            "me", listOf("s0", "s1"),
            listOf(
                RivalsAllCombo(
                    "01",
                    above = listOf(
                        entry("r1", null, RivalsAllSample(0, "Solo_Guitar", 10, 5), RivalsAllSample(9, "Solo_Guitar", 1, 1), RivalsAllSample(1, "Bogus", 1, 1)),
                        entry("r2", "Two", RivalsAllSample(0, "Solo_Guitar", 10, 12)),
                    ),
                    below = listOf(entry("r3", "Three", RivalsAllSample(1, "Solo_Bass", 3, 1))),
                ),
                RivalsAllCombo("02", above = listOf(entry("r1", "Renamed", RivalsAllSample(1, "Solo_Drums", 4, 8)))),
            ),
        )
        val index = RivalDataIndex.build(response, limit = 1)
        assertEquals(listOf("r1", "r3"), index.songRivals.map { it.accountId })
        assertEquals("Unknown", index.songRivals[0].displayName)
        assertEquals("below", index.songRivals[1].direction)
        assertEquals(2, index.byRival.getValue("r1").size)
        assertFalse("r2" in index.byRival)
        assertEquals(5, index.closestRivalBySong.getValue("s0:Solo_Guitar").rankDelta)

        val all = RivalDataIndex.build(response)
        assertEquals(-2, all.closestRivalBySong.getValue("s0:Solo_Guitar").rankDelta)
        assertEquals(listOf("r1"), RivalDataIndex.build(response, combo = "02").songRivals.map { it.accountId })
        assertEquals(RivalDataIndex.EMPTY, RivalDataIndex.build(RivalsAllResponse.empty("me")))
    }

    @Test
    fun rivalsAllDecodesTheLiveFallbackShape() {
        val body = """{"accountId":"me","combos":[{"combo":"01","above":[{"accountId":"r","sharedSongCount":2,"aheadCount":1,"behindCount":1,"rivalScore":1.5,"avgSignedDelta":-2.0}]}]}"""
        val response = FestivalApi.JSON.decodeFromString(RivalsAllResponse.serializer(), body)
        assertEquals(emptyList<String>(), response.songs)
        val rival = response.combos[0].above[0]
        assertEquals(emptyList<RivalsAllSample>(), rival.samples)
        assertEquals(-2.0, rival.avgSignedDelta!!, 0.0)
        assertEquals(emptyList<RivalsAllEntry>(), response.combos[0].below)
    }

    // endregion

    // region Filter

    @Test
    fun untouchedFilterIsInactiveAndEncodesEmpty() {
        val filter = SuggestionFilterSettings.DEFAULTS
        assertFalse(filter.isActive)
        assertFalse(filter.allTypesOff)
        assertEquals("", filter.encoded())
        assertEquals(filter, SuggestionFilterSettings.decodeSaved(""))
        assertEquals(filter, SuggestionFilterSettings.decodeSaved(null))
        assertEquals(filter, SuggestionFilterSettings.decodeSaved("{not json"))
        assertEquals(filter, SuggestionFilterSettings.decodeSaved("x".repeat(SuggestionFilterSettings.MAX_STORED_LENGTH + 1)))
    }

    @Test
    fun filterTogglesRoundTripThroughSortedJson() {
        val filter = SuggestionFilterSettings.DEFAULTS
            .withInstrument(Instrument.Bass, false)
            .withGlobalType(SuggestionCategoryType.Stale, false, listOf(Instrument.Lead, Instrument.Drums))
            .withPerInstrumentType(SuggestionCategoryType.NearFC, Instrument.Lead, false)
        assertTrue(filter.isActive)
        assertFalse(filter.isInstrumentEnabled(Instrument.Bass))
        assertFalse(filter.isGlobalEnabled(SuggestionCategoryType.Stale))
        assertFalse(filter.isTypeEnabled(SuggestionCategoryType.Stale, Instrument.Vocals))
        assertFalse(filter.isTypeEnabled(SuggestionCategoryType.NearFC, Instrument.Lead))
        assertTrue(filter.isTypeEnabled(SuggestionCategoryType.NearFC, Instrument.Bass))
        assertTrue(filter.isTypeEnabled(SuggestionCategoryType.NearFC, null))
        assertEquals(setOf(Instrument.Lead), filter.effectiveInstruments(setOf(Instrument.Lead, Instrument.Bass)))
        val encoded = filter.encoded()
        assertTrue(encoded, encoded.startsWith("{\"instrumentOff\":[\"Solo_Bass\"]"))
        assertEquals(filter, SuggestionFilterSettings.decodeSaved(encoded))
        assertEquals(SuggestionFilterSettings.DEFAULTS, filter.withInstrument(Instrument.Bass, true)
            .withGlobalType(SuggestionCategoryType.Stale, true, listOf(Instrument.Lead, Instrument.Drums))
            .withPerInstrumentType(SuggestionCategoryType.NearFC, Instrument.Lead, true))
    }

    @Test
    fun perInstrumentRowsCascadeToTheGlobalSwitch() {
        val rows = listOf(Instrument.Lead, Instrument.Bass)
        val oneOff = SuggestionFilterSettings.DEFAULTS.withPerInstrumentType(SuggestionCategoryType.Unplayed, Instrument.Lead, false, rows)
        assertTrue(oneOff.isGlobalEnabled(SuggestionCategoryType.Unplayed))
        val bothOff = oneOff.withPerInstrumentType(SuggestionCategoryType.Unplayed, Instrument.Bass, false, rows)
        assertFalse(bothOff.isGlobalEnabled(SuggestionCategoryType.Unplayed))
        val oneBack = bothOff.withPerInstrumentType(SuggestionCategoryType.Unplayed, Instrument.Bass, true, rows)
        assertTrue(oneBack.isGlobalEnabled(SuggestionCategoryType.Unplayed))
        assertFalse(oneBack.isTypeEnabled(SuggestionCategoryType.Unplayed, Instrument.Lead))

        var everything = SuggestionFilterSettings.DEFAULTS
        SuggestionCategoryType.entries.forEach { everything = everything.withGlobalType(it, false, emptyList()) }
        assertTrue(everything.allTypesOff)
    }

    @Test
    fun categoryFilterDropsOrTrimsRows() {
        val all = Instrument.entries.toSet()
        val filter = SuggestionFilterSettings.DEFAULTS
        val plain = category("k")
        assertSame(plain, SuggestionCategoryFilter.visible(plain, all, filter))
        assertNull(SuggestionCategoryFilter.visible(plain, all, filter.withGlobalType(SuggestionCategoryType.NearFC, false)))

        val drums = category("d", Instrument.Drums)
        assertSame(drums, SuggestionCategoryFilter.visible(drums, all, filter))
        assertNull(SuggestionCategoryFilter.visible(drums, all - Instrument.Drums, filter))

        val mixed = category("m", songs = listOf(SuggestionSongItem(song("a"), Instrument.Lead), SuggestionSongItem(song("b"), Instrument.Bass), SuggestionSongItem(song("c"))))
        assertSame(mixed, SuggestionCategoryFilter.visible(mixed, all, filter))
        val trimmed = SuggestionCategoryFilter.visible(mixed, all - Instrument.Lead, filter.withPerInstrumentType(SuggestionCategoryType.NearFC, Instrument.Bass, false))!!
        assertEquals(listOf("c"), trimmed.songs.map { it.id })
        val onlyCharted = category("o", songs = listOf(SuggestionSongItem(song("a"), Instrument.Lead)))
        assertNull(SuggestionCategoryFilter.visible(onlyCharted, all - Instrument.Lead, filter))
    }

    // endregion

    // region Row presentation

    @Test
    fun layoutFollowsTheWebKeyTable() {
        val cases = mapOf(
            "song_rival_gap_x" to SuggestionRowLayout.Rival,
            "LB_RIVAL_x" to SuggestionRowLayout.Rival,
            "variety_pack" to SuggestionRowLayout.Hidden,
            "artist_sampler_A" to SuggestionRowLayout.Hidden,
            "artist_unplayed_a" to SuggestionRowLayout.Hidden,
            "unplayed_any" to SuggestionRowLayout.Hidden,
            "samename_Track" to SuggestionRowLayout.Hidden,
            "samename_nearfc_Track" to SuggestionRowLayout.SingleInstrument,
            "unfc_Solo_Guitar" to SuggestionRowLayout.UnfcAccuracy,
            "stale_global_1" to SuggestionRowLayout.Season,
            "almost_elite" to SuggestionRowLayout.Percentile,
            "pct_push_Solo_Bass" to SuggestionRowLayout.Percentile,
            "pct_improve_5" to SuggestionRowLayout.Percentile,
            "same_pct_improve" to SuggestionRowLayout.Percentile,
            "improve_rankings_Solo_Bass" to SuggestionRowLayout.Percentile,
            "near_fc_any" to SuggestionRowLayout.SingleInstrument,
            "almost_six_star" to SuggestionRowLayout.SingleInstrument,
            "more_stars" to SuggestionRowLayout.SingleInstrument,
            "first_plays_mixed" to SuggestionRowLayout.SingleInstrument,
            "star_gains" to SuggestionRowLayout.SingleInstrument,
            "near_max_5k" to SuggestionRowLayout.SingleInstrument,
            "something_else" to SuggestionRowLayout.InstrumentChips,
        )
        cases.forEach { (key, layout) -> assertEquals(key, layout, SuggestionRowPresentation.layoutFor(key)) }
    }

    @Test
    fun percentileTiers() {
        assertEquals(PercentileTier.Top1, SuggestionRowPresentation.tierFor("Top 1%"))
        assertEquals(PercentileTier.Top5, SuggestionRowPresentation.tierFor("Top 5%"))
        assertEquals(PercentileTier.Default, SuggestionRowPresentation.tierFor("Top 10%"))
        assertEquals(PercentileTier.Default, SuggestionRowPresentation.tierFor("Top x%"))
        assertEquals(PercentileTier.Default, SuggestionRowPresentation.tierFor("5%"))
        assertEquals(PercentileTier.Default, SuggestionRowPresentation.tierFor(null))
    }

    @Test
    fun rowPresentationPerLayout() {
        val s = song("a", title = "Alpha", artist = "Band", year = 2001)
        val scores = mapOf("a" to mapOf(Instrument.Lead to SuggestionScore(1, stars = 6, isFullCombo = true, season = 3), Instrument.Bass to SuggestionScore(1, stars = 0, season = 7)))
        val chips = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums)
        fun make(key: String, item: SuggestionSongItem, instrument: Instrument? = null) =
            SuggestionRowPresentation.create(category(key, instrument, listOf(item)), item, scores, chips, Locale.US)

        val rival = make("song_rival_gap_r", SuggestionSongItem(s, Instrument.Lead, rivalName = "AVeryLongRivalName", rivalRankDelta = -3))
        assertEquals("AVeryLongRi…", rival.rivalName)
        assertEquals("-3", rival.rivalDeltaText)
        assertEquals(-1, rival.rivalDeltaSign)
        assertTrue(rival.rivalFromSong)
        assertFalse(make("lb_rival_x", SuggestionSongItem(s, rivalName = "LB", rivalRankDelta = 1)).rivalFromSong)
        assertEquals("Alpha, Band · 2001, Lead, rival AVeryLongRivalName, behind by 3 ranks", rival.accessibleLabel)
        assertEquals("+4", make("song_rival_x", SuggestionSongItem(s, rivalRankDelta = 4)).rivalDeltaText)
        assertNull(make("song_rival_x", SuggestionSongItem(s)).rivalDeltaText)

        val unfc = make("unfc_Solo_Guitar", SuggestionSongItem(s, percent = 99.7), Instrument.Lead)
        assertEquals("99", unfc.accuracyText)
        assertEquals(990_000.0, unfc.accuracyExpanded!!, 0.0)
        assertNull(make("unfc_Solo_Guitar", SuggestionSongItem(s, percent = 0.0)).accuracyText)

        assertEquals("S3", make("stale_Solo_Guitar_1", SuggestionSongItem(s, Instrument.Lead)).seasonText)
        assertEquals("S7", make("stale_global_1", SuggestionSongItem(s)).seasonText)
        assertNull(make("stale_Solo_Drums_1", SuggestionSongItem(s, Instrument.Drums)).seasonText)

        val pct = make("pct_push", SuggestionSongItem(s, Instrument.Bass, percentileDisplay = "Top 2%"))
        assertEquals(PercentileTier.Top5, pct.percentileTier)
        assertEquals("Alpha, Band · 2001, Bass, Top 2%", pct.accessibleLabel)

        val gold = make("star_gains", SuggestionSongItem(s, Instrument.Lead, stars = 6))
        assertEquals(5, gold.starCount)
        assertTrue(gold.goldStars)
        assertEquals(1, make("star_gains", SuggestionSongItem(s, stars = 1)).starCount)
        assertTrue(make("star_gains", SuggestionSongItem(s, stars = 3)).accessibleLabel.endsWith("3 stars"))
        assertTrue(make("star_gains", SuggestionSongItem(s, stars = 1)).accessibleLabel.endsWith("1 star"))
        assertEquals(0, make("near_fc_any", SuggestionSongItem(s, stars = 4)).starCount)

        val chipRow = make("other", SuggestionSongItem(song("a", year = null)))
        assertEquals(listOf(true, false, false), chipRow.chips.map { it.hasScore })
        assertEquals(listOf(true, false, false), chipRow.chips.map { it.isFullCombo })
        assertEquals("Artist a", chipRow.subtitle)
        assertEquals(SuggestionRowLayout.Hidden, make("variety_pack", SuggestionSongItem(s)).layout)
        assertEquals(emptyList<SuggestionInstrumentChip>(), SuggestionRowPresentation.create(category("x"), SuggestionSongItem(s), null, emptyList()).chips)
    }

    // endregion

    // region Generator

    @Test
    fun generatorHelpers() {
        assertNull(SuggestionGenerator.percentileBucket(0.0))
        assertEquals(1, SuggestionGenerator.percentileBucket(0.001))
        assertEquals(100, SuggestionGenerator.percentileBucket(5.0))
        assertNull(SuggestionGenerator.nextLowerThreshold(1))
        assertNull(SuggestionGenerator.nextLowerThreshold(7))
        assertEquals(5, SuggestionGenerator.nextLowerThreshold(10))
        assertTrue(SuggestionGenerator.isNearNextBracket(0.07))
        assertFalse(SuggestionGenerator.isNearNextBracket(0.09))
        assertFalse(SuggestionGenerator.isNearNextBracket(0.005))
        assertFalse(SuggestionGenerator.isNearNextBracket(0.0))
        assertNull(SuggestionGenerator.decadeStart(1969))
        assertNull(SuggestionGenerator.decadeStart(2100))
        assertNull(SuggestionGenerator.decadeStart(null))
        assertEquals(2090, SuggestionGenerator.decadeStart(2099))
        assertEquals("00's", SuggestionGenerator.decadeLabel(2000))
        assertEquals("80's", SuggestionGenerator.decadeLabel(1980))
        assertEquals("A\nB", SuggestionGenerator.trimSpaces("\t A\nB  "))
    }

    @Test
    fun emptySourceProducesNothingAndResetIsSafe() {
        val generator = SuggestionGenerator()
        assertEquals(emptyList<SuggestionCategory>(), generator.getNext(10))
        generator.resetForEndless()
        generator.setRivalData(null)
        assertEquals(emptyList<SuggestionCategory>(), generator.getNext(10))
    }

    @Test
    fun deterministicModeEmitsFixedSizeCategoriesWithoutRepeatsUntilRemix() {
        val songs = (0 until 30).map { song("s$it", year = 1970 + it) }
        val scores = songs.take(20).associate { s ->
            s.songId to mapOf(Instrument.Lead to SuggestionScore(100, accuracy = 960_000.0, isFullCombo = false, stars = 6, season = 2, rank = 3, totalEntries = 100))
        }
        val generator = SuggestionGenerator(SuggestionGenerator.Options(seed = 5, disableSkipping = true, fixedDisplayCount = 0, currentSeason = 9))
        generator.setSource(songs, scores)
        val first = generator.getNext(500)
        assertTrue(first.isNotEmpty())
        assertEquals(first.size, first.map { it.key }.toSet().size)
        assertTrue(first.any { it.key == "near_fc_any" })
        assertTrue(first.all { it.songs.size == 1 })
        assertEquals(emptyList<SuggestionCategory>(), generator.getNext(5))
        generator.resetForEndless()
        assertTrue(generator.getNext(5).isNotEmpty())
    }

    @Test
    fun skipStreakForcesAnEmitOnTheThirdTry() {
        val songs = (0 until 3).map { song("s$it") }
        val scores = songs.associate { it.songId to mapOf(Instrument.Lead to SuggestionScore(1, stars = 6, accuracy = 990_000.0)) }
        // A constant 0.999 never beats any emit probability below 1, so only the skip streak can emit.
        val generator = SuggestionGenerator(SuggestionGenerator.Options(fixedDisplayCount = 2), ConstantRng(0.999))
        generator.setSource(songs, scores)
        val keys = mutableListOf<String>()
        repeat(3) {
            keys += generator.getNext(1000).map { it.key }
            generator.resetForEndless()
        }
        assertTrue(keys.toString(), "unfc_Solo_Guitar" in keys)
    }

    @Test
    fun spotlightNeedsThreeSharedSongsAndIsNotRolled() {
        val songs = (0 until 6).map { song("s$it") }
        val samples = listOf(-5, -2, 3, 40, -30).mapIndexed { i, delta -> RivalsAllSample(i, "Solo_Guitar", 50 + delta, 50) }
        val response = RivalsAllResponse("me", songs.map { it.songId }, listOf(RivalsAllCombo("01", above = listOf(entry("r1", "Rival", *samples.toTypedArray())))))
        val generator = SuggestionGenerator(SuggestionGenerator.Options(seed = 3, currentSeason = 5), ConstantRng(0.999))
        generator.setSource(songs, emptyMap())
        generator.setRivalData(RivalDataIndex.build(response))
        val spotlight = generator.getNext(1000).single { it.key == "song_rival_spotlight_r1" }
        assertEquals(listOf(-2, -5, 3, 40, -30), spotlight.songs.map { it.rivalRankDelta })
        assertTrue(spotlight.songs.all { it.rivalName == "Rival" && it.rivalAccountId == "r1" && it.instrument == Instrument.Lead })
    }

    // endregion
}
