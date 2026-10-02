package com.festivalscoretracker.android.ui.compete

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.compete.CompeteReads
import com.festivalscoretracker.android.presentation.compete.CompeteViewModel

// region Destinations

/**
 * Register Compete as the phone tab root and as a pushed page. The view model is
 * keyed by player and visible charts, so a Settings change re-derives the scopes.
 *
 * @param container Process dependencies.
 * @param settings Current settings.
 */
fun NavGraphBuilder.competeDestinations(container: AppContainer, settings: AppSettings) {
    composable<CompeteTab> { Compete(container, settings, isRoot = true) }
    composable<CompeteRoute> { Compete(container, settings, isRoot = false) }
}

@Composable
private fun Compete(container: AppContainer, settings: AppSettings, isRoot: Boolean) {
    val accountId = settings.selectedPlayer?.accountId
    val viewModel = viewModel(key = "compete:$accountId:${settings.visibleInstruments}") {
        CompeteViewModel(accountId, settings.visibleInstruments, CompeteReads.from(container.api), container.rivals, container.backoff, container.api.publicationChanges)
    }
    CompeteScreen(viewModel, isRoot)
}

// endregion
