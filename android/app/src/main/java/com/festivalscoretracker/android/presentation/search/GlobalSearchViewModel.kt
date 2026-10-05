package com.festivalscoretracker.android.presentation.search

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.search.GlobalPlayerResult
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
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
    val announcement: String? = null,
) {
    /** Whether the query is too short to search. */
    val isShortQuery: Boolean get() = !GlobalSearchResults.isSearchable(query)

    /** Whether the Bands scope (explanation, no request) is chosen. */
    val isBandsScope: Boolean get() = scope == SearchScope.Bands

    private val allEmpty: Boolean get() = songsPhase == SectionPhase.Empty && playersPhase == SectionPhase.Empty

    private val showsResults: Boolean get() = !isShortQuery && !isBandsScope && settledQuery.isNotEmpty()

    /** Whether the Songs section is shown (rows or its failure line). */
    val showSongsSection: Boolean
        get() = showsResults && (scope == SearchScope.All || scope == SearchScope.Songs) &&
            (songs.isNotEmpty() || songsPhase == SectionPhase.Failed)

    /** Whether the Players section is shown (rows or failure). An empty envelope never shows a section: in
     *  All it is hidden like the web (`shouldRenderGlobalSection`), in Players it is [emptyState]. While
     *  players load, [isBusy] shows the one centred spinner instead. */
    val showPlayersSection: Boolean
        get() = showsResults && (scope == SearchScope.All || scope == SearchScope.Players) &&
            playersPhase != SectionPhase.Idle && playersPhase != SectionPhase.Empty

    /** Centred short-query hint naming what the selected scope searches (issue #299), else null. */
    val hint: String?
        get() = if (isShortQuery) GlobalSearchResults.enterQueryHint(scope) else null

    /**
     * Centred title-and-subtitle empty state (issue #99): every scope empty in All, Songs with no
     * match, or Players with an empty envelope; else null. No Retry (issue #299).
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
            else -> null
        }

    /**
     * Whether the one centred spinner shows: the debounce is pending, or a scope the current view
     * shows is still loading (issue #299: like the web, no inline per-section progress, so in All the
     * rows appear together once songs and players both settle).
     */
    val isBusy: Boolean
        get() = !isShortQuery && !isBandsScope && (
            debouncing || settledQuery.isEmpty() ||
                (scope != SearchScope.Players && songsPhase == SectionPhase.Loading) ||
                (scope != SearchScope.Songs && playersPhase == SectionPhase.Loading)
            )
}

// endregion

// region View model

/**
 * The one global-search engine (global-search spec): trimmed query, two-character minimum,
 * 250 ms debounce, local song matches and the keyless account search behind one centred spinner,
 * per-scope empty/error states, cancellation of
 * superseded queries (late results dropped) and one polite count announcement per settled query.
 * Bands are shown but never requested (the service's band search GET can write).
 *
 * Activity-scoped so folding, rotating or resizing only swaps the surface; query, scope and
 * the open flag also survive process death through [savedState]. Nothing is persisted to disk.
 *
 * @param loadCatalog Current catalogue (in-process memo in `FestivalApi`).
 * @param searchPlayers Keyless account search (`FestivalApi.searchPlayers`).
 * @param selectedAccountId Selected player, read when players arrive.
 * @param backoff Shared scrape-freeze backoff.
 * @param savedState Saved query/scope/expanded.
 */
class GlobalSearchViewModel(
    private val loadCatalog: suspend () -> List<Song>,
    private val searchPlayers: suspend (query: String, limit: Int) -> List<PlayerSearchResult>,
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
     * Toggle a scope chip (tapping the selected chip returns to All). Bands never requests.
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
     * (issue #299), Search on a settled query whose songs or players failed, or whose players
     * envelope came back empty (possibly a server timeout), runs it again.
     */
    fun submit() {
        val current = mutableState.value
        val text = GlobalSearchResults.normalize(current.query)
        if (text.length < GlobalSearchResults.MIN_QUERY) return
        val rerunnable = current.songsPhase == SectionPhase.Failed ||
            current.playersPhase == SectionPhase.Failed || current.playersPhase == SectionPhase.Empty
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
                players = emptyList(), playersPhase = SectionPhase.Idle, playersIssue = null, playersCountdown = null, announcement = null,
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
        val canSearchPlayers = GlobalSearchResults.canSearchPlayers(text)
        mutableState.update {
            it.copy(
                debouncing = false, settledQuery = text, announcement = null,
                players = emptyList(), playersIssue = null, playersCountdown = null,
                playersPhase = if (canSearchPlayers) SectionPhase.Loading else SectionPhase.Empty,
            )
        }
        loadSongs(text)
        if (canSearchPlayers) loadPlayers(text)
        announce()
    }

    private suspend fun loadSongs(text: String) {
        mutableState.update { it.copy(songsPhase = SectionPhase.Loading) }
        val (songs, phase) = try {
            val matches = GlobalSearchResults.matchSongs(loadCatalog(), text)
            matches to if (matches.isEmpty()) SectionPhase.Empty else SectionPhase.Loaded
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            emptyList<GlobalSongResult>() to SectionPhase.Failed
        }
        mutableState.update { it.copy(songs = songs, songsPhase = phase) }
    }

    private suspend fun loadPlayers(text: String) {
        while (true) {
            mutableState.update { it.copy(playersPhase = SectionPhase.Loading, playersIssue = null, playersCountdown = null) }
            try {
                val players = GlobalSearchResults.players(searchPlayers(text, GlobalSearchResults.PLAYER_LIMIT), selectedAccountId())
                backoff.reset(BACKOFF_KEY)
                mutableState.update {
                    it.copy(players = players, playersPhase = if (players.isEmpty()) SectionPhase.Empty else SectionPhase.Loaded)
                }
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val issue = ServiceIssue.from(error)
                mutableState.update { it.copy(players = emptyList(), playersPhase = SectionPhase.Failed, playersIssue = issue) }
                if (!issue.retriesAutomatically) return
                // A scrape freeze counts down and retries on its own; announce the failure first.
                announce()
                var remaining = backoff.nextDelay(BACKOFF_KEY, issue.retryAfterSeconds)
                while (remaining > 0) {
                    mutableState.update { it.copy(playersCountdown = remaining) }
                    delay(1_000)
                    remaining--
                }
            }
        }
    }

    private fun announce() {
        mutableState.update {
            it.copy(
                announcement = GlobalSearchResults.announcement(
                    songs = if (it.songsPhase == SectionPhase.Failed) null else it.songs.size,
                    players = if (it.playersPhase == SectionPhase.Failed) null else it.players.size,
                ),
            )
        }
    }

    // endregion

    companion object {
        private const val KEY_QUERY = "globalSearch.query"
        private const val KEY_SCOPE = "globalSearch.scope"
        private const val KEY_EXPANDED = "globalSearch.expanded"
        private const val BACKOFF_KEY = "global-search.players"
    }
}

// endregion
