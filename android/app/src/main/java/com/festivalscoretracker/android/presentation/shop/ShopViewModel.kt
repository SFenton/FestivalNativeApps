package com.festivalscoretracker.android.presentation.shop

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import com.festivalscoretracker.android.presentation.valueOrNull
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.stateIn

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
 * @property offers Title-ordered offers.
 * @property hidden Hide Item Shop is on.
 * @property detailsUnavailable The catalogue read failed (offers stay usable).
 */
data class ShopUiState(
    val shop: LoadState<ShopPayload> = LoadState.Loading,
    val offers: List<ShopOfferItem> = emptyList(),
    val hidden: Boolean = false,
    val detailsUnavailable: Boolean = false,
)

// endregion

// region View model

/**
 * Item Shop page: the shared Shop feed plus a best-effort catalogue read for
 * in-app Details links. A genuinely empty Shop and a failed read stay distinct.
 *
 * @param shop Shared Shop state.
 * @param loadCatalog Catalogue read.
 * @param settings Effective settings.
 * @param backoff Shared retry backoff.
 */
class ShopViewModel(
    shop: Flow<LoadState<ShopPayload>>,
    loadCatalog: suspend (Boolean) -> CatalogPayload,
    settings: Flow<AppSettings?>,
    backoff: ServiceRetryBackoff,
) : ViewModel() {
    private val catalog = RetryingLoader(viewModelScope, "shop-catalog", backoff, loadCatalog)

    /** Derived state. */
    val uiState: StateFlow<ShopUiState> = combine(shop, catalog.state, settings.filterNotNull()) { shopState, catalogState, app ->
        val songIds = catalogState.valueOrNull?.catalog?.songs?.mapTo(HashSet()) { it.songId }
        val offers = shopState.valueOrNull?.sortedSongs.orEmpty().map { offer ->
            ShopOfferItem(
                offer = offer,
                highlight = ShopPresentationPolicy.highlight(offer, app.hideShop, app.disableShopHighlighting),
                detailSongId = offer.songId.takeIf { songIds?.contains(it) == true },
                officialUrl = offer.shopUrl.takeIf(ShopResponse::isOfficialShopUrl),
            )
        }
        ShopUiState(shopState, offers, app.hideShop, catalogState is LoadState.Failed)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, ShopUiState())

    init {
        catalog.ensureStarted()
    }

    /** Retry the catalogue for Details links. */
    fun retryCatalog() = catalog.retry()
}

// endregion
