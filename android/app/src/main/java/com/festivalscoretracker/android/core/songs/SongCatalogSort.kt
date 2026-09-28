package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import java.text.Collator
import java.text.Normalizer
import java.util.Locale

// region Sort modes

/**
 * Catalogue sort modes that work without a selected profile (Apple `SongSortMode`).
 * Item Shop sorting waits for the Shop feed port.
 */
enum class SongSortMode(val label: String) {
    Title("Title"),
    Artist("Artist"),
    Year("Year"),
    Duration("Duration");

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
 * Sort typed catalogue fields with the source's tie-breakers and a stable ID,
 * never profile scores (Apple `SongCatalogSort`).
 *
 * @property collator Locale-aware string comparison; injectable for deterministic tests.
 */
class SongCatalogSort(private val collator: Collator = Collator.getInstance(Locale.getDefault())) {
    /**
     * Order songs; title breaks ties, then the song ID keeps equal rows stable.
     *
     * @param songs Songs after search and instrument filtering.
     * @param mode Sort field.
     * @param ascending Reverse every field and tie when false.
     * @return A new ordered list.
     */
    fun sorted(songs: List<Song>, mode: SongSortMode, ascending: Boolean): List<Song> {
        val comparator = Comparator<Song> { left, right ->
            val primary = when (mode) {
                SongSortMode.Title -> collator.compare(left.title, right.title)
                SongSortMode.Artist -> collator.compare(left.artist, right.artist)
                SongSortMode.Year -> (left.year ?: 0).compareTo(right.year ?: 0)
                SongSortMode.Duration -> (left.durationSeconds ?: 0).compareTo(right.durationSeconds ?: 0)
            }
            val result = if (primary != 0) primary else collator.compare(left.title, right.title)
            if (result != 0) result else left.songId.compareTo(right.songId)
        }
        return songs.sortedWith(if (ascending) comparator else comparator.reversed())
    }
}

// endregion

// region List pipeline

/**
 * Everything that shapes the visible Songs list.
 *
 * @property query Search text (already debounced by the caller).
 * @property instrument Optional single-chart filter; hides songs without that chart.
 * @property sort Sort field.
 * @property ascending Sort direction.
 */
data class SongListQuery(
    val query: String = "",
    val instrument: Instrument? = null,
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
)

/** Pure search → instrument filter → sort pipeline for the Songs list. */
object SongListPipeline {
    /**
     * Produce the on-screen song order.
     *
     * @param songs Full validated catalogue.
     * @param query Current list inputs.
     * @param sorter Sorter to use.
     * @return Filtered, sorted songs.
     */
    fun apply(songs: List<Song>, query: SongListQuery, sorter: SongCatalogSort = SongCatalogSort()): List<Song> {
        val matching = songs.filter { song ->
            (query.instrument == null || song.supports(query.instrument)) && SongSearch.matches(song, query.query)
        }
        return sorter.sorted(matching, query.sort, query.ascending)
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
            SongSortMode.Year -> { song -> song.year?.toString() ?: "—" }
            SongSortMode.Duration -> return emptyList()
        }
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
