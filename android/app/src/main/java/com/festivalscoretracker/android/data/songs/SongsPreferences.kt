package com.festivalscoretracker.android.data.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongCatalogBuckets
import com.festivalscoretracker.android.core.songs.SongGeneralFilter
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
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
 * @property filter Public chart and Song Intensity filter (Selected Instrument Filters; player only).
 * @property general Public General filters (Year, Duration, Item Shop, Double Bass).
 * @property playerFilter Selected-player filter, or null when the saved value is corrupt
 *   (the list is blocked until an explicit Reset).
 * @property shopViewMode Item Shop layout.
 * @property metadataOrder Metadata sort priority (row order while independent visual order is off).
 */
data class SongsPreferencesState(
    val filter: SongFilter = SongFilter(),
    val general: SongGeneralFilter = SongGeneralFilter(),
    val playerFilter: SongPlayerScoreFilter? = SongPlayerScoreFilter(),
    val shopViewMode: ShopViewMode = ShopViewMode.Grid,
    val metadataOrder: List<MetadataField> = MetadataField.entries,
) {
    /**
     * Whether any saved filter applies (gold filter icon, web `isFilterActive`): General
     * filters always (Item Shop only while shown); the instrument and player filters only
     * with a selected player.
     *
     * @param hasPlayer A player is selected.
     * @param hideShop Item Shop hidden in Settings.
     * @return True when the icon should show an active filter.
     */
    fun filterActive(hasPlayer: Boolean, hideShop: Boolean): Boolean =
        general.isActive(shopVisible = !hideShop) || (hasPlayer && (filter.isActive || playerFilter?.appliesTo(filter.instrument) == true))

    /**
     * Spoken state of the Filter button (issue #181), so TalkBack hears what the gold tint shows:
     * "No filters", or "Filters on: " and the applied groups in sheet order (Year, Duration,
     * Item Shop, Double Bass, then with a player Score & FC and Selected Instrument). Same
     * vocabulary as the Item Shop Filter (issue #145); empty exactly when [filterActive] is false.
     *
     * @param hasPlayer A player is selected.
     * @param hideShop Item Shop hidden in Settings.
     * @return The button's state description.
     */
    fun filterStateDescription(hasPlayer: Boolean, hideShop: Boolean): String {
        val groups = listOfNotNull(
            "Year".takeIf { general.excludedDecades.isNotEmpty() },
            "Duration".takeIf { general.excludedDurations.isNotEmpty() },
            "Item Shop".takeIf { !hideShop && general.shopActive },
            "Double Bass".takeIf { !general.doubleBassSupported || !general.doubleBassUnsupported },
            "Score & FC".takeIf { hasPlayer && playerFilter?.hasChecks == true },
            "Selected Instrument".takeIf { hasPlayer && filter.isActive },
        )
        return if (groups.isEmpty()) "No filters" else "Filters on: " + groups.joinToString(", ")
    }
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
        settings.blob(SettingsRegistry.SONG_METADATA_ORDER),
    ) { filters, player, view, order ->
        val public = decodePublic(filters)
        SongsPreferencesState(
            filter = public.first,
            general = public.second,
            playerFilter = SongPlayerScoreFilter.decodeSaved(player),
            shopViewMode = if (view == ShopViewMode.List.name) ShopViewMode.List else ShopViewMode.Grid,
            metadataOrder = SettingsOrder.decode(order, MetadataField.entries, MetadataField::fromToken),
        )
    }

    /**
     * Apply a filter draft.
     *
     * @param filter Public filter.
     * @param general General filters.
     * @param playerFilter Player filter (already scoped to visible charts).
     */
    suspend fun setFilters(filter: SongFilter, general: SongGeneralFilter, playerFilter: SongPlayerScoreFilter) {
        settings.writeBlob(SettingsRegistry.SONG_FILTERS, encodePublic(filter, general))
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, playerFilter.encoded().ifEmpty { null })
    }

    /** Clear every filter (the explicit Reset that also repairs a corrupt saved filter). */
    suspend fun clearFilters() {
        settings.writeBlob(SettingsRegistry.SONG_FILTERS, null)
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, null)
    }

    /**
     * Clear the player-scoped filters on confirmed deselection: score predicates and the
     * Selected Instrument Filters (instrument and Song Intensity, which the web resets and
     * hides without a profile). The public General filters stay.
     */
    suspend fun clearPlayerFilter() {
        settings.writeBlob(SettingsRegistry.SONG_PLAYER_SCORE_FILTERS, null)
        val general = decodePublic(settings.blob(SettingsRegistry.SONG_FILTERS).first()).second
        settings.writeBlob(SettingsRegistry.SONG_FILTERS, encodePublic(SongFilter(), general))
    }

    /** Reset a saved sort that reads the selected player's scores to Title ascending. */
    suspend fun clearScoreSort() {
        if (settings.settings.first().songSort.needsScores) settings.setSongSort(SongSortMode.Title, true)
    }

    /**
     * Persist the metadata sort priority (the default order is stored as absent).
     *
     * @param order Every field once.
     */
    suspend fun setMetadataOrder(order: List<MetadataField>) {
        val complete = SettingsOrder.normalize(order, MetadataField.entries)
        settings.writeBlob(SettingsRegistry.SONG_METADATA_ORDER, if (complete == MetadataField.entries) null else SettingsOrder.encode(complete) { it.token })
    }

    /**
     * Persist the Item Shop layout.
     *
     * @param mode Layout.
     */
    suspend fun setShopViewMode(mode: ShopViewMode) {
        settings.writeBlob(SettingsRegistry.SHOP_VIEW_MODE, mode.name)
    }

    /**
     * Public filter blob. [inShop]/[leavingTomorrow] are the retired Shop toggles, decoded
     * only to migrate them to "Available in Item Shop" (web `migrateShopAvailability`).
     */
    @Serializable
    private data class StoredPublic(
        val instrument: String? = null,
        val excludedIntensities: List<Int> = emptyList(),
        val inShop: Boolean = false,
        val leavingTomorrow: Boolean = false,
        val excludedDecades: List<Int> = emptyList(),
        val excludedDurations: List<Int> = emptyList(),
        val shopAvailable: Boolean? = null,
        val shopUnavailable: Boolean? = null,
        val doubleBassSupported: Boolean = true,
        val doubleBassUnsupported: Boolean = true,
    )

    companion object {
        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Encode the public filters, or null for defaults.
         *
         * @param filter Public filter.
         * @param general General filters.
         * @return JSON or null.
         */
        internal fun encodePublic(filter: SongFilter, general: SongGeneralFilter): String? {
            if (!filter.isActive && filter.excludedIntensities.isEmpty() && general == SongGeneralFilter()) return null
            val stored = StoredPublic(
                instrument = filter.instrument?.wireId,
                excludedIntensities = filter.excludedIntensities.sorted(),
                excludedDecades = general.excludedDecades.sorted(),
                excludedDurations = general.excludedDurations.sorted(),
                shopAvailable = general.shopAvailable,
                shopUnavailable = general.shopUnavailable,
                doubleBassSupported = general.doubleBassSupported,
                doubleBassUnsupported = general.doubleBassUnsupported,
            )
            return JSON.encodeToString(StoredPublic.serializer(), stored)
        }

        /**
         * Decode public filters; anything invalid falls back to defaults (they gate nothing
         * unsafe). A malformed Song Intensity, Year or Duration list drops only that section.
         *
         * @param raw Stored JSON.
         * @return Filter and General filters.
         */
        internal fun decodePublic(raw: String?): Pair<SongFilter, SongGeneralFilter> {
            val stored = raw?.let { runCatching { JSON.decodeFromString(StoredPublic.serializer(), it) }.getOrNull() }
                ?: return SongFilter() to SongGeneralFilter()
            val filter = SongFilter(stored.instrument?.let(Instrument::fromWireId), stored.excludedIntensities.toSet())
            val valid = filter.isValid && filter.excludedIntensities.size == stored.excludedIntensities.size
            fun keys(values: List<Int>, check: (Int) -> Boolean): Set<Int> =
                values.toSet().takeIf { it.size == values.size && it.all(check) } ?: emptySet()
            val legacyAvailable = stored.inShop || stored.leavingTomorrow
            val general = SongGeneralFilter(
                excludedDecades = keys(stored.excludedDecades, SongCatalogBuckets::isDecade),
                excludedDurations = keys(stored.excludedDurations, SongCatalogBuckets::isDuration),
                shopAvailable = stored.shopAvailable ?: true,
                shopUnavailable = stored.shopUnavailable ?: !legacyAvailable,
                doubleBassSupported = stored.doubleBassSupported,
                doubleBassUnsupported = stored.doubleBassUnsupported,
            )
            return (if (valid) filter else SongFilter(filter.instrument)) to general
        }
    }
}

// endregion

// region Deselection

/**
 * Clear selected-player predicates and Selected Instrument Filters when a selected player
 * is deselected (a player-to-player switch keeps them; public General choices always stay).
 * A saved score sort falls back to Title ascending, like the filters it depends on.
 *
 * @receiver Songs preferences.
 * @param scope Process-lifetime scope.
 * @param players Effective selected-player stream.
 */
fun SongsPreferences.watchDeselection(scope: CoroutineScope, players: Flow<SelectedPlayer?>) {
    scope.launch {
        var previous: SelectedPlayer? = null
        players.collect { player ->
            if (previous != null && player == null) {
                clearPlayerFilter()
                clearScoreSort()
            }
            previous = player
        }
    }
}

// endregion
