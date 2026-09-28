package com.festivalscoretracker.android.ui.suggestions

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsTab
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.suggestions.suggestionRivals
import com.festivalscoretracker.android.data.suggestions.suggestionScores
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsViewModel
import com.festivalscoretracker.android.ui.common.LocalShellActions
import kotlinx.coroutines.flow.Flow

// region Destinations

/**
 * Register `/suggestions` as the tab root and as a pushed route (drawer).
 *
 * @param container Process dependencies.
 * @param settings Effective settings (with the debug profile override).
 */
fun NavGraphBuilder.suggestionsDestinations(container: AppContainer, settings: Flow<AppSettings?>) {
    composable<SuggestionsTab> { SuggestionsDestination(container, settings, isRoot = true) }
    composable<SuggestionsRoute> { SuggestionsDestination(container, settings, isRoot = false) }
}

@Composable
private fun SuggestionsDestination(container: AppContainer, settings: Flow<AppSettings?>, isRoot: Boolean) {
    val api = container.api
    val shell = LocalShellActions.current
    val viewModel: SuggestionsViewModel = viewModel {
        SuggestionsViewModel(
            loadCatalog = { api.catalog(it) },
            loadScores = { api.suggestionScores(it) },
            loadRivals = { api.suggestionRivals(it) },
            settings = settings,
            savedFilter = container.suggestionFilters.filter,
            saveFilter = container.suggestionFilters::save,
            backoff = container.backoff,
            seeds = container.suggestionsSeed?.let { seed -> { seed } } ?: SuggestionsViewModel.RANDOM_SEEDS,
        )
    }
    SuggestionsScreen(viewModel, isRoot, api::artworkUrl) { shell.navigate(SongDetailRoute(it)) }
}

// endregion
