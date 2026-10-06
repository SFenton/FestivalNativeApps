package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
import com.festivalscoretracker.android.core.songs.SongCatalogBuckets
import com.festivalscoretracker.android.core.songs.SongCatalogSort
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongListHeader
import com.festivalscoretracker.android.core.songs.SongListInputs
import com.festivalscoretracker.android.core.songs.SongListPipeline
import com.festivalscoretracker.android.core.songs.SongQuickLinkBuckets
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.core.songs.SongRowProjector
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.songs.SongsPreferencesState
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.presentation.songs.InvalidScoreContext
import com.festivalscoretracker.android.presentation.songs.songScoreSource
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn

// region Songs state

/**
 * Everything the Songs screen renders.
 *
 * @property catalog Catalogue load state (drives loading/error views).
 * @property rows Projected rows in order.
 * @property sections Scrubber sections (Title/Artist/Year only).
 * @property headers In-list headers (Shop buckets).
 * @property notices Pause/status notices shown above the list.
 * @property sortPaused The saved sort's pause notice (one of [notices]; test ID `fst.songs.sort-paused`).
 * @property prefs Saved filters.
 * @property sort Saved sort mode.
 * @property ascending Saved direction.
 * @property effectiveSort Applied sort (a paused Shop sort shows Title order).
 * @property hasPlayer A player is selected (score and Selected Instrument filter sections).
 * @property hideShop Item Shop hidden (Shop sort/filter choices removed or disabled).
 * @property invalidSavedFilter A corrupt saved player filter blocks the list until Reset.
 * @property filtersApplied Whether filters narrowed the list (empty-state wording).
 * @property totalSongs Catalogue size before filtering.
 * @property filterInvalidScores Filter Invalid Scores (Over CHOpt Threshold checks in the Filter sheet).
 * @property sortChart Settings-visible single-chart filter (single-chart sort modes).
 * @property visibleMetadata Settings-visible metadata fields (sort modes and priority rows).
 * @property availableSeasons Seasons in the selected player's scores (Filter Season buckets).
 * @property availableDecades Catalogue release decades (General Year toggles).
 * @property durationBuckets Catalogue duration buckets (General Duration toggles).
 */
data class SongsUiState(
    val catalog: LoadState<CatalogPayload> = LoadState.Loading,
    val rows: List<SongRowModel> = emptyList(),
    val sections: List<SongSection> = emptyList(),
    val headers: List<SongListHeader> = emptyList(),
    val notices: List<String> = emptyList(),
    val sortPaused: String? = null,
    val prefs: SongsPreferencesState = SongsPreferencesState(),
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
    val effectiveSort: SongSortMode = SongSortMode.Title,
    val hasPlayer: Boolean = false,
    val hideShop: Boolean = false,
    val invalidSavedFilter: Boolean = false,
    val filtersApplied: Boolean = false,
    val totalSongs: Int = 0,
    val filterInvalidScores: Boolean = false,
    val sortChart: com.festivalscoretracker.android.core.model.Instrument? = null,
    val visibleMetadata: Set<MetadataField> = MetadataField.entries.toSet(),
    val availableSeasons: List<Int> = emptyList(),
    val availableDecades: List<Int> = emptyList(),
    val durationBuckets: List<Int> = emptyList(),
) {
    /** Whether a saved filter applies (gold Filter icon; web `isFilterActive`). */
    val filterActive: Boolean get() = prefs.filterActive(hasPlayer, hideShop)

    /** Filter button's spoken state ("No filters" / "Filters on: Year, …"), matching [filterActive]. */
    val filterStateDescription: String get() = prefs.filterStateDescription(hasPlayer, hideShop)

    /** Non-default sort (gold Sort icon). */
    val sortChanged: Boolean get() = sort != SongSortMode.Title || !ascending

    /** Songs Quick Links title for the applied sort. */
    val quickLinksTitle: String get() = SongQuickLinkBuckets.title(effectiveSort)

    /** Empty-list message. */
    val emptyMessage: String get() = if (filtersApplied) "No songs match the filters." else "No songs match your search."
}

/**
 * Pairs the Shop feed with the catalogue generation it may decorate.
 *
 * @property offers Same-publication offers, or null.
 * @property mismatch A feed exists but from a different generation.
 */
internal data class ShopMatch(val offers: Map<String, com.festivalscoretracker.android.core.shop.ShopSong>?, val mismatch: Boolean) {
    companion object {
        /**
         * Match Shop data to a catalogue.
         *
         * @param shop Shop state.
         * @param catalogPublication Generation observed for the catalogue.
         * @param current Latest observed generation.
         * @return Offers when every observation agrees.
         */
        fun of(shop: LoadState<ShopPayload>, catalogPublication: Int?, current: Int?): ShopMatch {
            val payload = shop.valueOrNull ?: return ShopMatch(null, false)
            val matches = SongRelatedPublicationPolicy.matches(catalogPublication, payload.observedPublicationId, current)
            return if (matches) ShopMatch(payload.offersById, false) else ShopMatch(null, true)
        }
    }
}

// endregion

// region Songs view model

/**
 * Songs list logic: catalogue load with service-status retry, 250 ms debounced
 * search, persisted sort/filters, same-publication Shop membership and
 * selected-player chips/metadata. List derivation runs off the main thread.
 *
 * @param loadCatalog Catalogue read (`FestivalApi.catalog`).
 * @param settings Effective settings stream.
 * @param prefs Saved Songs filters.
 * @param shop Shared Shop state.
 * @param profile Shared selected-player state (scores are publication-matched here).
 * @param publication Latest observed publication.
 * @param backoff Shared retry backoff.
 * @param sorter Catalogue sorter.
 * @param computeDispatcher Dispatcher for filtering/sorting.
 */
@OptIn(FlowPreview::class)
class SongsViewModel(
    loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    settings: Flow<AppSettings?>,
    prefs: Flow<SongsPreferencesState>,
    shop: Flow<LoadState<ShopPayload>> = flowOf(LoadState.Loading),
    profile: Flow<SelectedProfileState> = flowOf(SelectedProfileState()),
    publication: Flow<Int?> = flowOf(null),
    backoff: ServiceRetryBackoff,
    private val sorter: SongCatalogSort = SongCatalogSort(),
    computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val loader = RetryingLoader(viewModelScope, "songs", backoff, loadCatalog)
    private val searchText = MutableStateFlow("")

    /** Raw (undebounced) search field text. */
    val searchInput: StateFlow<String> = searchText.asStateFlow()

    private val related = combine(shop, profile, publication) { shopState, player, current -> Triple(shopState, player, current) }

    /** Derived screen state. */
    val uiState: StateFlow<SongsUiState> = combine(
        loader.state,
        searchText.debounce { if (it.isEmpty()) 0L else SEARCH_DEBOUNCE_MS },
        settings.filterNotNull(),
        prefs,
        related,
    ) { catalog, text, app, saved, (shopState, player, current) ->
        build(catalog, text, app, saved, shopState, player, current)
    }.flowOn(computeDispatcher).stateIn(viewModelScope, SharingStarted.Eagerly, SongsUiState())

    init {
        loader.ensureStarted()
    }

    private fun build(
        catalog: LoadState<CatalogPayload>,
        text: String,
        app: AppSettings,
        saved: SongsPreferencesState,
        shopState: LoadState<ShopPayload>,
        player: SelectedProfileState,
        current: Int?,
    ): SongsUiState {
        // Selected Instrument Filters are player-only (web hides them without a profile).
        val filter = if (app.selectedPlayer == null) SongFilter() else saved.filter
        val base = SongsUiState(
            catalog = catalog, prefs = saved, sort = app.songSort, ascending = app.songSortAscending,
            effectiveSort = app.songSort, hasPlayer = app.selectedPlayer != null, hideShop = app.hideShop,
            filterInvalidScores = app.filterInvalidScores, sortChart = filter.scopedTo(app.visibleInstruments).instrument,
            visibleMetadata = app.visibleMetadata,
            availableSeasons = if (app.selectedPlayer == null) emptyList() else seasons(player),
        )
        val payload = catalog.valueOrNull ?: return base
        val (decades, durations) = buckets(payload)
        val playerFilter = saved.playerFilter ?: return base.copy(
            invalidSavedFilter = true, totalSongs = payload.catalog.songs.size, availableDecades = decades, durationBuckets = durations,
        )
        val observed = current ?: payload.publicationId
        val match = if (app.hideShop) ShopMatch(null, false) else ShopMatch.of(shopState, payload.publicationId, observed)
        val invalid = if (app.filterInvalidScores) {
            InvalidScoreContext(app.leeway, songsById(payload), playerFilter.scopedTo(app.visibleInstruments).overThreshold)
        } else {
            null
        }
        val source = if (app.selectedPlayer == null) SongScoreSource.NONE else player.songScoreSource(payload.publicationId, observed, invalid)
        val result = SongListPipeline.run(
            SongListInputs(
                songs = payload.catalog.songs,
                search = text,
                filter = filter,
                general = saved.general,
                playerFilter = playerFilter,
                sort = app.songSort,
                ascending = app.songSortAscending,
                visible = app.visibleInstruments,
                hideShop = app.hideShop,
                offers = match.offers,
                shopPublicationMismatch = match.mismatch,
                hasPlayer = source.hasPlayer,
                filterInvalidScores = app.filterInvalidScores,
                scores = source.detail,
                invalid = source.invalid,
            ),
            sorter,
        )
        val projector = SongRowProjector(
            app, filter, payload.catalog.currentSeason, match.offers, source, result.effectiveSort, saved.metadataOrder,
        )
        return base.copy(
            rows = result.songs.map(projector::project),
            sections = result.sections,
            headers = result.headers,
            notices = listOfNotNull(source.notice) + result.notices,
            sortPaused = result.sortPaused,
            effectiveSort = result.effectiveSort,
            filtersApplied = result.filtersApplied,
            totalSongs = payload.catalog.songs.size,
            availableDecades = decades,
            durationBuckets = durations,
        )
    }

    @Volatile private var bucketIndex: Pair<CatalogPayload, Pair<List<Int>, List<Int>>>? = null

    private fun buckets(payload: CatalogPayload): Pair<List<Int>, List<Int>> {
        bucketIndex?.takeIf { it.first === payload }?.let { return it.second }
        val songs = payload.catalog.songs
        return (SongCatalogBuckets.decades(songs) to SongCatalogBuckets.durations(songs)).also { bucketIndex = payload to it }
    }

    @Volatile private var seasonIndex: Pair<Any?, List<Int>>? = null

    private fun seasons(player: SelectedProfileState): List<Int> {
        val index = player.scoreIndex ?: return emptyList()
        seasonIndex?.takeIf { it.first === index }?.let { return it.second }
        val seasons = index.values.flatMap { charts -> charts.values.mapNotNull { it.season } }.distinct().sorted()
        return seasons.also { seasonIndex = index to it }
    }

    @Volatile private var songIndex: Pair<CatalogPayload, Map<String, Song>>? = null

    private fun songsById(payload: CatalogPayload): Map<String, Song> {
        songIndex?.takeIf { it.first === payload }?.let { return it.second }
        return payload.catalog.songs.associateBy { it.songId }.also { songIndex = payload to it }
    }

    /**
     * Update the search field.
     *
     * @param text New text.
     */
    fun onSearchChange(text: String) {
        searchText.value = text
    }

    /** Retry after a failure. */
    fun retry() = loader.retry()

    /** Pull to refresh: re-check the publication and reload. */
    fun refresh() = loader.refresh()

    companion object {
        /** Web search debounce. */
        const val SEARCH_DEBOUNCE_MS = 250L
    }
}

// endregion
