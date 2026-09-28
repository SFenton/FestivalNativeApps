package com.festivalscoretracker.android.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.profile.PercentileBar
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.profile.PlayerStatistics
import com.festivalscoretracker.android.core.profile.PlayerStats
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.LoadState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// region Reads

/**
 * The keyless reads the player page uses (injected so tests use fakes).
 *
 * @property profile `FestivalApi.playerProfile`.
 * @property ranking `FestivalApi.playerInstrumentRanking`.
 * @property rankHistory `FestivalApi.playerRankHistory` (30 days).
 */
class ProfileReads(
    val profile: suspend (String) -> PlayerProfilePayload,
    val ranking: suspend (Instrument, String) -> PlayerInstrumentRankingPayload,
    val rankHistory: suspend (Instrument, String) -> PlayerRankHistory,
)

// endregion

// region UI state

/** What the header offers for the shown account. */
enum class PlayerIdentityAction {
    /** Nothing (loading, failed or syncing). */
    None,

    /** No player selected: select directly. */
    Select,

    /** Another player selected: switch after confirmation. */
    Switch,

    /** This is the selected player: deselect after confirmation. */
    Deselect,

    /** The read had no verified publication header; selection is paused. */
    Unverified,

    /** Published scores changed since this read; reload before selecting. */
    Changed,
}

/** Page-level phase. */
sealed interface ProfilePhase {
    /** Statistics with no selection. */
    data object NoAccount : ProfilePhase

    /** First read in flight. */
    data object Loading : ProfilePhase

    /** HTTP 202: scores still syncing (never an empty profile). */
    data object Syncing : ProfilePhase

    /**
     * Read failed.
     *
     * @property issue Classified failure.
     * @property countdown Seconds to the automatic retry (scrape freeze), else null.
     */
    data class Failed(val issue: ServiceIssue, val countdown: Int?) : ProfilePhase

    /** Content shown. */
    data object Loaded : ProfilePhase
}

/**
 * One stat tile (value over a label).
 *
 * @property label Label.
 * @property value Value text.
 * @property gold Gold tint (gold stars, full combos, top 5%).
 */
data class PlayerStatTile(val label: String, val value: String, val gold: Boolean = false) {
    /** Screen-reader text. */
    val announcement: String get() = "$label: $value"
}

/**
 * One Settings-visible chart's client-side section.
 *
 * @property instrument Chart.
 * @property hasScores Whether the chart has any scores (unplayed charts read nothing).
 * @property stats Stat tiles.
 * @property percentiles Placement bars.
 */
data class PlayerInstrumentSection(
    val instrument: Instrument,
    val hasScores: Boolean,
    val stats: List<PlayerStatTile>,
    val percentiles: List<PercentileBar>,
)

/** Global-rank lifecycle for one chart. */
sealed interface RankLoad {
    /** Loading. */
    data object Loading : RankLoad

    /** HTTP 404: not ranked yet. */
    data object Unranked : RankLoad

    /**
     * Rank shown.
     *
     * @property tiles Global Rank, Total Score and Percentile tiles.
     */
    data class Available(val tiles: List<PlayerStatTile>) : RankLoad

    /**
     * Failed with an inline retry.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : RankLoad
}

/** Rank-history lifecycle for one chart. */
sealed interface RankHistoryLoad {
    /** Loading. */
    data object Loading : RankHistoryLoad

    /**
     * Loaded.
     *
     * @property chart Geometry, or null with no ranked snapshots (card hidden).
     */
    data class Loaded(val chart: RankHistoryChartModel?) : RankHistoryLoad

    /**
     * Failed with an inline retry.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : RankHistoryLoad
}

/**
 * Everything the player page renders.
 *
 * @property accountId Shown account ("" when Statistics has no selection).
 * @property displayName Server name, else the selected/route name, else the account ID.
 * @property isSelected Whether this is the selected player ("This Is Me").
 * @property phase Page phase.
 * @property identity Header action.
 * @property overview Overview tiles.
 * @property instruments One section per Settings-visible chart.
 * @property actionError Why the last Select failed.
 */
data class PlayerProfileUiState(
    val accountId: String = "",
    val displayName: String = "",
    val isSelected: Boolean = false,
    val phase: ProfilePhase = ProfilePhase.Loading,
    val identity: PlayerIdentityAction = PlayerIdentityAction.None,
    val overview: List<PlayerStatTile> = emptyList(),
    val instruments: List<PlayerInstrumentSection> = emptyList(),
    val actionError: String? = null,
) {
    /** "This Is Me" or "Public Profile". */
    val subtitle: String get() = if (isSelected) "This Is Me" else "Public Profile"

    /** Select button label. */
    val selectLabel: String get() = if (identity == PlayerIdentityAction.Switch) "Switch to This Profile" else "Select Profile"

    /** Why selection is paused, or null. */
    val identityNotice: String?
        get() = when (identity) {
            PlayerIdentityAction.Unverified -> "These scores have no verified publication. Selection is paused."
            PlayerIdentityAction.Changed -> "Published scores changed. Reload this page before selecting."
            else -> null
        }
}

// endregion

// region View model

/**
 * The player page (`/player/:accountId`) and the Statistics tab (the selected
 * player's profile; the web renders both from `PlayerPage`). Reads only the keyless
 * compact profile, the per-instrument rankings row and rank history — never
 * player-stats. Select, Switch and Deselect never navigate away.
 *
 * @param accountId Viewed account, or null to follow the selected player (Statistics).
 * @param routeDisplayName Name known before the read (search result or leaderboard row).
 * @param reads Keyless reads.
 * @param store Selected player's scores (mirrored instead of reading again).
 * @param settings Effective settings (selected player and visible charts).
 * @param publications Current publication (`FestivalApi.publicationChanges`).
 * @param backoff Shared scrape-freeze backoff.
 * @param onSelect Persist a selection (`ShellViewModel.selectPlayer`).
 * @param onDeselect Persist a deselection.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PlayerProfileViewModel(
    accountId: String?,
    private val routeDisplayName: String?,
    private val reads: ProfileReads,
    private val store: SelectedProfileStore,
    private val settings: StateFlow<AppSettings?>,
    private val publications: StateFlow<Int?>,
    private val backoff: ServiceRetryBackoff,
    private val onSelect: (SelectedPlayer) -> Unit,
    private val onDeselect: () -> Unit,
) : ViewModel() {
    /** Whether this is the Statistics root (always the selected player). */
    val followsSelection: Boolean = accountId == null

    private val target = MutableStateFlow(accountId ?: settings.value?.selectedPlayer?.accountId ?: "")
    private val viewed = MutableStateFlow<LoadState<PlayerProfilePayload>>(LoadState.Loading)
    private var viewedAccount: String? = null
    private var viewedJob: Job? = null
    private val actionError = MutableStateFlow<String?>(null)
    private val rankLoads = MutableStateFlow<Map<Instrument, RankLoad>>(emptyMap())
    private val historyLoads = MutableStateFlow<Map<Instrument, RankHistoryLoad>>(emptyMap())
    private val sectionJobs = mutableMapOf<String, Job>()
    private var sectionKey: String? = null
    private var memo: Triple<PlayerProfileResponse, Set<Instrument>, Pair<List<PlayerStatTile>, List<PlayerInstrumentSection>>>? = null

    private val selectedAccount = settings.map { it?.selectedPlayer?.accountId }.distinctUntilChanged()

    private val source = combine(target, selectedAccount) { account, selected -> account to selected }
        .distinctUntilChanged()
        .flatMapLatest { (account, selected) ->
            when {
                account.isEmpty() -> flowOf(account to null)
                account.equals(selected, ignoreCase = true) -> store.state.map { state ->
                    account to if (state.player?.accountId.equals(account, ignoreCase = true)) state.load else LoadState.Loading
                }
                else -> {
                    startViewed(account)
                    viewed.map { account to it }
                }
            }
        }

    /** Page state. */
    val state: StateFlow<PlayerProfileUiState> = combine(source, settings, publications, actionError) { (account, load), current, publication, error ->
        build(account, load, current, publication, error)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, PlayerProfileUiState(accountId = target.value))

    /** Global rank per chart, loaded when its section is shown. */
    val ranks: StateFlow<Map<Instrument, RankLoad>> = rankLoads.asStateFlow()

    /** Rank history per chart, loaded when its section is shown. */
    val rankHistories: StateFlow<Map<Instrument, RankHistoryLoad>> = historyLoads.asStateFlow()

    init {
        if (followsSelection) {
            viewModelScope.launch {
                settings.map { it?.selectedPlayer?.accountId ?: "" }.distinctUntilChanged().collect { account ->
                    if (!account.equals(target.value, ignoreCase = true)) actionError.value = null
                    target.value = account
                }
            }
        }
    }

    // region Actions

    /** Force a fresh read (Retry). */
    fun retry() {
        val current = state.value
        if (current.isSelected) {
            store.retry()
        } else if (current.accountId.isNotEmpty()) {
            viewedAccount = null
            startViewed(current.accountId)
        }
    }

    /** Select (or switch to) the shown player; the caller confirms a switch first. Never navigates. */
    fun select() {
        val current = state.value
        val payload = currentPayload() ?: return
        if (current.identity != PlayerIdentityAction.Select && current.identity != PlayerIdentityAction.Switch) return
        val player = SelectedPlayer.validated(current.accountId, current.displayName)
        if (player == null || !payload.isSelectable(publications.value)) {
            actionError.value = "This profile could not be selected. Reload the page and try again."
            return
        }
        actionError.value = null
        store.seed(player, payload)
        onSelect(player)
    }

    /** Deselect the shown (selected) player; the caller confirms first. Never navigates. */
    fun deselect() {
        val current = state.value
        if (current.identity != PlayerIdentityAction.Deselect) return
        // Keep showing the same read as a viewed profile instead of reading again.
        val payload = currentPayload()
        if (payload != null && !followsSelection) {
            viewedJob?.cancel()
            viewedAccount = current.accountId
            viewed.value = LoadState.Loaded(payload)
        }
        onDeselect()
    }

    /**
     * Start the rank and rank-history reads for one chart once (when its section is shown).
     *
     * @param instrument Chart.
     */
    fun ensureInstrument(instrument: Instrument) {
        val current = state.value
        val section = current.instruments.firstOrNull { it.instrument == instrument } ?: return
        if (!section.hasScores || current.phase != ProfilePhase.Loaded) return
        if (instrument !in rankLoads.value) loadRank(current.accountId, instrument)
        if (instrument !in historyLoads.value) loadRankHistory(current.accountId, instrument)
    }

    /**
     * Retry one chart's global rank.
     *
     * @param instrument Chart.
     */
    fun retryRank(instrument: Instrument) {
        loadRank(state.value.accountId, instrument)
    }

    /**
     * Retry one chart's rank history.
     *
     * @param instrument Chart.
     */
    fun retryRankHistory(instrument: Instrument) {
        loadRankHistory(state.value.accountId, instrument)
    }

    // endregion

    // region Loading

    private fun currentPayload(): PlayerProfilePayload? {
        val current = state.value
        return if (current.isSelected) {
            store.state.value.payload?.takeIf { it.belongsTo(current.accountId) }
        } else {
            (viewed.value as? LoadState.Loaded)?.value?.takeIf { it.belongsTo(current.accountId) }
        }
    }

    private fun startViewed(account: String) {
        if (viewedAccount.equals(account, ignoreCase = true) && viewed.value !is LoadState.Failed) return
        viewedAccount = account
        viewedJob?.cancel()
        viewedJob = viewModelScope.launch {
            val key = "player-profile:$account"
            while (true) {
                viewed.value = LoadState.Loading
                try {
                    val payload = reads.profile(account)
                    backoff.reset(key)
                    viewed.value = LoadState.Loaded(payload)
                    return@launch
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    val issue = ServiceIssue.from(error)
                    if (!issue.retriesAutomatically) {
                        viewed.value = LoadState.Failed(issue)
                        return@launch
                    }
                    var remaining = backoff.nextDelay(key, issue.retryAfterSeconds)
                    while (remaining > 0) {
                        viewed.value = LoadState.Failed(issue, remaining)
                        delay(1_000)
                        remaining--
                    }
                }
            }
        }
    }

    private fun loadRank(account: String, instrument: Instrument) {
        sectionJobs.remove("rank:$instrument")?.cancel()
        rankLoads.value = rankLoads.value + (instrument to RankLoad.Loading)
        sectionJobs["rank:$instrument"] = viewModelScope.launch {
            val result = try {
                val ranking = reads.ranking(instrument, account).ranking
                if (ranking == null) {
                    RankLoad.Unranked
                } else {
                    RankLoad.Available(
                        listOf(
                            PlayerStatTile("Global Rank", ProfileFormatting.rank(ranking.totalScoreRank)),
                            PlayerStatTile("Total Score", ProfileFormatting.count(ranking.totalScore)),
                            PlayerStatTile(
                                "Percentile",
                                ranking.totalScorePercentile?.let(ProfileFormatting::topPercent) ?: "—",
                                gold = ranking.isTopFive,
                            ),
                        ),
                    )
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                RankLoad.Failed(ServiceIssue.from(error))
            }
            rankLoads.value = rankLoads.value + (instrument to result)
        }
    }

    private fun loadRankHistory(account: String, instrument: Instrument) {
        sectionJobs.remove("history:$instrument")?.cancel()
        historyLoads.value = historyLoads.value + (instrument to RankHistoryLoad.Loading)
        sectionJobs["history:$instrument"] = viewModelScope.launch {
            val result = try {
                RankHistoryLoad.Loaded(RankHistoryChartModel.build(reads.rankHistory(instrument, account).rankedChronological))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                RankHistoryLoad.Failed(ServiceIssue.from(error))
            }
            historyLoads.value = historyLoads.value + (instrument to result)
        }
    }

    // endregion

    // region Building

    private fun build(
        account: String,
        load: LoadState<PlayerProfilePayload>?,
        current: AppSettings?,
        publication: Int?,
        error: String?,
    ): PlayerProfileUiState {
        val selected = current?.selectedPlayer
        val isSelected = account.isNotEmpty() && selected?.accountId.equals(account, ignoreCase = true)
        val payload = (load as? LoadState.Loaded)?.value?.takeIf { it.belongsTo(account) }
        resetSections("$account:${payload?.observedPublicationId}")
        val name = payload?.profile?.displayName ?: selected?.takeIf { isSelected }?.displayName ?: routeDisplayName ?: account
        val phase = when {
            account.isEmpty() -> ProfilePhase.NoAccount
            load is LoadState.Failed -> ProfilePhase.Failed(load.issue, load.countdown)
            payload == null -> ProfilePhase.Loading
            payload.state == PlayerProfileState.Syncing -> ProfilePhase.Syncing
            else -> ProfilePhase.Loaded
        }
        val identity = when {
            phase != ProfilePhase.Loaded || payload == null -> PlayerIdentityAction.None
            isSelected -> PlayerIdentityAction.Deselect
            payload.publicationId == null -> PlayerIdentityAction.Unverified
            !payload.isSelectable(publication) -> PlayerIdentityAction.Changed
            selected != null -> PlayerIdentityAction.Switch
            else -> PlayerIdentityAction.Select
        }
        val (overview, instruments) = if (phase == ProfilePhase.Loaded && payload != null) {
            sections(payload.profile, current?.visibleInstruments ?: Instrument.entries.toSet())
        } else {
            emptyList<PlayerStatTile>() to emptyList()
        }
        return PlayerProfileUiState(account, name, isSelected, phase, identity, overview, instruments, error)
    }

    private fun resetSections(key: String) {
        if (key == sectionKey) return
        sectionKey = key
        sectionJobs.values.forEach { it.cancel() }
        sectionJobs.clear()
        rankLoads.value = emptyMap()
        historyLoads.value = emptyMap()
    }

    private fun sections(profile: PlayerProfileResponse, visible: Set<Instrument>): Pair<List<PlayerStatTile>, List<PlayerInstrumentSection>> {
        memo?.let { (p, v, result) -> if (p === profile && v == visible) return result }
        val stats = PlayerStatistics.overall(profile, visible)
        val overview = listOf(
            PlayerStatTile("Songs Played", ProfileFormatting.count(stats.songsPlayed.toLong())),
            PlayerStatTile("Full Combos", fullComboText(stats)),
            PlayerStatTile("Gold Stars", ProfileFormatting.count(stats.goldStarCount.toLong()), gold = true),
            PlayerStatTile("Avg Accuracy", accuracyText(stats)),
            PlayerStatTile("Best Rank", stats.bestRank?.let(ProfileFormatting::rank) ?: "—"),
        )
        val instruments = Instrument.entries.filter { it in visible }.map { instrument ->
            val chart = PlayerStatistics.forInstrument(profile, instrument)
            PlayerInstrumentSection(
                instrument = instrument,
                hasScores = chart.songsPlayed > 0,
                stats = listOf(
                    PlayerStatTile("Songs Played", ProfileFormatting.count(chart.songsPlayed.toLong())),
                    PlayerStatTile("Full Combos", fullComboText(chart), gold = chart.fullComboCount > 0),
                    PlayerStatTile("Gold Stars", ProfileFormatting.count(chart.goldStarCount.toLong()), gold = true),
                    PlayerStatTile("5 Stars", ProfileFormatting.count(chart.fiveStarCount.toLong())),
                    PlayerStatTile("Avg Accuracy", accuracyText(chart)),
                    PlayerStatTile("Best Rank", chart.bestRank?.let(ProfileFormatting::rank) ?: "—"),
                ),
                percentiles = PercentileBar.build(PlayerStatistics.percentileBuckets(profile, instrument)),
            )
        }
        val result = overview to instruments
        memo = Triple(profile, visible, result)
        return result
    }

    private fun fullComboText(stats: PlayerStats): String =
        if (stats.fullComboCount == 0) "0" else "${ProfileFormatting.count(stats.fullComboCount.toLong())} (${ProfileFormatting.percent(stats.fullComboPercent)}%)"

    private fun accuracyText(stats: PlayerStats): String = stats.averageAccuracy?.let { ScoreFormatting.accuracy(it) + "%" } ?: "—"

    // endregion
}

// endregion
