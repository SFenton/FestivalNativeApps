package com.festivalscoretracker.android.ui.firstrun

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSongs
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.valueOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.StateFlow
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsTab
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// region Route mapping

/**
 * The first-run page for the visible back-stack entry (the one seam every page
 * shares, so screens never register first-run themselves).
 *
 * @param entry Top back-stack entry.
 * @return Page, or null for destinations without slides.
 */
fun firstRunPage(entry: NavBackStackEntry?): FirstRunPageKey? {
    val destination = entry?.destination ?: return null
    return when {
        destination.hasRoute(SongsTab::class) -> FirstRunPageKey.Songs
        destination.hasRoute(SongDetailRoute::class) -> FirstRunPageKey.SongInfo
        destination.hasRoute(PlayerHistoryRoute::class) -> FirstRunPageKey.PlayerHistory
        destination.hasRoute(StatisticsTab::class) || destination.hasRoute(StatisticsRoute::class) || destination.hasRoute(PlayerRoute::class) -> FirstRunPageKey.Statistics
        destination.hasRoute(SuggestionsTab::class) || destination.hasRoute(SuggestionsRoute::class) -> FirstRunPageKey.Suggestions
        destination.hasRoute(LeaderboardsTab::class) || destination.hasRoute(LeaderboardsRoute::class) -> FirstRunPageKey.Leaderboards
        destination.hasRoute(CompeteTab::class) || destination.hasRoute(CompeteRoute::class) -> FirstRunPageKey.Compete
        destination.hasRoute(RivalsTab::class) || destination.hasRoute(RivalsRoute::class) -> FirstRunPageKey.Rivals
        destination.hasRoute(ShopRoute::class) -> FirstRunPageKey.Shop
        else -> null
    }
}

// endregion

// region Host

/**
 * Shell-level first-run host: after the visible page settles, claims the single
 * carousel slot for its unseen gate-passing slides, and presents whichever
 * carousel is active (first visit or Settings replay). Re-evaluates when a
 * gate input changes, so selecting a player surfaces only the newly eligible slides.
 *
 * @param center First-run arbiter.
 * @param page Visible page, or null.
 * @param settings Current settings (gate facts; non-null means `ready`).
 * @param compact Compact window width.
 * @param blocked Another modal owns the screen (e.g. the profile sheet).
 * @param destinationResolved The navigation stack has a destination (a null [page] then means
 *   "no carousel here", which settles the launch for What's New).
 * @param demoSongs Where song demos read real catalogue songs; null shows placeholders.
 */
@Composable
fun FirstRunHost(
    center: FirstRunCenter,
    page: FirstRunPageKey?,
    settings: AppSettings,
    compact: Boolean,
    blocked: Boolean,
    destinationResolved: Boolean = true,
    demoSongs: FirstRunDemoSongsSource? = null,
) {
    val active by center.active.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val hasPlayer = settings.selectedPlayer != null
    LaunchedEffect(page, hasPlayer, settings.shopHighlightEnabled, settings.experimentalRanks, compact, blocked, destinationResolved) {
        if (blocked) return@LaunchedEffect
        if (page == null) {
            if (destinationResolved) {
                delay(SETTLE_MS)
                center.markLaunchSettled()
            }
            return@LaunchedEffect
        }
        delay(SETTLE_MS)
        center.tryBegin(page, settings, compact)
    }
    active?.let { carousel ->
        val demoCatalog = demoSongs?.let { rememberFirstRunDemoCatalog(it, settings.hideShop) } ?: FirstRunDemoCatalog()
        CompositionLocalProvider(LocalFirstRunDemoCatalog provides demoCatalog) {
            FirstRunCarouselDialog(carousel, compact) { viewed -> scope.launch { center.complete(carousel, viewed) } }
        }
    }
}

/**
 * Catalogue inputs for song demos (web `useDemoSongs`/`useItemShopDemoSongs`). Demos only read
 * the memoized keyless `/api/songs` and an already-loaded Shop feed; they never fetch the Shop.
 *
 * @property loadCatalog Memoized catalogue read.
 * @property shop Shared Shop feed state.
 * @property publication Latest publication the app observed.
 * @property artworkUrl Artwork resolver.
 */
class FirstRunDemoSongsSource(
    val loadCatalog: suspend () -> CatalogPayload,
    val shop: StateFlow<LoadState<ShopPayload>>,
    val publication: StateFlow<Int?>,
    val artworkUrl: (String?) -> String?,
)

/**
 * Loads the catalogue once while a carousel is shown; a failure keeps placeholders (the demos
 * are decorative and online-only).
 *
 * @param source Inputs.
 * @param hideShop Shop hidden in Settings: Shop demos then use Epic Games songs.
 * @return Demo songs.
 */
@Composable
private fun rememberFirstRunDemoCatalog(source: FirstRunDemoSongsSource, hideShop: Boolean): FirstRunDemoCatalog {
    val catalog by produceState<CatalogPayload?>(null, source) {
        value = try {
            source.loadCatalog()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }
    val shop by source.shop.collectAsStateWithLifecycle()
    val current by source.publication.collectAsStateWithLifecycle()
    val payload = catalog
    return remember(payload, shop, current, hideShop) {
        val shopIds = if (hideShop) emptyList() else FirstRunDemoSongs.shopPreference(shop.valueOrNull, payload?.publicationId, current)
        FirstRunDemoCatalog(payload?.catalog?.songs, shopIds, source.artworkUrl)
    }
}

/** Wait after navigation before presenting, so the page is visible behind the dialog. */
private const val SETTLE_MS = 600L

// endregion
