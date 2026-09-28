package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandText
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import kotlinx.serialization.Serializable

// region Metrics

/**
 * Sort metric for `/api/rankings/{instrument}` (web `RankingMetric`,
 * `packages/core/src/api/serverTypes.ts`). Declaration order is the web picker
 * order: Total Score (the default) first, then the experimental metrics.
 *
 * @property wireId `rankBy` query value.
 * @property label Picker label matching the web client.
 */
enum class RankingMetric(val wireId: String, val label: String) {
    TotalScore("totalscore", "Total Score"),
    Adjusted("adjusted", "Adjusted"),
    Weighted("weighted", "Weighted"),
    FcRate("fcrate", "FC Rate"),
    MaxScore("maxscore", "Max Score");

    /** Adjusted and weighted rank by a raw percentile shown as "Top N%". */
    val isPercentile: Boolean get() = this == Adjusted || this == Weighted

    /** Bands have no Max Score board; narrow like the web's `coerceBandRankingMetric`. */
    val bandMetric: BandRankingMetric get() = BandRankingMetric.fromWireId(wireId) ?: BandRankingMetric.DEFAULT

    companion object {
        /** The web default (`leaderboardSettings.ts`). */
        val DEFAULT = TotalScore

        /**
         * Parse a stored or routed metric.
         *
         * @param wireId Candidate `rankBy` value.
         * @return The metric, or null when unknown.
         */
        fun fromWireId(wireId: String?): RankingMetric? = entries.firstOrNull { it.wireId == wireId }
    }
}

/** Widened metric used for shared rankings formatting. */
val BandRankingMetric.asRankingMetric: RankingMetric get() = RankingMetric.fromWireId(wireId) ?: RankingMetric.TotalScore

// endregion

// region Account rankings

/**
 * One row of `/api/rankings/{instrument}` (web `AccountRankingEntry`). Every field
 * has a default: production serves anonymous rows with an empty `accountId` and
 * no `displayName` (Lead total-score rank 15, 2026-09-28), which must never reject
 * the page.
 */
@Serializable
data class AccountRankingEntry(
    val accountId: String = "",
    val displayName: String? = null,
    val songsPlayed: Int = 0,
    val totalChartedSongs: Int = 0,
    val coverage: Double = 0.0,
    val rawSkillRating: Double = 0.0,
    val adjustedSkillRating: Double = 0.0,
    val adjustedSkillRank: Int = 0,
    val weightedRating: Double = 0.0,
    val weightedRank: Int = 0,
    val fcRate: Double = 0.0,
    val fcRateRank: Int = 0,
    val totalScore: Long = 0,
    val totalScoreRank: Int = 0,
    val maxScorePercent: Double = 0.0,
    val maxScorePercentRank: Int = 0,
    val avgAccuracy: Double = 0.0,
    val fullComboCount: Int = 0,
    val avgStars: Double = 0.0,
    val bestRank: Int = 0,
    val avgRank: Double = 0.0,
    val rawMaxScorePercent: Double? = null,
    val rawWeightedRating: Double? = null,
) {
    /** Stable list key; anonymous rows fall back to their ranks instead of colliding on `""`. */
    val key: String get() = if (accountId.isEmpty()) "anonymous-$totalScoreRank-$adjustedSkillRank-$weightedRank" else accountId

    /** Whether the row has a public profile to open (a well-formed account ID). */
    val hasProfile: Boolean get() = ProfileSearchText.isValidAccountId(accountId)

    /** Display name, "Unknown User" when blank. */
    val name: String get() = displayName?.takeIf { it.isNotBlank() } ?: UNKNOWN_USER

    /**
     * Rank column for a metric (web `getRankForMetric`).
     *
     * @param metric Selected metric.
     * @return One-based rank.
     */
    fun rank(metric: RankingMetric): Int = when (metric) {
        RankingMetric.Adjusted -> adjustedSkillRank
        RankingMetric.Weighted -> weightedRank
        RankingMetric.FcRate -> fcRateRank
        RankingMetric.TotalScore -> totalScoreRank
        RankingMetric.MaxScore -> maxScorePercentRank
    }

    /**
     * Raw value behind the displayed rating (web `getRatingForMetric`).
     *
     * @param metric Selected metric.
     * @return Percentile fraction, score total or fraction.
     */
    fun ratingValue(metric: RankingMetric): Double = when (metric) {
        RankingMetric.Adjusted -> rawSkillRating
        RankingMetric.Weighted -> rawWeightedRating ?: weightedRating
        RankingMetric.FcRate -> if (totalChartedSongs > 0) fullComboCount.toDouble() / totalChartedSongs else 0.0
        RankingMetric.TotalScore -> totalScore.toDouble()
        RankingMetric.MaxScore -> maxScorePercent
    }

    /**
     * Bayesian value shown beside a percentile (web `getBayesianRatingForMetric`).
     *
     * @param metric Selected metric.
     * @return The value for Adjusted/Weighted, else null.
     */
    fun bayesianValue(metric: RankingMetric): Double? = when (metric) {
        RankingMetric.Adjusted -> adjustedSkillRating
        RankingMetric.Weighted -> weightedRating
        else -> null
    }

    /**
     * Songs column; full combos under FC Rate (web `getSongsLabel`).
     *
     * @param metric Selected metric.
     * @return "X / Y".
     */
    fun songsLabel(metric: RankingMetric): String =
        "${if (metric == RankingMetric.FcRate) fullComboCount else songsPlayed} / $totalChartedSongs"

    companion object {
        /** Label for rows without a display name. */
        const val UNKNOWN_USER = "Unknown User"
    }
}

/** `/api/rankings/{instrument}` page. */
@Serializable
data class RankingsResponse(
    val instrument: String = "",
    val rankBy: String = "",
    val page: Int = 0,
    val pageSize: Int = 0,
    val totalAccounts: Int = 0,
    val entries: List<AccountRankingEntry> = emptyList(),
) {
    /** Pages of [pageSize] rows, at least one. */
    val pageCount: Int get() = RankingPaging.pageCount(totalAccounts, pageSize)

    /**
     * Reject a response for another chart or with impossible counts.
     *
     * @param instrument Requested chart.
     * @throws FestivalApiException.InvalidLeaderboard when corrupt.
     */
    fun validate(instrument: Instrument) {
        if (this.instrument != instrument.wireId || page < 1 || pageSize < 1 || totalAccounts < 0 || entries.size > pageSize) {
            throw FestivalApiException.InvalidLeaderboard()
        }
    }
}

/**
 * One account's own row from `/api/rankings/{instrument}/{accountId}`: the list row
 * fields plus `instrument` and `totalRankedAccounts`.
 *
 * @property entry Shared row fields.
 * @property instrument Service echo; live-probed blank in production (2026-09-28), so blank is accepted.
 * @property totalRankedAccounts Board population.
 */
data class PlayerInstrumentRanking(val entry: AccountRankingEntry, val instrument: String, val totalRankedAccounts: Int) {
    /**
     * Reject a response for another account or chart.
     *
     * @param instrument Requested chart.
     * @param accountId Requested account.
     * @throws FestivalApiException.InvalidLeaderboard on mismatch.
     */
    fun validate(instrument: Instrument, accountId: String) {
        val valid = (this.instrument.isEmpty() || this.instrument == instrument.wireId) &&
            entry.accountId.equals(accountId, ignoreCase = true) && totalRankedAccounts >= 0
        if (!valid) throw FestivalApiException.InvalidLeaderboard()
    }
}

/** Envelope-only fields of [PlayerInstrumentRanking], decoded alongside the row. */
@Serializable
data class PlayerInstrumentRankingEnvelope(val instrument: String = "", val totalRankedAccounts: Int = 0)

/** The selected player's own-row read: a row, or an honest 404 "not ranked yet". */
sealed interface PlayerRankingResult {
    /**
     * Ranked.
     *
     * @property ranking Own row.
     */
    data class Ranked(val ranking: PlayerInstrumentRanking) : PlayerRankingResult

    /** HTTP 404: no rank on this board yet. */
    data object Unranked : PlayerRankingResult
}

// endregion

// region Band rankings

/** One row of `/api/rankings/bands/{bandType}` (web `BandRankingEntry`). */
@Serializable
data class BandRankingEntry(
    val bandId: String = "",
    val teamKey: String = "",
    val teamMembers: List<BandMember> = emptyList(),
    val songsPlayed: Int = 0,
    val totalChartedSongs: Int = 0,
    val coverage: Double = 0.0,
    val rawSkillRating: Double = 0.0,
    val adjustedSkillRating: Double = 0.0,
    val adjustedSkillRank: Int = 0,
    val weightedRating: Double = 0.0,
    val weightedRank: Int = 0,
    val fcRate: Double = 0.0,
    val fcRateRank: Int = 0,
    val totalScore: Long = 0,
    val totalScoreRank: Int = 0,
    val avgAccuracy: Double = 0.0,
    val fullComboCount: Int = 0,
    val avgStars: Double = 0.0,
    val bestRank: Int = 0,
    val avgRank: Double = 0.0,
    val rawWeightedRating: Double? = null,
) {
    /** Stable list key. */
    val key: String get() = teamKey.ifEmpty { "band-$totalScoreRank-$adjustedSkillRank-$weightedRank" }

    /**
     * Whether Band Detail can be opened: it resolves through the safe
     * `?teamKey=` rankings read, so both identifiers must be present and path-safe.
     */
    val hasDetail: Boolean get() = BandText.isValidMemberId(bandId) && BandText.isValidTeamKey(teamKey)

    /**
     * Whether the selected player is a member (web `BandRankingCard` highlight).
     *
     * @param selectedAccountId Selected player, or null.
     * @return True when a member matches.
     */
    fun includes(selectedAccountId: String?): Boolean = teamMembers.any { RankingSpotlight.isSelected(selectedAccountId, it.accountId) }

    /** Roster label joined with ` + `, "Unknown User" for blank member names (web `formatBandTeamName`). */
    val membersLabel: String get() = BandMember.joinNames(teamMembers)

    /**
     * Rank column for a metric.
     *
     * @param metric Selected metric.
     * @return One-based rank.
     */
    fun rank(metric: BandRankingMetric): Int = when (metric) {
        BandRankingMetric.Adjusted -> adjustedSkillRank
        BandRankingMetric.Weighted -> weightedRank
        BandRankingMetric.FcRate -> fcRateRank
        BandRankingMetric.TotalScore -> totalScoreRank
    }

    /**
     * Raw rating value for a metric.
     *
     * @param metric Selected metric.
     * @return Percentile fraction, score total or fraction.
     */
    fun ratingValue(metric: BandRankingMetric): Double = when (metric) {
        BandRankingMetric.Adjusted -> rawSkillRating
        BandRankingMetric.Weighted -> rawWeightedRating ?: weightedRating
        BandRankingMetric.FcRate -> if (totalChartedSongs > 0) fullComboCount.toDouble() / totalChartedSongs else 0.0
        BandRankingMetric.TotalScore -> totalScore.toDouble()
    }

    /**
     * Bayesian value for percentile metrics.
     *
     * @param metric Selected metric.
     * @return Value, or null.
     */
    fun bayesianValue(metric: BandRankingMetric): Double? = when (metric) {
        BandRankingMetric.Adjusted -> adjustedSkillRating
        BandRankingMetric.Weighted -> weightedRating
        else -> null
    }

    /**
     * Songs column.
     *
     * @param metric Selected metric.
     * @return "X / Y".
     */
    fun songsLabel(metric: BandRankingMetric): String =
        "${if (metric == BandRankingMetric.FcRate) fullComboCount else songsPlayed} / $totalChartedSongs"

}

/** `/api/rankings/bands/{bandType}` page. */
@Serializable
data class BandRankingsResponse(
    val bandType: String = "",
    val rankBy: String = "",
    val page: Int = 0,
    val pageSize: Int = 0,
    val totalTeams: Int = 0,
    val entries: List<BandRankingEntry> = emptyList(),
) {
    /** Pages of [pageSize] rows, at least one. */
    val pageCount: Int get() = RankingPaging.pageCount(totalTeams, pageSize)

    /**
     * Reject a response for another band size or with impossible counts.
     *
     * @param bandType Requested size.
     * @throws FestivalApiException.InvalidLeaderboard when corrupt.
     */
    fun validate(bandType: BandType) {
        if (this.bandType != bandType.wireId || page < 1 || pageSize < 1 || totalTeams < 0 || entries.size > pageSize) {
            throw FestivalApiException.InvalidLeaderboard()
        }
    }
}

// endregion

// region Paging

/** Paging rules shared by the rankings boards (web `LEADERBOARD_PAGE_SIZE`). */
object RankingPaging {
    /** Rows on a full rankings page. */
    const val PAGE_SIZE = 25

    /** Rows on an overview card. */
    const val CARD_SIZE = 10

    /** Largest page size the service accepts. */
    const val MAX_PAGE_SIZE = 200

    /**
     * Page count for a population.
     *
     * @param total Ranked rows.
     * @param pageSize Rows per page.
     * @return At least one.
     */
    fun pageCount(total: Int, pageSize: Int): Int {
        val size = maxOf(1, pageSize)
        return if (total <= 0) 1 else (total - 1) / size + 1
    }
}

// endregion
