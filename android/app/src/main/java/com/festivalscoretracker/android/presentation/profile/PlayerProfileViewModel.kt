package com.festivalscoretracker.android.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerPercentileBucket
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.profile.PlayerStatistics
import com.festivalscoretracker.android.core.profile.PlayerStats
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.PlayerTopSongs
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.RankHistoryChartModel
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.profile.StatTints
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
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
 * @property catalog Catalogue songs for top-song titles and art (`FestivalApi.catalog`, cached in process).
 * @property bands First page of the player's bands (`FestivalApi.playerBands`, group All,
 *   [PlayerProfileViewModel.BANDS_PREVIEW_SIZE] rows; a pure read, never band search).
 */
class ProfileReads(
    val profile: suspend (String) -> PlayerProfilePayload,
    val ranking: suspend (Instrument, String) -> PlayerInstrumentRankingPayload,
    val rankHistory: suspend (Instrument, String) -> PlayerRankHistory,
    val catalog: suspend () -> List<Song> = { emptyList() },
    val bands: suspend (String) -> PlayerBandListResponse = { PlayerBandListResponse(accountId = it) },
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
 * One stat tile (web `StatBox`: value over an uppercase label, its own card).
 *
 * @property id Stable key within its grid (`songs-played`, `stars-6`…), the lazy key and test-tag suffix.
 * @property label Label.
 * @property value Value text.
 * @property tint Value colour `0xRRGGBB` ([StatTints]), or null for the default blue.
 * @property action What tapping does (web `StatBox.onClick`), or null for a flat tile.
 * @property stars Show this many star images instead of [value] (6 = five gold stars; web `GoldStars`).
 * @property placeholder Still loading: [value] is a same-width stand-in drawn redacted.
 * @property spokenLabel Screen-reader label when [label] is ambiguous on its own.
 */
data class PlayerStatTile(
    val id: String,
    val label: String,
    val value: String,
    val tint: Int? = null,
    val action: PlayerTileAction? = null,
    val stars: Int? = null,
    val placeholder: Boolean = false,
    val spokenLabel: String = label,
) {
    /** Gold value (gold stars, 100% full combos, top 5%). */
    val gold: Boolean get() = tint == StatTints.GOLD

    /** Screen-reader text. */
    val announcement: String get() = if (placeholder) "$spokenLabel: loading" else "$spokenLabel: $value"
}

/**
 * One percentile table row (web `PlayerPercentileRow`).
 *
 * @property bucket Band.
 * @property action Songs filtered to the band (web `instPercentileBucketUpdater`).
 */
data class PercentileRow(val bucket: PlayerPercentileBucket, val action: PlayerTileAction? = null) {
    /** Screen-reader text. */
    val announcement: String get() = "${bucket.label}: ${bucket.count} ${if (bucket.count == 1) "song" else "songs"}"
}

/** Outcome of a tile or top-song tap. */
sealed interface ProfileActionResult {
    /**
     * Show a destination (the Songs filter is already saved).
     *
     * @property route Destination.
     */
    data class Navigate(val route: AppRoute) : ProfileActionResult

    /** Another player is selected: confirm the switch first (web "Switch to {name}"). */
    data object ConfirmSwitch : ProfileActionResult

    /** Selection is paused (unverified or changed publication), so the Songs filter cannot apply. */
    data object Unavailable : ProfileActionResult
}

/**
 * One Settings-visible chart's client-side section.
 *
 * The web's tile order is [stats], then the global-rank tile (loaded separately,
 * [RankLoad.tile]), then [trailing].
 *
 * @property instrument Chart.
 * @property hasScores Whether the chart has any scores (unplayed charts read nothing).
 * @property stats Tiles before the rank tile (Songs Played … Best Song Rank).
 * @property percentiles Percentile table rows, best first.
 * @property trailing Tiles after the rank tile (Percentile, Songs Played percentile).
 */
data class PlayerInstrumentSection(
    val instrument: Instrument,
    val hasScores: Boolean,
    val stats: List<PlayerStatTile>,
    val percentiles: List<PercentileRow>,
    val trailing: List<PlayerStatTile> = emptyList(),
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
     * @property tiles The Total Score Rank tile.
     */
    data class Available(val tiles: List<PlayerStatTile>) : RankLoad

    /**
     * Failed with an inline retry.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : RankLoad

    companion object {
        /** The rank tile's stable id. */
        const val TILE_ID = "global-rank"

        /** The rank tile's label (web `player.totalScoreRank`). */
        const val TILE_LABEL = "Total Score Rank"

        /**
         * The rank tile for any state, so the grid keeps its shape: a same-width
         * placeholder while loading, an em dash when unranked or failed.
         *
         * @param load State, or null before the read starts.
         * @return Tile.
         */
        fun tile(load: RankLoad?): PlayerStatTile = when (load) {
            is Available -> load.tiles.first()
            null, Loading -> PlayerStatTile(TILE_ID, TILE_LABEL, "#0,000", placeholder = true)
            Unranked, is Failed -> PlayerStatTile(TILE_ID, TILE_LABEL, "—")
        }
    }
}

/** Bands preview lifecycle (web `PlayerBandsSection`). */
sealed interface BandsLoad {
    /** Loading. */
    data object Loading : BandsLoad

    /**
     * Loaded.
     *
     * @property bands First page (group All).
     */
    data class Loaded(val bands: PlayerBandListResponse) : BandsLoad

    /**
     * Failed with an inline retry.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : BandsLoad
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
 * @property isSelected Whether this is the selected player (shown only through the Deselect action).
 * @property phase Page phase.
 * @property identity Header action.
 * @property overview Overview tiles.
 * @property instruments One section per Settings-visible chart.
 * @property actionError Why the last Select failed.
 * @property topSongs Top/bottom five per Settings-visible chart.
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
    val topSongs: List<PlayerTopSongs> = emptyList(),
) {
    /**
     * Whether a tile action can run now: selected pages always can; a viewed page can
     * when selecting it is possible, or when the action does not need the selection.
     *
     * @param action Action.
     * @return True when the tile is interactive.
     */
    fun canRun(action: PlayerTileAction): Boolean =
        isSelected || identity == PlayerIdentityAction.Select || identity == PlayerIdentityAction.Switch || !action.requiresSelection

    /** Select button label. */
    val selectLabel: String get() = if (identity == PlayerIdentityAction.Switch) "Switch to This Profile" else "Select Profile"

    /** Why selection is paused, or null. */
    val identityNotice: String?
        get() = when (identity) {
            PlayerIdentityAction.Unverified -> "These scores have no verified publication. Selection is paused."
            PlayerIdentityAction.Changed -> "Published scores changed. Reload this page before selecting."
            else -> null
        }

    /** Whether the page needs its identity row: a Select/Switch button, a paused-selection notice or an action error. */
    val showsIdentityRow: Boolean
        get() = identity == PlayerIdentityAction.Select || identity == PlayerIdentityAction.Switch ||
            identityNotice != null || actionError != null
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
 * @param saveSongsPreset Persist a stat tile's Songs filter before showing Songs.
 * @param artworkUrl Resolve catalogue art for top-song rows (`FestivalApi.artworkUrl`).
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
    private val saveSongsPreset: suspend (SongsPreset) -> Unit = {},
    private val artworkUrl: (String?) -> String? = { null },
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
    private val bandsLoad = MutableStateFlow<BandsLoad?>(null)
    private val sectionJobs = mutableMapOf<String, Job>()
    private var sectionKey: String? = null
    private var memo: Pair<SectionsKey, Pair<List<PlayerStatTile>, List<PlayerInstrumentSection>>>? = null
    private var topMemo: Triple<PlayerProfileResponse, Set<Instrument>, Pair<Map<String, Song>, List<PlayerTopSongs>>>? = null
    private val catalog = MutableStateFlow<Map<String, Song>>(emptyMap())
    private var catalogJob: Job? = null

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
    val state: StateFlow<PlayerProfileUiState> = combine(source, settings, publications, actionError, catalog) { (account, load), current, publication, error, songs ->
        build(account, load, current, publication, error, songs)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, PlayerProfileUiState(accountId = target.value))

    /** Global rank per chart, loaded when its section is shown. */
    val ranks: StateFlow<Map<Instrument, RankLoad>> = rankLoads.asStateFlow()

    /** Rank history per chart, loaded when its section is shown. */
    val rankHistories: StateFlow<Map<Instrument, RankHistoryLoad>> = historyLoads.asStateFlow()

    /** Bands preview, loaded when its section is shown (null until then). */
    val bands: StateFlow<BandsLoad?> = bandsLoad.asStateFlow()

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

    /**
     * Run a tile or top-song action (web `withProfileSwitch`): a viewed player is selected
     * first when possible (a switch needs [confirmedSwitch]); a Songs filter is saved
     * before the Songs route is returned.
     *
     * @param action Action.
     * @param confirmedSwitch The user confirmed replacing another selected player.
     * @return Where to go, or why not yet.
     */
    suspend fun run(action: PlayerTileAction, confirmedSwitch: Boolean = false): ProfileActionResult {
        val current = state.value
        if (!current.isSelected) {
            when (current.identity) {
                PlayerIdentityAction.Select -> select()
                PlayerIdentityAction.Switch -> if (confirmedSwitch) select() else return ProfileActionResult.ConfirmSwitch
                else -> if (action.requiresSelection) return ProfileActionResult.Unavailable
            }
            if (action.requiresSelection && actionError.value != null) return ProfileActionResult.Unavailable
        }
        val route = when (action) {
            is PlayerTileAction.FilterSongs -> {
                saveSongsPreset(action.preset)
                SongsTab
            }
            is PlayerTileAction.OpenSong -> SongDetailRoute(action.songId, action.instrument.wireId)
            is PlayerTileAction.OpenRankings -> FullRankingsRoute(action.instrument.wireId, action.metric.wireId, action.page)
        }
        return ProfileActionResult.Navigate(route)
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

    /** Start the Bands preview read once (when its section is shown). */
    fun ensureBands() {
        val current = state.value
        if (current.phase != ProfilePhase.Loaded || bandsLoad.value != null) return
        loadBands(current.accountId)
    }

    /** Retry the Bands preview. */
    fun retryBands() {
        loadBands(state.value.accountId)
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

    private fun ensureCatalog() {
        if (catalogJob != null) return
        catalogJob = viewModelScope.launch {
            // Titles are optional: a failed read keeps the web's song-ID fallback.
            catalog.value = try {
                reads.catalog().associateBy { it.songId }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                emptyMap()
            }
        }
    }

    private fun loadBands(account: String) {
        sectionJobs.remove("bands")?.cancel()
        bandsLoad.value = BandsLoad.Loading
        sectionJobs["bands"] = viewModelScope.launch {
            bandsLoad.value = try {
                BandsLoad.Loaded(reads.bands(account))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                BandsLoad.Failed(ServiceIssue.from(error))
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
                    // Web per-metric rank card (Total Score; experimental metrics stay off):
                    // opens the full rankings on the page holding this rank.
                    val rank = ranking.totalScoreRank
                    RankLoad.Available(
                        listOf(
                            PlayerStatTile(
                                RankLoad.TILE_ID,
                                RankLoad.TILE_LABEL,
                                if (rank > 0) ProfileFormatting.rank(rank) else "—",
                                action = PlayerTileAction.OpenRankings(instrument, rank = rank).takeIf { rank > 0 },
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
        songs: Map<String, Song>,
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
        val visible = current?.visibleInstruments ?: Instrument.entries.toSet()
        val profile = payload?.profile?.takeIf { phase == ProfilePhase.Loaded }
        if (profile != null) ensureCatalog()
        val leeway = current?.leeway?.takeIf { current.filterInvalidScores }
        val (overview, instruments) = if (profile != null) sections(SectionsKey(profile, visible, songs, leeway)) else emptyList<PlayerStatTile>() to emptyList()
        val topSongs = if (profile != null) topSongs(profile, visible, songs) else emptyList()
        return PlayerProfileUiState(account, name, isSelected, phase, identity, overview, instruments, error, topSongs)
    }

    private fun resetSections(key: String) {
        if (key == sectionKey) return
        sectionKey = key
        sectionJobs.values.forEach { it.cancel() }
        sectionJobs.clear()
        rankLoads.value = emptyMap()
        historyLoads.value = emptyMap()
        bandsLoad.value = null
    }

    /**
     * What the stat sections are built from (memo key).
     *
     * @property profile Loaded profile.
     * @property visible Settings-visible charts.
     * @property songs Catalogue (total songs, CHOpt maxima).
     * @property leeway Filter Invalid Scores leeway, or null when off (no Over CHOpt Threshold tiles).
     */
    private data class SectionsKey(val profile: PlayerProfileResponse, val visible: Set<Instrument>, val songs: Map<String, Song>, val leeway: Double?)

    private fun sections(key: SectionsKey): Pair<List<PlayerStatTile>, List<PlayerInstrumentSection>> {
        memo?.let { (last, result) -> if (last.profile === key.profile && last.visible == key.visible && last.songs === key.songs && last.leeway == key.leeway) return result }
        val (profile, visible, songs, leeway) = key
        val totalSongs = songs.size
        val stats = PlayerStatistics.overall(profile, visible)
        // Web `buildOverallSummaryItems`.
        val overview = listOf(
            PlayerStatTile(
                "songs-played",
                "Songs Played",
                ProfileFormatting.count(stats.songsPlayed.toLong()),
                tint = StatTints.GREEN.takeIf { totalSongs > 0 && stats.songsPlayed >= totalSongs },
                action = PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasScores, visible)),
            ),
            PlayerStatTile(
                "full-combos",
                "Full Combos",
                fullComboText(stats),
                tint = StatTints.GOLD.takeIf { stats.allFullCombos },
                action = PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasFCs, visible)),
            ),
            PlayerStatTile("gold-stars", "Gold Stars", ProfileFormatting.count(stats.goldStarCount.toLong()), tint = StatTints.GOLD),
            accuracyTile(stats),
            PlayerStatTile("best-rank", "Best Song Rank", stats.bestRank?.let(ProfileFormatting::rank) ?: "—", action = bestRankAction(stats)),
        )
        val instruments = Instrument.entries.filter { it in visible }.map { instrument ->
            val chart = PlayerStatistics.forInstrument(profile, instrument)
            PlayerInstrumentSection(
                instrument = instrument,
                hasScores = chart.songsPlayed > 0,
                stats = instrumentTiles(chart, instrument, totalSongs, leeway?.let { PlayerStatistics.overThresholdCount(profile, instrument, songs, it) }),
                percentiles = PlayerStatistics.percentileBuckets(profile, instrument).map { bucket ->
                    PercentileRow(bucket, PlayerTileAction.FilterSongs(SongsPreset.PercentileBucket(instrument, bucket.topPercent)))
                },
                trailing = percentileTiles(chart, instrument, totalSongs),
            )
        }
        val result = overview to instruments
        memo = key to result
        return result
    }

    /**
     * Web `buildInstrumentStatsItems` tiles before the rank card, in its order.
     *
     * @param overThreshold Scores over the CHOpt threshold (Filter Invalid Scores on), else null.
     */
    private fun instrumentTiles(chart: PlayerStats, instrument: Instrument, totalSongs: Int, overThreshold: Int?): List<PlayerStatTile> = buildList {
        add(
            PlayerStatTile(
                "songs-played",
                "Songs Played",
                ProfileFormatting.count(chart.songsPlayed.toLong()),
                tint = StatTints.GREEN.takeIf { totalSongs > 0 && chart.songsPlayed >= totalSongs },
                action = PlayerTileAction.FilterSongs(SongsPreset.ForInstrument(SongScoreFilterKind.HasScores, instrument)),
            ),
        )
        if (chart.fullComboCount > 0) {
            add(
                PlayerStatTile(
                    "full-combos",
                    "FCs",
                    fullComboText(chart),
                    tint = StatTints.GOLD.takeIf { chart.allFullCombos },
                    action = PlayerTileAction.FilterSongs(SongsPreset.ForInstrument(SongScoreFilterKind.HasFCs, instrument)),
                    spokenLabel = "Full Combos",
                ),
            )
        }
        if (overThreshold != null && overThreshold > 0) {
            add(
                PlayerStatTile(
                    "over-threshold",
                    "Over CHOpt Threshold",
                    ProfileFormatting.count(overThreshold.toLong()),
                    tint = StatTints.RED,
                    action = PlayerTileAction.FilterSongs(SongsPreset.OverThreshold(instrument)),
                ),
            )
        }
        chart.starCounts.forEach { (stars, count) ->
            add(
                PlayerStatTile(
                    "stars-$stars",
                    starLabel(stars),
                    ProfileFormatting.count(count.toLong()),
                    tint = StatTints.GOLD.takeIf { stars == 6 },
                    action = PlayerTileAction.FilterSongs(SongsPreset.Stars(instrument, stars)),
                ),
            )
        }
        add(accuracyTile(chart))
        add(averageStarsTile(chart))
        add(
            PlayerStatTile(
                "best-rank",
                "Best ${instrument.label} Song Rank",
                chart.bestRank?.let(ProfileFormatting::rank) ?: "—",
                action = bestRankAction(chart),
            ),
        )
    }

    /** Web "Percentile" (catalogue-wide) and average-percentile ("Songs Played") tiles after the rank card. */
    private fun percentileTiles(chart: PlayerStats, instrument: Instrument, totalSongs: Int): List<PlayerStatTile> {
        val overall = chart.overallPercentile(totalSongs) ?: "—"
        val average = chart.averagePercentile() ?: "—"
        return listOf(
            PlayerStatTile(
                "percentile",
                "Percentile",
                overall,
                tint = StatTints.percentile(overall),
                action = PlayerTileAction.FilterSongs(SongsPreset.Percentile(instrument, scoredOnly = false)),
            ),
            PlayerStatTile(
                "songs-played-percentile",
                "Songs Played",
                average,
                tint = StatTints.percentile(average),
                action = PlayerTileAction.FilterSongs(SongsPreset.Percentile(instrument, scoredOnly = true)),
                spokenLabel = "Songs Played percentile",
            ),
        )
    }

    private fun topSongs(profile: PlayerProfileResponse, visible: Set<Instrument>, songs: Map<String, Song>): List<PlayerTopSongs> {
        topMemo?.let { (p, v, cached) -> if (p === profile && v == visible && cached.first === songs) return cached.second }
        val result = Instrument.entries.filter { it in visible }.map { PlayerTopSongs.build(profile, it, songs, artworkUrl) }
        topMemo = Triple(profile, visible, songs to result)
        return result
    }

    /** Web "Avg Stars": five gold star images at a perfect 6, else two trimmed decimals. */
    private fun averageStarsTile(stats: PlayerStats): PlayerStatTile {
        val average = stats.averageStars ?: return PlayerStatTile("avg-stars", "Avg Stars", "—")
        if (average >= 6.0) return PlayerStatTile("avg-stars", "Avg Stars", "Gold stars", tint = StatTints.GOLD, stars = 6)
        return PlayerStatTile("avg-stars", "Avg Stars", ProfileFormatting.twoDecimals(average))
    }

    private fun bestRankAction(stats: PlayerStats): PlayerTileAction? {
        val song = stats.bestRankSongId ?: return null
        val instrument = stats.bestRankInstrument ?: return null
        return PlayerTileAction.OpenSong(song, instrument)
    }

    /** Web FC value: the count alone at 0 or 100%, otherwise "count (pct%)". */
    private fun fullComboText(stats: PlayerStats): String {
        val count = ProfileFormatting.count(stats.fullComboCount.toLong())
        return if (stats.fullComboCount == 0 || stats.allFullCombos) count else "$count (${ProfileFormatting.percent(stats.fullComboPercent)}%)"
    }

    private fun accuracyText(stats: PlayerStats): String = stats.averageAccuracy?.let { ScoreFormatting.accuracy(it) + "%" } ?: "—"

    /** Web "Avg Accuracy": red-to-green by accuracy, gold at a perfect 100% with every chart full-combed. */
    private fun accuracyTile(stats: PlayerStats): PlayerStatTile {
        val tint = stats.averageAccuracy?.takeIf { it > 0 }?.let { StatTints.accuracy(it / 10_000, stats.allFullCombos) }
        return PlayerStatTile("avg-accuracy", "Avg Accuracy", accuracyText(stats), tint = tint)
    }

    /** Web star-card labels: "Gold Stars", "5 Stars" … "1 Star". */
    private fun starLabel(stars: Int): String = when (stars) {
        6 -> "Gold Stars"
        1 -> "1 Star"
        else -> "$stars Stars"
    }

    // endregion

    companion object {
        /** Band cards the player page previews before "View all bands". */
        const val BANDS_PREVIEW_SIZE = 4
    }
}

// endregion
