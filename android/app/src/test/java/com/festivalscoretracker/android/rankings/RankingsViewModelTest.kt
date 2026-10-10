package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.rankings.BandRankingsResponse
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankHistoryResponse
import com.festivalscoretracker.android.core.rankings.RankHistorySnapshot
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingsResponse
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.rankings.BandRankingsPayload
import com.festivalscoretracker.android.data.rankings.RankingsPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.leaderboards.BandRankingsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.FullRankingsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.RankingsReads
import com.festivalscoretracker.android.presentation.valueOrNull
import com.festivalscoretracker.android.testing.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Scriptable rankings reads that record every call. */
internal class FakeReads {
    val calls = mutableListOf<String>()
    var inFlight = 0
    var maxInFlight = 0
    var failNext: Exception? = null
    var failOwnRow: Exception? = null
    var hold: CompletableDeferred<Unit>? = null
    var unranked = setOf<Instrument>()
    var selectedRank = RankingsFixtures.SELECTED_RANK
    var accounts = RankingsFixtures.TOTAL_ACCOUNTS
    var failBands: Exception? = null
    var holdOwnRow: CompletableDeferred<Unit>? = null

    private suspend fun <T> track(label: String, block: () -> T): T {
        calls += label
        inFlight++
        maxInFlight = maxOf(maxInFlight, inFlight)
        try {
            delay(10)
            hold?.await()
            failNext?.let { failNext = null; throw it }
            return block()
        } finally {
            inFlight--
        }
    }

    val reads = RankingsReads(
        rankings = { instrument, metric, page, size ->
            track("rankings:${instrument.wireId}:${metric.wireId}:$page:$size") {
                val json = RankingsFixtures.rankings(instrument.wireId, metric.wireId, page, size, total = accounts)
                RankingsPayload(FestivalApi.JSON.decodeFromString(RankingsResponse.serializer(), json), 7)
            }
        },
        bandRankings = { bandType, metric, page, size ->
            track("bands:${bandType.wireId}:${metric.wireId}:$page:$size") {
                failBands?.let { throw it }
                val json = RankingsFixtures.bandRankings(bandType.wireId, metric.wireId, page, size)
                BandRankingsPayload(FestivalApi.JSON.decodeFromString(BandRankingsResponse.serializer(), json), 7)
            }
        },
        playerRanking = { instrument, accountId ->
            holdOwnRow?.await()
            track("own:${instrument.wireId}:$accountId") {
                failOwnRow?.let { failOwnRow = null; throw it }
                if (instrument in unranked) {
                    PlayerRankingResult.Unranked
                } else {
                    val row = FestivalApi.JSON.decodeFromString(AccountRankingEntry.serializer(), RankingsFixtures.accountRow(selectedRank)).copy(accountId = accountId)
                    PlayerRankingResult.Ranked(PlayerInstrumentRanking(row, "", RankingsFixtures.TOTAL_ACCOUNTS))
                }
            }
        },
    )

    val history = RankHistoryResponse(
        "Solo_Guitar",
        RankingsFixtures.SELECTED,
        listOf(RankHistorySnapshot("2026-09-20", totalScoreRank = 45), RankHistorySnapshot("2026-09-25", totalScoreRank = 40)),
    )
    var failHistory: Exception? = null

    val historyReads = reads.copy(
        rankHistory = { instrument, accountId ->
            track("history:${instrument.wireId}:$accountId") {
                failHistory?.let { failHistory = null; throw it }
                history.copy(instrument = instrument.wireId, accountId = accountId)
            }
        },
    )

    fun count(prefix: String) = calls.count { it.startsWith(prefix) }
}

@OptIn(ExperimentalCoroutinesApi::class)
class RankingsViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val fake = FakeReads()
    private val selectedPlayer = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
    private val settings = MutableStateFlow<AppSettings?>(AppSettings(visibleInstruments = setOf(Instrument.Lead, Instrument.Bass)))
    private val rankBy = MutableStateFlow(RankingMetric.TotalScore)

    private fun overview() = LeaderboardsViewModel(fake.reads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())

    // region Overview

    @Test
    fun overviewLoadsVisibleCardsWithBoundedConcurrency() = runTest(main.dispatcher) {
        settings.value = AppSettings()
        val viewModel = overview()
        advanceUntilIdle()
        assertTrue(viewModel.ready.value)
        assertEquals(Instrument.entries.toList(), viewModel.instruments.value)
        Instrument.entries.forEach { assertEquals(10, viewModel.card(it).value.valueOrNull?.rankings?.entries?.size) }
        BandType.entries.forEach { assertEquals(10, viewModel.bandCard(it).value.valueOrNull?.rankings?.entries?.size) }
        assertEquals(12, fake.calls.size)
        assertTrue(fake.maxInFlight <= LeaderboardsViewModel.MAX_CONCURRENT)
        assertTrue(fake.calls.all { it.endsWith(":1:10") })
        assertEquals(0, fake.count("own:"))
    }

    @Test
    fun metricChangesReloadOnlyAffectedCards() = runTest(main.dispatcher) {
        settings.value = settings.value!!.copy(experimentalRanks = true)
        val viewModel = overview()
        advanceUntilIdle()
        fake.calls.clear()
        viewModel.selectMetric(RankingMetric.TotalScore)
        advanceUntilIdle()
        assertTrue(fake.calls.isEmpty())
        // Max Score narrows to Total Score for bands: band cards keep their data.
        viewModel.selectMetric(RankingMetric.MaxScore)
        advanceUntilIdle()
        assertEquals(RankingMetric.MaxScore, rankBy.value)
        assertEquals(RankingMetric.MaxScore, viewModel.metric.value)
        assertEquals(setOf("rankings:Solo_Guitar:maxscore:1:10", "rankings:Solo_Bass:maxscore:1:10"), fake.calls.toSet())
        assertEquals(0, fake.count("bands:"))
        viewModel.selectMetric(RankingMetric.Weighted)
        advanceUntilIdle()
        assertEquals(3, fake.count("bands:"))
        assertTrue(fake.calls.filter { it.startsWith("bands:") }.all { it.contains(":weighted:") })
    }

    @Test
    fun spotlightLoadsOnlyWhenOutsideTopTenAndSurvivesMetricChanges() = runTest(main.dispatcher) {
        fake.unranked = setOf(Instrument.Bass)
        settings.value = AppSettings(selectedPlayer = selectedPlayer, visibleInstruments = setOf(Instrument.Lead, Instrument.Bass), experimentalRanks = true)
        val viewModel = overview()
        advanceUntilIdle()
        assertEquals(RankingsFixtures.SELECTED, viewModel.selectedAccountId.value)
        val lead = viewModel.spotlight(Instrument.Lead).value.valueOrNull as PlayerRankingResult.Ranked
        assertEquals(RankingsFixtures.SELECTED_RANK, lead.ranking.entry.totalScoreRank)
        assertEquals(PlayerRankingResult.Unranked, viewModel.spotlight(Instrument.Bass).value.valueOrNull)
        assertEquals(2, fake.count("own:"))
        viewModel.selectMetric(RankingMetric.FcRate)
        advanceUntilIdle()
        assertEquals(RankingMetric.FcRate, viewModel.metric.value)
        assertEquals(2, fake.count("own:"))
        // A new selection reloads the cards and its own rows.
        val other = RankingsFixtures.accountId(55)
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(other, "Other"), visibleInstruments = setOf(Instrument.Lead, Instrument.Bass))
        advanceUntilIdle()
        assertEquals(1, fake.count("own:Solo_Guitar:$other"))
    }

    @Test
    fun selectedPlayerInTopTenNeedsNoOwnRowRead() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(RankingsFixtures.accountId(4), "Fourth"), visibleInstruments = setOf(Instrument.Lead))
        overview()
        advanceUntilIdle()
        assertEquals(0, fake.count("own:"))
    }

    @Test
    fun failuresRetryPerCardAndPerSpotlight() = runTest(main.dispatcher) {
        settings.value = AppSettings(visibleInstruments = setOf(Instrument.Lead))
        fake.failNext = FestivalApiException.HttpStatus(500)
        val viewModel = overview()
        advanceUntilIdle()
        val failedCards = listOf(viewModel.card(Instrument.Lead).value) + BandType.entries.map { viewModel.bandCard(it).value }
        assertEquals(1, failedCards.count { it is LoadState.Failed })
        val failedLead = viewModel.card(Instrument.Lead).value is LoadState.Failed
        if (failedLead) viewModel.retryCard(Instrument.Lead) else BandType.entries.forEach(viewModel::retryBand)
        advanceUntilIdle()
        assertTrue(viewModel.card(Instrument.Lead).value is LoadState.Loaded)
        BandType.entries.forEach { assertTrue(viewModel.bandCard(it).value is LoadState.Loaded) }

        fake.failOwnRow = FestivalApiException.HttpStatus(500)
        settings.value = AppSettings(selectedPlayer = selectedPlayer, visibleInstruments = setOf(Instrument.Lead))
        advanceUntilIdle()
        assertTrue(viewModel.spotlight(Instrument.Lead).value is LoadState.Failed)
        viewModel.retrySpotlight(Instrument.Lead)
        advanceUntilIdle()
        assertTrue(viewModel.spotlight(Instrument.Lead).value.valueOrNull is PlayerRankingResult.Ranked)
    }

    @Test
    fun scrapeFreezeCountsDownAndRetriesAutomatically() = runTest(main.dispatcher) {
        settings.value = AppSettings(visibleInstruments = setOf(Instrument.Lead))
        fake.failNext = FestivalApiException.PublicReadFrozen("scrape", "2")
        val viewModel = overview()
        advanceUntilIdle()
        val all = listOf(viewModel.card(Instrument.Lead).value) + BandType.entries.map { viewModel.bandCard(it).value }
        assertTrue(all.all { it is LoadState.Loaded })
        assertEquals(5, fake.calls.size)
    }

    @Test
    fun refreshKeepsContentAndReportsProgress() = runTest(main.dispatcher) {
        settings.value = AppSettings(visibleInstruments = setOf(Instrument.Lead))
        val viewModel = overview()
        advanceUntilIdle()
        fake.calls.clear()
        viewModel.refresh()
        assertTrue(viewModel.refreshing.value)
        assertTrue(viewModel.card(Instrument.Lead).value is LoadState.Loaded)
        advanceUntilIdle()
        assertFalse(viewModel.refreshing.value)
        assertEquals(4, fake.calls.size)
    }

    @Test
    fun newlyVisibleInstrumentsLoadWithoutReloadingOthers() = runTest(main.dispatcher) {
        settings.value = AppSettings(visibleInstruments = setOf(Instrument.Lead))
        val viewModel = overview()
        advanceUntilIdle()
        fake.calls.clear()
        settings.value = AppSettings(visibleInstruments = setOf(Instrument.Lead, Instrument.Drums))
        advanceUntilIdle()
        assertEquals(listOf("rankings:Solo_Drums:totalscore:1:10"), fake.calls)
        assertEquals(listOf(Instrument.Lead, Instrument.Drums), viewModel.instruments.value)
    }

    @Test
    fun rankHistoryLoadsOnDemandOncePerPlayerAndChart() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = selectedPlayer, visibleInstruments = setOf(Instrument.Lead, Instrument.Bass), experimentalRanks = true)
        val viewModel = LeaderboardsViewModel(fake.historyReads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        advanceUntilIdle()
        // The first visible chart is shown; nothing is read until the card asks.
        assertEquals(Instrument.Lead, viewModel.historyInstrument.value)
        assertEquals(0, fake.count("history:"))
        viewModel.ensureHistory(Instrument.Lead)
        advanceUntilIdle()
        viewModel.ensureHistory(Instrument.Lead)
        rankBy.value = RankingMetric.FcRate
        advanceUntilIdle()
        // Each snapshot carries every metric, so a metric change reuses the read.
        assertEquals(1, fake.count("history:Solo_Guitar:${RankingsFixtures.SELECTED}"))
        assertEquals(2, viewModel.rankHistory(Instrument.Lead).value.valueOrNull?.history?.size)
        viewModel.selectHistoryInstrument(Instrument.Bass)
        advanceUntilIdle()
        assertEquals(Instrument.Bass, viewModel.historyInstrument.value)
        assertEquals(1, fake.count("history:Solo_Bass:"))
        // A new player re-reads the chart.
        settings.value = settings.value!!.copy(selectedPlayer = SelectedPlayer("b".repeat(32), "Other"))
        advanceUntilIdle()
        viewModel.ensureHistory(Instrument.Bass)
        advanceUntilIdle()
        assertEquals(1, fake.count("history:Solo_Bass:${"b".repeat(32)}"))
    }

    @Test
    fun rankHistoryRetriesAfterFailureAndFollowsVisibleCharts() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = selectedPlayer, visibleInstruments = setOf(Instrument.Lead, Instrument.Bass))
        val viewModel = LeaderboardsViewModel(fake.historyReads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        advanceUntilIdle()
        fake.failHistory = FestivalApiException.HttpStatus(500)
        viewModel.ensureHistory(Instrument.Lead)
        advanceUntilIdle()
        assertTrue(viewModel.rankHistory(Instrument.Lead).value is LoadState.Failed)
        // A failed read is retried on the next request rather than reused.
        viewModel.ensureHistory(Instrument.Lead)
        advanceUntilIdle()
        assertNotNull(viewModel.rankHistory(Instrument.Lead).value.valueOrNull)
        viewModel.retryHistory(Instrument.Lead)
        advanceUntilIdle()
        assertEquals(3, fake.count("history:Solo_Guitar:"))
        // Hiding the shown chart moves the card to the first visible one.
        settings.value = settings.value!!.copy(visibleInstruments = setOf(Instrument.Bass))
        advanceUntilIdle()
        assertEquals(Instrument.Bass, viewModel.historyInstrument.value)
    }

    @Test
    fun rankHistoryNeedsASelectedPlayer() = runTest(main.dispatcher) {
        val viewModel = LeaderboardsViewModel(fake.historyReads, settings, rankBy, { rankBy.value = it }, ServiceRetryBackoff())
        advanceUntilIdle()
        viewModel.ensureHistory(Instrument.Lead)
        advanceUntilIdle()
        assertEquals(0, fake.count("history:"))
        // The default read answers an empty history without touching the service.
        assertEquals(0, RankingsReads(fake.reads.rankings, fake.reads.bandRankings, fake.reads.playerRanking).rankHistory(Instrument.Lead, "x").history.size)
    }

    // endregion

    // region Full rankings

    private fun full(page: Int = 1, instrument: Instrument = Instrument.Lead) =
        FullRankingsViewModel(instrument, RankingMetric.TotalScore, fake.reads, settings, ServiceRetryBackoff(), page)

    @Test
    fun fullRankingsCorrectsOutOfRangePagesAndPages() = runTest(main.dispatcher) {
        val viewModel = full(page = 99)
        advanceUntilIdle()
        assertEquals(3, viewModel.page.value)
        assertEquals(10, viewModel.displayed.value?.rankings?.entries?.size)
        assertEquals(listOf("rankings:Solo_Guitar:totalscore:99:25", "rankings:Solo_Guitar:totalscore:3:25"), fake.calls)
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), viewModel.visibleInstruments.value)
        viewModel.goTo(0)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        // The previous page stays displayed while the next one loads.
        fake.hold = CompletableDeferred()
        viewModel.goTo(2)
        advanceUntilIdle()
        assertTrue(viewModel.board.value is LoadState.Loading)
        assertEquals(1, viewModel.displayed.value?.rankings?.page)
        fake.hold!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(2, viewModel.displayed.value?.rankings?.page)
    }

    @Test
    fun fullRankingsSwitchersResetToFirstPage() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = selectedPlayer, experimentalRanks = true)
        val viewModel = full(page = 2)
        // No page count (so no pager) before the first board answers (#575).
        assertNull(viewModel.pageCount.value)
        advanceUntilIdle()
        assertEquals(1, fake.count("own:Solo_Guitar"))
        viewModel.selectInstrument(Instrument.Lead)
        viewModel.selectMetric(RankingMetric.TotalScore)
        viewModel.selectInstrument(Instrument.Drums)
        assertNull(viewModel.displayed.value)
        // The pager keeps the last board's page count until the new chart answers (#431).
        assertEquals(3, viewModel.pageCount.value)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertEquals(Instrument.Drums, viewModel.instrument.value)
        assertEquals(1, fake.count("own:Solo_Drums"))
        viewModel.goTo(3)
        advanceUntilIdle()
        viewModel.selectMetric(RankingMetric.Adjusted)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertEquals(RankingMetric.Adjusted, viewModel.metric.value)
        assertEquals("adjusted", viewModel.displayed.value?.rankings?.rankBy)
        assertEquals(1, fake.count("own:Solo_Drums"))
    }

    @Test
    fun fullRankingsJumpsToTheSelectedPlayersPage() = runTest(main.dispatcher) {
        val viewModel = full()
        advanceUntilIdle()
        assertNull(viewModel.selectedPage())
        viewModel.jumpToSelected()
        assertEquals(1, viewModel.page.value)
        settings.value = AppSettings(selectedPlayer = selectedPlayer)
        advanceUntilIdle()
        assertEquals(RankingsFixtures.SELECTED, viewModel.selectedAccountId.value)
        assertEquals(2, viewModel.selectedPage())
        viewModel.jumpToSelected()
        advanceUntilIdle()
        assertEquals(2, viewModel.page.value)
        assertNotNull(viewModel.displayed.value?.rankings?.entries?.firstOrNull { it.accountId == RankingsFixtures.SELECTED })
        // Unranked own rows and failures give no page; retry recovers.
        fake.failOwnRow = FestivalApiException.HttpStatus(500)
        viewModel.selectInstrument(Instrument.Bass)
        advanceUntilIdle()
        assertTrue(viewModel.spotlight.value is LoadState.Failed)
        assertNull(viewModel.selectedPage())
        viewModel.retrySpotlight()
        advanceUntilIdle()
        assertEquals(2, viewModel.selectedPage())
        fake.selectedRank = 0
        viewModel.retrySpotlight()
        advanceUntilIdle()
        assertNull(viewModel.selectedPage())
        fake.failNext = FestivalApiException.HttpStatus(500)
        viewModel.retry()
        advanceUntilIdle()
        assertTrue(viewModel.board.value is LoadState.Failed)
    }

    // endregion

    // region Band rankings

    @Test
    fun bandRankingsStartFromTheNarrowedStoredMetric() = runTest(main.dispatcher) {
        rankBy.value = RankingMetric.MaxScore
        val viewModel = BandRankingsViewModel(BandType.Trios, rankBy, MutableStateFlow(true), fake.reads, ServiceRetryBackoff())
        assertTrue(viewModel.board.value is LoadState.Loading)
        // No page count (so no pager) before the first board answers (#575).
        assertNull(viewModel.pageCount.value)
        advanceUntilIdle()
        assertEquals(BandRankingMetric.TotalScore, viewModel.metric.value)
        assertEquals(listOf("bands:Band_Trios:totalscore:1:25"), fake.calls)
        // Later preference changes don't move an open board.
        rankBy.value = RankingMetric.Weighted
        advanceUntilIdle()
        assertEquals(1, fake.calls.size)
        viewModel.goTo(5)
        advanceUntilIdle()
        assertEquals(2, viewModel.page.value)
        viewModel.selectBandType(BandType.Trios)
        viewModel.selectBandType(BandType.Quad)
        assertNull(viewModel.displayed.value)
        assertEquals(2, viewModel.pageCount.value)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertEquals(BandType.Quad, viewModel.bandType.value)
        viewModel.selectMetric(BandRankingMetric.TotalScore)
        viewModel.selectMetric(BandRankingMetric.FcRate)
        advanceUntilIdle()
        assertEquals("fcrate", viewModel.displayed.value?.rankings?.rankBy)
        fake.failNext = FestivalApiException.HttpStatus(500)
        viewModel.retry()
        advanceUntilIdle()
        assertTrue(viewModel.board.value is LoadState.Failed)
        assertEquals("fcrate", viewModel.displayed.value?.rankings?.rankBy)
    }

    @Test
    fun bandBoardStartsOnTheRoutedPage() = runTest(main.dispatcher) {
        val viewModel = BandRankingsViewModel(BandType.Trios, rankBy, MutableStateFlow(false), fake.reads, ServiceRetryBackoff(), initialPage = 2)
        advanceUntilIdle()
        assertEquals(2, viewModel.page.value)
        assertTrue(fake.calls.any { it == "bands:Band_Trios:totalscore:2:25" })
    }

    // endregion

    // region Experimental Ranks (#541)

    @Test
    fun experimentalMetricsNeedTheSettingAndTurningItOffReturnsToTotalScore() = runTest(main.dispatcher) {
        rankBy.value = RankingMetric.Adjusted
        val viewModel = overview()
        advanceUntilIdle()
        // A saved experimental metric reads as Total Score while the setting is off.
        assertFalse(viewModel.experimentalRanks.value)
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        assertTrue(fake.calls.filter { it.startsWith("rankings:") }.all { it.contains(":totalscore:") })
        // Rank By offers nothing else while off.
        viewModel.selectMetric(RankingMetric.Weighted)
        advanceUntilIdle()
        assertEquals(RankingMetric.Adjusted, rankBy.value)
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        // Turning it on restores the saved preference; turning it off goes back to Total Score.
        settings.value = settings.value!!.copy(experimentalRanks = true)
        advanceUntilIdle()
        assertTrue(viewModel.experimentalRanks.value)
        assertEquals(RankingMetric.Adjusted, viewModel.metric.value)
        assertTrue(fake.calls.any { it == "rankings:Solo_Guitar:adjusted:1:10" })
        fake.calls.clear()
        settings.value = settings.value!!.copy(experimentalRanks = false)
        advanceUntilIdle()
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        assertTrue(fake.calls.filter { it.startsWith("rankings:") }.all { it.contains(":totalscore:") })
    }

    @Test
    fun fullRankingsDeepLinkedExperimentalMetricFallsBackToTotalScore() = runTest(main.dispatcher) {
        val viewModel = FullRankingsViewModel(Instrument.Lead, RankingMetric.FcRate, fake.reads, settings, ServiceRetryBackoff(), 2)
        advanceUntilIdle()
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        assertEquals(listOf("rankings:Solo_Guitar:totalscore:2:25"), fake.calls)
        viewModel.selectMetric(RankingMetric.Adjusted)
        advanceUntilIdle()
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        assertEquals(1, fake.calls.size)
    }

    @Test
    fun fullRankingsReturnToTotalScoreWhenTheSettingTurnsOff() = runTest(main.dispatcher) {
        settings.value = settings.value!!.copy(experimentalRanks = true)
        val viewModel = FullRankingsViewModel(Instrument.Lead, RankingMetric.Weighted, fake.reads, settings, ServiceRetryBackoff(), 2)
        advanceUntilIdle()
        assertEquals(RankingMetric.Weighted, viewModel.metric.value)
        assertEquals("weighted", viewModel.displayed.value?.rankings?.rankBy)
        settings.value = settings.value!!.copy(experimentalRanks = false)
        advanceUntilIdle()
        assertFalse(viewModel.experimentalRanks.value)
        assertEquals(RankingMetric.TotalScore, viewModel.metric.value)
        assertEquals(1, viewModel.page.value)
        assertEquals("totalscore", viewModel.displayed.value?.rankings?.rankBy)
    }

    @Test
    fun bandRankingsReturnToTotalScoreWhenTheSettingTurnsOff() = runTest(main.dispatcher) {
        rankBy.value = RankingMetric.FcRate
        val experimental = MutableStateFlow(false)
        val viewModel = BandRankingsViewModel(BandType.Trios, rankBy, experimental, fake.reads, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(BandRankingMetric.TotalScore, viewModel.metric.value)
        viewModel.selectMetric(BandRankingMetric.Adjusted)
        advanceUntilIdle()
        assertEquals(BandRankingMetric.TotalScore, viewModel.metric.value)
        assertEquals(listOf("bands:Band_Trios:totalscore:1:25"), fake.calls)
        experimental.value = true
        advanceUntilIdle()
        viewModel.selectMetric(BandRankingMetric.Adjusted)
        advanceUntilIdle()
        assertEquals("adjusted", viewModel.displayed.value?.rankings?.rankBy)
        experimental.value = false
        advanceUntilIdle()
        assertEquals(BandRankingMetric.TotalScore, viewModel.metric.value)
        assertEquals("totalscore", viewModel.displayed.value?.rankings?.rankBy)
    }

    // endregion
}
