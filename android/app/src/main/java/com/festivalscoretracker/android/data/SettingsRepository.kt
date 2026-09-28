package com.festivalscoretracker.android.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.SettingsCodec
import com.festivalscoretracker.android.core.songs.SongSortMode
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

// region Settings repository

/**
 * DataStore-backed settings that survive cold starts, including the selected
 * player. Keys mirror Apple's `fst.settings.*` names where one exists.
 *
 * @property store Preferences store (a temp-file store in tests).
 */
class SettingsRepository(private val store: DataStore<Preferences>) {
    /** Current settings; a corrupt or unreadable file falls back to defaults. */
    val settings: Flow<AppSettings> = store.data
        .catch { error -> if (error is IOException) emit(emptyPreferences()) else throw error }
        .map(::decode)

    /**
     * Persist the selected player, or clear it.
     *
     * @param player Validated identity, or null to deselect.
     */
    suspend fun setSelectedPlayer(player: SelectedPlayer?) {
        store.edit { prefs ->
            if (player == null) {
                prefs.remove(KEY_ACCOUNT_ID)
                prefs.remove(KEY_DISPLAY_NAME)
            } else {
                prefs[KEY_ACCOUNT_ID] = player.accountId
                prefs[KEY_DISPLAY_NAME] = player.displayName
            }
        }
    }

    /**
     * Show or hide one chart.
     *
     * @param instrument Chart to toggle.
     * @param visible New visibility.
     */
    suspend fun setInstrumentVisible(instrument: Instrument, visible: Boolean) {
        store.edit { prefs ->
            val currentSet = SettingsCodec.decodeInstruments(prefs[KEY_VISIBLE_INSTRUMENTS])
            val updated = if (visible) currentSet + instrument else currentSet - instrument
            prefs[KEY_VISIBLE_INSTRUMENTS] = SettingsCodec.encodeInstruments(updated)
        }
    }

    /**
     * Persist the Songs sort.
     *
     * @param mode Sort field.
     * @param ascending Direction.
     */
    suspend fun setSongSort(mode: SongSortMode, ascending: Boolean) {
        store.edit { prefs ->
            prefs[KEY_SONG_SORT] = mode.name
            prefs[KEY_SONG_SORT_ASCENDING] = ascending
        }
    }

    /**
     * Toggle the additive contrast override.
     *
     * @param enabled New value.
     */
    suspend fun setIncreaseContrast(enabled: Boolean) {
        store.edit { it[KEY_INCREASE_CONTRAST] = enabled }
    }

    /**
     * Toggle the additive reduce-motion override.
     *
     * @param enabled New value.
     */
    suspend fun setReduceMotion(enabled: Boolean) {
        store.edit { it[KEY_REDUCE_MOTION] = enabled }
    }

    companion object {
        internal val KEY_ACCOUNT_ID = stringPreferencesKey("fst.profile.accountId")
        internal val KEY_DISPLAY_NAME = stringPreferencesKey("fst.profile.displayName")
        internal val KEY_VISIBLE_INSTRUMENTS = stringPreferencesKey("fst.settings.visibleInstruments")
        internal val KEY_SONG_SORT = stringPreferencesKey("fst.songs.sort")
        internal val KEY_SONG_SORT_ASCENDING = booleanPreferencesKey("fst.songs.sortAscending")
        internal val KEY_INCREASE_CONTRAST = booleanPreferencesKey("fst.accessibility.moreContrast")
        internal val KEY_REDUCE_MOTION = booleanPreferencesKey("fst.accessibility.reduceMotion")

        /**
         * Decode preferences; an invalid stored profile is ignored rather than trusted.
         *
         * @param prefs Raw preferences.
         * @return Typed settings.
         */
        fun decode(prefs: Preferences): AppSettings {
            val accountId = prefs[KEY_ACCOUNT_ID]
            val displayName = prefs[KEY_DISPLAY_NAME]
            return AppSettings(
                selectedPlayer = if (accountId != null && displayName != null) SelectedPlayer.validated(accountId, displayName) else null,
                visibleInstruments = SettingsCodec.decodeInstruments(prefs[KEY_VISIBLE_INSTRUMENTS]),
                songSort = SongSortMode.fromStored(prefs[KEY_SONG_SORT]),
                songSortAscending = prefs[KEY_SONG_SORT_ASCENDING] ?: true,
                increaseContrast = prefs[KEY_INCREASE_CONTRAST] ?: false,
                reduceMotion = prefs[KEY_REDUCE_MOTION] ?: false,
            )
        }
    }
}

// endregion
