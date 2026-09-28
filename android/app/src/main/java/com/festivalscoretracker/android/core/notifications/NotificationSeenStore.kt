package com.festivalscoretracker.android.core.notifications

import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.settings.BlobStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

// region Seen store

/**
 * Seen notification GUIDs per account (the native simplification of web
 * `notificationSeenState.ts`, as on iPhone/Windows): each account's list is
 * pruned to the IDs still in its latest feed, bounded, and corrupt data reads
 * as empty. Accounts are kept in least-recently-marked-first order for eviction.
 *
 * @property blob Backing value (`fst.notifications.seen.v1`).
 */
class NotificationSeenStore(private val blob: BlobStore) {
    private val mutex = Mutex()

    /**
     * Seen GUIDs for an account.
     *
     * @param accountId Account.
     * @return Seen set.
     */
    suspend fun seen(accountId: String): Set<String> = mutex.withLock { decode(blob.read())[accountId]?.toSet() ?: emptySet() }

    /**
     * Mark GUIDs seen (idempotent), keeping only IDs still in the current feed when given.
     *
     * @param accountId Account.
     * @param ids GUIDs to mark.
     * @param currentFeed IDs in the latest feed (prunes expired ones), or null to keep all.
     */
    suspend fun markSeen(accountId: String, ids: Collection<String>, currentFeed: Collection<String>? = null) = mutex.withLock {
        val all = decode(blob.read())
        val existing = all[accountId].orEmpty()
        val feed = currentFeed?.toHashSet()
        var merged = (existing + ids).filter { feed == null || it in feed }.distinct()
        if (merged.size > MAX_PER_ACCOUNT) merged = merged.takeLast(MAX_PER_ACCOUNT)
        if (merged == existing) return@withLock
        val next = LinkedHashMap<String, List<String>>()
        all.filterKeys { it != accountId }.forEach { (k, v) -> next[k] = v }
        next[accountId] = merged
        val kept = next.entries.toList().takeLast(MAX_ACCOUNTS)
        blob.write(encode(kept.associate { it.key to it.value }))
    }

    companion object {
        /** Most GUIDs kept per account. */
        const val MAX_PER_ACCOUNT = 400

        /** Most accounts kept. */
        const val MAX_ACCOUNTS = 20

        /** Largest accepted blob, in characters. */
        const val MAX_CHARS = 512 * 1024

        /**
         * Decode, dropping malformed entries.
         *
         * @param raw Stored JSON.
         * @return Account → GUIDs in stored order.
         */
        fun decode(raw: String?): LinkedHashMap<String, List<String>> {
            val result = LinkedHashMap<String, List<String>>()
            if (raw.isNullOrEmpty() || raw.length > MAX_CHARS) return result
            val root = runCatching { Json.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return result
            root.forEach { (account, value) ->
                val ids = (value as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content?.takeIf { id -> id.length in 1..64 } }
                if (ids != null && ProfileSearchText.isValidAccountId(account)) result[account] = ids
            }
            return result
        }

        /**
         * Encode in insertion order.
         *
         * @param state Account → GUIDs.
         * @return JSON.
         */
        fun encode(state: Map<String, List<String>>): String = buildJsonObject {
            state.forEach { (account, ids) -> put(account, JsonArray(ids.map(::JsonPrimitive))) }
        }.toString()
    }
}

// endregion
