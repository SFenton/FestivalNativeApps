package com.festivalscoretracker.android.ui.songs

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.SettingsTab
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.ui.common.LocalShellActions
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
 * @param onListHead Reports (loaded, first row ID) so the shell's list-detail layout can
 *   auto-select the first song (two populated columns).
 */
@Composable
fun SongsRoute(
    container: AppContainer,
    shellViewModel: ShellViewModel,
    settings: AppSettings,
    onSongClick: (Song) -> Unit,
    selectedSongId: String? = null,
    modifier: Modifier = Modifier,
    onListHead: ((loaded: Boolean, firstId: String?) -> Unit)? = null,
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
    if (onListHead != null) {
        val state by songsViewModel.uiState.collectAsStateWithLifecycle()
        val loaded = state.catalog !is LoadState.Loading
        val first = state.rows.firstOrNull()?.song?.songId
        LaunchedEffect(loaded, first) { onListHead(loaded, first) }
    }
    val scope = rememberCoroutineScope()
    val shell = LocalShellActions.current
    SongsScreen(
        viewModel = songsViewModel,
        artworkUrl = api::artworkUrl,
        onApplySort = { draft ->
            shellViewModel.setSongSort(draft.mode, draft.ascending)
            scope.launch { container.songsPreferences.setMetadataOrder(draft.metadataOrder) }
        },
        onApplyFilter = { draft ->
            val (filter, shop, player) = draft.result
            val (mode, ascending) = SongSortDraft.normalized(settings.songSort, settings.songSortAscending, filter.instrument)
            if (mode != settings.songSort) shellViewModel.setSongSort(mode, ascending)
            scope.launch { container.songsPreferences.setFilters(filter, shop, player) }
        },
        onClearFilters = { scope.launch { container.songsPreferences.clearFilters() } },
        onSongClick = onSongClick,
        selectedSongId = selectedSongId,
        visibleInstruments = settings.visibleInstruments,
        onOpenSettings = { shell.navigate(SettingsTab) },
        modifier = modifier,
    )
}

// endregion
