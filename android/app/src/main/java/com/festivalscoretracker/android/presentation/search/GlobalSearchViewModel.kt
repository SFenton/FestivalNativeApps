package com.festivalscoretracker.android.presentation.search

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.search.GlobalBandResult
import com.festivalscoretracker.android.core.search.GlobalPlayerResult
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// region State

/** One scope's lifecycle for the settled query. */
enum class SectionPhase {
    /** Nothing asked (short query). */
    Idle,

    /** Read in flight. */
    Loading,

    /** Rows available. */
    Loaded,

    /** Finished with no rows. */
    Empty,

    /** Read failed. */
    Failed,
}

/**
 * A centred empty state: a title and a subtitle (no Retry, issue #299: editing the query is the way on).
 *
 * @property title Bold title, e.g. "No players found".
 * @property subtitle What to try next.
 */
data class SearchEmptyState(val title: String, val subtitle: String)

/**
 * Everything the search surface renders; derived flags keep the view logic-free.
 *
 * @property query Field text.
 * @property scope Scope filter ([SearchScope.All] = no chip).
 * @property expanded Whether the surface is open.
 * @property settledQuery Query whose results are shown.
 * @property debouncing Whether newer text is waiting for the debounce.
 * @property songs Song matches (≤20, catalogue order).
 * @property songsPhase Songs lifecycle.
 * @property players Player matches (≤10).
 * @property playersPhase Players lifecycle.
 * @property playersIssue Players failure, when [playersPhase] is [SectionPhase.Failed].
 * @property playersCountdown Seconds until an automatic players retry (scrape freeze).
 * @property bands Band matches (≤10).
 * @property bandsPhase Bands lifecycle.
 * @property bandsIssue Bands failure, when [bandsPhase] is [SectionPhase.Failed].
 * @property bandsCountdown Seconds until an automatic bands retry (scrape freeze).
 * @property announcement Polite count announcement for the settled query, or null while unsettled.
 */
data class GlobalSearchUiState(
    val query: String = "",
    val scope: SearchScope = SearchScope.All,
    val expanded: Boolean = false,
    val settledQuery: String = "",
    val debouncing: Boolean = false,
    val songs: List<GlobalSongResult> = emptyList(),
    val songsPhase: SectionPhase = SectionPhase.Idle,
    val players: List<GlobalPlayerResult> = emptyList(),
    val playersPhase: SectionPhase = SectionPhase.Idle,
    val playersIssue: ServiceIssue? = null,
    val playersCountdown: Int? = null,
    val bands: List<GlobalBandResult> = emptyList(),
    val bandsPhase: SectionPhase = SectionPhase.Idle,
    val bandsIssue: ServiceIssue? = null,
    val bandsCountdown: Int? = null,
    val announcement: String? = null,
) {
    /** Whether the query is too short to search. */
    val isShortQuery: Boolean get() = !GlobalSearchResults.isSearchable(query)

    private val allEmpty: Boolean
        get() = songsPhase == SectionPhase.Empty && playersPhase == SectionPhase.Empty && bandsPhase == SectionPhase.Empty

    private val showsResults: Boolean get() = !isShortQuery && settledQuery.isNotEmpty()

    private fun shows(section: SearchScope): Boolean = scope == SearchScope.All || scope == section

    /** Whether the Songs section is shown (rows or its failure line). */
    val showSongsSection: Boolean
        get() = showsResults && shows(SearchScope.Songs) && (songs.isNotEmpty() || songsPhase == SectionPhase.Failed)

    /** Whether the Players section is shown (rows or failure). An empty envelope never shows a section: in
     *  All it is hidden like the web (`shouldRenderGlobalSection`), in Players it is [emptyState]. While
     *  players load, [isBusy] shows the one centred spinner instead. */
    val showPlayersSection: Boolean
        get() = showsResults && shows(SearchScope.Players) && playersPhase != SectionPhase.Idle && playersPhase != SectionPhase.Empty

    /** Whether the Bands section is shown (rows or failure); the same rules as [showPlayersSection]. */
    val showBandsSection: Boolean
        get() = showsResults && shows(SearchScope.Bands) && bandsPhase != SectionPhase.Idle && bandsPhase != SectionPhase.Empty

    /** Centred short-query hint naming what the selected scope searches (issue #299), else null. */
    val hint: String?
        get() = if (isShortQuery) GlobalSearchResults.enterQueryHint(scope) else null

    /**
     * Centred title-and-subtitle empty state (issue #99): every scope empty in All, Songs with no
     * match, Players with an empty envelope, or Bands with no match; else null. No Retry (issue #299).
     */
    val emptyState: SearchEmptyState?
        get() = when {
            !showsResults -> null
            scope == SearchScope.All && allEmpty ->
                SearchEmptyState(GlobalSearchResults.EMPTY_ALL_TITLE, GlobalSearchResults.EMPTY_ALL_SUBTITLE)
            scope == SearchScope.Songs && songsPhase == SectionPhase.Empty ->
                SearchEmptyState(GlobalSearchResults.EMPTY_SONGS_TITLE, GlobalSearchResults.EMPTY_SONGS_SUBTITLE)
            scope == SearchScope.Players && playersPhase == SectionPhase.Empty ->
                SearchEmptyState(GlobalSearchResults.EMPTY_PLAYERS_TITLE, GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE)
            scope == SearchScope.Bands && bandsPhase == SectionPhase.Empty ->
                SearchEmptyState(GlobalSearchResults.EMPTY_BANDS_TITLE, GlobalSearchResults.EMPTY_BANDS_SUBTITLE)
            else -> null
        }

    /**
     * Whether the one centred spinner shows: the debounce is pending, or a scope the current view
     * shows is still loading (issue #299: like the web, no inline per-section progress, so in All the
     * rows appear together once songs, players and bands all settle).
     */
    val isBusy: Boolean
        get() = !isShortQuery && (
            debouncing || settledQuery.isEmpty() ||
                (shows(SearchScope.Songs) && songsPhase == SectionPhase.Loading) ||
                (shows(SearchScope.Players) && playersPhase == SectionPhase.Loading) ||
                (shows(SearchScope.Bands) && bandsPhase == SectionPhase.Loading)
            )
}

// endregion

// region View model

/**
 * The one global-search engine (global-search spec): trimmed query, two-character minimum,
 * 250 ms debounce, local song matches plus the keyless account and band searches (in parallel, like
 * the web's `useUnifiedSearch`) behind one centred spinner, per-scope empty/error states, cancellation
 * of superseded queries (late results dropped) and one polite count announcement per settled query.
 *
 * Activity-scoped so folding, rotating or resizing only swaps the surface; query, scope and
 * the open flag also survive process death through [savedState]. Nothing is persisted to disk.
 *
 * @param loadCatalog Current catalogue (in-process memo in `FestivalApi`).
 * @param searchPlayers Keyless account search (`FestivalApi.searchPlayers`).
 * @param searchBands Keyless band search (`FestivalApi.searchBands`, a pure read).
 * @param selectedAccountId Selected player, read when players arrive.
 * @param backoff Shared scrape-freeze backoff.
 * @param savedState Saved query/scope/expanded.
 */
class GlobalSearchViewModel(
    private val loadCatalog: suspend () -> List<Song>,
    private val searchPlayers: suspend (query: String, limit: Int) -> List<PlayerSearchResult>,
    private val searchBands: suspend (query: String, limit: Int) -> List<PlayerBandEntry>,
    private val selectedAccountId: () -> String?,
    private val backoff: ServiceRetryBackoff = ServiceRetryBackoff(),
    private val savedState: SavedStateHandle = SavedStateHandle(),
) : ViewModel() {
    private val mutableState = MutableStateFlow(
        GlobalSearchUiState(
            query = savedState[KEY_QUERY] ?: "",
            scope = SearchScope.parse(savedState[KEY_SCOPE]),
            expanded = savedState[KEY_EXPANDED] ?: false,
        ),
    )
    private var job: Job? = null

    /** Current state. */
    val state: StateFlow<GlobalSearchUiState> = mutableState.asStateFlow()

    init {
        if (mutableState.value.expanded && GlobalSearchResults.isSearchable(mutableState.value.query)) {
            start(GlobalSearchResults.normalize(mutableState.value.query), debounce = false)
        }
    }

    // region Commands

    /**
     * Open the surface (search action, persistent bar, Ctrl+K, Search key).
     *
     * @param initialQuery Optional text to search at once (debug launch).
     */
    fun open(initialQuery: String? = null) {
        setExpanded(true)
        if (initialQuery != null) {
            onQueryChange(initialQuery)
            submit()
        }
    }

    /** Close the surface; the query and scope reset (web parity: nothing is remembered). */
    fun close() {
        setExpanded(false)
        reset()
    }

    /**
     * Update the field; short text clears at once, otherwise the debounce restarts.
     *
     * @param value New text.
     */
    fun onQueryChange(value: String) {
        savedState[KEY_QUERY] = value
        val current = mutableState.value
        mutableState.update { it.copy(query = value) }
        val text = GlobalSearchResults.normalize(value)
        if (text == current.settledQuery && !current.debouncing && text.isNotEmpty()) return
        if (text.length < GlobalSearchResults.MIN_QUERY) {
            cancel()
            clearResults()
            return
        }
        start(text, debounce = true)
    }

    /**
     * Toggle a scope chip (tapping the selected chip returns to All). Every scope is already
     * searched, so switching never sends a request.
     *
     * @param chip Chip tapped.
     */
    fun toggleScope(chip: SearchScope) {
        val next = chip.toggledFrom(mutableState.value.scope)
        savedState[KEY_SCOPE] = next.token
        mutableState.update { it.copy(scope = next) }
    }

    /**
     * Run the current text now, skipping the debounce (IME Search action). With no Retry button
     * (issue #299), Search on a settled query whose songs, players or bands failed, or whose players
     * or bands came back empty (possibly a server timeout), runs it again.
     */
    fun submit() {
        val current = mutableState.value
        val text = GlobalSearchResults.normalize(current.query)
        if (text.length < GlobalSearchResults.MIN_QUERY) return
        val rerunnable = current.songsPhase == SectionPhase.Failed ||
            current.playersPhase == SectionPhase.Failed || current.playersPhase == SectionPhase.Empty ||
            current.bandsPhase == SectionPhase.Failed || current.bandsPhase == SectionPhase.Empty
        if (current.debouncing || current.settledQuery != text || rerunnable) start(text, debounce = false)
    }

    /** Clear the text (clear button, first Escape). */
    fun clearQuery() {
        onQueryChange("")
    }

    // endregion

    // region Search

    private fun setExpanded(value: Boolean) {
        savedState[KEY_EXPANDED] = value
        mutableState.update { it.copy(expanded = value) }
    }

    private fun reset() {
        cancel()
        savedState[KEY_QUERY] = ""
        savedState[KEY_SCOPE] = SearchScope.All.token
        mutableState.update { GlobalSearchUiState(expanded = it.expanded) }
    }

    private fun cancel() {
        job?.cancel()
        job = null
    }

    private fun clearResults() {
        mutableState.update {
            it.copy(
                settledQuery = "", debouncing = false, songs = emptyList(), songsPhase = SectionPhase.Idle,
                players = emptyList(), playersPhase = SectionPhase.Idle, playersIssue = null, playersCountdown = null,
                bands = emptyList(), bandsPhase = SectionPhase.Idle, bandsIssue = null, bandsCountdown = null, announcement = null,
            )
        }
    }

    private fun start(text: String, debounce: Boolean) {
        cancel()
        job = viewModelScope.launch { run(text, debounce) }
    }

    private suspend fun run(text: String, debounce: Boolean) {
        if (debounce) {
            mutableState.update { it.copy(debouncing = true, announcement = null) }
            delay(GlobalSearchResults.DEBOUNCE_MS)
        }
        val canSearch = GlobalSearchResults.canSearchPlayers(text)
        val remotePhase = if (canSearch) SectionPhase.Loading else SectionPhase.Empty
        mutableState.update {
            it.copy(
                debouncing = false, settledQuery = text, announcement = null, songsPhase = SectionPhase.Loading,
                players = emptyList(), playersIssue = null, playersCountdown = null, playersPhase = remotePhase,
                bands = emptyList(), bandsIssue = null, bandsCountdown = null, bandsPhase = remotePhase,
            )
        }
        coroutineScope {
            launch { loadSongs(text) }
            if (canSearch) {
                launch {
                    loadRemote(PLAYERS_BACKOFF_KEY, { GlobalSearchResults.players(searchPlayers(text, GlobalSearchResults.PLAYER_LIMIT), selectedAccountId()) }) { rows, phase, issue, countdown ->
                        copy(players = rows, playersPhase = phase, playersIssue = issue, playersCountdown = countdown)
                    }
                }
                launch {
                    loadRemote(BANDS_BACKOFF_KEY, { GlobalSearchResults.bands(searchBands(text, GlobalSearchResults.BAND_LIMIT)) }) { rows, phase, issue, countdown ->
                        copy(bands = rows, bandsPhase = phase, bandsIssue = issue, bandsCountdown = countdown)
                    }
                }
            }
        }
    }

    private suspend fun loadSongs(text: String) {
        val (songs, phase) = try {
            val matches = GlobalSearchResults.matchSongs(loadCatalog(), text)
            matches to if (matches.isEmpty()) SectionPhase.Empty else SectionPhase.Loaded
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            emptyList<GlobalSongResult>() to SectionPhase.Failed
        }
        mutableState.update { it.copy(songs = songs, songsPhase = phase) }
        announceIfSettled()
    }

    /**
     * Load one service scope (players or bands). A scrape freeze counts down and retries on its
     * own with that scope's backoff; any other failure stays failed (no Retry, issue #299).
     *
     * @param backoffKey Shared backoff key for this scope.
     * @param read The keyless read, already projected to result rows.
     * @param set Writes rows, phase, issue and countdown into the state.
     */
    private suspend fun <T> loadRemote(
        backoffKey: String,
        read: suspend () -> List<T>,
        set: GlobalSearchUiState.(rows: List<T>, phase: SectionPhase, issue: ServiceIssue?, countdown: Int?) -> GlobalSearchUiState,
    ) {
        while (true) {
            mutableState.update { it.set(emptyList(), SectionPhase.Loading, null, null) }
            try {
                val rows = read()
                backoff.reset(backoffKey)
                mutableState.update { it.set(rows, if (rows.isEmpty()) SectionPhase.Empty else SectionPhase.Loaded, null, null) }
                announceIfSettled()
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val issue = ServiceIssue.from(error)
                mutableState.update { it.set(emptyList(), SectionPhase.Failed, issue, null) }
                // A scrape freeze announces the failure first, then counts down and retries.
                announceIfSettled()
                if (!issue.retriesAutomatically) return
                var remaining = backoff.nextDelay(backoffKey, issue.retryAfterSeconds)
                while (remaining > 0) {
                    mutableState.update { it.set(emptyList(), SectionPhase.Failed, issue, remaining) }
                    delay(1_000)
                    remaining--
                }
            }
        }
    }

    /** Announce the counts once no scope is still loading. */
    private fun announceIfSettled() {
        mutableState.update {
            val phases = listOf(it.songsPhase, it.playersPhase, it.bandsPhase)
            if (SectionPhase.Loading in phases) return@update it
            it.copy(
                announcement = GlobalSearchResults.announcement(
                    songs = count(it.songsPhase, it.songs.size),
                    players = count(it.playersPhase, it.players.size),
                    bands = count(it.bandsPhase, it.bands.size),
                ),
            )
        }
    }

    private fun count(phase: SectionPhase, size: Int): GlobalSearchResults.Count =
        if (phase == SectionPhase.Failed) GlobalSearchResults.Count.Failed else GlobalSearchResults.Count.Of(size)

    // endregion

    companion object {
        private const val KEY_QUERY = "globalSearch.query"
        private const val KEY_SCOPE = "globalSearch.scope"
        private const val KEY_EXPANDED = "globalSearch.expanded"
        private const val PLAYERS_BACKOFF_KEY = "global-search.players"
        private const val BANDS_BACKOFF_KEY = "global-search.bands"
    }
}

// endregion
