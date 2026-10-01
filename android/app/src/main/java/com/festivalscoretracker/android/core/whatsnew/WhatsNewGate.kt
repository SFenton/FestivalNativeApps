package com.festivalscoretracker.android.core.whatsnew

import com.festivalscoretracker.android.core.settings.BlobStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

// region Seen store

/**
 * What the user last dismissed: the web's `fst:changelog` `{ version, hash }` record.
 *
 * @property version App version shown in the dismissed sheet's title.
 * @property hash Changelog content hash at dismissal.
 */
data class ChangelogSeenRecord(val version: String, val hash: String)

/**
 * Persisted "What's New" dismissal (web `localStorage['fst:changelog']` gate in `App.tsx`,
 * Apple/Windows `ChangelogSeenStore`): the sheet shows when nothing valid is stored or the
 * stored hash differs from the current changelog hash.
 *
 * @property blob Backing value (`fst.changelog.seen.v1`).
 */
class ChangelogSeenStore(private val blob: BlobStore) {
    private val mutex = Mutex()

    /**
     * The last dismissal, or null when absent, oversized or corrupt (the web treats a parse
     * failure as "show again").
     *
     * @return Validated record or null.
     */
    suspend fun load(): ChangelogSeenRecord? = mutex.withLock { decode(blob.read()) }

    /**
     * Whether the sheet is owed for a changelog hash.
     *
     * @param hash Current changelog hash.
     * @return True when the changelog has content and was never dismissed or was dismissed for different content.
     */
    suspend fun shouldShow(hash: String = Changelog.currentHash): Boolean = hash != Changelog.emptyHash && load()?.hash != hash

    /**
     * Persist a dismissal.
     *
     * @param version App version shown in the sheet.
     * @param hash Changelog hash that was shown.
     */
    suspend fun markSeen(version: String, hash: String = Changelog.currentHash) = mutex.withLock {
        blob.write(encode(ChangelogSeenRecord(version.take(MAX_VERSION), hash)))
    }

    /** Forget the dismissal so the sheet shows again. */
    suspend fun reset() = mutex.withLock { blob.write(null) }

    companion object {
        /** Largest accepted stored blob, in characters. */
        const val MAX_CHARS = 1024

        /** Longest accepted hash. */
        const val MAX_HASH = 32

        /** Longest accepted version. */
        const val MAX_VERSION = 64

        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Decode and validate a stored record.
         *
         * @param raw Stored JSON.
         * @return Record, or null when absent or invalid.
         */
        fun decode(raw: String?): ChangelogSeenRecord? {
            if (raw.isNullOrEmpty() || raw.length > MAX_CHARS) return null
            return runCatching {
                val root = JSON.parseToJsonElement(raw) as JsonObject
                val version = root.getValue("version").jsonPrimitive.also { require(it.isString) }.content
                val hash = root.getValue("hash").jsonPrimitive.also { require(it.isString) }.content
                ChangelogSeenRecord(version, hash).takeIf { hash.isNotEmpty() && hash.length <= MAX_HASH && version.length <= MAX_VERSION }
            }.getOrNull()
        }

        /**
         * Encode a record.
         *
         * @param record Record.
         * @return JSON.
         */
        fun encode(record: ChangelogSeenRecord): String = buildJsonObject {
            put("version", record.version)
            put("hash", record.hash)
        }.toString()
    }
}

// endregion

// region Gate

/** How the launch "What's New" sheet behaves (`FST_DEBUG_WHATS_NEW`, sibling of `FST_DEBUG_FIRST_RUN`). */
enum class WhatsNewMode {
    /** Never auto-present (debug default, so screenshots and journeys never meet it). Settings replay still works. */
    Off,

    /** Real gate: present when the stored changelog hash differs (`on`, release). */
    Normal,

    /** Forget the stored dismissal once at launch, then behave as [Normal] (`fresh`). */
    Fresh,

    /** Present on every launch regardless of the stored dismissal (`force`). */
    Force,
    ;

    companion object {
        /**
         * Resolve `FST_DEBUG_WHATS_NEW` (`off|on|fresh|force`); unset is [Off] in debug builds.
         *
         * @param raw Extra value, or null.
         * @param debugBuild Whether this is a debug build (release always uses [Normal]).
         * @return Mode.
         */
        fun parse(raw: String?, debugBuild: Boolean): WhatsNewMode {
            if (!debugBuild) return Normal
            return when (raw?.trim()?.lowercase()) {
                "on" -> Normal
                "fresh" -> Fresh
                "force" -> Force
                else -> Off
            }
        }
    }
}

/**
 * Pure launch gate (web `App.tsx`: `hasNewChangelog && !changelogDismissed && !activeCarouselKey`).
 */
object WhatsNewGate {
    /** Slot key claimed in the first-run center while the sheet is up, so no carousel presents over it. */
    const val SLOT_KEY = "whats-new"

    /** Delay before the launch check, so the launch page's first-run carousel claims the slot first (web order). */
    const val SETTLE_MS = 700L

    /**
     * Whether this launch owes the user the sheet.
     *
     * @param mode Resolved mode.
     * @param hasUnseenChangelog [ChangelogSeenStore.shouldShow] after any [WhatsNewMode.Fresh] reset.
     * @return True when the sheet should present once the slot is free.
     */
    fun isPending(mode: WhatsNewMode, hasUnseenChangelog: Boolean): Boolean = when (mode) {
        WhatsNewMode.Off -> false
        WhatsNewMode.Force -> true
        WhatsNewMode.Normal, WhatsNewMode.Fresh -> hasUnseenChangelog
    }

    /**
     * Sheet title, e.g. "What's New · 0.2.0" (web `What's New · 0.1.133`).
     *
     * @param version App version; omitted when blank.
     * @return Title.
     */
    fun title(version: String): String = if (version.isBlank()) "What's New" else "What's New · $version"
}

// endregion
