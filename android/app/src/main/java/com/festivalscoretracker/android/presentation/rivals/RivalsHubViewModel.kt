package com.festivalscoretracker.android.presentation.rivals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalCommonRivals
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalSettingsScope
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.rivals.rivalEntries
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

// region Hub state

/** The hub's two lists (web `?tab=`). */
enum class RivalsHubTab(val title: String) {
    Song(RivalText.SONG_TAB),
    Leaderboard(RivalText.LEADERBOARD_TAB),
}

/**
 * One hub card: a scope's 3-above/3-below preview.
 *
 * @property id Quick-link and test ID: `common`, `combo`, a chart wire ID, or `leaderboard.<wireId>`.
 * @property title Title Case card title.
 * @property instrument Header icon, for single-chart cards.
 * @property seeAll Scope opened by "View All" / "View All Rivals".
 * @property rowScope Scope carried by a tapped row into Rival Detail.
 * @property state Loading, failed, or the preview rows (empty cards are omitted once loaded).
 */
data class RivalsHubSection(
    val id: String,
    val title: String,
    val instrument: Instrument?,
    val seeAll: RivalScope,
    val rowScope: RivalScope,
    val state: LoadState<List<RivalEntry>>,
)

/**
 * Everything the hub renders for one tab.
 *
 * @property sections Cards in web order; loaded-empty cards removed.
 * @property settled Whether every read finished (loaded or failed).
 * @property fullPageIssue Set when every read failed: show the full-page status.
 * @property countdown Automatic retry countdown for [fullPageIssue].
 * @property empty Whether every read loaded and nothing had rivals.
 */
data class RivalsHubContent(
    val sections: List<RivalsHubSection>,
    val settled: Boolean,
    val fullPageIssue: ServiceIssue?,
    val countdown: Int?,
    val empty: Boolean,
)

// endregion

// region Hub view model

/**
 * Rivals hub logic (web `RivalsPage` + `LeaderboardRivalsTab`). Every Settings-visible
 * chart, the Settings-derived combo and Common Rivals load independently with the
 * shared service-status semantics; a scrape freeze counts down and retries.
 *
 * @param accountId Selected player.
 * @param visible Settings-visible charts.
 * @param repository Rivals reads.
 * @param backoff Shared retry backoff.
 * @param experimentalRanks Settings → Experimental Ranks: offers the Leaderboard Rivals Rank By
 *   (web `RivalsPage`); while off the tab ranks by Total Score only (experimental-ranks R1).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RivalsHubViewModel(
    private val accountId: String,
    visible: Set<Instrument>,
    private val repository: RivalsRepository,
    private val backoff: ServiceRetryBackoff,
    experimentalRanks: Boolean = false,
) : ViewModel() {
    private val charts = Instrument.entries.filter { it in visible }
    private val comboToken = RivalCombo.deriveToken(charts)
    private val tabFlow = MutableStateFlow(RivalsHubTab.Song)

    private val songLoaders = charts.associateWith { chart ->
        RetryingLoader(viewModelScope, "rivals:$accountId:${chart.wireId}", backoff) { refresh -> repository.list(accountId, chart.wireId, refresh) }
    }
    private val comboLoader = comboToken?.let { token ->
        RetryingLoader(viewModelScope, "rivals:$accountId:$token", backoff) { refresh -> repository.list(accountId, token, refresh) }
    }
    private val metricFlow = MutableStateFlow(RivalRankMetric.TotalScore)
    private val leaderboardLoaderSets = mutableMapOf<RivalRankMetric, Map<Instrument, RetryingLoader<LeaderboardRivalsListResponse>>>()

    /** Selected tab. */
    val tab: StateFlow<RivalsHubTab> = tabFlow.asStateFlow()

    /** Leaderboard Rivals Rank By (web `?rankBy=`, not persisted). */
    val rankBy: StateFlow<RivalRankMetric> = metricFlow.asStateFlow()

    /** Rank By choices: every metric with Experimental Ranks on, else Total Score only. */
    val rankByOptions: List<RivalRankMetric> =
        if (experimentalRanks) RivalRankMetric.entries.toList() else listOf(RivalRankMetric.TotalScore)

    /** Song Rivals content. */
    val songContent: StateFlow<RivalsHubContent> = combineStates(songLoaders.values.map { it.state } + listOfNotNull(comboLoader?.state)) { states ->
        buildSongContent(states.take(charts.size), comboLoader?.let { states.last() })
    }

    /** Leaderboard Rivals content for the selected [rankBy]. */
    val leaderboardContent: StateFlow<RivalsHubContent> = metricFlow
        .flatMapLatest { metric ->
            val states = leaderboardLoaders(metric).values.map { it.state }
            if (states.isEmpty()) flowOf(buildLeaderboardContent(metric, emptyList())) else combine(states) { buildLeaderboardContent(metric, it.toList()) }
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, buildLeaderboardContent(RivalRankMetric.TotalScore, charts.map { LoadState.Loading }))

    init {
        songLoaders.values.forEach { it.ensureStarted() }
        comboLoader?.ensureStarted()
    }

    /**
     * Switch tabs; the leaderboard reads start the first time that tab is shown.
     *
     * @param tab New tab.
     */
    fun select(tab: RivalsHubTab) {
        tabFlow.value = tab
        if (tab == RivalsHubTab.Leaderboard) leaderboardLoaders().values.forEach { it.ensureStarted() }
    }

    /**
     * Change the Leaderboard Rivals Rank By; a metric not in [rankByOptions] is ignored
     * (experimental-ranks R2). Each metric's lists load once and are kept.
     *
     * @param metric New metric.
     */
    fun selectRankBy(metric: RivalRankMetric) {
        if (metric !in rankByOptions || metric == metricFlow.value) return
        metricFlow.value = metric
        if (tabFlow.value == RivalsHubTab.Leaderboard) leaderboardLoaders(metric).values.forEach { it.ensureStarted() }
    }

    /** Retry every failed read on the current tab. */
    fun retryFailed() {
        activeLoaders().filter { it.state.value is LoadState.Failed }.forEach { it.retry() }
    }

    /**
     * Retry one card's reads (Common retries every chart).
     *
     * @param sectionId Card ID.
     */
    fun retry(sectionId: String) {
        when {
            sectionId == COMMON_ID -> songLoaders.values.filter { it.state.value is LoadState.Failed }.forEach { it.retry() }
            sectionId == COMBO_ID -> comboLoader?.retry()
            sectionId.startsWith("leaderboard.") -> leaderboardLoaders()[Instrument.fromWireId(sectionId.removePrefix("leaderboard."))]?.retry()
            else -> songLoaders[Instrument.fromWireId(sectionId)]?.retry()
        }
    }

    /** Re-read the current tab, keeping content visible (pull to refresh). */
    fun refresh() {
        activeLoaders().forEach { it.refresh() }
    }

    private fun activeLoaders(): List<RetryingLoader<*>> =
        if (tabFlow.value == RivalsHubTab.Song) songLoaders.values + listOfNotNull(comboLoader) else leaderboardLoaders().values.toList()

    private fun leaderboardLoaders(metric: RivalRankMetric = metricFlow.value): Map<Instrument, RetryingLoader<LeaderboardRivalsListResponse>> =
        leaderboardLoaderSets.getOrPut(metric) {
            charts.associateWith { chart ->
                RetryingLoader(viewModelScope, "lbrivals:$accountId:${chart.wireId}:${metric.wireId}", backoff) { refresh ->
                    repository.leaderboardList(accountId, chart, metric, refresh)
                }
            }
        }

    private fun buildLeaderboardContent(metric: RivalRankMetric, states: List<LoadState<LeaderboardRivalsListResponse>>): RivalsHubContent =
        assemble(
            charts.zip(states).map { (chart, state) ->
                RivalsHubSection(
                    id = "leaderboard.${chart.wireId}",
                    title = RivalText.rivalsTitle(chart.label),
                    instrument = chart,
                    seeAll = RivalScope.Leaderboard(chart, metric),
                    rowScope = RivalScope.Leaderboard(chart, metric),
                    state = state.map { rivalEntries(it.above, it.below, PREVIEW_COUNT) },
                )
            },
        )

    private fun buildSongContent(states: List<LoadState<RivalsListResponse>>, combo: LoadState<RivalsListResponse>?): RivalsHubContent {
        val perChart = charts.zip(states)
        val sections = mutableListOf<RivalsHubSection>()
        if (charts.size >= 2) {
            val settled = states.none { it is LoadState.Loading }
            val loaded = states.mapNotNull { (it as? LoadState.Loaded)?.value }
            // Web: the intersection covers the lists that loaded; failed charts don't block it.
            val common: LoadState<List<RivalEntry>> = if (!settled) {
                LoadState.Loading
            } else {
                val (above, below) = RivalCommonRivals.intersect(loaded)
                LoadState.Loaded(rivalEntries(above, below, PREVIEW_COUNT))
            }
            sections += RivalsHubSection(
                COMMON_ID, RivalText.COMMON_RIVALS, null,
                seeAll = RivalScopes.song(charts), rowScope = RivalScopes.song(charts), state = common,
            )
        }
        if (combo != null && comboToken != null) {
            val label = if (comboToken == RivalCombo.PRO_DRUMS_TOKEN) RivalText.PRO_DRUMS_FAMILY else RivalText.COMBINED
            sections += RivalsHubSection(
                COMBO_ID, RivalText.rivalsTitle(label), null,
                seeAll = RivalScope.FromSettings(RivalSettingsScope.Combo), rowScope = RivalScope.Combo(comboToken),
                state = combo.map { rivalEntries(it.above, it.below, PREVIEW_COUNT) },
            )
        }
        perChart.forEach { (chart, state) ->
            sections += RivalsHubSection(
                chart.wireId, RivalText.rivalsTitle(chart.label), chart,
                seeAll = RivalScopes.song(listOf(chart)), rowScope = RivalScopes.song(listOf(chart)),
                state = state.map { rivalEntries(it.above, it.below, PREVIEW_COUNT) },
            )
        }
        return assemble(sections, rawStates = states + listOfNotNull(combo))
    }

    private fun assemble(sections: List<RivalsHubSection>, rawStates: List<LoadState<*>> = sections.map { it.state }): RivalsHubContent {
        val settled = rawStates.none { it is LoadState.Loading }
        val failures = rawStates.filterIsInstance<LoadState.Failed>()
        val allFailed = rawStates.isNotEmpty() && failures.size == rawStates.size
        val visibleSections = sections.filter { (it.state as? LoadState.Loaded)?.value?.isEmpty() != true }
        val empty = settled && failures.isEmpty() && visibleSections.isEmpty()
        return RivalsHubContent(
            sections = visibleSections,
            settled = settled,
            fullPageIssue = if (allFailed) failures.first().issue else null,
            countdown = if (allFailed) failures.first().countdown else null,
            empty = empty,
        )
    }

    private fun <T> combineStates(flows: List<StateFlow<LoadState<T>>>, transform: (List<LoadState<T>>) -> RivalsHubContent): StateFlow<RivalsHubContent> {
        val initial = transform(flows.map { it.value })
        if (flows.isEmpty()) return MutableStateFlow(initial)
        return combine(flows) { transform(it.toList()) }.stateIn(viewModelScope, SharingStarted.Eagerly, initial)
    }

    companion object {
        /** Rows kept from each side of a hub card. */
        const val PREVIEW_COUNT = 3

        /** Common Rivals card ID. */
        const val COMMON_ID = "common"

        /** Combo card ID. */
        const val COMBO_ID = "combo"
    }
}

/**
 * Map a loaded value, keeping loading/failed states.
 *
 * @param transform Mapping.
 * @return Mapped state.
 */
fun <T, R> LoadState<T>.map(transform: (T) -> R): LoadState<R> = when (this) {
    LoadState.Loading -> LoadState.Loading
    is LoadState.Failed -> this
    is LoadState.Loaded -> LoadState.Loaded(transform(value), refreshing)
}

// endregion
