package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongShopFilter
import com.festivalscoretracker.android.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Model

/** Item Shop layout preference (compact widths always use the list). */
enum class ShopViewMode {
    /** Artwork grid. */
    Grid,

    /** Compact list. */
    List,
}

/**
 * Saved Songs filter state.
 *
 * @property filter Public chart/difficulty filter.
 * @property shopFilter Public Shop filter.
 * @property playerFilter Selected-player filter, or null when the saved value is corrupt
 *   (the list is blocked until an explicit Reset).
 * @property shopViewMode Item Shop layout.
 */
data class SongsPreferencesState(
    val filter: SongFilter = SongFilter(),
    val shopFilter: SongShopFilter = SongShopFilter(),
    val playerFilter: SongPlayerScoreFilter? = SongPlayerScoreFilter(),
    val shopViewMode: ShopViewMode = ShopViewMode.Grid,
) {
    /** Whether any saved filter is set (gold filter icon). */
    val anyFilterActive: Boolean get() = filter.isActive || shopFilter.isActive || playerFilter?.isActive == true
}

// endregion

// region Store

/**
 * Songs-owned persisted state on the shared settings DataStore (`fst.songs.*`,
 * `fst.shop.viewMode`, all [com.festivalscoretracker.android.core.settings.ResetPolicy.Kept]).
 *
 * @property settings Shared repository.
 */
class SongsPreferences(private val settings: SettingsRepository) {
    /** Current saved state. */
    val state: Flow<SongsPreferencesState> = combine(
        settings.blob(SettingsRegistry.SONG_FILTERS),
        settings.blob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS),
        settings.blob(SettingsRegistry.SHOP_VIEW_MODE),
    ) { filters, player, view ->
        val public = decodePublic(filters)
        SongsPreferencesState(
            filter = public.first,
            shopFilter = public.second,
            playerFilter = SongPlayerScoreFilter.decodeSaved(player),
            shopViewMode = if (view == ShopViewMode.List.name) ShopViewMode.List else ShopViewMode.Grid,
        )
    }

    /**
     * Apply a filter draft.
     *
     * @param filter Public filter.
     * @param shopFilter Shop filter.
     * @param playerFilter Player filter (already scoped to visible charts).
     */
    suspend fun setFilters(filter: SongFilter, shopFilter: SongShopFilter, playerFilter: SongPlayerScoreFilter) {
        settings.writeBlob(SettingsRegistry.SONG_FILTERS, encodePublic(filter, shopFilter))
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, playerFilter.encoded().ifEmpty { null })
    }

    /** Clear every filter (the explicit Reset that also repairs a corrupt saved filter). */
    suspend fun clearFilters() {
        settings.writeBlob(SettingsRegistry.SONG_FILTERS, null)
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, null)
    }

    /** Clear only the selected-player predicates (confirmed deselection keeps public Shop choices). */
    suspend fun clearPlayerFilter() {
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, null)
    }

    /**
     * Persist the Item Shop layout.
     *
     * @param mode Layout.
     */
    suspend fun setShopViewMode(mode: ShopViewMode) {
        settings.writeBlob(SettingsRegistry.SHOP_VIEW_MODE, mode.name)
    }

    @Serializable
    private data class StoredPublic(
        val instrument: String? = null,
        val minDifficulty: Int = 1,
        val maxDifficulty: Int = 7,
        val inShop: Boolean = false,
        val leavingTomorrow: Boolean = false,
    )

    companion object {
        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Encode the public filters, or null for defaults.
         *
         * @param filter Public filter.
         * @param shopFilter Shop filter.
         * @return JSON or null.
         */
        internal fun encodePublic(filter: SongFilter, shopFilter: SongShopFilter): String? {
            if (!filter.isActive && !shopFilter.isActive) return null
            val stored = StoredPublic(filter.instrument?.wireId, filter.minDifficulty, filter.maxDifficulty, shopFilter.inShop, shopFilter.leavingTomorrow)
            return JSON.encodeToString(StoredPublic.serializer(), stored)
        }

        /**
         * Decode public filters; anything invalid falls back to defaults (they gate nothing unsafe).
         *
         * @param raw Stored JSON.
         * @return Filter and Shop filter.
         */
        internal fun decodePublic(raw: String?): Pair<SongFilter, SongShopFilter> {
            val stored = raw?.let { runCatching { JSON.decodeFromString(StoredPublic.serializer(), it) }.getOrNull() }
                ?: return SongFilter() to SongShopFilter()
            val filter = SongFilter(stored.instrument?.let(Instrument::fromWireId), stored.minDifficulty, stored.maxDifficulty)
            return (if (filter.isValid) filter else SongFilter()) to SongShopFilter(stored.inShop, stored.leavingTomorrow)
        }
    }
}

// endregion

// region Deselection

/**
 * Clear selected-player predicates when a selected player is deselected (a
 * player-to-player switch keeps them; public Shop choices always stay).
 *
 * @receiver Songs preferences.
 * @param scope Process-lifetime scope.
 * @param players Effective selected-player stream.
 */
fun SongsPreferences.watchDeselection(scope: CoroutineScope, players: Flow<SelectedPlayer?>) {
    scope.launch {
        var previous: SelectedPlayer? = null
        players.collect { player ->
            if (previous != null && player == null) clearPlayerFilter()
            previous = player
        }
    }
}

// endregion
