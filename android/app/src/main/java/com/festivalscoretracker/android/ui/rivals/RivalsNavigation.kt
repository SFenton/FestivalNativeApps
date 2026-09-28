package com.festivalscoretracker.android.ui.rivals

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.presentation.rivals.AllRivalsViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalDetailViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalsHubViewModel

// region Destinations

/**
 * Register the Rivals destinations (hub tab/pushed, All Rivals, Rival Detail, Rivalry).
 * Scopes travel on the typed routes; view models are keyed by player and scope so a
 * player or Settings change never shows another scope's data.
 *
 * @param container Process dependencies.
 * @param settings Current settings.
 */
fun NavGraphBuilder.rivalsDestinations(container: AppContainer, settings: AppSettings) {
    composable<RivalsTab> { RivalsHub(container, settings, isRoot = true) }
    composable<RivalsRoute> { RivalsHub(container, settings, isRoot = false) }
    composable<AllRivalsRoute> { entry ->
        val route = entry.toRoute<AllRivalsRoute>()
        val player = settings.selectedPlayer
        if (player == null) {
            RivalsNoPlayerScreen("Rivals")
        } else {
            val scope = RivalScopes.fromToken(route.scope)
            val viewModel: AllRivalsViewModel = viewModel(key = "all-rivals:${player.accountId}:${route.scope}:${settings.visibleInstruments}") {
                AllRivalsViewModel(player.accountId, scope, settings.visibleInstruments, container.rivals, container.backoff)
            }
            AllRivalsScreen(viewModel)
        }
    }
    composable<RivalDetailRoute> { entry ->
        val route = entry.toRoute<RivalDetailRoute>()
        val viewModel = detailViewModel(container, settings, route.rivalId, route.name, route.scope, route.allowLiveFallback)
        if (viewModel == null) RivalsNoPlayerScreen(route.name ?: "Rival") else RivalDetailScreen(viewModel, route, container.api::artworkUrl)
    }
    composable<RivalryRoute> { entry ->
        val route = entry.toRoute<RivalryRoute>()
        val viewModel = detailViewModel(container, settings, route.rivalId, route.name, route.scope, route.allowLiveFallback)
        if (viewModel == null) {
            RivalsNoPlayerScreen(RivalCategorization.title(route.mode))
        } else {
            RivalryScreen(viewModel, route.rivalId, route.mode, container.api::artworkUrl)
        }
    }
}

@Composable
private fun RivalsHub(container: AppContainer, settings: AppSettings, isRoot: Boolean) {
    val player = settings.selectedPlayer
    val hub = player?.let {
        viewModel(key = "rivals-hub:${it.accountId}:${settings.visibleInstruments}") {
            RivalsHubViewModel(it.accountId, settings.visibleInstruments, container.rivals, container.backoff)
        }
    }
    val search = viewModel<ProfileSearchViewModel>(key = "find-rival") { ProfileSearchViewModel { query -> container.api.searchPlayers(query) } }
    RivalsScreen(hub, isRoot, settings.visibleInstruments.size, search)
}

@Composable
private fun detailViewModel(
    container: AppContainer,
    settings: AppSettings,
    rivalId: String,
    name: String?,
    scopeToken: String?,
    allowLiveFallback: Boolean,
): RivalDetailViewModel? {
    val player = settings.selectedPlayer ?: return null
    return viewModel(key = "rival:${player.accountId}:$rivalId:$scopeToken:$allowLiveFallback:${settings.visibleInstruments}") {
        RivalDetailViewModel(
            accountId = player.accountId,
            rivalId = rivalId,
            routeName = name,
            scope = RivalScopes.fromToken(scopeToken),
            allowLiveFallback = allowLiveFallback,
            visible = settings.visibleInstruments,
            repository = container.rivals,
            loadCatalog = { container.api.catalog() },
            backoff = container.backoff,
        )
    }
}

// endregion
