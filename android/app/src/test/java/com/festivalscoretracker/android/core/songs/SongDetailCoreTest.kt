package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.data.songs.songHistoryEndpoint
import com.festivalscoretracker.android.data.songs.songScoreHistory
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Instrument Selector rules, Song Detail layout and the song score-history chart. */
class SongDetailCoreTest {
    private val charts = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals)

    // region Instrument selector

    @Test
    fun selectorHidesDisablesAndTogglesLikeTheWeb() {
        val available = InstrumentSelection.available(charts, setOf(Instrument.Bass))
        assertEquals(listOf(Instrument.Lead, Instrument.Drums, Instrument.Vocals), available)
        assertNull(InstrumentSelection.effective(Instrument.Bass, available))
        assertEquals(Instrument.Drums, InstrumentSelection.effective(Instrument.Drums, available))
        assertNull(InstrumentSelection.press(Instrument.Lead, Instrument.Lead, required = false))
        assertEquals(Instrument.Lead, InstrumentSelection.press(Instrument.Lead, Instrument.Lead, required = true))
        assertEquals(Instrument.Drums, InstrumentSelection.press(Instrument.Lead, Instrument.Drums, required = false))
    }

    @Test
    fun selectorGoesCompactWhenTheRowCannotFit() {
        // 4 × 64 + 3 × 12 = 292.
        assertTrue(InstrumentSelection.needsCompact(291f, 4))
        assertFalse(InstrumentSelection.needsCompact(292f, 4))
        assertFalse(InstrumentSelection.needsCompact(0f, 4))
        assertFalse(InstrumentSelection.needsCompact(100f, 0))
    }

    @Test
    fun compactCyclingSkipsDisabledWrapsAndDefers() {
        val disabled = setOf(Instrument.Bass)
        assertEquals(2, InstrumentSelection.nextSelectable(charts, 0, 1, disabled))
        assertEquals(3, InstrumentSelection.nextSelectable(charts, 0, -1, disabled))
        assertEquals(-1, InstrumentSelection.nextSelectable(charts, 0, 1, charts.toSet()))
        assertEquals(InstrumentSelection.Cycle.Select(Instrument.Drums), InstrumentSelection.cycle(charts, Instrument.Lead, 0, 1, false, disabled))
        assertEquals(InstrumentSelection.Cycle.Select(Instrument.Lead), InstrumentSelection.cycle(charts, null, 0, 1, false, disabled))
        assertEquals(InstrumentSelection.Cycle.Select(Instrument.Vocals), InstrumentSelection.cycle(charts, null, 0, -1, false, disabled))
        assertEquals(InstrumentSelection.Cycle.Preview(3), InstrumentSelection.cycle(charts, null, 0, -1, true, disabled))
        assertEquals(InstrumentSelection.Cycle.None, InstrumentSelection.cycle(emptyList(), null, 0, 1, false, emptySet()))
        assertEquals(InstrumentSelection.Cycle.None, InstrumentSelection.cycle(charts, null, 0, 1, false, charts.toSet()))
        assertEquals(InstrumentSelection.Cycle.None, InstrumentSelection.cycle(charts, Instrument.Lead, 0, 1, false, charts.toSet()))
        assertEquals(InstrumentSelection.Cycle.Select(null), InstrumentSelection.compactPress(Instrument.Lead, Instrument.Lead, required = false))
        assertEquals(InstrumentSelection.Cycle.None, InstrumentSelection.compactPress(Instrument.Lead, Instrument.Lead, required = true))
        assertEquals(InstrumentSelection.Cycle.Select(Instrument.Drums), InstrumentSelection.compactPress(null, Instrument.Drums, required = false))
        assertEquals(InstrumentSelection.Cycle.None, InstrumentSelection.compactPress(null, null, required = false))
    }

    // endregion

    // region Layout

    @Test
    fun pageRevealsOnlyWhenEverythingSettled() {
        assertTrue(SongDetailLayout.ready(listOf(false, false), null))
        assertTrue(SongDetailLayout.ready(emptyList(), false))
        assertFalse(SongDetailLayout.ready(listOf(false, true), null))
        assertFalse(SongDetailLayout.ready(listOf(false), true))
    }

    @Test
    fun instrumentCardsUseTwoColumnsOnWidePanesAndAroundHinges() {
        assertEquals(1, SongDetailLayout.columns(380f, 9, hinge = false))
        assertEquals(2, SongDetailLayout.columns(600f, 9, hinge = false))
        assertEquals(2, SongDetailLayout.columns(380f, 9, hinge = true))
        assertEquals(1, SongDetailLayout.columns(900f, 1, hinge = true))
    }


    @Test
    fun itemsFollowTheWebOrderWithBandsLast() {
        val bands = BandType.entries
        val items = SongDetailLayout.items(charts, columns = 2, history = true, hinge = false, bands = bands)
        assertEquals(
            listOf("header", "actions", "intensity", "history", "instruments:Solo_Guitar,Solo_Bass", "instruments:Solo_Drums,Solo_Vocals",
                "bands:Band_Duets", "bands:Band_Trios", "bands:Band_Quad"),
            items.map { it.key },
        )
        assertEquals(6, SongDetailLayout.indexOf(items, "band-Band_Duets"))
        assertEquals(5, SongDetailLayout.indexOf(items, SongDetailLayout.instrumentId(Instrument.Vocals)))
        assertEquals(3, SongDetailLayout.indexOf(items, "score-history"))
        assertNull(SongDetailLayout.indexOf(items, "missing"))
        val single = SongDetailLayout.items(charts, columns = 1, history = false, hinge = false, bands = emptyList())
        assertEquals(listOf("header", "actions", "intensity") + charts.map { "instruments:${it.wireId}" }, single.map { it.key })
    }

    @Test
    fun aHingeSplitsIntensityAndHistoryAndPairsBands() {
        val items = SongDetailLayout.items(charts, columns = 2, history = true, hinge = true, bands = BandType.entries)
        assertEquals(SongDetailItem.HingeSummary(history = true), items[2])
        assertEquals(listOf("intensity", "score-history"), items[2].sections)
        assertEquals(2, SongDetailLayout.indexOf(items, "score-history"))
        assertEquals(listOf("bands:Band_Duets,Band_Trios", "bands:Band_Quad"), items.drop(5).map { it.key })
        assertEquals(listOf("intensity"), SongDetailItem.HingeSummary(history = false).sections)
        val all = Instrument.entries.take(5)
        assertEquals(all.take(3) to all.drop(3), SongDetailLayout.splitIntensity(all))
        assertEquals(listOf(Instrument.Lead) to emptyList<Instrument>(), SongDetailLayout.splitIntensity(listOf(Instrument.Lead)))
    }

    @Test
    fun quickLinksAndFocusMatchTheWeb() {
        val links = SongDetailLayout.quickLinks(listOf(Instrument.Lead, Instrument.Bass), history = true, bands = listOf(BandType.Duets))
        assertEquals(listOf("intensity", "score-history", "instrument-Solo_Guitar", "instrument-Solo_Bass", "band-Band_Duets"), links.map { it.id })
        assertEquals("Song Intensity", links[0].accessibleTitle)
        assertEquals("Lead Leaderboard", links[2].accessibleTitle)
        assertEquals(Instrument.Lead, links[2].instrument)
        assertEquals("Duos Band Leaderboard", links[4].accessibleTitle)
        assertEquals(listOf("intensity", "instrument-Solo_Guitar"), SongDetailLayout.quickLinks(listOf(Instrument.Lead), history = false, bands = emptyList()).map { it.id })
        assertEquals(Instrument.Drums, SongDetailLayout.focus("Solo_Drums", charts))
        assertNull(SongDetailLayout.focus("Solo_PeripheralDrums", charts))
        assertNull(SongDetailLayout.focus("bogus", charts))
        assertNull(SongDetailLayout.focus(null, charts))
    }

    // endregion

    // region History chart

    private fun entry(instrument: String, score: Long, date: String, accuracy: Double? = 990_000.0, fc: Boolean = false) =
        ScoreHistoryEntry(songId = "s-alpha", instrument = instrument, newScore = score, accuracy = accuracy, isFullCombo = fc, season = 4, difficulty = 3.0, changedAt = date)

    @Test
    fun historyPointsAreOldestFirstWithWebLabels() {
        val rows = listOf(
            entry("Solo_Guitar", 900, "2024-08-02T12:00:00Z", 1_000_000.0, fc = true),
            entry("Solo_Guitar", 800, "2024-01-05T00:00:00Z"),
            entry("Solo_Bass", 1, "2024-01-01T00:00:00Z", accuracy = null),
            entry("Solo_Guitar", 700, "not a date"),
        )
        val points = SongHistoryChart.points(rows, Instrument.Lead, ZoneOffset.UTC)
        assertEquals(listOf(800L, 900L), points.map { it.score })
        assertEquals("1/5/24", points.first().dateLabel)
        assertEquals(99.0, points.first().accuracyPercent, 0.001)
        assertTrue(points.last().isGold)
        assertFalse(points.first().isGold)
        assertEquals(3, points.first().difficulty)
        assertEquals(0.0, SongHistoryChart.points(rows, Instrument.Bass, ZoneOffset.UTC).single().accuracyPercent, 0.0)
        assertEquals(mapOf(Instrument.Lead to 3, Instrument.Bass to 1), SongHistoryChart.counts(rows))
        assertEquals(listOf(Instrument.Lead), SongHistoryChart.available(SongHistoryChart.counts(rows), setOf(Instrument.Lead, Instrument.Drums)))
    }

    @Test
    fun historyAutoSelectPrefersCurrentThenLeadThenFirst() {
        assertEquals(Instrument.Bass, SongHistoryChart.resolve(Instrument.Bass, listOf(Instrument.Lead, Instrument.Bass)))
        assertEquals(Instrument.Lead, SongHistoryChart.resolve(Instrument.Drums, listOf(Instrument.Lead, Instrument.Bass)))
        assertEquals(Instrument.Bass, SongHistoryChart.resolve(null, listOf(Instrument.Bass, Instrument.Drums)))
        assertNull(SongHistoryChart.resolve(null, emptyList()))
    }

    @Test
    fun historyTopFiveAndInvalidScoreFilter() {
        val rows = (1..7).map { entry("Solo_Guitar", it * 100L, "2024-01-0${it}T00:00:00Z") }
        val points = SongHistoryChart.points(rows, Instrument.Lead, ZoneOffset.UTC)
        assertEquals(listOf(700L, 600L, 500L, 400L, 300L), SongHistoryChart.top(points).map { it.score })
        val song = Fixtures.song("s-alpha", "Alpha").copy(maxScores = mapOf("Solo_Guitar" to 400))
        val kept = SongHistoryChart.valid(rows + entry("Solo_Unknown", 9_999, "2024-01-01T00:00:00Z"), song, leeway = 0.0)
        assertEquals(listOf(100L, 200L, 300L, 400L, 9_999L), kept.map { it.newScore })
        assertEquals(rows, SongHistoryChart.valid(rows, song, leeway = null))
        assertEquals(rows, SongHistoryChart.valid(rows, Fixtures.song("s-alpha", "Alpha").copy(maxScores = null), leeway = 1.0))
        assertEquals(1, SongHistoryChart.maxBars(10f))
        assertEquals(3, SongHistoryChart.maxBars(3 * 96f + 2 * 8f))
    }

    @Test
    fun historyPagingFollowsTheWebHook() {
        var paging = SongHistoryPaging(size = 10, maxBars = 4)
        assertTrue(paging.needsPaging)
        assertEquals(6 until 10, paging.pageStart until paging.pageEnd)
        assertTrue(paging.forwardDisabled)
        assertFalse(paging.backDisabled)
        paging = paging.step(-4)
        assertEquals(2 until 6, paging.pageStart until paging.pageEnd)
        paging = paging.step(-4)
        assertEquals(0, paging.pageStart)
        assertTrue(paging.backDisabled)
        // Selecting a bar makes the pager step the selection and follow it.
        paging = paging.toggle(1)
        assertEquals(1, paging.selected)
        paging = paging.step(4)
        assertEquals(5, paging.selected)
        assertTrue(paging.selected!! in paging.pageStart until paging.pageEnd)
        paging = paging.step(-5)
        assertEquals(0, paging.selected)
        assertTrue(paging.backDisabled)
        paging = paging.step(20)
        assertEquals(9, paging.selected)
        assertTrue(paging.forwardDisabled)
        paging = paging.toggle(9)
        assertNull(paging.selected)
        val resized = SongHistoryPaging(10, 4, offset = 6, selected = 8).resized(5, 10)
        assertEquals(0, resized.offset)
        assertNull(resized.selected)
        assertFalse(resized.needsPaging)
        assertEquals(SongHistoryPaging(0, 4), SongHistoryPaging(0, 4).step(1))
    }

    @Test
    fun historySwapFadesInstantsAndSettles() {
        assertEquals(SongHistorySwap.Plan.None, SongHistorySwap.plan(Instrument.Lead, null, reduceMotion = false))
        assertEquals(SongHistorySwap.Plan.Instant, SongHistorySwap.plan(null, Instrument.Lead, reduceMotion = false))
        assertEquals(SongHistorySwap.Plan.Settle, SongHistorySwap.plan(Instrument.Lead, Instrument.Lead, reduceMotion = false))
        assertEquals(SongHistorySwap.Plan.Settle, SongHistorySwap.plan(Instrument.Lead, Instrument.Lead, reduceMotion = true))
        assertEquals(SongHistorySwap.Plan.Fade, SongHistorySwap.plan(Instrument.Lead, Instrument.Bass, reduceMotion = false))
        assertEquals(SongHistorySwap.Plan.Instant, SongHistorySwap.plan(Instrument.Lead, Instrument.Bass, reduceMotion = true))
        assertTrue(SongHistorySwap.FADE_OUT_MILLIS < SongHistorySwap.FADE_IN_MILLIS)
    }

    @Test
    fun historyReservesPagerWhenAnySelectableChartPages() {
        val counts = mapOf(Instrument.Lead to 8, Instrument.Bass to 2, Instrument.Drums to 3)
        val all = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums)
        assertTrue(SongHistoryChart.reservesPager(counts, all, maxBars = 2))
        assertFalse(SongHistoryChart.reservesPager(counts, all, maxBars = 8))
        // A hidden chart's long history doesn't reserve space.
        assertFalse(SongHistoryChart.reservesPager(counts, listOf(Instrument.Bass, Instrument.Drums), maxBars = 3))
        assertFalse(SongHistoryChart.reservesPager(counts, listOf(Instrument.Vocals), maxBars = 1))
    }

    // endregion

    // region Song history read

    @Test
    fun songHistoryReadIsKeylessAndScopedToTheSong() = runTest {
        val transport = FakeTransport.standard().apply {
            on("/api/player/${Fixtures.ACCOUNT_A}/history") {
                """{"accountId":"${Fixtures.ACCOUNT_A}","count":2,"history":[
                  {"songId":"s-alpha","instrument":"Solo_Guitar","newScore":5,"newRank":1,"changedAt":"2024-01-01T00:00:00Z"},
                  {"songId":"other","instrument":"Solo_Guitar","newScore":6,"newRank":1,"changedAt":"2024-01-01T00:00:00Z"}]}"""
            }
        }
        val api = FestivalApi("https://fixture.test", transport)
        val payload = api.songScoreHistory(Fixtures.ACCOUNT_A, "s-alpha")
        assertEquals(PlayerHistoryState.Available, payload.state)
        assertEquals(listOf(5L), payload.response.history.map { it.newScore })
        val request = transport.sent("/api/player/${Fixtures.ACCOUNT_A}/history").single()
        assertTrue(request.url.contains("songId=s-alpha"))
        assertFalse(request.url.contains("instrument="))
        transport.requests.forEach(RequestGate::validateKeyless)

        transport.on("/api/player/${Fixtures.ACCOUNT_A}/history", status = 404) { "{}" }
        assertEquals(PlayerHistoryState.Unregistered, api.songScoreHistory(Fixtures.ACCOUNT_A, "s-alpha").state)
        transport.on("/api/player/${Fixtures.ACCOUNT_A}/history", status = 202) { """{"accountId":"${Fixtures.ACCOUNT_A}","count":0,"history":[],"status":"syncing"}""" }
        assertEquals(PlayerHistoryState.Syncing, api.songScoreHistory(Fixtures.ACCOUNT_A, "s-alpha").state)
        transport.on("/api/player/${Fixtures.ACCOUNT_A}/history", status = 500) { "{}" }
        assertThrows(FestivalApiException::class.java) { kotlinx.coroutines.runBlocking { api.songScoreHistory(Fixtures.ACCOUNT_A, "s-alpha") } }
        assertThrows(FestivalApiException.InvalidResource::class.java) { songHistoryEndpoint("", "s-alpha") }
        assertThrows(FestivalApiException.InvalidResource::class.java) { songHistoryEndpoint(Fixtures.ACCOUNT_A, "a/b") }
    }

    // endregion

    // region Filter buckets

    @Test
    fun bucketKeysFollowTheWeb() {
        assertEquals(0, SongPercentileBucket.of(scored = false, rank = 1, totalEntries = 10))
        assertEquals(0, SongPercentileBucket.of(scored = true, rank = 0, totalEntries = 10))
        assertEquals(0, SongPercentileBucket.of(scored = true, rank = 3, totalEntries = null))
        assertEquals(1, SongPercentileBucket.of(scored = true, rank = 1, totalEntries = 1000))
        assertEquals(5, SongPercentileBucket.of(scored = true, rank = 42, totalEntries = 1000))
        assertEquals(10, SongPercentileBucket.of(scored = true, rank = 51, totalEntries = 1000))
        assertEquals(100, SongPercentileBucket.of(scored = true, rank = 2000, totalEntries = 1000))
        assertEquals(6, SongStarsBucket.of(9))
        assertEquals(0, SongStarsBucket.of(null))
        assertEquals(listOf(3, 9, 0), SongSeasonBucket.keys(listOf(9, 3, 3, 0, 5000)))
        assertEquals(0, SongSeasonBucket.of(scored = false, season = 7))
        assertEquals(7, SongSeasonBucket.of(scored = true, season = 7))
        assertEquals(0, SongIntensityBucket.of(null))
        assertEquals(0, SongIntensityBucket.of(Double.NaN))
        assertEquals(1, SongIntensityBucket.of(0.0))
        assertEquals(4, SongIntensityBucket.of(3.5))
        assertEquals(7, SongIntensityBucket.of(9.0))
        assertEquals(0, ChartScoreFacts(5, null).bucket(SongBucketKind.Intensity))
        assertEquals(0, ChartScoreFacts(0, null, stars = 5).bucket(SongBucketKind.Stars))
    }

    @Test
    fun playerBucketsApplyOnlyWithOneVisibleInstrument() {
        val a = Fixtures.song("a", "A")
        val b = Fixtures.song("b", "B")
        val c = Fixtures.song("c", "C")
        val facts = mapOf(
            "a" to ChartScoreFacts(100, true, stars = 6, season = 9, rank = 1, totalEntries = 1000),
            "b" to ChartScoreFacts(50, false, stars = 3, season = 4, rank = 900, totalEntries = 1000),
        )
        val lookup = { id: String, chart: Instrument -> if (chart == Instrument.Lead) facts[id] else null }
        val songs = listOf(a, b, c)
        val all = Instrument.entries.toSet()
        val gold = SongPlayerScoreFilter().onlyStars(6)
        assertTrue(gold.isActive)
        assertFalse(gold.appliesTo(null))
        assertTrue(gold.appliesTo(Instrument.Lead))
        assertEquals(songs, gold.filter(songs, lookup, all, null))
        assertEquals(listOf(a), gold.filter(songs, lookup, all, Instrument.Lead))
        assertEquals(songs, gold.filter(songs, lookup, all - Instrument.Lead, Instrument.Lead))
        assertEquals(listOf(c), SongPlayerScoreFilter().onlyPercentile(0).filter(songs, lookup, all, Instrument.Lead))
        assertEquals(listOf(b), SongPlayerScoreFilter(excludedSeasons = setOf(9, 0)).filter(songs, lookup, all, Instrument.Lead))
        // Checks and buckets combine (AND).
        val both = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead), excludedStars = setOf(6))
        assertEquals(listOf(b), both.filter(songs, lookup, all, Instrument.Lead))
        // cleanedFor clears buckets and that chart's checks only.
        val cleaned = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead, Instrument.Bass), excludedStars = setOf(1), excludedSeasons = setOf(2), excludedPercentiles = setOf(3)).cleanedFor(Instrument.Lead)
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Bass)), cleaned)
    }

    @Test
    fun bucketsPersistBoundedAndOldFiltersDecodeUnchanged() {
        val filter = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead), excludedSeasons = setOf(3, 1), excludedPercentiles = setOf(10), excludedStars = setOf(0, 6))
        val raw = filter.encoded()
        assertTrue(raw.contains("\"excludedSeasons\":[1,3]"))
        assertEquals(filter, SongPlayerScoreFilter.decodeSaved(raw))
        val legacy = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Lead)).encoded()
        assertFalse(legacy.contains("excluded"))
        assertEquals(SongPlayerScoreFilter(excludedStars = setOf(2)), SongPlayerScoreFilter.decodeSaved(SongPlayerScoreFilter(excludedStars = setOf(2)).encoded()))
        fun stored(field: String, values: String) =
            """{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":[],"$field":$values}"""
        assertNull(SongPlayerScoreFilter.decodeSaved(stored("excludedStars", "[7]")))
        assertNull(SongPlayerScoreFilter.decodeSaved(stored("excludedPercentiles", "[6]")))
        assertNull(SongPlayerScoreFilter.decodeSaved(stored("excludedSeasons", "[1,1]")))
        assertNull(SongPlayerScoreFilter.decodeSaved(stored("excludedSeasons", "[-1]")))
        assertEquals(setOf(0, 1, 2, 3, 4, 5), SongPlayerScoreFilter().onlyStars(6).excludedStars)
        assertEquals(SongPercentileBucket.KEYS.toSet() - 5, SongPlayerScoreFilter().onlyPercentile(5).excludedPercentiles)
        assertEquals(setOf(4), SongPlayerScoreFilter().withExcluded(SongBucketKind.Season, setOf(4)).excluded(SongBucketKind.Season))
        assertEquals(SongPlayerScoreFilter(), SongPlayerScoreFilter().withExcluded(SongBucketKind.Intensity, setOf(4)))
        assertEquals(emptySet<Int>(), SongPlayerScoreFilter(excludedStars = setOf(1)).excluded(SongBucketKind.Intensity))
    }

    // endregion
}
