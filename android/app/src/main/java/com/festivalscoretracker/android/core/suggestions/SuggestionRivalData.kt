package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.model.Instrument
import kotlin.math.abs
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// region Wire: GET /api/player/{accountId}/rivals/all

/**
 * One compact song sample shared between the player and a rival (web
 * `RivalsAllSample`); single-letter wire keys keep the precomputed payload small.
 *
 * @property songIndex Index into [RivalsAllResponse.songs].
 * @property instrument Instrument key such as `Solo_Guitar` (unknown keys are skipped later).
 * @property userRank Player's rank.
 * @property rivalRank Rival's rank.
 * @property userScore Player's score, when known.
 * @property rivalScore Rival's score, when known.
 */
@Serializable
data class RivalsAllSample(
    @SerialName("s") val songIndex: Int,
    @SerialName("i") val instrument: String,
    @SerialName("ur") val userRank: Int,
    @SerialName("rr") val rivalRank: Int,
    @SerialName("us") val userScore: Int? = null,
    @SerialName("rs") val rivalScore: Int? = null,
)

/**
 * A rival in one combo. The precomputed payload carries `direction`/`samples`;
 * the service's live fallback omits both and adds `avgSignedDelta`.
 */
@Serializable
data class RivalsAllEntry(
    val accountId: String,
    val displayName: String? = null,
    val direction: String? = null,
    val sharedSongCount: Int,
    val aheadCount: Int,
    val behindCount: Int,
    val rivalScore: Double,
    val avgSignedDelta: Double? = null,
    val samples: List<RivalsAllSample> = emptyList(),
)

/**
 * One combo's rivals ahead of and behind the player.
 *
 * @property combo Hex combo identifier such as `01`.
 */
@Serializable
data class RivalsAllCombo(
    val combo: String,
    val above: List<RivalsAllEntry> = emptyList(),
    val below: List<RivalsAllEntry> = emptyList(),
)

/**
 * Every combo's rivals in one read, samples indexed into a shared song table.
 * A pure read (`service-safety.md`); HTTP 404 "No rivals found." is normalized to [empty].
 */
@Serializable
data class RivalsAllResponse(
    val accountId: String,
    val songs: List<String> = emptyList(),
    val combos: List<RivalsAllCombo>,
) {
    /**
     * Resolve a sample's song ID without trapping on a malformed index.
     *
     * @param sample Sample from this response.
     * @return Song ID, or null when out of range.
     */
    fun songId(sample: RivalsAllSample): String? = songs.getOrNull(sample.songIndex)

    companion object {
        /**
         * An empty response (used for 404).
         *
         * @param accountId Requested player.
         * @return Response with no combos.
         */
        fun empty(accountId: String) = RivalsAllResponse(accountId, emptyList(), emptyList())
    }
}

// endregion

// region Rival index

/**
 * Summary of one per-song rival (web `RivalInfo`).
 *
 * @property direction `above` or `below`.
 */
data class RivalInfo(
    val accountId: String,
    val displayName: String,
    val direction: String,
    val sharedSongCount: Int,
    val aheadCount: Int,
    val behindCount: Int,
)

/**
 * One per-song, per-chart comparison with a rival (web `RivalSongMatch`).
 *
 * @property rankDelta `userRank - rivalRank`; negative means the rival ranks ahead.
 */
data class RivalSongMatch(
    val rival: RivalInfo,
    val songId: String,
    val instrument: Instrument,
    val userRank: Int,
    val rivalRank: Int,
    val rankDelta: Int,
    val userScore: Int?,
    val rivalScore: Int?,
)

/**
 * Indexed lookups feeding the `song_rival_*` families, ported from the web
 * `buildRivalDataIndexFromRivalsAll` via Apple `RivalDataIndex`. `lb_rival_*` is
 * not represented: the web never populates it.
 *
 * @property songRivals Kept rivals (`limit` per direction, above first).
 * @property byRival Every match per rival account, merged across combos.
 * @property closestRivalBySong Smallest-|delta| match per song/chart ([closestKey]).
 */
data class RivalDataIndex(
    val songRivals: List<RivalInfo>,
    val byRival: Map<String, List<RivalSongMatch>>,
    val closestRivalBySong: Map<String, RivalSongMatch>,
) {
    companion object {
        /** An index with no rivals. */
        val EMPTY = RivalDataIndex(emptyList(), emptyMap(), emptyMap())

        /**
         * Lookup key for one song/chart pairing (web `${songId}:${instrument}`).
         *
         * @param songId Song ID.
         * @param instrument Chart.
         * @return Key.
         */
        fun closestKey(songId: String, instrument: Instrument): String = "$songId:${instrument.wireId}"

        /**
         * Build from one `/rivals/all` read: dedup rivals by account (first
         * occurrence wins, combos in response order), keep the first [limit] per
         * direction, then resolve every sample of those rivals.
         *
         * @param response `/rivals/all` payload.
         * @param combo Restrict to one combo token, or null for every combo.
         * @param limit Rivals kept per direction (web default 5).
         * @return Index for [SuggestionGenerator.setRivalData].
         */
        fun build(response: RivalsAllResponse, combo: String? = null, limit: Int = 5): RivalDataIndex {
            val comboData = if (combo == null) response.combos else response.combos.filter { it.combo == combo }
            val aboveInfo = LinkedHashMap<String, RivalInfo>()
            val belowInfo = LinkedHashMap<String, RivalInfo>()
            for (entryCombo in comboData) {
                for (entry in entryCombo.above) {
                    if (entry.accountId !in aboveInfo) aboveInfo[entry.accountId] = info(entry, "above")
                }
                for (entry in entryCombo.below) {
                    if (entry.accountId !in belowInfo) belowInfo[entry.accountId] = info(entry, "below")
                }
            }
            val songRivals = aboveInfo.values.take(limit) + belowInfo.values.take(limit)
            val rivalSet = songRivals.mapTo(HashSet()) { it.accountId }

            val byRival = LinkedHashMap<String, MutableList<RivalSongMatch>>()
            val closest = HashMap<String, RivalSongMatch>()
            for (entryCombo in comboData) {
                for (group in listOf(entryCombo.above, entryCombo.below)) {
                    for (entry in group) {
                        if (entry.accountId !in rivalSet) continue
                        val rivalInfo = aboveInfo[entry.accountId] ?: belowInfo[entry.accountId] ?: continue
                        val matches = byRival.getOrPut(entry.accountId) { mutableListOf() }
                        for (sample in entry.samples) {
                            val songId = response.songId(sample) ?: continue
                            val instrument = Instrument.fromWireId(sample.instrument) ?: continue
                            val match = RivalSongMatch(
                                rivalInfo, songId, instrument, sample.userRank, sample.rivalRank,
                                sample.userRank - sample.rivalRank, sample.userScore, sample.rivalScore,
                            )
                            matches += match
                            val key = closestKey(songId, instrument)
                            val existing = closest[key]
                            if (existing == null || abs(match.rankDelta) < abs(existing.rankDelta)) closest[key] = match
                        }
                    }
                }
            }
            return RivalDataIndex(songRivals, byRival, closest)
        }

        private fun info(entry: RivalsAllEntry, direction: String) = RivalInfo(
            entry.accountId, entry.displayName ?: "Unknown", direction,
            entry.sharedSongCount, entry.aheadCount, entry.behindCount,
        )
    }
}

// endregion
