package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.shop.ShopSong
import java.text.Collator
import java.text.Normalizer
import java.util.Locale

// region Sort modes

/**
 * Catalogue and public-Shop sort modes that work without a selected profile
 * (Apple `SongSortMode`).
 *
 * @property label Sheet label.
 */
enum class SongSortMode(val label: String) {
    Title("Title"),
    Artist("Artist"),
    Year("Year"),
    Duration("Duration"),
    Shop("Item Shop");

    companion object {
        /**
         * Parse a persisted value, falling back to [Title] for unknown or removed modes.
         *
         * @param raw Stored enum name.
         * @return The matching mode or [Title].
         */
        fun fromStored(raw: String?): SongSortMode = entries.firstOrNull { it.name == raw } ?: Title
    }
}

// endregion

// region Sorting

/**
 * Sort typed catalogue fields and validated public Shop membership, never
 * profile scores (Apple `SongCatalogSort`).
 *
 * @property collator Locale-aware string comparison; injectable for deterministic tests.
 */
class SongCatalogSort(private val collator: Collator = Collator.getInstance(Locale.getDefault())) {
    /**
     * Order songs. Catalogue modes break ties by title; Shop breaks ties by title,
     * artist, then year. The song ID keeps equal rows stable; descending reverses all.
     *
     * @param songs Songs after search and filtering.
     * @param mode Sort field.
     * @param ascending Direction.
     * @param shopIds Validated membership, required for [SongSortMode.Shop].
     * @return A new ordered list.
     */
    fun sorted(songs: List<Song>, mode: SongSortMode, ascending: Boolean, shopIds: Set<String> = emptySet()): List<Song> {
        val comparator = Comparator<Song> { left, right ->
            var result = when (mode) {
                SongSortMode.Title -> collator.compare(left.title, right.title)
                SongSortMode.Artist -> collator.compare(left.artist, right.artist)
                SongSortMode.Year -> (left.year ?: 0).compareTo(right.year ?: 0)
                SongSortMode.Duration -> (left.durationSeconds ?: 0).compareTo(right.durationSeconds ?: 0)
                SongSortMode.Shop -> (right.songId in shopIds).compareTo(left.songId in shopIds)
            }
            if (result == 0) result = collator.compare(left.title, right.title)
            if (result == 0 && mode == SongSortMode.Shop) {
                result = collator.compare(left.artist, right.artist)
                if (result == 0) result = (left.year ?: 0).compareTo(right.year ?: 0)
            }
            if (result != 0) result else left.songId.compareTo(right.songId)
        }
        return songs.sortedWith(if (ascending) comparator else comparator.reversed())
    }
}

// endregion

// region Section index

/**
 * One nonempty jump-to bucket for the right-edge index scrubber.
 *
 * @property id Stable position index (labels may legitimately repeat).
 * @property label Uppercase letter, `#` or a year.
 * @property firstIndex Position of the section's first song in the list.
 * @property count Songs in the section.
 */
data class SongSection(val id: Int, val label: String, val firstIndex: Int, val count: Int)

/** Contacts-style drag-to-jump index for Title/Artist/Year (Apple `SongSectionIndex`). */
object SongSectionIndex {
    /** Label for songs with no year. */
    const val UNKNOWN_YEAR = "—"

    /**
     * Chunk an already-sorted list on **consecutive** key changes.
     *
     * @param songs Songs in on-screen order.
     * @param mode Active sort; only Title, Artist and Year group.
     * @return Order-preserving sections; empty for other modes or fewer than two songs.
     */
    fun sections(songs: List<Song>, mode: SongSortMode): List<SongSection> {
        if (songs.size < 2) return emptyList()
        val key: (Song) -> String = when (mode) {
            SongSortMode.Title -> { song -> firstLetter(song.title) }
            SongSortMode.Artist -> { song -> firstLetter(song.artist) }
            SongSortMode.Year -> { song -> song.year?.takeIf { it != 0 }?.toString() ?: UNKNOWN_YEAR }
            SongSortMode.Duration, SongSortMode.Shop -> return emptyList()
        }
        return chunk(songs, key)
    }

    /**
     * Chunk rows on consecutive key changes.
     *
     * @param songs Rows in order.
     * @param key Section key.
     * @return Sections.
     */
    internal fun chunk(songs: List<Song>, key: (Song) -> String): List<SongSection> {
        if (songs.isEmpty()) return emptyList()
        val result = mutableListOf<SongSection>()
        var start = 0
        var label = key(songs[0])
        for (index in 1 until songs.size) {
            val next = key(songs[index])
            if (next != label) {
                result += SongSection(result.size, label, start, index - start)
                start = index
                label = next
            }
        }
        result += SongSection(result.size, label, start, songs.size - start)
        return result
    }

    /**
     * Diacritic-folded first character when it is A–Z, otherwise `#`.
     *
     * @param text Raw title or artist.
     * @return One uppercase ASCII letter or `#`.
     */
    fun firstLetter(text: String): String {
        val first = text.trim().firstOrNull() ?: return "#"
        val folded = Normalizer.normalize(first.toString(), Normalizer.Form.NFD)
            .firstOrNull()?.uppercaseChar() ?: return "#"
        return if (folded in 'A'..'Z') folded.toString() else "#"
    }
}

// endregion

// region Shop sections

/**
 * Source Shop buckets in first-seen order (Apple `SongShopSectionKind`).
 *
 * @property id Stable test/scroll ID.
 * @property label Section header.
 */
enum class SongShopBucket(val id: String, val label: String) {
    LeavingTomorrow("leaving-tomorrow", "Leaving Tomorrow"),
    InShop("in-shop", "In Shop"),
    NotInShop("not-in-shop", "Not In Shop"),
}

/**
 * A labeled header inserted before [firstIndex] in the row list.
 *
 * @property id Stable ID.
 * @property label White Title Case header.
 * @property firstIndex Row index the header precedes.
 */
data class SongListHeader(val id: String, val label: String, val firstIndex: Int)

/** Shop quick-link grouping (web `buildSongQuickLinkSections`). */
object SongShopSections {
    /**
     * Headers for rows sorted by Shop: only when two or more buckets are non-empty.
     * A leaving offer is never also "In Shop".
     *
     * @param sorted Rows sorted by Shop (contiguous buckets).
     * @param offers Validated offers.
     * @return Headers, or empty when one bucket would add nothing.
     */
    fun headers(sorted: List<Song>, offers: Map<String, ShopSong>): List<SongListHeader> {
        val sections = SongSectionIndex.chunk(sorted) { song -> bucket(song, offers).name }
        if (sections.size < 2) return emptyList()
        return sections.map { section ->
            val bucket = SongShopBucket.valueOf(section.label)
            SongListHeader("shop-${bucket.id}-${section.id}", bucket.label, section.firstIndex)
        }
    }

    /**
     * Bucket for one song.
     *
     * @param song Row.
     * @param offers Validated offers.
     * @return Bucket.
     */
    fun bucket(song: Song, offers: Map<String, ShopSong>): SongShopBucket = when (offers[song.songId]?.leavingTomorrow) {
        true -> SongShopBucket.LeavingTomorrow
        false -> SongShopBucket.InShop
        null -> SongShopBucket.NotInShop
    }
}

// endregion

// region Pipeline

/**
 * Everything that shapes the Songs list, captured once per rebuild.
 *
 * @property songs Validated catalogue rows.
 * @property search Applied (debounced) search text.
 * @property filter Public chart/difficulty filter.
 * @property shopFilter Saved Shop filter.
 * @property playerFilter Saved selected-player filter.
 * @property sort Saved sort mode.
 * @property ascending Saved direction.
 * @property visible Settings-visible charts.
 * @property hideShop Hide Item Shop setting.
 * @property offers Same-publication offers, or null when unavailable.
 * @property shopPublicationMismatch A Shop feed exists but from a different publication.
 * @property hasPlayer A player is selected.
 * @property filterInvalidScores Filter Invalid Scores setting.
 * @property scores Facts for a matching, available score index; null when unavailable.
 */
data class SongListInputs(
    val songs: List<Song>,
    val search: String = "",
    val filter: SongFilter = SongFilter(),
    val shopFilter: SongShopFilter = SongShopFilter(),
    val playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
    val visible: Set<Instrument> = Instrument.entries.toSet(),
    val hideShop: Boolean = false,
    val offers: Map<String, ShopSong>? = null,
    val shopPublicationMismatch: Boolean = false,
    val hasPlayer: Boolean = false,
    val filterInvalidScores: Boolean = false,
    val scores: ((String, Instrument) -> ChartScoreFacts?)? = null,
)

/**
 * Rows plus the pause notices explaining any saved choice not currently applied.
 *
 * @property songs Rows in order.
 * @property sections Scrubber sections (Title/Artist/Year only).
 * @property headers In-list headers (Shop buckets).
 * @property effectiveSort Sort actually applied (a paused Shop sort shows Title order).
 * @property sortPaused Why a saved Shop sort is paused.
 * @property shopFilterPaused Why a saved Shop filter is paused.
 * @property scoreFilterPaused Why saved player filters are paused.
 * @property filtersApplied Whether any filter actually narrowed the pipeline.
 */
data class SongListResult(
    val songs: List<Song>,
    val sections: List<SongSection>,
    val headers: List<SongListHeader>,
    val effectiveSort: SongSortMode,
    val sortPaused: String?,
    val shopFilterPaused: String?,
    val scoreFilterPaused: String?,
    val filtersApplied: Boolean,
) {
    /** Every pause notice, in display order. */
    val notices: List<String> get() = listOfNotNull(sortPaused, shopFilterPaused, scoreFilterPaused)
}

/** Search → chart filter → Shop filter → player filter → sort → group, pausing rather than guessing. */
object SongListPipeline {
    /**
     * Run the pipeline.
     *
     * @param input Captured inputs.
     * @param sorter Sorter.
     * @return Rows, sections and notices.
     */
    fun run(input: SongListInputs, sorter: SongCatalogSort = SongCatalogSort()): SongListResult {
        val filter = input.filter.scopedTo(input.visible)
        var rows = input.songs.filter { SongSearch.matches(it, input.search) && filter.matches(it) }

        val shopPaused = if (input.shopFilter.isActive) shopPauseReason(input, "filters") else null
        if (input.shopFilter.isActive && shopPaused == null) rows = input.shopFilter.filter(rows, input.offers.orEmpty())

        val scorePaused = scorePauseReason(input)
        val scoped = input.playerFilter.scopedTo(input.visible)
        val scores = input.scores
        if (scorePaused == null && scoped.isActive && scores != null) {
            rows = scoped.filter(rows, scores, input.visible, filter.instrument)
        }

        val sortPaused = if (input.sort == SongSortMode.Shop) shopPauseReason(input, "sort") else null
        val effective = if (input.sort == SongSortMode.Shop && sortPaused != null) SongSortMode.Title else input.sort
        val sorted = sorter.sorted(rows, effective, input.ascending, input.offers?.keys.orEmpty())
        val headers = if (effective == SongSortMode.Shop) SongShopSections.headers(sorted, input.offers.orEmpty()) else emptyList()
        val applied = filter.isActive || (input.shopFilter.isActive && shopPaused == null) || (scoped.isActive && scorePaused == null)
        return SongListResult(
            sorted, SongSectionIndex.sections(sorted, effective), headers, effective,
            sortPaused, shopPaused, scorePaused, applied,
        )
    }

    private fun shopPauseReason(input: SongListInputs, what: String): String? {
        val fallback = if (what == "sort") "Showing title order" else "Showing all songs"
        return when {
            input.hideShop -> "Item Shop $what paused while the Item Shop is hidden. $fallback; your choice is saved."
            input.shopPublicationMismatch ->
                "Item Shop $what paused until songs and Item Shop data update together. $fallback; your choice is saved."
            input.offers == null -> "Item Shop $what paused until Item Shop data loads. $fallback; your choice is saved."
            else -> null
        }
    }

    private fun scorePauseReason(input: SongListInputs): String? = when {
        !input.playerFilter.isActive -> null
        !input.playerFilter.scopedTo(input.visible).isActive ->
            "Player score filters paused while their instruments are hidden in Settings. Your choices are saved."
        !input.hasPlayer -> "Player score filters paused until a player is selected."
        input.filterInvalidScores ->
            "Player score filters paused while Filter Invalid Scores is on. Published raw scores can't stand in for validated scores."
        input.scores == null ->
            "Player score filters paused until the player's scores and songs are from the same update. Showing songs without score filters."
        else -> null
    }
}

// endregion
