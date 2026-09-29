package com.festivalscoretracker.android.core.songs

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
}
