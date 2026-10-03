package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import kotlin.math.abs

// region Rival detail from rivals/all

/**
 * Rebuilds a rival detail from `GET /api/player/{id}/rivals/all` when the detail
 * endpoint answers 503 during a public-read freeze (issue #95). The service never
 * precomputes detail, so every uncached detail is refused while it publishes, but
 * `rivals/all` is precomputed and stays readable, and its per-rival samples are the
 * same stored `rival_song_samples` rows (≤ 200 per chart) the detail endpoint reads:
 * ranks, scores and categories match. Titles come from the catalogue.
 */
object RivalsAllDetail {
    /** `source` echoed by a rebuilt detail. */
    const val SOURCE = "rivals-all"

    /**
     * The charts a detail scope covers when it can be rebuilt: a chart wire ID or hex
     * combo. The Pro Drums family is excluded because its samples do not say which
     * chart each player used.
     *
     * @param scope Detail scope token.
     * @return Charts, or null when the scope cannot be rebuilt.
     */
    fun instrumentsFor(scope: String): List<Instrument>? =
        if (scope == RivalCombo.PRO_DRUMS_TOKEN) null else Instrument.fromWireId(scope)?.let(::listOf) ?: RivalCombo.instrumentsFor(scope)

    /**
     * Build the detail for [rivalId] limited to [instruments]: the rival's samples
     * across every combo entry, deduplicated per song and chart, invalid samples
     * dropped, `rankDelta = rivalRank − userRank` (positive: the player leads), sorted
     * closest-first like the service's `sort=closest`.
     *
     * @param all Rivals for every combo.
     * @param rivalId Rival account.
     * @param instruments Charts to include.
     * @param combo Scope echoed as [RivalDetailResponse.combo].
     * @return Detail, or null when the rival has no usable sample on those charts.
     */
    fun build(all: RivalsAllResponse, rivalId: String, instruments: Collection<Instrument>, combo: String): RivalDetailResponse? {
        var name: String? = null
        val seen = HashSet<Pair<String, Instrument>>()
        val songs = ArrayList<RivalSongComparison>()
        for (entry in all.combos.asSequence().flatMap { it.above.asSequence() + it.below.asSequence() }) {
            if (!entry.accountId.equals(rivalId, ignoreCase = true) || !ProfileSearchText.isValidAccountId(entry.accountId)) continue
            if (name == null) name = entry.displayName?.trim()?.takeIf { it.isNotEmpty() }
            for (sample in entry.samples) {
                val instrument = Instrument.fromWireId(sample.instrument) ?: continue
                val songId = all.songId(sample) ?: continue
                if (instrument !in instruments || sample.userRank < 0 || sample.rivalRank < 0) continue
                if (songId.isBlank() || songId.length > 200 || !seen.add(songId to instrument)) continue
                songs += RivalSongComparison(
                    songId = songId,
                    instrument = instrument.wireId,
                    userRank = sample.userRank,
                    rivalRank = sample.rivalRank,
                    rankDelta = sample.rivalRank - sample.userRank,
                    userScore = sample.userScore?.toLong(),
                    rivalScore = sample.rivalScore?.toLong(),
                )
            }
        }
        if (songs.isEmpty()) return null
        val sorted = songs.sortedBy { abs(it.rankDelta.toLong()) }
        return RivalDetailResponse(RivalIdentity(rivalId, name), combo = combo, source = SOURCE, totalSongs = sorted.size, sort = "closest", songs = sorted)
    }
}

// endregion
