package com.festivalscoretracker.android.data

import androidx.datastore.core.DataMigration
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.ScoreLeeway
import com.festivalscoretracker.android.core.settings.SettingsCodec
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongSortMode
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// region Settings repository

/**
 * DataStore-backed settings that survive cold starts, including the selected
 * player. Every key is declared in [SettingsRegistry] with its reset policy.
 *
 * @property store Preferences store (a temp-file store in tests).
 */
class SettingsRepository(private val store: DataStore<Preferences>) {
    private val safeData: Flow<Preferences> = store.data
        .catch { error -> if (error is IOException) emit(emptyPreferences()) else throw error }

    /** Current settings; a corrupt or unreadable file falls back to defaults. */
    val settings: Flow<AppSettings> = safeData.map(::decode)

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
     * Show or hide one chart; the last visible chart stays visible.
     *
     * @param instrument Chart to toggle.
     * @param visible New visibility.
     */
    suspend fun setInstrumentVisible(instrument: Instrument, visible: Boolean) {
        update { it.withInstrumentVisible(instrument, visible) }
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
        update { it.copy(increaseContrast = enabled) }
    }

    /**
     * Toggle the additive reduce-motion override.
     *
     * @param enabled New value.
     */
    suspend fun setReduceMotion(enabled: Boolean) {
        update { it.copy(reduceMotion = enabled) }
    }

    /**
     * Apply a Settings-page change atomically: decode, transform, sanitize and
     * write every app-setting field. The profile and Songs sort are written only
     * by their own setters.
     *
     * @param transform New settings from the current ones.
     */
    suspend fun update(transform: (AppSettings) -> AppSettings) {
        store.edit { prefs -> encodeAppSettings(prefs, transform(decode(prefs)).sanitized()) }
    }

    /**
     * Settings → Reset: remove every `ResetPolicy.AppSetting` key so its default
     * applies. The profile, Songs sort, seen-state and other kept keys survive
     * (web `resetSettings`).
     */
    suspend fun resetAppSettings() {
        val names = SettingsRegistry.appSettingKeys.toSet()
        store.edit { prefs -> prefs.asMap().keys.filter { it.name in names }.forEach { prefs.remove(it) } }
    }

    /**
     * Read a registered string blob (first-run or notification seen-state).
     *
     * @param key Registered key name.
     * @return Stored value, or null (also for an unreadable store).
     */
    suspend fun readBlob(key: String): String? {
        require(SettingsRegistry.isRegistered(key)) { "Unregistered key $key" }
        return safeData.first()[stringPreferencesKey(key)]
    }

    /**
     * Observe a registered string blob.
     *
     * @param key Registered key name.
     * @return Stored value stream (null when absent or unreadable), without repeats.
     */
    fun blob(key: String): Flow<String?> {
        require(SettingsRegistry.isRegistered(key)) { "Unregistered key $key" }
        val prefKey = stringPreferencesKey(key)
        return safeData.map { it[prefKey] }.distinctUntilChanged()
    }

    /**
     * Write or remove a registered string blob.
     *
     * @param key Registered key name.
     * @param value New value, or null to remove it.
     */
    suspend fun writeBlob(key: String, value: String?) {
        require(SettingsRegistry.isRegistered(key)) { "Unregistered key $key" }
        val prefKey = stringPreferencesKey(key)
        store.edit { prefs -> if (value == null) prefs.remove(prefKey) else prefs[prefKey] = value }
    }

    companion object {
        internal val KEY_ACCOUNT_ID = stringPreferencesKey(SettingsRegistry.ACCOUNT_ID)
        internal val KEY_DISPLAY_NAME = stringPreferencesKey(SettingsRegistry.DISPLAY_NAME)
        internal val KEY_VISIBLE_INSTRUMENTS = stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS)
        internal val KEY_SONG_SORT = stringPreferencesKey(SettingsRegistry.SONG_SORT)
        internal val KEY_SONG_SORT_ASCENDING = booleanPreferencesKey(SettingsRegistry.SONG_SORT_ASCENDING)
        internal val KEY_INCREASE_CONTRAST = booleanPreferencesKey(SettingsRegistry.INCREASE_CONTRAST)
        internal val KEY_REDUCE_MOTION = booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)
        private val KEY_REDUCE_TRANSPARENCY = booleanPreferencesKey(SettingsRegistry.REDUCE_TRANSPARENCY)
        private val KEY_DISABLE_ANIMATED_ARTWORK = booleanPreferencesKey(SettingsRegistry.DISABLE_ANIMATED_ARTWORK)
        private val KEY_SHOW_INSTRUMENT_ICONS = booleanPreferencesKey(SettingsRegistry.SHOW_INSTRUMENT_ICONS)
        private val KEY_ENABLE_VISUAL_ORDER = booleanPreferencesKey(SettingsRegistry.ENABLE_VISUAL_ORDER)
        private val KEY_SONG_ROW_VISUAL_ORDER = stringPreferencesKey(SettingsRegistry.SONG_ROW_VISUAL_ORDER)
        private val KEY_PATH_COLUMN_ORDER = stringPreferencesKey(SettingsRegistry.PATH_COLUMN_ORDER)
        private val KEY_PATH_DEFAULT_VIEW = stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW)
        private val KEY_PATH_WARNING_DISMISSED = booleanPreferencesKey(SettingsRegistry.PATH_WARNING_DISMISSED)
        private val KEY_FILTER_INVALID_SCORES = booleanPreferencesKey(SettingsRegistry.FILTER_INVALID_SCORES)
        private val KEY_LEEWAY = doublePreferencesKey(SettingsRegistry.LEEWAY)
        private val KEY_EXPERIMENTAL_RANKS = booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS)
        private val KEY_HIDE_SHOP = booleanPreferencesKey(SettingsRegistry.HIDE_SHOP)
        private val KEY_DISABLE_SHOP_HIGHLIGHTING = booleanPreferencesKey(SettingsRegistry.DISABLE_SHOP_HIGHLIGHTING)
        private val KEY_VISIBLE_METADATA = stringPreferencesKey(SettingsRegistry.VISIBLE_METADATA)

        /**
         * Write every app-setting field (not the profile or Songs sort).
         *
         * @param prefs Mutable preferences inside an edit.
         * @param settings Sanitized settings.
         */
        private fun encodeAppSettings(prefs: MutablePreferences, settings: AppSettings) {
            prefs[KEY_VISIBLE_INSTRUMENTS] = SettingsCodec.encodeInstruments(settings.visibleInstruments)
            prefs[KEY_INCREASE_CONTRAST] = settings.increaseContrast
            prefs[KEY_REDUCE_MOTION] = settings.reduceMotion
            prefs[KEY_REDUCE_TRANSPARENCY] = settings.reduceTransparency
            prefs[KEY_DISABLE_ANIMATED_ARTWORK] = settings.disableAnimatedArtwork
            prefs[KEY_SHOW_INSTRUMENT_ICONS] = settings.showInstrumentIcons
            prefs[KEY_ENABLE_VISUAL_ORDER] = settings.enableVisualOrder
            prefs[KEY_SONG_ROW_VISUAL_ORDER] = SettingsOrder.encode(settings.songRowVisualOrder) { it.token }
            prefs[KEY_PATH_COLUMN_ORDER] = SettingsOrder.encode(settings.pathColumnOrder) { it.token }
            prefs[KEY_PATH_DEFAULT_VIEW] = settings.pathDefaultView.token
            prefs[KEY_PATH_WARNING_DISMISSED] = settings.pathUnavailableWarningDismissed
            prefs[KEY_FILTER_INVALID_SCORES] = settings.filterInvalidScores
            prefs[KEY_LEEWAY] = settings.leeway
            prefs[KEY_EXPERIMENTAL_RANKS] = settings.experimentalRanks
            prefs[KEY_HIDE_SHOP] = settings.hideShop
            prefs[KEY_DISABLE_SHOP_HIGHLIGHTING] = settings.disableShopHighlighting
            prefs[KEY_VISIBLE_METADATA] = SettingsCodec.encodeMetadata(settings.visibleMetadata)
        }

        /**
         * Decode preferences; an invalid stored profile is ignored rather than
         * trusted, and every other field is sanitized.
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
                reduceTransparency = prefs[KEY_REDUCE_TRANSPARENCY] ?: false,
                disableAnimatedArtwork = prefs[KEY_DISABLE_ANIMATED_ARTWORK] ?: false,
                showInstrumentIcons = prefs[KEY_SHOW_INSTRUMENT_ICONS] ?: true,
                enableVisualOrder = prefs[KEY_ENABLE_VISUAL_ORDER] ?: false,
                songRowVisualOrder = SettingsOrder.decode(prefs[KEY_SONG_ROW_VISUAL_ORDER], MetadataField.entries, MetadataField::fromToken),
                pathColumnOrder = SettingsOrder.decode(prefs[KEY_PATH_COLUMN_ORDER], PathColumnKey.entries, PathColumnKey::fromToken),
                pathDefaultView = PathDisplayMode.fromToken(prefs[KEY_PATH_DEFAULT_VIEW]),
                pathUnavailableWarningDismissed = prefs[KEY_PATH_WARNING_DISMISSED] ?: false,
                filterInvalidScores = prefs[KEY_FILTER_INVALID_SCORES] ?: false,
                leeway = prefs[KEY_LEEWAY] ?: ScoreLeeway.DEFAULT,
                experimentalRanks = prefs[KEY_EXPERIMENTAL_RANKS] ?: false,
                hideShop = prefs[KEY_HIDE_SHOP] ?: false,
                disableShopHighlighting = prefs[KEY_DISABLE_SHOP_HIGHLIGHTING] ?: false,
                visibleMetadata = SettingsCodec.decodeMetadata(prefs[KEY_VISIBLE_METADATA]),
            ).sanitized()
        }
    }
}

// endregion

// region Retired keys

/**
 * Deletes [SettingsRegistry.retiredKeys] (Tap Diagnostics / Tap Telemetry, #374)
 * that older builds persisted; runs once when the settings store first opens.
 */
object RetiredSettingsMigration : DataMigration<Preferences> {
    override suspend fun shouldMigrate(currentData: Preferences): Boolean =
        currentData.asMap().keys.any { it.name in SettingsRegistry.retiredKeys }

    override suspend fun migrate(currentData: Preferences): Preferences =
        currentData.toMutablePreferences().apply {
            asMap().keys.filter { it.name in SettingsRegistry.retiredKeys }.forEach { remove(it) }
        }.toPreferences()

    override suspend fun cleanUp() = Unit
}

// endregion
