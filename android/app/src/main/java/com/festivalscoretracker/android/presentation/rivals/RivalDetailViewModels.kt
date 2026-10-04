package com.festivalscoretracker.android.presentation.rivals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalCategory
import com.festivalscoretracker.android.core.rivals.RivalCommonRivals
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalHeadToHead
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalrySort
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.rivals.rivalEntries
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// region All rivals

/**
 * A full rivals list.
 *
 * @property scope Resolved scope (rows carry it into Rival Detail).
 * @property entries Above, then below.
 * @property subtitle Leaderboard rank line or the Common/combo charts, if any.
 */
data class AllRivalsContent(val scope: RivalScope, val entries: List<RivalEntry>, val subtitle: String?)

/**
 * All Rivals logic (web `AllRivalsPage`): one scope's complete list. Common Rivals
 * intersects every chart's full list; Settings-derived scopes resolve at load and an
 * unresolvable scope has no [loader].
 *
 * @param accountId Selected player.
 * @param routeScope Scope carried by the route.
 * @param visible Settings-visible charts.
 * @param repository Rivals reads.
 * @param backoff Shared retry backoff.
 */
class AllRivalsViewModel(
    private val accountId: String,
    routeScope: RivalScope?,
    visible: Set<Instrument>,
    private val repository: RivalsRepository,
    backoff: ServiceRetryBackoff,
) : ViewModel() {
    /** Concrete scope, or null when the route names no identifiable list. */
    val scope: RivalScope? = RivalScopes.resolveList(routeScope, visible)

    /** Page title. */
    val title: String = RivalScopes.listTitle(scope ?: routeScope)

    private val loader = scope?.let { resolved ->
        RetryingLoader(viewModelScope, "all-rivals:$accountId:${resolved.routeToken}", backoff) { refresh -> load(resolved, refresh) }
    }

    /** List state; [LoadState.Loading] forever when [scope] is null (the screen shows its own message). */
    val state: StateFlow<LoadState<AllRivalsContent>> = loader?.state ?: MutableStateFlow(LoadState.Loading)

    init {
        loader?.ensureStarted()
    }

    /** Retry after a failure. */
    fun retry() {
        loader?.retry()
    }

    private suspend fun load(scope: RivalScope, refresh: Boolean): AllRivalsContent = when (scope) {
        is RivalScope.Leaderboard -> {
            val list = repository.leaderboardList(accountId, scope.instrument, scope.rankBy, refresh)
            val rank = list.userRank?.let { "Your rank: #${"%,d".format(it)} · ${scope.rankBy.label}" }
            AllRivalsContent(scope, rivalEntries(list.above, list.below), rank)
        }
        is RivalScope.Song -> if (scope.isCommon) {
            val lists = loadCommonLists(scope.instruments, refresh)
            val (above, below) = RivalCommonRivals.intersect(lists)
            AllRivalsContent(scope, rivalEntries(above, below), scope.instruments.joinToString(" · ") { it.label })
        } else {
            val list = repository.list(accountId, scope.instruments.single().wireId, refresh)
            AllRivalsContent(scope, rivalEntries(list.above, list.below), null)
        }
        is RivalScope.Combo -> {
            val list = repository.list(accountId, scope.token, refresh)
            AllRivalsContent(scope, rivalEntries(list.above, list.below), scope.instruments.joinToString(" · ") { it.label })
        }
        is RivalScope.FromSettings -> error("Settings scopes are resolved before loading")
    }

    /**
     * Every chart's full list for Common Rivals. Like the hub's Common card and the web, a
     * chart that fails (for example a 503 during publication) is left out of the
     * intersection instead of failing the page; only when every chart fails does the
     * first failure surface (issue #108).
     *
     * @param instruments Charts to intersect.
     * @param refresh Bypass the read cache.
     * @return The lists that loaded.
     */
    private suspend fun loadCommonLists(instruments: List<Instrument>, refresh: Boolean): List<RivalsListResponse> {
        val results = coroutineScope {
            instruments.map { chart ->
                async {
                    try {
                        Result.success(repository.list(accountId, chart.wireId, refresh))
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        Result.failure(failure)
                    }
                }
            }.awaitAll()
        }
        val loaded = results.mapNotNull { it.getOrNull() }
        if (loaded.isEmpty()) results.firstNotNullOfOrNull { it.exceptionOrNull() }?.let { throw it }
        return loaded
    }
}

// endregion

// region Rival detail

/**
 * A rival comparison ready to render.
 *
 * @property rivalName Rival display name, if known.
 * @property songs Every compared song.
 * @property categories Non-empty categories in web order.
 * @property summary Web `rivals.detail.summary`.
 */
data class RivalDetailContent(
    val rivalName: String?,
    val songs: List<RivalSongComparison>,
    val categories: List<RivalCategory>,
    val summary: String,
)

/**
 * Rival Detail and Rivalry logic (web `RivalDetailPage` / `RivalryPage`): one read for
 * the route's typed scope (a missing scope resolves against Settings), categorized
 * like the web. The catalogue is read best-effort for titles, years and artwork.
 *
 * @param accountId Selected player.
 * @param rivalId Rival.
 * @param routeName Name carried by the route, shown until the read names the rival.
 * @param scope Route scope.
 * @param allowLiveFallback Compute untracked comparisons live (Find Rival only).
 * @param visible Settings-visible charts.
 * @param repository Rivals reads.
 * @param loadCatalog Catalogue read for song lookups.
 * @param backoff Shared retry backoff.
 */
class RivalDetailViewModel(
    private val accountId: String,
    private val rivalId: String,
    private val routeName: String?,
    scope: RivalScope?,
    private val allowLiveFallback: Boolean,
    visible: Set<Instrument>,
    private val repository: RivalsRepository,
    private val loadCatalog: suspend () -> CatalogPayload,
    backoff: ServiceRetryBackoff,
) : ViewModel() {
    private val request = RivalScopes.resolveDetail(scope, visible)
    private val loader = RetryingLoader(viewModelScope, "rival:$accountId:$rivalId:$request", backoff) { refresh ->
        val detail = repository.detail(accountId, rivalId, request, allowLiveFallback, refresh)
        RivalDetailContent(
            rivalName = detail.rival.displayName ?: routeName,
            songs = detail.songs,
            categories = RivalCategorization.categorize(detail.songs),
            summary = RivalHeadToHead.summary(detail.songs),
        )
    }
    private val catalogFlow = MutableStateFlow<Map<String, Song>>(emptyMap())
    private val sortFlow = MutableStateFlow(RivalrySort.Category)

    /** Comparison state. */
    val state: StateFlow<LoadState<RivalDetailContent>> = loader.state

    /** Catalogue songs by ID (empty until loaded or when the read fails). */
    val catalog: StateFlow<Map<String, Song>> = catalogFlow.asStateFlow()

    /** Rivalry ordering. */
    val sort: StateFlow<RivalrySort> = sortFlow.asStateFlow()

    /** Name to show before and after the read. */
    val displayName: StateFlow<String?> = loader.state
        .map { state -> (state as? LoadState.Loaded)?.value?.rivalName ?: routeName }
        .stateIn(viewModelScope, SharingStarted.Eagerly, routeName)

    init {
        loader.ensureStarted()
        viewModelScope.launch {
            try {
                catalogFlow.value = loadCatalog().catalog.songs.associateBy { it.songId }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Titles and art come from the comparison itself; the catalogue only adds years and artwork.
            }
        }
    }

    /**
     * Songs of one category (Rivalry `mode`), ordered. Rows without a title (rebuilt
     * from `rivals/all` during a freeze) take catalogue titles so Title sort and Quick
     * Links read like the web.
     *
     * @param content Loaded comparison.
     * @param mode Category key.
     * @param sort Ordering.
     * @return Category, or null for an unknown or empty key.
     */
    fun category(content: RivalDetailContent, mode: String, sort: RivalrySort): RivalCategory? {
        val catalog = catalogFlow.value
        return content.categories.firstOrNull { it.key == mode }?.let { category ->
            val titled = category.songs.map { song ->
                val known = catalog[song.songId]
                if (song.title != null || known == null) song else song.copy(title = known.title, artist = song.artist ?: known.artist)
            }
            category.copy(songs = RivalHeadToHead.sort(titled, sort))
        }
    }

    /**
     * Change the Rivalry ordering.
     *
     * @param sort New ordering.
     */
    fun setSort(sort: RivalrySort) {
        sortFlow.value = sort
    }

    /** Retry after a failure. */
    fun retry() {
        loader.retry()
    }
}

// endregion
