package com.festivalscoretracker.android.data

import com.google.gson.JsonParser
import java.io.Reader

// region Models and decoding

/** A preview entry; identifiers are fixture-local and must not be used for public API navigation. */
data class Song(val id: String, val title: String, val artist: String, val difficulty: Int)

/** The immutable publication and its songs. */
data class SongCatalog(val publication: String, val songs: List<Song>)

/** Decodes the bundled preview format, rejecting missing fields and out-of-range difficulty. */
object SongCatalogDecoder {
    /** Returns a validated catalog from [source], or throws for malformed fixture data. */
    fun decode(source: Reader): SongCatalog {
        val root = JsonParser.parseReader(source).asJsonObject
        val publication = root.get("publication")
            ?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }
            ?.asString?.takeIf { it.isNotBlank() }
            ?: error("Missing publication")
        val songs = root.getAsJsonArray("songs") ?: error("Missing songs")
        val entries = songs.map { element ->
            val item = element.asJsonObject
            fun required(key: String): String =
                item.get(key)
                    ?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }
                    ?.asString?.takeIf { it.isNotBlank() } ?: error("Missing $key")
            val difficulty = item.get("difficulty")
                ?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isNumber }
                ?.asString?.toIntOrNull() ?: error("Missing or noninteger difficulty")
            require(difficulty in 1..7) { "Difficulty must be between 1 and 7" }
            Song(required("id"), required("title"), required("artist"), difficulty)
        }
        require(entries.map(Song::id).distinct().size == entries.size) { "Duplicate song ID" }
        return SongCatalog(publication, entries)
    }
}

// endregion

// region Data boundary

/** Injectable source of fixture or, after wire verification, public catalog data. */
fun interface CatalogSource {
    /** Reads a complete catalog; failures are propagated to the caller. */
    fun load(): SongCatalog
}

/** Monotonic clock in milliseconds, injectable for deterministic cache tests. */
fun interface MonotonicClock {
    /** Returns elapsed milliseconds since an arbitrary origin. */
    fun nowMillis(): Long
}

/** Session cache that pins a catalog until expiry or explicit invalidation. */
class SongCatalogRepository(
    private val source: CatalogSource,
    private val clock: MonotonicClock,
    private val ttlMillis: Long = 60_000L,
) {
    init {
        require(ttlMillis > 0) { "TTL must be positive" }
    }

    private var cached: Pair<Long, SongCatalog>? = null

    /** Returns a cached publication while fresh, otherwise loads atomically from [source]. */
    @Synchronized
    fun get(): SongCatalog {
        val now = clock.nowMillis()
        cached?.let { (loadedAt, catalog) ->
            if (now - loadedAt in 0 until ttlMillis) return catalog
        }
        return source.load().also { cached = now to it }
    }

    /** Removes the pinned publication so the next [get] reloads it. */
    @Synchronized
    fun invalidate() {
        cached = null
    }
}

// endregion
