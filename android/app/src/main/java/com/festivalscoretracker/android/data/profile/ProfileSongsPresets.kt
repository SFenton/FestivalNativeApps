package com.festivalscoretracker.android.data.profile

import com.festivalscoretracker.android.core.profile.SongsFilterState
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.songs.SongsPreferences
import kotlinx.coroutines.flow.first

// region Tap-to-filter

/**
 * Persist a player-page stat tile's Songs filter (web `navigateToSongs`: load the saved
 * Songs settings, apply the updater, save) through the Songs lane's own stores, so the
 * Songs tab shows it as its normal saved state. A corrupt saved player filter is
 * replaced, since the preset is an explicit new choice.
 *
 * @receiver Saved Songs filters.
 * @param settings Settings repository (the Songs sort lives there).
 * @param preset Filter to apply.
 */
suspend fun SongsPreferences.applyPreset(settings: SettingsRepository, preset: SongsPreset) {
    val saved = state.first()
    val app = settings.settings.first()
    val current = SongsFilterState(
        filter = saved.filter,
        shopFilter = saved.shopFilter,
        playerFilter = saved.playerFilter ?: SongPlayerScoreFilter(),
        sort = app.songSort,
        ascending = app.songSortAscending,
    )
    val next = preset.apply(current)
    setFilters(next.filter.scopedTo(app.visibleInstruments), next.shopFilter, next.playerFilter.scopedTo(app.visibleInstruments))
    if (next.sort != current.sort || next.ascending != current.ascending) settings.setSongSort(next.sort, next.ascending)
}

// endregion
