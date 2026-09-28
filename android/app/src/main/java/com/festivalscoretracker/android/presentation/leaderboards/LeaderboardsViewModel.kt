package com.festivalscoretracker.android.presentation.leaderboards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankHistoryChart
import com.festivalscoretracker.android.core.rankings.RankHistoryResponse
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.rankings.BandRankingsPayload
import com.festivalscoretracker.android.data.rankings.RankingsPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

// region Reads

/**
 * The rankings reads every Leaderboards view model uses, injected so tests pass fakes.
 *
 * @property rankings `(instrument, metric, page, pageSize)` account page.
 * @property bandRankings `(bandType, metric, page, pageSize)` band page.
 * @property playerRanking `(instrument, accountId)` own row or unranked.
 * @property rankHistory `(instrument, accountId)` daily rank history over [RankHistoryChart.DAYS].
 */
data class RankingsReads(
    val rankings: suspend (Instrument, RankingMetric, Int, Int) -> RankingsPayload,
    val bandRankings: suspend (BandType, BandRankingMetric, Int, Int) -> BandRankingsPayload,
    val playerRanking: suspend (Instrument, String) -> PlayerRankingResult,
    val rankHistory: suspend (Instrument, String) -> RankHistoryResponse = { instrument, accountId -> RankHistoryResponse(instrument.wireId, accountId) },
)

// endregion

// region Overview

/**
 * `/leaderboards` logic: one top-ten card per Settings-visible instrument and per band
 * size, the persisted Rank By metric, and the selected player's spotlight per instrument.
 *
 * Cards reload only when their inputs change (metric, and for instrument cards the
 * selected player), so returning from a pushed page keeps them. At most
 * [MAX_CONCURRENT] reads are in flight. The spotlight's own-row read is skipped when
 * the player is already in the top ten, and reused across metric changes (the row
 * carries every metric's rank).
 *
 * @param reads Rankings reads.
 * @param settings App settings (visible instruments, selected player).
 * @param rankBy Persisted metric.
 * @param persistRankBy Persist a new metric.
 * @param backoff Shared retry backoff.
 */
class LeaderboardsViewModel(
    private val reads: RankingsReads,
    settings: Flow<AppSettings?>,
    rankBy: Flow<RankingMetric>,
    private val persistRankBy: suspend (RankingMetric) -> Unit,
    private val backoff: ServiceRetryBackoff,
) : ViewModel() {
    private val permits = Semaphore(MAX_CONCURRENT)
    private val metricFlow = MutableStateFlow(RankingMetric.DEFAULT)
    private val instrumentsFlow = MutableStateFlow<List<Instrument>>(emptyList())
    private val selectedFlow = MutableStateFlow<String?>(null)
    private val readyFlow = MutableStateFlow(false)
    private val refreshingFlow = MutableStateFlow(false)
    private val cards = mutableMapOf<Instrument, RetryingLoader<RankingsPayload>>()
    private val cardKeys = mutableMapOf<Instrument, String>()
    private val bands = mutableMapOf<BandType, RetryingLoader<BandRankingsPayload>>()
    private val bandKeys = mutableMapOf<BandType, BandRankingMetric>()
    private val spotlights = mutableMapOf<Instrument, RetryingLoader<PlayerRankingResult>>()
    private val spotlightAccounts = mutableMapOf<Instrument, String>()
    private val historyInstrumentFlow = MutableStateFlow<Instrument?>(null)
    private val histories = mutableMapOf<Instrument, RetryingLoader<RankHistoryResponse>>()
    private val historyAccounts = mutableMapOf<Instrument, String>()

    /** Current Rank By metric. */
    val metric: StateFlow<RankingMetric> = metricFlow.asStateFlow()

    /** Settings-visible instruments in canonical order. */
    val instruments: StateFlow<List<Instrument>> = instrumentsFlow.asStateFlow()

    /** Selected player's account ID, or null. */
    val selectedAccountId: StateFlow<String?> = selectedFlow.asStateFlow()

    /** False until settings and the metric have been read once. */
    val ready: StateFlow<Boolean> = readyFlow.asStateFlow()

    /** True while a pull-to-refresh is in flight. */
    val refreshing: StateFlow<Boolean> = refreshingFlow.asStateFlow()

    /** Chart shown on the rank-history card (first visible chart until the user picks one). */
    val historyInstrument: StateFlow<Instrument?> = historyInstrumentFlow.asStateFlow()

    init {
        viewModelScope.launch {
            combine(rankBy, settings.filterNotNull()) { metric, current ->
                Inputs(metric, Instrument.entries.filter { it in current.visibleInstruments }, current.selectedPlayer?.accountId)
            }.distinctUntilChanged().collect(::apply)
        }
    }

    private data class Inputs(val metric: RankingMetric, val instruments: List<Instrument>, val selected: String?)

    private fun apply(inputs: Inputs) {
        metricFlow.value = inputs.metric
        instrumentsFlow.value = inputs.instruments
        if (historyInstrumentFlow.value !in inputs.instruments) historyInstrumentFlow.value = inputs.instruments.firstOrNull()
        selectedFlow.value = inputs.selected
        val cardKey = "${inputs.metric.wireId}|${inputs.selected.orEmpty()}"
        inputs.instruments.forEach { instrument ->
            if (cardKeys[instrument] != cardKey) {
                cardKeys[instrument] = cardKey
                cardLoader(instrument).retry()
            }
        }
        val bandMetric = inputs.metric.bandMetric
        BandType.entries.forEach { bandType ->
            if (bandKeys[bandType] != bandMetric) {
                bandKeys[bandType] = bandMetric
                bandLoader(bandType).retry()
            }
        }
        readyFlow.value = true
    }

    /**
     * One instrument card's top-ten state.
     *
     * @param instrument Chart.
     * @return Card state.
     */
    fun card(instrument: Instrument): StateFlow<LoadState<RankingsPayload>> = cardLoader(instrument).state

    /**
     * One band card's top-ten state.
     *
     * @param bandType Band size.
     * @return Card state.
     */
    fun bandCard(bandType: BandType): StateFlow<LoadState<BandRankingsPayload>> = bandLoader(bandType).state

    /**
     * The selected player's own-row state for one instrument; meaningful only when
     * the card's placement is not inline.
     *
     * @param instrument Chart.
     * @return Own-row state.
     */
    fun spotlight(instrument: Instrument): StateFlow<LoadState<PlayerRankingResult>> = spotlightLoader(instrument).state

    /**
     * The selected player's rank history on one chart (web `useRankHistoryAll`; one
     * read per chart and player, reused across metric changes since each snapshot
     * carries every metric). Call [ensureHistory] to start it.
     *
     * @param instrument Chart.
     * @return History state.
     */
    fun rankHistory(instrument: Instrument): StateFlow<LoadState<RankHistoryResponse>> = historyLoader(instrument).state

    /**
     * Load the selected player's history on a chart unless it is already loaded for them.
     *
     * @param instrument Chart.
     */
    fun ensureHistory(instrument: Instrument) {
        val selected = selectedFlow.value ?: return
        if (historyAccounts[instrument] == selected && historyLoader(instrument).state.value !is LoadState.Failed) return
        historyAccounts[instrument] = selected
        historyLoader(instrument).retry()
    }

    /**
     * Show another chart on the rank-history card.
     *
     * @param instrument Chart.
     */
    fun selectHistoryInstrument(instrument: Instrument) {
        historyInstrumentFlow.value = instrument
        ensureHistory(instrument)
    }

    /**
     * Retry one chart's history.
     *
     * @param instrument Chart.
     */
    fun retryHistory(instrument: Instrument) = historyLoader(instrument).retry()

    /**
     * Change and persist Rank By; cards reload when the stored value comes back.
     *
     * @param metric New metric.
     */
    fun selectMetric(metric: RankingMetric) {
        if (metric == metricFlow.value) return
        viewModelScope.launch { persistRankBy(metric) }
    }

    /**
     * Retry one instrument card.
     *
     * @param instrument Chart.
     */
    fun retryCard(instrument: Instrument) = cardLoader(instrument).retry()

    /**
     * Retry one band card.
     *
     * @param bandType Band size.
     */
    fun retryBand(bandType: BandType) = bandLoader(bandType).retry()

    /**
     * Retry one spotlight read.
     *
     * @param instrument Chart.
     */
    fun retrySpotlight(instrument: Instrument) = spotlightLoader(instrument).retry()

    /** Reload every visible card (pull to refresh), keeping content visible. */
    fun refresh() {
        val loaders = instrumentsFlow.value.map(::cardLoader) + BandType.entries.map(::bandLoader)
        refreshingFlow.value = true
        loaders.forEach { it.refresh() }
        viewModelScope.launch {
            combine(loaders.map { it.state }) { states -> states.none { it is LoadState.Loading || (it is LoadState.Loaded && it.refreshing) } }
                .first { it }
            refreshingFlow.value = false
        }
    }

    private fun cardLoader(instrument: Instrument): RetryingLoader<RankingsPayload> = cards.getOrPut(instrument) {
        RetryingLoader(viewModelScope, "leaderboards:${instrument.wireId}", backoff) {
            val payload = permits.withPermit { reads.rankings(instrument, metricFlow.value, 1, RankingPaging.CARD_SIZE) }
            updateSpotlight(instrument, payload)
            payload
        }
    }

    private fun bandLoader(bandType: BandType): RetryingLoader<BandRankingsPayload> = bands.getOrPut(bandType) {
        RetryingLoader(viewModelScope, "leaderboards:${bandType.wireId}", backoff) {
            permits.withPermit { reads.bandRankings(bandType, metricFlow.value.bandMetric, 1, RankingPaging.CARD_SIZE) }
        }
    }

    private fun spotlightLoader(instrument: Instrument): RetryingLoader<PlayerRankingResult> = spotlights.getOrPut(instrument) {
        RetryingLoader(viewModelScope, "leaderboards:spotlight:${instrument.wireId}", backoff) {
            val accountId = selectedFlow.value ?: return@RetryingLoader PlayerRankingResult.Unranked
            permits.withPermit { reads.playerRanking(instrument, accountId) }
        }
    }

    private fun historyLoader(instrument: Instrument): RetryingLoader<RankHistoryResponse> = histories.getOrPut(instrument) {
        RetryingLoader(viewModelScope, "leaderboards:history:${instrument.wireId}", backoff) {
            val accountId = selectedFlow.value ?: return@RetryingLoader RankHistoryResponse(instrument.wireId)
            permits.withPermit { reads.rankHistory(instrument, accountId) }
        }
    }

    private fun updateSpotlight(instrument: Instrument, payload: RankingsPayload) {
        val selected = selectedFlow.value ?: return
        if (payload.rankings.entries.any { RankingSpotlight.isSelected(selected, it.accountId) }) return
        val loader = spotlightLoader(instrument)
        val reusable = spotlightAccounts[instrument] == selected && loader.state.value !is LoadState.Failed
        if (!reusable) {
            spotlightAccounts[instrument] = selected
            loader.retry()
        }
    }

    companion object {
        /** Reads in flight at once (twelve at once is needlessly bursty for the service). */
        const val MAX_CONCURRENT = 4
    }
}

// endregion
