package com.festivalscoretracker.android.core.shop

import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.songs.SongCatalogSort
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.core.songs.SongSortMode

// region Sort choice

/**
 * Item Shop sort (issue #379): the Songs catalogue modes Title, Artist, Year and Duration
 * with a direction, offered in the Songs Sort sheet's frame and persisted like the Songs sort
 * (`fst.shop.sort`, `fst.shop.sortAscending`). Grid and list show the same order.
 *
 * @property mode Sort field (one of [modes]).
 * @property ascending Direction.
 */
data class ShopSortChoice(val mode: SongSortMode = SongSortMode.Title, val ascending: Boolean = true) {
    /** Whether the sort differs from the default Title ascending (gold Sort icon, like Songs). */
    val changed: Boolean get() = mode != SongSortMode.Title || !ascending

    /** Spoken state of the Sort button, for example "Artist, descending" (Songs vocabulary). */
    val stateDescription: String get() = SongSortDraft.describe(mode, ascending)

    companion object {
        /** Sheet modes in Songs order: the catalogue fields the Shop feed (plus the catalogue) can order by. */
        val modes: List<SongSortMode> = listOf(SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration)

        /**
         * Decode persisted values; anything unknown or outside [modes] falls back to the default.
         *
         * @param mode Stored mode name, or null.
         * @param ascending Stored direction (`"false"` is descending), or null.
         * @return The saved choice.
         */
        fun decode(mode: String?, ascending: String?): ShopSortChoice =
            ShopSortChoice(modes.firstOrNull { it.name == mode } ?: SongSortMode.Title, ascending != "false")
    }
}

// endregion

// region Durations

/**
 * Song lengths for the Duration sort. The `/api/shop` wire has no duration, so it comes from
 * the catalogue the Shop page already reads for Details links, and only from the same observed
 * publication as the Shop feed.
 */
sealed interface ShopDurations {
    /** The catalogue is still loading. */
    data object Loading : ShopDurations

    /** The catalogue read failed. */
    data object Failed : ShopDurations

    /** The catalogue and the Shop feed come from different publications. */
    data object Mismatch : ShopDurations

    /**
     * Same-publication catalogue lengths.
     *
     * @property seconds Duration by song ID (absent or null sorts as zero, like Songs).
     */
    data class Ready(val seconds: Map<String, Int?>) : ShopDurations

    companion object {
        /**
         * Pick the durations a Shop feed may use.
         *
         * @param catalog Catalogue lengths by song ID, or null while loading or failed.
         * @param failed The catalogue read failed.
         * @param catalogPublication Publication observed for the catalogue.
         * @param shopPublication Publication observed for the Shop feed.
         * @return Ready only when both reads observed the same publication.
         */
        fun of(catalog: Map<String, Int?>?, failed: Boolean, catalogPublication: Int?, shopPublication: Int?): ShopDurations = when {
            failed -> Failed
            catalog == null -> Loading
            catalogPublication == null || catalogPublication != shopPublication -> Mismatch
            else -> Ready(catalog)
        }
    }
}

// endregion

// region Sorting

/**
 * Offers in their effective order.
 *
 * @property offers Ordered offers.
 * @property effective Mode actually applied (Title while the Duration sort pauses).
 * @property paused Visible pause notice, or null.
 * @property waiting The Duration sort waits for the catalogue (the page keeps loading instead of reordering later).
 */
data class ShopSortResult(val offers: List<ShopSong>, val effective: SongSortMode, val paused: String?, val waiting: Boolean = false)

/**
 * Orders Item Shop offers with the Songs comparator ([SongCatalogSort]), so a Shop sort and the
 * same Songs sort agree: missing year/duration sort as zero, ties break by title then song ID
 * in the sort direction. Duration pauses to Title order (choice kept) without same-publication
 * catalogue lengths, like the Songs Item Shop sort pauses without a matching Shop feed.
 *
 * @property sorter Songs comparator.
 */
class ShopOfferSort(private val sorter: SongCatalogSort = SongCatalogSort()) {
    /**
     * Sort offers.
     *
     * @param offers Offers after the page filter.
     * @param choice Saved sort.
     * @param durations Catalogue lengths (Duration only).
     * @return Ordered offers, the applied mode and any pause.
     */
    fun sorted(offers: List<ShopSong>, choice: ShopSortChoice, durations: ShopDurations): ShopSortResult {
        val mode = choice.mode.takeIf { it in ShopSortChoice.modes } ?: SongSortMode.Title
        val seconds = (durations as? ShopDurations.Ready)?.seconds
        val paused = if (mode == SongSortMode.Duration) pauseReason(durations) else null
        val effective = if (mode == SongSortMode.Duration && seconds == null) SongSortMode.Title else mode
        val byId = offers.associateBy { it.songId }
        val rows = offers.map { Song(it.songId, it.title, it.artist, year = it.year, durationSeconds = seconds?.get(it.songId)) }
        val ordered = sorter.sorted(rows, effective, choice.ascending).map { byId.getValue(it.songId) }
        return ShopSortResult(ordered, effective, paused, waiting = mode == SongSortMode.Duration && durations == ShopDurations.Loading)
    }

    private fun pauseReason(durations: ShopDurations): String? = when (durations) {
        ShopDurations.Failed -> "Duration sort paused until song details load. Showing title order; your choice is saved."
        ShopDurations.Mismatch ->
            "Duration sort paused until Item Shop and song details update together. Showing title order; your choice is saved."
        else -> null
    }
}

// endregion
