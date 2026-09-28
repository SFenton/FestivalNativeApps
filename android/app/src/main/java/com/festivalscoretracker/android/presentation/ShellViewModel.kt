package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.SettingsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// region Shell state

/**
 * App-wide session state: persisted settings plus this launch's debug profile
 * override (in memory only, never written — Apple `FST_DEBUG_PROFILE`).
 *
 * @property repository Persisted settings.
 * @param launch Debug launch extras (empty in release builds).
 */
class ShellViewModel(private val repository: SettingsRepository, launch: DebugLaunch) : ViewModel() {
    private sealed interface ProfileOverride {
        data object None : ProfileOverride
        data class Forced(val player: SelectedPlayer?) : ProfileOverride
    }

    private val override = MutableStateFlow<ProfileOverride>(
        when {
            launch.profile != null -> ProfileOverride.Forced(launch.profile)
            launch.anonymous -> ProfileOverride.Forced(null)
            else -> ProfileOverride.None
        },
    )

    /** Effective settings with the debug profile override applied; null until the store is read. */
    val settings: StateFlow<AppSettings?> = combine(repository.settings, override) { stored, forced ->
        when (forced) {
            ProfileOverride.None -> stored
            is ProfileOverride.Forced -> stored.copy(selectedPlayer = forced.player)
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /**
     * Profile kind for tab policy.
     *
     * @param settings Current settings.
     * @return [ProfileKind.Player] when a player is selected.
     */
    fun profileKind(settings: AppSettings?): ProfileKind =
        if (settings?.selectedPlayer != null) ProfileKind.Player else ProfileKind.None

    /**
     * Select (and persist) a player; replaces any debug override.
     *
     * @param player Validated identity.
     */
    fun selectPlayer(player: SelectedPlayer) {
        override.value = ProfileOverride.None
        viewModelScope.launch { repository.setSelectedPlayer(player) }
    }

    /** Deselect (and persist) the player; replaces any debug override. */
    fun deselectPlayer() {
        override.value = ProfileOverride.None
        viewModelScope.launch { repository.setSelectedPlayer(null) }
    }

    /**
     * Show or hide a chart.
     *
     * @param instrument Chart.
     * @param visible New visibility.
     */
    fun setInstrumentVisible(instrument: Instrument, visible: Boolean) {
        viewModelScope.launch { repository.setInstrumentVisible(instrument, visible) }
    }

    /**
     * Persist the Songs sort.
     *
     * @param mode Field.
     * @param ascending Direction.
     */
    fun setSongSort(mode: SongSortMode, ascending: Boolean) {
        viewModelScope.launch { repository.setSongSort(mode, ascending) }
    }

    /**
     * Toggle the contrast override.
     *
     * @param enabled New value.
     */
    fun setIncreaseContrast(enabled: Boolean) {
        viewModelScope.launch { repository.setIncreaseContrast(enabled) }
    }

    /**
     * Toggle the reduce-motion override.
     *
     * @param enabled New value.
     */
    fun setReduceMotion(enabled: Boolean) {
        viewModelScope.launch { repository.setReduceMotion(enabled) }
    }
}

// endregion
