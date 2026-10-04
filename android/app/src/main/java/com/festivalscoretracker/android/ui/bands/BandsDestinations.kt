package com.festivalscoretracker.android.ui.bands

import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.BandsRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.data.bands.bandProfile
import com.festivalscoretracker.android.data.bands.bandRankHistory
import com.festivalscoretracker.android.data.bands.bandSongExtremes
import com.festivalscoretracker.android.data.bands.playerBands
import com.festivalscoretracker.android.data.bands.songBandLeaderboard
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.BandDetailViewModel
import com.festivalscoretracker.android.presentation.bands.PlayerBandsViewModel
import com.festivalscoretracker.android.presentation.bands.SongBandLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.core.bands.BandPaging

// region Destinations

/**
 * Register the Bands routes: `/bands` (Band not found, web parity), player bands, band detail and the per-song
 * band leaderboard. The single registration point in `FestivalApp`'s `NavHost`.
 *
 * @param container Process dependencies.
 */
fun NavGraphBuilder.bandsDestinations(container: AppContainer) {
    val api = container.api
    composable<BandsRoute> { BandNotFoundScreen() }
    composable<PlayerBandsRoute> { entry ->
        val route = entry.toRoute<PlayerBandsRoute>()
        val shell = LocalShellActions.current
        val list: PlayerBandsViewModel = viewModel(key = "player-bands:${route.accountId}") {
            PlayerBandsViewModel(route.accountId, BandPaging.PAGE_SIZE, api::playerBands, container.backoff)
        }
        val state by list.bands.collectAsStateWithLifecycle()
        val entries = (state as? LoadState.Loaded)?.value?.entries.orEmpty()
        PlayerBandsScreen(list, playerBandsTitle(route.displayName, shell.selectedPlayer, route.accountId, entries), shell.navigate)
    }
    composable<BandRoute> { entry ->
        val route = entry.toRoute<BandRoute>()
        val shell = LocalShellActions.current
        val detail: BandDetailViewModel = viewModel(key = "band:${route.bandType}:${route.teamKey}") {
            BandDetailViewModel(
                route.bandType,
                route.teamKey,
                api::bandProfile,
                api::bandRankHistory,
                api::bandSongExtremes,
                { api.catalog() },
                container.backoff,
            )
        }
        BandDetailScreen(detail, route.name, api::artworkUrl, shell.navigate)
    }
    composable<SongBandLeaderboardRoute> { entry ->
        val route = entry.toRoute<SongBandLeaderboardRoute>()
        val shell = LocalShellActions.current
        val board: SongBandLeaderboardViewModel = viewModel(key = "song-bands:${route.songId}") {
            SongBandLeaderboardViewModel(
                route.songId,
                BandType.fromWireId(route.bandType) ?: BandType.Duets,
                { api.catalog(it) },
                api::songBandLeaderboard,
                container.backoff,
            )
        }
        SongBandLeaderboardScreen(board, api::artworkUrl, container.background, shell.navigate)
    }
}

// endregion
