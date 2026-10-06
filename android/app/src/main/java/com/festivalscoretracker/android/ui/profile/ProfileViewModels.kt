package com.festivalscoretracker.android.ui.profile

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.data.bands.playerBands
import com.festivalscoretracker.android.data.profile.applyPreset
import com.festivalscoretracker.android.data.profile.playerHistory
import com.festivalscoretracker.android.data.profile.playerInstrumentRanking
import com.festivalscoretracker.android.data.profile.playerProfile
import com.festivalscoretracker.android.data.profile.playerRankHistory
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.profile.PlayerHistoryViewModel
import com.festivalscoretracker.android.presentation.profile.PlayerProfileViewModel
import com.festivalscoretracker.android.presentation.profile.ProfileReads

// region Factories

/**
 * The player-page view model for the current navigation entry.
 *
 * @param container Process dependencies.
 * @param shell Shell session (settings, select/deselect).
 * @param accountId Viewed account, or null for Statistics (follows the selection).
 * @param name Name known before the read.
 * @return Entry-scoped view model.
 */
@Composable
fun profileViewModel(container: AppContainer, shell: ShellViewModel, accountId: String?, name: String?): PlayerProfileViewModel {
    val api = container.api
    return viewModel {
        PlayerProfileViewModel(
            accountId = accountId,
            routeDisplayName = name,
            reads = ProfileReads(
                profile = { api.playerProfile(it) },
                ranking = { instrument, account -> api.playerInstrumentRanking(instrument, account) },
                rankHistory = { instrument, account -> api.playerRankHistory(instrument, account) },
                catalog = { api.catalog().catalog.songs },
                bands = { account, group -> api.playerBands(account, group, 1, PlayerProfileViewModel.BANDS_PREVIEW_SIZE) },
            ),
            store = container.selectedProfile,
            settings = shell.settings,
            publications = api.publicationChanges,
            backoff = container.backoff,
            onSelect = shell::selectPlayer,
            onDeselect = shell::deselectPlayer,
            saveSongsPreset = { preset -> container.songsPreferences.applyPreset(container.settings, preset) },
            artworkUrl = api::artworkUrl,
        )
    }
}

/**
 * The score-history view model for the current navigation entry.
 *
 * @param container Process dependencies.
 * @param shell Shell session (selected player).
 * @param route History route.
 * @return Entry-scoped view model.
 */
@Composable
fun playerHistoryViewModel(container: AppContainer, shell: ShellViewModel, route: PlayerHistoryRoute): PlayerHistoryViewModel {
    val api = container.api
    return viewModel {
        PlayerHistoryViewModel(
            songId = route.songId,
            instrument = Instrument.fromWireId(route.instrument) ?: Instrument.Lead,
            read = { account, song, instrument -> api.playerHistory(account, song, instrument) },
            findSong = { id -> api.catalog().catalog.songs.firstOrNull { it.songId == id } },
            settings = shell.settings,
            backoff = container.backoff,
        )
    }
}

// endregion
