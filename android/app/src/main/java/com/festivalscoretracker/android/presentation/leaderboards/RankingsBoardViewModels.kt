package com.festivalscoretracker.android.presentation.leaderboards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingPaging
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
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// region Full rankings

/**
 * `/leaderboards/all` logic: 25-row pages of one instrument's rankings with
 * instrument and metric switchers (both return to page 1), out-of-range page
 * correction, and the selected player's pinned own row with a jump to their page.
 * A newer request cancels an older one, so a superseded page never lands.
 *
 * @param initialInstrument Routed chart.
 * @param initialMetric Routed metric.
 * @param reads Rankings reads.
 * @param settings App settings (visible instruments, selected player).
 * @param backoff Shared retry backoff.
 * @param initialPage One-based starting page.
 */
class FullRankingsViewModel(
    initialInstrument: Instrument,
    initialMetric: RankingMetric,
    private val reads: RankingsReads,
    settings: Flow<AppSettings?>,
    backoff: ServiceRetryBackoff,
    initialPage: Int = 1,
) : ViewModel() {
    private val instrumentFlow = MutableStateFlow(initialInstrument)
    private val metricFlow = MutableStateFlow(initialMetric)
    private val pageFlow = MutableStateFlow(initialPage.coerceAtLeast(1))
    private val selectedFlow = MutableStateFlow<String?>(null)
    private val visibleFlow = MutableStateFlow(Instrument.entries.toList())
    private val boardLoader = RetryingLoader(viewModelScope, "full-rankings", backoff) {
        val instrument = instrumentFlow.value
        val metric = metricFlow.value
        val requested = pageFlow.value
        val payload = reads.rankings(instrument, metric, requested, RankingPaging.PAGE_SIZE)
        val corrected = LeaderboardPaging.corrected(requested, payload.rankings.pageCount)
        if (corrected != requested) {
            pageFlow.value = corrected
            reads.rankings(instrument, metric, corrected, RankingPaging.PAGE_SIZE)
        } else {
            payload
        }
    }
    private val spotlightLoader = RetryingLoader(viewModelScope, "full-rankings:spotlight", backoff) {
        val accountId = selectedFlow.value ?: return@RetryingLoader PlayerRankingResult.Unranked
        reads.playerRanking(instrumentFlow.value, accountId)
    }

    /** Current chart. */
    val instrument: StateFlow<Instrument> = instrumentFlow.asStateFlow()

    /** Current metric. */
    val metric: StateFlow<RankingMetric> = metricFlow.asStateFlow()

    /** Current one-based page. */
    val page: StateFlow<Int> = pageFlow.asStateFlow()

    /** Current page rows. */
    val board: StateFlow<LoadState<RankingsPayload>> = boardLoader.state

    private val displayedFlow = MutableStateFlow<RankingsPayload?>(null)

    /**
     * The last loaded page for the current chart and metric: kept visible (under a
     * progress bar) while the next page loads, cleared when the chart or metric changes.
     */
    val displayed: StateFlow<RankingsPayload?> = displayedFlow.asStateFlow()

    /** Selected player's own row (meaningful only while a player is selected). */
    val spotlight: StateFlow<LoadState<PlayerRankingResult>> = spotlightLoader.state

    /** Selected player, or null. */
    val selectedAccountId: StateFlow<String?> = selectedFlow.asStateFlow()

    /** Settings-visible charts; the switcher adds the current chart if hidden. */
    val visibleInstruments: StateFlow<List<Instrument>> = visibleFlow.asStateFlow()

    init {
        boardLoader.ensureStarted()
        viewModelScope.launch { boardLoader.state.collect { (it as? LoadState.Loaded)?.let { loaded -> displayedFlow.value = loaded.value } } }
        viewModelScope.launch {
            settings.filterNotNull().collect { current ->
                visibleFlow.value = Instrument.entries.filter { it in current.visibleInstruments }
                val selected = current.selectedPlayer?.accountId
                if (selected != selectedFlow.value) {
                    selectedFlow.value = selected
                    if (selected != null) spotlightLoader.retry()
                }
            }
        }
    }

    /**
     * Switch chart and return to page 1.
     *
     * @param instrument New chart.
     */
    fun selectInstrument(instrument: Instrument) {
        if (instrument == instrumentFlow.value) return
        instrumentFlow.value = instrument
        pageFlow.value = 1
        displayedFlow.value = null
        boardLoader.retry()
        if (selectedFlow.value != null) spotlightLoader.retry()
    }

    /**
     * Switch metric and return to page 1 (the own row carries every metric's rank).
     *
     * @param metric New metric.
     */
    fun selectMetric(metric: RankingMetric) {
        if (metric == metricFlow.value) return
        metricFlow.value = metric
        pageFlow.value = 1
        displayedFlow.value = null
        boardLoader.retry()
    }

    /**
     * Go to a page (the loader corrects past-the-end pages).
     *
     * @param page One-based page.
     */
    fun goTo(page: Int) {
        pageFlow.value = page.coerceAtLeast(1)
        boardLoader.retry()
    }

    /**
     * The page holding the selected player's row for the current metric.
     *
     * @return Page, or null when their row is unknown or unranked.
     */
    fun selectedPage(): Int? {
        val ranked = (spotlight.value as? LoadState.Loaded)?.value as? PlayerRankingResult.Ranked ?: return null
        val rank = ranked.ranking.entry.rank(metricFlow.value)
        return if (rank > 0) LeaderboardPaging.pageForRank(rank, RankingPaging.PAGE_SIZE) else null
    }

    /** Jump to the selected player's page (native addition; the web footer only links). */
    fun jumpToSelected() {
        selectedPage()?.let(::goTo)
    }

    /** Retry the current page. */
    fun retry() = boardLoader.retry()

    /** Retry the own-row read. */
    fun retrySpotlight() = spotlightLoader.retry()
}

// endregion

// region Band rankings

/**
 * `/leaderboards/bands/:bandType` logic: 25-row pages with band-size and band metric
 * switchers (both return to page 1). No selected-band spotlight: Android has no
 * selected-band identity (same gap as iPhone/Windows).
 *
 * @param initialBandType Routed band size.
 * @param rankBy Persisted Leaderboards metric, narrowed once for the starting value.
 * @param reads Rankings reads.
 * @param backoff Shared retry backoff.
 */
class BandRankingsViewModel(
    initialBandType: BandType,
    rankBy: Flow<RankingMetric>,
    private val reads: RankingsReads,
    backoff: ServiceRetryBackoff,
) : ViewModel() {
    private val bandTypeFlow = MutableStateFlow(initialBandType)
    private val metricFlow = MutableStateFlow<BandRankingMetric?>(null)
    private val pageFlow = MutableStateFlow(1)
    private val boardLoader = RetryingLoader(viewModelScope, "band-rankings", backoff) {
        val bandType = bandTypeFlow.value
        val metric = metricFlow.value ?: BandRankingMetric.TotalScore
        val requested = pageFlow.value
        val payload = reads.bandRankings(bandType, metric, requested, RankingPaging.PAGE_SIZE)
        val corrected = LeaderboardPaging.corrected(requested, payload.rankings.pageCount)
        if (corrected != requested) {
            pageFlow.value = corrected
            reads.bandRankings(bandType, metric, corrected, RankingPaging.PAGE_SIZE)
        } else {
            payload
        }
    }

    /** Current band size. */
    val bandType: StateFlow<BandType> = bandTypeFlow.asStateFlow()

    /** Current metric (Total Score until the stored preference is read). */
    val metric: StateFlow<BandRankingMetric?> = metricFlow.asStateFlow()

    /** Current one-based page. */
    val page: StateFlow<Int> = pageFlow.asStateFlow()

    /** Current page rows. */
    val board: StateFlow<LoadState<BandRankingsPayload>> = boardLoader.state

    private val displayedFlow = MutableStateFlow<BandRankingsPayload?>(null)

    /** The last loaded page for the current size and metric (see [FullRankingsViewModel.displayed]). */
    val displayed: StateFlow<BandRankingsPayload?> = displayedFlow.asStateFlow()

    init {
        viewModelScope.launch { boardLoader.state.collect { (it as? LoadState.Loaded)?.let { loaded -> displayedFlow.value = loaded.value } } }
        viewModelScope.launch {
            val initial = rankBy.map { it.bandMetric }.distinctUntilChanged()
            initial.collect { stored ->
                if (metricFlow.value == null) {
                    metricFlow.value = stored
                    boardLoader.retry()
                }
            }
        }
    }

    /**
     * Switch band size and return to page 1.
     *
     * @param bandType New size.
     */
    fun selectBandType(bandType: BandType) {
        if (bandType == bandTypeFlow.value) return
        bandTypeFlow.value = bandType
        pageFlow.value = 1
        displayedFlow.value = null
        boardLoader.retry()
    }

    /**
     * Switch metric and return to page 1.
     *
     * @param metric New band metric.
     */
    fun selectMetric(metric: BandRankingMetric) {
        if (metric == metricFlow.value) return
        metricFlow.value = metric
        pageFlow.value = 1
        displayedFlow.value = null
        boardLoader.retry()
    }

    /**
     * Go to a page.
     *
     * @param page One-based page.
     */
    fun goTo(page: Int) {
        pageFlow.value = page.coerceAtLeast(1)
        boardLoader.retry()
    }

    /** Retry the current page. */
    fun retry() = boardLoader.retry()
}

// endregion
