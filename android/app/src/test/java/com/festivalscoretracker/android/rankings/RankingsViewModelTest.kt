package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.rankings.BandRankingsResponse
import com.festivalscoretracker.android.core.rankings.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
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
private class FakeReads {
    val calls = mutableListOf<String>()
    var inFlight = 0
    var maxInFlight = 0
    var failNext: Exception? = null
    var failOwnRow: Exception? = null
    var hold: CompletableDeferred<Unit>? = null
    var unranked = setOf<Instrument>()
    var selectedRank = RankingsFixtures.SELECTED_RANK

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
                val json = RankingsFixtures.rankings(instrument.wireId, metric.wireId, page, size)
                RankingsPayload(FestivalApi.JSON.decodeFromString(RankingsResponse.serializer(), json), 7)
            }
        },
        bandRankings = { bandType, metric, page, size ->
            track("bands:${bandType.wireId}:${metric.wireId}:$page:$size") {
                val json = RankingsFixtures.bandRankings(bandType.wireId, metric.wireId, page, size)
                BandRankingsPayload(FestivalApi.JSON.decodeFromString(BandRankingsResponse.serializer(), json), 7)
            }
        },
        playerRanking = { instrument, accountId ->
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
        settings.value = AppSettings(selectedPlayer = selectedPlayer, visibleInstruments = setOf(Instrument.Lead, Instrument.Bass))
        val viewModel = overview()
        advanceUntilIdle()
        assertEquals(RankingsFixtures.SELECTED, viewModel.selectedAccountId.value)
        val lead = viewModel.spotlight(Instrument.Lead).value.valueOrNull as PlayerRankingResult.Ranked
        assertEquals(RankingsFixtures.SELECTED_RANK, lead.ranking.entry.totalScoreRank)
        assertEquals(PlayerRankingResult.Unranked, viewModel.spotlight(Instrument.Bass).value.valueOrNull)
        assertEquals(2, fake.count("own:"))
        viewModel.selectMetric(RankingMetric.FcRate)
        advanceUntilIdle()
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
        settings.value = AppSettings(selectedPlayer = selectedPlayer)
        val viewModel = full(page = 2)
        advanceUntilIdle()
        assertEquals(1, fake.count("own:Solo_Guitar"))
        viewModel.selectInstrument(Instrument.Lead)
        viewModel.selectMetric(RankingMetric.TotalScore)
        viewModel.selectInstrument(Instrument.Drums)
        assertNull(viewModel.displayed.value)
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
        val viewModel = BandRankingsViewModel(BandType.Trios, rankBy, fake.reads, ServiceRetryBackoff())
        assertTrue(viewModel.board.value is LoadState.Loading)
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

    // endregion
}
