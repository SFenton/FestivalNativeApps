package com.festivalscoretracker.android.ui.songs

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.SongsViewModel
import kotlinx.coroutines.launch

// region Songs route

/**
 * Songs tab root wiring: builds the view model from the container's shared
 * catalogue, Shop, selected-profile and preferences state, and persists sheet
 * results. Keeps the shell's route table to a single call.
 *
 * @param container Process dependencies.
 * @param shellViewModel Shell (effective settings, sort persistence).
 * @param settings Current settings.
 * @param onSongClick Open a song.
 * @param selectedSongId Highlighted song in two-pane layouts.
 * @param modifier Modifier.
 */
@Composable
fun SongsRoute(
    container: AppContainer,
    shellViewModel: ShellViewModel,
    settings: AppSettings,
    onSongClick: (Song) -> Unit,
    selectedSongId: String? = null,
    modifier: Modifier = Modifier,
) {
    val api = container.api
    val songsViewModel: SongsViewModel = viewModel {
        SongsViewModel(
            loadCatalog = { api.catalog(it) },
            settings = shellViewModel.settings,
            prefs = container.songsPreferences.state,
            shop = container.shop.state,
            profile = container.selectedProfile.state,
            publication = api.publicationChanges,
            backoff = container.backoff,
        )
    }
    LaunchedEffect(settings.hideShop) { if (!settings.hideShop) container.shop.ensureStarted() }
    val scope = rememberCoroutineScope()
    SongsScreen(
        viewModel = songsViewModel,
        artworkUrl = api::artworkUrl,
        onApplySort = shellViewModel::setSongSort,
        onApplyFilter = { draft ->
            val (filter, shop, player) = draft.result
            scope.launch { container.songsPreferences.setFilters(filter, shop, player) }
        },
        onClearFilters = { scope.launch { container.songsPreferences.clearFilters() } },
        onSongClick = onSongClick,
        selectedSongId = selectedSongId,
        visibleInstruments = settings.visibleInstruments,
        modifier = modifier,
    )
}

// endregion
