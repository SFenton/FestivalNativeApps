package com.festivalscoretracker.android.core.firstrun

import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy

// region Demo songs

/**
 * Chooses the real catalogue songs first-run demos display (issue #26/#57), ported from the
 * web's `useDemoSongs` (Epic Games songs with artwork) and `useItemShopDemoSongs` (current Shop
 * songs first, then catalogue songs with artwork), like Apple `FirstRunDemoSongs`.
 *
 * Demos never invent song titles: until the catalogue answers (or when it can't), [forDemo]
 * returns `null` slots, which the views draw as muted placeholder rows.
 */
object FirstRunDemoSongs {
    /** Artist marker the web uses to pick neutral, first-party demo songs. */
    const val PREFERRED_ARTIST_MARKER = "Epic Games"

    /**
     * Pick up to [count] distinct catalogue songs with artwork.
     *
     * Order: songs whose IDs appear in [preferring] (in that order), then songs whose artist
     * contains [PREFERRED_ARTIST_MARKER], then any other song with artwork. Within each group
     * catalogue order is kept (instead of the web's shuffle), so captures and tests are stable.
     *
     * @param catalog Songs from the observed `/api/songs` response.
     * @param count Maximum songs; non-positive returns none.
     * @param preferring Song IDs to show first, e.g. current Item Shop songs.
     * @return At most [count] songs, each with a non-empty `albumArt`.
     */
    fun pick(catalog: List<Song>, count: Int, preferring: List<String> = emptyList()): List<Song> {
        if (count <= 0) return emptyList()
        val withArt = catalog.filter { !it.albumArt.isNullOrEmpty() }
        val byId = withArt.associateBy { it.songId }
        val result = LinkedHashMap<String, Song>()
        fun add(song: Song) {
            if (result.size < count) result.putIfAbsent(song.songId, song)
        }
        preferring.forEach { id -> byId[id]?.let(::add) }
        withArt.filter { PREFERRED_ARTIST_MARKER in it.artist }.forEach(::add)
        withArt.forEach(::add)
        return result.values.toList()
    }

    /**
     * The songs one demo shows: catalogue picks, or [count] `null` placeholder slots while the
     * catalogue is loading, unavailable or has no song with artwork.
     *
     * @param catalog Loaded catalogue, or null while loading/unavailable.
     * @param count Rows the demo shows.
     * @param preferring Song IDs to show first.
     * @return Non-empty picks, or [count] nulls.
     */
    fun forDemo(catalog: List<Song>?, count: Int, preferring: List<String> = emptyList()): List<Song?> =
        pick(catalog.orEmpty(), count, preferring).ifEmpty { List(count.coerceAtLeast(0)) { null } }

    /** Most songs a rotating demo walks through (issue #58). */
    const val ROTATION_POOL = 40

    /** Placeholder rows a rotating demo draws while it has no songs (its largest visible count). */
    const val ROTATION_PLACEHOLDERS = 4

    /**
     * The pool a rotating demo walks through (issue #58): [pick]ed catalogue songs in the same
     * order as the still demos, or [ROTATION_PLACEHOLDERS] placeholders (which never rotate)
     * while the catalogue is loading, unavailable or has no song with artwork.
     *
     * @param catalog Loaded catalogue, or null.
     * @param artworkUrl Resolves a raw `albumArt` to a loadable URL.
     * @return Real songs, or placeholders.
     */
    fun rotationPool(catalog: List<Song>?, artworkUrl: (String?) -> String?): List<FirstRunDemoSong> =
        pick(catalog.orEmpty(), ROTATION_POOL)
            .map { FirstRunDemoSong(it.songId, it.title, it.artist, it.year?.takeIf { year -> year != 0 }, artworkUrl(it.albumArt)) }
            .ifEmpty { FirstRunDemoSong.placeholders(ROTATION_PLACEHOLDERS) }

    /**
     * Shop song IDs Shop demos may prefer: only when the already-loaded feed, the catalogue and
     * the app observed one publication (never a cross-publication Shop decoration). Demos never
     * fetch the Shop themselves.
     *
     * @param shop Loaded Shop feed, or null.
     * @param catalogPublication Publication the catalogue was observed in.
     * @param current Latest publication the app observed.
     * @return Shop song IDs in feed order, or empty.
     */
    fun shopPreference(shop: ShopPayload?, catalogPublication: Int?, current: Int?): List<String> =
        if (shop != null && SongRelatedPublicationPolicy.matches(catalogPublication, shop.observedPublicationId, current)) {
            shop.shop.songs.map { it.songId }
        } else {
            emptyList()
        }
}

// endregion
