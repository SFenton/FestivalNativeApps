package com.festivalscoretracker.android.data.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongGeneralFilter
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.songs.SongsPreferences
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Stat-tile Songs presets written through the Songs stores. */
class ProfileSongsPresetsTest {
    private val repository = SettingsRepository(InMemoryPreferences())
    private val prefs = SongsPreferences(repository)

    @Test
    fun overallPresetReplacesFiltersAndSort() = runTest {
        prefs.setFilters(SongFilter(Instrument.Bass, setOf(2, 6)), SongGeneralFilter(shopUnavailable = false), SongPlayerScoreFilter(missingScores = setOf(Instrument.Lead)))
        repository.setSongSort(SongSortMode.Year, false)
        repository.setInstrumentVisible(Instrument.Karaoke, false)
        val visible = repository.settings.first().visibleInstruments
        prefs.applyPreset(repository, SongsPreset.Overall(SongScoreFilterKind.HasScores, visible))
        val saved = prefs.state.first()
        assertEquals(SongFilter(), saved.filter)
        assertEquals(SongGeneralFilter(), saved.general)
        assertEquals(SongPlayerScoreFilter(hasScores = visible), saved.playerFilter)
        val app = repository.settings.first()
        assertEquals(SongSortMode.Title, app.songSort)
        assertTrue(app.songSortAscending)
    }

    @Test
    fun instrumentPresetSortsByScoreAndRepairsACorruptPlayerFilter() = runTest {
        repository.setSongSort(SongSortMode.Duration, false)
        repository.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, "{corrupt")
        assertEquals(null, prefs.state.first().playerFilter)
        prefs.applyPreset(repository, SongsPreset.ForInstrument(SongScoreFilterKind.HasFCs, Instrument.Drums))
        val saved = prefs.state.first()
        assertEquals(SongFilter(Instrument.Drums), saved.filter)
        assertEquals(SongPlayerScoreFilter(hasFCs = setOf(Instrument.Drums)), saved.playerFilter)
        val app = repository.settings.first()
        assertEquals(SongSortMode.Score, app.songSort)
        assertTrue(app.songSortAscending)
    }
}
