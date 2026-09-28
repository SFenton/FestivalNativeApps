package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Song
import java.text.Normalizer

// region Search

/** Website-equivalent title/artist matching (Apple `SongSearch`). */
object SongSearch {
    private const val APOSTROPHES = "'‘’`´"
    private const val SEPARATORS = "()[]{}\"“”.,:;!?_-–—/\\"

    /**
     * Match raw text first, then normalized accents and word separators.
     *
     * @param song Catalogue row.
     * @param query User-entered text.
     * @return True if title or artist contains the query on either scale.
     */
    fun matches(song: Song, query: String): Boolean {
        val raw = query.trim().lowercase()
        if (raw.isEmpty() || song.title.lowercase().contains(raw) || song.artist.lowercase().contains(raw)) {
            return true
        }
        val normalizedQuery = normalized(query)
        if (normalizedQuery.isEmpty()) return true
        return normalized(song.title).contains(normalizedQuery) || normalized(song.artist).contains(normalizedQuery)
    }

    /**
     * Apply the PWA's NFKD, combining-mark, apostrophe and separator rules.
     *
     * @param value Title, artist or query.
     * @return Collapsed lowercase text with single-space word boundaries.
     */
    fun normalized(value: String): String {
        val decomposed = Normalizer.normalize(value, Normalizer.Form.NFKD).lowercase()
        val output = StringBuilder()
        for (char in decomposed) {
            when {
                char in '̀'..'ͯ' || char in APOSTROPHES -> Unit
                char.isWhitespace() || char in SEPARATORS -> {
                    if (output.isNotEmpty() && output.last() != ' ') output.append(' ')
                }
                else -> output.append(char)
            }
        }
        return output.toString().trim()
    }
}

// endregion
