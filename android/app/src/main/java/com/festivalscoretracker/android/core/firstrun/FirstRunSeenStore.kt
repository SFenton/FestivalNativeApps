package com.festivalscoretracker.android.core.firstrun

import com.festivalscoretracker.android.core.settings.BlobStore
import java.time.Instant
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

// region Seen store

/**
 * Bounded, validated first-run seen-state (web `loadSeenSlides`/`saveSeenSlides`,
 * Apple `FirstRunSeenStore`). An unparsable or oversized blob recovers to empty;
 * individually malformed records are dropped while the rest are kept.
 *
 * @property blob Backing value (`fst.firstRun.seen.v1`).
 */
class FirstRunSeenStore(private val blob: BlobStore) {
    private val mutex = Mutex()

    /**
     * Read validated seen-state.
     *
     * @return Slide ID → record.
     */
    suspend fun load(): Map<String, FirstRunSeenRecord> = mutex.withLock { decode(blob.read()) }

    /**
     * Replace the seen-state (bounded before writing).
     *
     * @param storage New state.
     */
    suspend fun save(storage: Map<String, FirstRunSeenRecord>) = mutex.withLock { blob.write(encode(bounded(storage))) }

    /**
     * Mark every displayed slide seen at once.
     *
     * @param slides Slides that were shown.
     * @param now Timestamp.
     */
    suspend fun markSeen(slides: List<FirstRunSlide>, now: Instant = Instant.now()) {
        if (slides.isEmpty()) return
        mutex.withLock {
            val storage = decode(blob.read()).toMutableMap()
            slides.forEach { storage[it.id] = FirstRunSlideEvaluator.seenRecord(it, now) }
            blob.write(encode(bounded(storage)))
        }
    }

    /**
     * Forget one page's slides (before a Settings replay, web `resetPage`).
     *
     * @param slideIds The page's slide IDs.
     */
    suspend fun resetPage(slideIds: List<String>) {
        if (slideIds.isEmpty()) return
        mutex.withLock {
            val storage = decode(blob.read()) - slideIds.toSet()
            blob.write(encode(storage))
        }
    }

    /** Forget everything (web `resetAll`; no UI, as on the web). */
    suspend fun resetAll() = mutex.withLock { blob.write(null) }

    companion object {
        /** Most records kept; the oldest `seenAt` are evicted first (well above the ~42 real slides). */
        const val MAX_RECORDS = 500

        /** Largest accepted blob, in UTF-16 characters. */
        const val MAX_CHARS = 256 * 1024

        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Decode, dropping malformed records; any top-level failure is empty.
         *
         * @param raw Stored JSON.
         * @return Validated state.
         */
        fun decode(raw: String?): Map<String, FirstRunSeenRecord> {
            if (raw.isNullOrEmpty() || raw.length > MAX_CHARS) return emptyMap()
            val root = runCatching { JSON.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return emptyMap()
            return root.mapNotNull { (id, element) ->
                runCatching {
                    val fields = element.jsonObject
                    val record = FirstRunSeenRecord(
                        version = fields.getValue("version").jsonPrimitive.int,
                        hash = fields.getValue("hash").jsonPrimitive.also { require(it.isString) }.content,
                        seenAt = Instant.parse(fields.getValue("seenAt").jsonPrimitive.content),
                    )
                    (id to record).takeIf { id.length in 1..200 && record.isValid }
                }.getOrNull()
            }.toMap()
        }

        /**
         * Encode with sorted keys for stable storage.
         *
         * @param storage State.
         * @return JSON.
         */
        fun encode(storage: Map<String, FirstRunSeenRecord>): String = buildJsonObject {
            storage.toSortedMap().forEach { (id, record) ->
                put(
                    id,
                    buildJsonObject {
                        put("version", record.version)
                        put("hash", record.hash)
                        put("seenAt", JsonPrimitive(record.seenAt.toString()))
                    },
                )
            }
        }.toString()

        /**
         * Cap the record count, keeping the most recently seen.
         *
         * @param storage Candidate state.
         * @return At most [MAX_RECORDS] records.
         */
        private fun bounded(storage: Map<String, FirstRunSeenRecord>): Map<String, FirstRunSeenRecord> =
            if (storage.size <= MAX_RECORDS) storage
            else storage.entries.sortedByDescending { it.value.seenAt }.take(MAX_RECORDS).associate { it.key to it.value }
    }
}

// endregion
