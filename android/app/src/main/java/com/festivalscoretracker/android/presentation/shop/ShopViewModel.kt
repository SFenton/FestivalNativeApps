package com.festivalscoretracker.android.presentation.shop

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.shop.ShopDurations
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopOfferFilter
import com.festivalscoretracker.android.core.shop.ShopOfferSort
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.core.shop.ShopSortChoice
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import com.festivalscoretracker.android.presentation.valueOrNull
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// region State

/**
 * One offer as the Shop page shows it.
 *
 * @property offer Validated offer.
 * @property highlight Effective badge (none when highlighting is off).
 * @property detailSongId Catalogue song for the in-app Details action, or null.
 * @property officialUrl Validated official Shop URL, or null (never opened otherwise).
 */
data class ShopOfferItem(val offer: ShopSong, val highlight: ShopHighlight?, val detailSongId: String?, val officialUrl: String?) {
    /** Spoken summary: title, artist/year and availability. */
    val announcement: String get() = listOfNotNull(offer.title, offer.subtitle, highlight?.label).joinToString(", ")
}

/**
 * Item Shop page state.
 *
 * @property shop Shop load state.
 * @property offers Offers that pass [filter], in [sort] order (Title while the sort pauses).
 * @property hidden Hide Item Shop is on.
 * @property detailsUnavailable The catalogue read failed (offers stay usable).
 * @property filter Page filter (New / Available / Leaving Tomorrow).
 * @property totalOffers Offers in the feed before filtering (a genuine empty Shop has none).
 * @property sort Saved sort (issue #379).
 * @property sortPaused Duration sort pause notice (`fst.shop.sort-paused`), or null.
 * @property sortWaiting The Duration sort waits for the catalogue, so the page keeps loading.
 */
data class ShopUiState(
    val shop: LoadState<ShopPayload> = LoadState.Loading,
    val offers: List<ShopOfferItem> = emptyList(),
    val hidden: Boolean = false,
    val detailsUnavailable: Boolean = false,
    val filter: ShopOfferFilter = ShopOfferFilter(),
    val totalOffers: Int = 0,
    val sort: ShopSortChoice = ShopSortChoice(),
    val sortPaused: String? = null,
    val sortWaiting: Boolean = false,
) {
    /** The feed has offers but the filter hides them all ("No Matching Songs", not the empty Shop). */
    val filteredEmpty: Boolean get() = offers.isEmpty() && totalOffers > 0
}

// endregion

// region View model

/**
 * Item Shop page: the shared Shop feed plus a best-effort catalogue read for
 * in-app Details links and the Duration sort. A genuinely empty Shop and a failed read stay distinct.
 *
 * @param shop Shared Shop state.
 * @param loadCatalog Catalogue read.
 * @param settings Effective settings.
 * @param backoff Shared retry backoff.
 * @param savedSort Persisted Item Shop sort.
 * @param saveSort Persist a sort.
 */
class ShopViewModel(
    shop: Flow<LoadState<ShopPayload>>,
    loadCatalog: suspend (Boolean) -> CatalogPayload,
    settings: Flow<AppSettings?>,
    backoff: ServiceRetryBackoff,
    savedSort: Flow<ShopSortChoice> = flowOf(ShopSortChoice()),
    private val saveSort: suspend (ShopSortChoice) -> Unit = {},
) : ViewModel() {
    private val catalog = RetryingLoader(viewModelScope, "shop-catalog", backoff, loadCatalog)

    // Page-scoped: kept while the Shop stays on the back stack, so a reopened sheet shows it (not persisted).
    private val filter = MutableStateFlow(ShopOfferFilter())

    // The sheet's latest choice applies at once while it is being saved.
    private val chosenSort = MutableStateFlow<ShopSortChoice?>(null)
    private val sort = combine(savedSort, chosenSort) { saved, chosen -> chosen ?: saved }
    private val sorter = ShopOfferSort()

    /** Derived state. */
    val uiState: StateFlow<ShopUiState> = combine(shop, catalog.state, settings.filterNotNull(), filter, sort) { shopState, catalogState, app, offerFilter, choice ->
        val catalogue = catalogState.valueOrNull
        val songIds = catalogue?.catalog?.songs?.mapTo(HashSet()) { it.songId }
        val loaded = shopState.valueOrNull
        val all = loaded?.sortedSongs.orEmpty()
        val durations = if (choice.mode == SongSortMode.Duration) {
            ShopDurations.of(
                catalogue?.catalog?.songs?.associate { it.songId to it.durationSeconds },
                catalogState is LoadState.Failed,
                catalogue?.publicationId,
                loaded?.observedPublicationId,
            )
        } else {
            ShopDurations.Loading
        }
        val sorted = sorter.sorted(offerFilter.apply(all), choice, durations)
        val offers = sorted.offers.map { offer ->
            ShopOfferItem(
                offer = offer,
                highlight = ShopPresentationPolicy.highlight(offer, app.hideShop, app.disableShopHighlighting),
                detailSongId = offer.songId.takeIf { songIds?.contains(it) == true },
                officialUrl = offer.shopUrl.takeIf(ShopResponse::isOfficialShopUrl),
            )
        }
        ShopUiState(shopState, offers, app.hideShop, catalogState is LoadState.Failed, offerFilter, all.size, choice, sorted.paused, sorted.waiting)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, ShopUiState())

    init {
        catalog.ensureStarted()
        // A Shop feed from a newer publication re-reads the catalogue once, so the Duration
        // sort (and Details links) catch up instead of pausing until the page is reopened.
        viewModelScope.launch {
            var healed: Int? = null
            combine(shop, catalog.state) { shopState, catalogState -> shopState.valueOrNull to catalogState.valueOrNull }.collect { (feed, catalogue) ->
                val observed = feed?.observedPublicationId ?: return@collect
                if (catalogue != null && catalogue.publicationId < observed && healed != observed) {
                    healed = observed
                    catalog.refresh()
                }
            }
        }
    }

    /** Retry the catalogue for Details links. */
    fun retryCatalog() = catalog.retry()

    /**
     * Apply a filter at once (the sheet is live, like Songs).
     *
     * @param next New filter.
     */
    fun setFilter(next: ShopOfferFilter) {
        filter.value = next
    }

    /** Show every offer again (Reset). */
    fun resetFilter() = setFilter(ShopOfferFilter())

    /**
     * Apply and persist a sort at once (the sheet is live, like Songs).
     *
     * @param next New sort.
     */
    fun setSort(next: ShopSortChoice) {
        chosenSort.value = next
        viewModelScope.launch { saveSort(next) }
    }
}

// endregion
