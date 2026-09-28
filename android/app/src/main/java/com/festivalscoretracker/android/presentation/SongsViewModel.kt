package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongCatalogSort
import com.festivalscoretracker.android.core.songs.SongListPipeline
import com.festivalscoretracker.android.core.songs.SongListQuery
import com.festivalscoretracker.android.core.songs.SongSection
import com.festivalscoretracker.android.core.songs.SongSectionIndex
import com.festivalscoretracker.android.data.CatalogPayload
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
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn

// region Songs state

/**
 * Everything the Songs screen renders.
 *
 * @property catalog Catalogue load state (drives loading/error views).
 * @property songs Filtered, sorted rows.
 * @property sections Scrubber sections (empty when the sort has no key).
 * @property query Applied list inputs.
 * @property totalSongs Catalogue size before filtering.
 */
data class SongsUiState(
    val catalog: LoadState<CatalogPayload> = LoadState.Loading,
    val songs: List<Song> = emptyList(),
    val sections: List<SongSection> = emptyList(),
    val query: SongListQuery = SongListQuery(),
    val totalSongs: Int = 0,
)

// endregion

// region Songs view model

/**
 * Songs list logic: catalogue load with service-status retry, 250 ms debounced
 * search, persisted sort and a player-only instrument filter. List derivation
 * runs off the main thread.
 *
 * @param loadCatalog Catalogue read (`FestivalApi.catalog`).
 * @param settings Effective settings stream.
 * @param backoff Shared retry backoff.
 * @param sorter Catalogue sorter.
 * @param computeDispatcher Dispatcher for filtering/sorting.
 */
@OptIn(FlowPreview::class)
class SongsViewModel(
    loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    settings: Flow<AppSettings?>,
    backoff: ServiceRetryBackoff,
    private val sorter: SongCatalogSort = SongCatalogSort(),
    computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val loader = RetryingLoader(viewModelScope, "songs", backoff, loadCatalog)
    private val searchText = MutableStateFlow("")
    private val instrumentFilter = MutableStateFlow<Instrument?>(null)

    /** Raw (undebounced) search field text. */
    val searchInput: StateFlow<String> = searchText.asStateFlow()

    /** Derived screen state. */
    val uiState: StateFlow<SongsUiState> = combine(
        loader.state,
        searchText.debounce { if (it.isEmpty()) 0L else SEARCH_DEBOUNCE_MS },
        instrumentFilter,
        settings.filterNotNull(),
    ) { catalog, text, instrument, prefs ->
        val effectiveInstrument = instrument?.takeIf { prefs.selectedPlayer != null && it in prefs.visibleInstruments }
        val query = SongListQuery(text, effectiveInstrument, prefs.songSort, prefs.songSortAscending)
        val all = catalog.valueOrNull?.catalog?.songs.orEmpty()
        val songs = SongListPipeline.apply(all, query, sorter)
        SongsUiState(catalog, songs, SongSectionIndex.sections(songs, query.sort), query, all.size)
    }.flowOn(computeDispatcher).stateIn(viewModelScope, SharingStarted.Eagerly, SongsUiState())

    init {
        loader.ensureStarted()
    }

    /**
     * Update the search field.
     *
     * @param text New text.
     */
    fun onSearchChange(text: String) {
        searchText.value = text
    }

    /**
     * Apply or clear the single-chart filter (only honoured with a selected player).
     *
     * @param instrument Chart or null.
     */
    fun setInstrumentFilter(instrument: Instrument?) {
        instrumentFilter.value = instrument
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
