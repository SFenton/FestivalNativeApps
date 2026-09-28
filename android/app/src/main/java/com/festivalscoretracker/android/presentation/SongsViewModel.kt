package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
import com.festivalscoretracker.android.core.songs.SongCatalogSort
import com.festivalscoretracker.android.core.songs.SongListHeader
import com.festivalscoretracker.android.core.songs.SongListInputs
import com.festivalscoretracker.android.core.songs.SongListPipeline
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.core.songs.SongRowProjector
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.songs.SongsPreferencesState
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
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
 * @property prefs Saved filters.
 * @property sort Saved sort mode.
 * @property ascending Saved direction.
 * @property effectiveSort Applied sort (a paused Shop sort shows Title order).
 * @property hasPlayer A player is selected (Filter action and score sections).
 * @property hideShop Item Shop hidden (Shop sort/filter choices removed or disabled).
 * @property invalidSavedFilter A corrupt saved player filter blocks the list until Reset.
 * @property filtersApplied Whether filters narrowed the list (empty-state wording).
 * @property totalSongs Catalogue size before filtering.
 */
data class SongsUiState(
    val catalog: LoadState<CatalogPayload> = LoadState.Loading,
    val rows: List<SongRowModel> = emptyList(),
    val sections: List<SongSection> = emptyList(),
    val headers: List<SongListHeader> = emptyList(),
    val notices: List<String> = emptyList(),
    val prefs: SongsPreferencesState = SongsPreferencesState(),
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
    val effectiveSort: SongSortMode = SongSortMode.Title,
    val hasPlayer: Boolean = false,
    val hideShop: Boolean = false,
    val invalidSavedFilter: Boolean = false,
    val filtersApplied: Boolean = false,
    val totalSongs: Int = 0,
) {
    /** Non-default sort (gold Sort icon). */
    val sortChanged: Boolean get() = sort != SongSortMode.Title || !ascending

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
        val base = SongsUiState(
            catalog = catalog, prefs = saved, sort = app.songSort, ascending = app.songSortAscending,
            effectiveSort = app.songSort, hasPlayer = app.selectedPlayer != null, hideShop = app.hideShop,
        )
        val payload = catalog.valueOrNull ?: return base
        val playerFilter = saved.playerFilter ?: return base.copy(invalidSavedFilter = true, totalSongs = payload.catalog.songs.size)
        val observed = current ?: payload.publicationId
        val match = if (app.hideShop) ShopMatch(null, false) else ShopMatch.of(shopState, payload.publicationId, observed)
        val source = if (app.selectedPlayer == null) SongScoreSource.NONE else player.songScoreSource(payload.publicationId, observed)
        val result = SongListPipeline.run(
            SongListInputs(
                songs = payload.catalog.songs,
                search = text,
                filter = saved.filter,
                shopFilter = saved.shopFilter,
                playerFilter = playerFilter,
                sort = app.songSort,
                ascending = app.songSortAscending,
                visible = app.visibleInstruments,
                hideShop = app.hideShop,
                offers = match.offers,
                shopPublicationMismatch = match.mismatch,
                hasPlayer = source.hasPlayer,
                filterInvalidScores = app.filterInvalidScores,
                scores = source.facts,
            ),
            sorter,
        )
        val projector = SongRowProjector(app, saved.filter, payload.catalog.currentSeason, match.offers, source)
        return base.copy(
            rows = result.songs.map(projector::project),
            sections = result.sections,
            headers = result.headers,
            notices = listOfNotNull(source.notice) + result.notices,
            effectiveSort = result.effectiveSort,
            filtersApplied = result.filtersApplied,
            totalSongs = payload.catalog.songs.size,
        )
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
