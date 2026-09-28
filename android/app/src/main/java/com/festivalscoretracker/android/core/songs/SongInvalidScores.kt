package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.PlayerRankTier
import com.festivalscoretracker.android.core.profile.PlayerScore

// region Resolution

/** Why a chart's shown score is not the player's raw best (web `InvalidReason`). */
enum class InvalidScoreReason {
    /** The raw score is invalid; the next valid score is shown. */
    Fallback,

    /** The raw score is invalid and no valid score exists at this leeway; nothing is shown. */
    NoFallback,

    /** The raw invalid score is shown on purpose (Over CHOpt Threshold filter). */
    OverThreshold,
}

/**
 * The score Songs shows for one chart and why it differs from the raw score.
 *
 * @property detail Effective score, or null when an invalid score has no valid fallback.
 * @property reason Why it differs, or null for a valid raw score.
 */
data class InvalidScoreResolution(val detail: SongScoreDetail?, val reason: InvalidScoreReason?)

/**
 * Filter Invalid Scores (web `useScoreFilter` + `SongsPage` substitution). A score is
 * invalid when its precomputed `minLeeway` exceeds the user's leeway or, without it,
 * when it exceeds the chart's CHOpt maximum × (1 + leeway / 100). Invalid scores are
 * replaced by the best `validScores` variant valid at that leeway (filtered rank from
 * its `rankTiers`, filtered population from the catalogue's `populationTiers`), else
 * by the legacy `validScore` fields, else dropped — always with an explicit reason.
 */
object InvalidScorePolicy {
    /**
     * Highest valid score for a chart at a leeway.
     *
     * @param song Catalogue row.
     * @param chart Chart.
     * @param leeway Leeway percent.
     * @return Threshold, or null when the chart has no CHOpt maximum (cannot be judged).
     */
    fun threshold(song: Song?, chart: Instrument, leeway: Double): Double? = song?.maxScore(chart)?.let { it * (1 + leeway / 100) }

    /**
     * Whether a raw score is valid at a leeway.
     *
     * @param score Raw wire score.
     * @param song Catalogue row.
     * @param chart Chart.
     * @param leeway Leeway percent.
     * @return True when valid (or not judgeable).
     */
    fun isValid(score: PlayerScore, song: Song?, chart: Instrument, leeway: Double): Boolean {
        val min = score.minLeeway
        if (min != null) return min <= leeway
        val limit = threshold(song, chart, leeway) ?: return true
        return score.score <= limit
    }

    /**
     * The last rank changepoint at or below a leeway (web `findTier`).
     *
     * @param tiers Changepoints, ascending by leeway.
     * @param leeway Leeway percent.
     * @return Rank, or null.
     */
    fun rankAt(tiers: List<PlayerRankTier>?, leeway: Double): Int? {
        var result: Int? = null
        for (tier in tiers.orEmpty()) {
            if (tier.leeway <= leeway) result = tier.rank else break
        }
        return result
    }

    /**
     * Resolve one raw score.
     *
     * @param score Raw wire score.
     * @param raw Its unfiltered detail.
     * @param song Catalogue row (maximum and population tiers).
     * @param chart Chart.
     * @param leeway Leeway percent.
     * @param showOverThreshold Over CHOpt Threshold is on for this chart: keep the raw invalid score.
     * @return Effective detail and reason.
     */
    fun resolve(
        score: PlayerScore,
        raw: SongScoreDetail,
        song: Song?,
        chart: Instrument,
        leeway: Double,
        showOverThreshold: Boolean,
    ): InvalidScoreResolution {
        if (isValid(score, song, chart, leeway)) return InvalidScoreResolution(raw, null)
        if (showOverThreshold) return InvalidScoreResolution(raw, InvalidScoreReason.OverThreshold)
        val variants = score.validScores
        if (!variants.isNullOrEmpty()) {
            val fallback = variants.firstOrNull { it.minLeeway <= leeway }
                ?: return InvalidScoreResolution(null, InvalidScoreReason.NoFallback)
            val detail = raw.copy(
                score = fallback.score.toLong(),
                accuracy = fallback.accuracy ?: raw.accuracy,
                isFullCombo = fallback.isFullCombo ?: raw.isFullCombo,
                stars = fallback.stars ?: raw.stars,
                rank = rankAt(fallback.rankTiers, leeway) ?: raw.rank,
                totalEntries = song?.filteredPopulation(chart, leeway) ?: raw.totalEntries,
            )
            return InvalidScoreResolution(detail, InvalidScoreReason.Fallback)
        }
        val legacy = score.validScore ?: return InvalidScoreResolution(null, InvalidScoreReason.NoFallback)
        val detail = raw.copy(
            score = legacy.toLong(),
            rank = score.validRank ?: 0,
            accuracy = score.validAccuracy ?: raw.accuracy,
            isFullCombo = score.validIsFullCombo ?: raw.isFullCombo,
            stars = score.validStars ?: raw.stars,
            totalEntries = score.validTotalEntries ?: raw.totalEntries,
        )
        return InvalidScoreResolution(detail, InvalidScoreReason.Fallback)
    }
}

// endregion

// region Warning

/**
 * The row's invalid-score warning (web `InvalidScoreIcon`): a pulsing icon that
 * opens a "Filtered Score" alert with OK and Settings actions.
 *
 * @property reasons Charts whose shown score differs, in service order.
 * @property warning Gold warning (every described chart is Over CHOpt Threshold) instead of a red alert.
 * @property message Alert body.
 */
data class InvalidScoreWarning(val reasons: Map<Instrument, InvalidScoreReason>, val warning: Boolean, val message: String) {
    /** Alert title. */
    val title: String get() = TITLE

    companion object {
        /** Alert title (web `songs.invalidScoreTitle`). */
        const val TITLE = "Filtered Score"

        /** TalkBack label for the icon (web `songs.invalidScoreAriaLabel`). */
        const val LABEL = "Invalid score indicator"

        /** Settings toggle name used in the footer. */
        const val TOGGLE = "Filter Invalid Scores"

        /**
         * Build the warning for one row, or null when the icon does not apply
         * (web `SongRow`: filtered rows only warn about the filtered chart).
         *
         * @param songTitle Song title.
         * @param reasons Every invalid chart's reason (visible charts).
         * @param filterChart Single-chart filter.
         * @return Warning or null.
         */
        fun of(songTitle: String, reasons: Map<Instrument, InvalidScoreReason>, filterChart: Instrument?): InvalidScoreWarning? {
            val described = if (filterChart != null) reasons.filterKeys { it == filterChart } else reasons
            if (described.isEmpty()) return null
            val ordered = Instrument.entries.mapNotNull { chart -> described[chart]?.let { chart to it } }
            val warning = ordered.all { it.second == InvalidScoreReason.OverThreshold }
            return InvalidScoreWarning(ordered.toMap(), warning, message(songTitle, ordered, filterChart))
        }

        private fun message(song: String, ordered: List<Pair<Instrument, InvalidScoreReason>>, filterChart: Instrument?): String {
            val names = ordered.map { it.first.label }
            val list = when (names.size) {
                1 -> names[0]
                2 -> "${names[0]} and ${names[1]}"
                else -> names.dropLast(1).joinToString(", ") + ", and ${names.last()}"
            }
            if (ordered.all { it.second == InvalidScoreReason.OverThreshold }) {
                return "$song has a score on $list that exceeds the CHOpt maximum. This is the highest unfiltered invalid score."
            }
            val chips = filterChart == null
            val details = mutableListOf<String>()
            val fallbacks = ordered.filter { it.second == InvalidScoreReason.Fallback }
            if (fallbacks.isNotEmpty()) {
                details += when {
                    !chips -> "We are showing the next valid score here."
                    fallbacks.size == 1 -> "The ${fallbacks[0].first.label} chip reflects the next valid score."
                    else -> "The chips for these instruments reflect the next valid score."
                }
            }
            ordered.filter { it.second != InvalidScoreReason.Fallback }.forEach { (chart, reason) ->
                details += if (reason == InvalidScoreReason.OverThreshold) {
                    "The ${chart.label} score shown exceeds the CHOpt maximum."
                } else {
                    "Because there is no valid other score for ${chart.label}, the ${chart.label} icon chip is red here."
                }
            }
            val footer = if (ordered.size > 1) {
                "To see the absolute highest scores you've achieved, toggle off '$TOGGLE' in App Settings."
            } else {
                "To see the absolute highest score you've achieved, toggle off '$TOGGLE' in App Settings."
            }
            val hint = if (chips) {
                "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument."
            } else {
                "You can also temporarily filter to '${filterChart!!.label} Over CHOpt Threshold' in the Filter modal."
            }
            return "$song has an invalid, filtered-out score on $list. ${details.joinToString(" ")}\n\n$footer $hint"
        }
    }
}

// endregion
