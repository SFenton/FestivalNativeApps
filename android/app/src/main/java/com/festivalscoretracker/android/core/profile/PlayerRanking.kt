package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.RankingMetric
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlinx.serialization.Serializable

// region Formatting

/** Rank and percentile text shared by the player page and its charts. */
object ProfileFormatting {
    /**
     * Grouped integer such as `1,234`.
     *
     * @param value Number.
     * @param locale Locale.
     * @return Text.
     */
    fun count(value: Long, locale: Locale = Locale.getDefault()): String = NumberFormat.getIntegerInstance(locale).format(value)

    /**
     * `#1,234`.
     *
     * @param rank One-based rank.
     * @param locale Locale.
     * @return Text.
     */
    fun rank(rank: Int, locale: Locale = Locale.getDefault()): String = "#" + count(rank.toLong(), locale)

    /**
     * Short axis label: `950`, `12K`, `1.2M` (one decimal below ten of a unit).
     *
     * @param value Non-negative number.
     * @param locale Locale.
     * @return Text.
     */
    fun compact(value: Long, locale: Locale = Locale.getDefault()): String {
        val (scaled, suffix) = when {
            value >= 1_000_000_000 -> value / 1e9 to "B"
            value >= 1_000_000 -> value / 1e6 to "M"
            value >= 1_000 -> value / 1e3 to "K"
            else -> return count(value, locale)
        }
        val digits = if (scaled < 10) 1 else 0
        return NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 0
            maximumFractionDigits = digits
            roundingMode = java.math.RoundingMode.DOWN
        }.format(scaled) + suffix
    }

    /**
     * Web `formatValueTick` (Total Score): `120M`, `2.5M`, `104.8M`, `950` — whole units
     * without a decimal, else one decimal, always with a `.` separator like the web.
     *
     * @param value Axis value.
     * @return Text.
     */
    fun valueTick(value: Double): String {
        val absolute = kotlin.math.abs(value)
        val sign = if (value < 0) "-" else ""
        val (scaled, suffix) = when {
            absolute >= 1_000_000_000 -> absolute / 1e9 to "B"
            absolute >= 1_000_000 -> absolute / 1e6 to "M"
            absolute >= 1_000 -> absolute / 1e3 to "K"
            else -> return Math.round(value).toString()
        }
        val digits = if (scaled % 1.0 == 0.0) "%.0f" else "%.1f"
        return sign + String.format(Locale.US, digits, scaled) + suffix
    }

    /**
     * Up to two decimals with trailing zeros dropped (`4.5`, `4.25`, `5`; web `formatClamped2`).
     *
     * @param value Number.
     * @param locale Locale.
     * @return Text.
     */
    fun twoDecimals(value: Double, locale: Locale = Locale.getDefault()): String = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 2
        roundingMode = java.math.RoundingMode.HALF_UP
    }.format(value)

    /**
     * One decimal only when needed (`40` or `40.5`).
     *
     * @param value Percent.
     * @param locale Locale.
     * @return Text.
     */
    fun percent(value: Double, locale: Locale = Locale.getDefault()): String {
        val digits = if (value == Math.rint(value)) 0 else 1
        return NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }.format(value)
    }

    /**
     * "Top N%" from a 0–1 fraction (two decimals below 1%), matching the web's percentile pill.
     *
     * @param fraction Rank over field size.
     * @param locale Locale.
     * @return Text, or `N/A` for a non-finite value.
     */
    fun topPercent(fraction: Double, locale: Locale = Locale.getDefault()): String {
        if (!fraction.isFinite()) return "N/A"
        val top = (fraction * 100).coerceIn(0.01, 100.0)
        val digits = if (top < 1) 2 else 0
        val text = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }.format(top)
        return "Top $text%"
    }
}

// endregion

// region Single-account ranking

/**
 * One account's own row on `GET /api/rankings/{instrument}/{accountId}`, a pure read
 * (`FSTService/Api/RankingsEndpoints.cs:272-327`). The web uses this route when
 * player-stats has not embedded ranks; natives never call player-stats.
 *
 * @property accountId Account.
 * @property displayName Name.
 * @property instrument Service instrument ID; production returns `""` here (live 2026-09-28).
 * @property totalScore Summed best scores.
 * @property totalScoreRank Total Score rank (web default metric).
 * @property adjustedSkillRank Adjusted percentile rank (experimental, 0 when absent).
 * @property weightedRank Weighted percentile rank (experimental, 0 when absent).
 * @property fcRateRank FC rate rank (experimental, 0 when absent).
 * @property maxScorePercentRank Max Score % rank (experimental, 0 when absent).
 * @property totalRankedAccounts Size of the ranked field.
 * @property songsPlayed Songs played.
 * @property totalChartedSongs Charted songs.
 */
@Serializable
data class PlayerInstrumentRanking(
    val accountId: String = "",
    val displayName: String? = null,
    val instrument: String? = null,
    val totalScore: Long = 0,
    val totalScoreRank: Int = 0,
    val adjustedSkillRank: Int = 0,
    val weightedRank: Int = 0,
    val fcRateRank: Int = 0,
    val maxScorePercentRank: Int = 0,
    val totalRankedAccounts: Int = -1,
    val songsPlayed: Int = 0,
    val totalChartedSongs: Int = 0,
) {
    /**
     * Reject a row for another account/instrument or an impossible total (a blank instrument is accepted).
     *
     * @param instrument Requested chart.
     * @param accountId Requested account.
     * @throws FestivalApiException.InvalidResponse when inconsistent.
     */
    fun validate(instrument: Instrument, accountId: String) {
        val valid = (this.instrument.isNullOrEmpty() || this.instrument == instrument.wireId) &&
            this.accountId.equals(accountId, ignoreCase = true) && totalRankedAccounts >= 0 && totalScoreRank >= 0 && totalScore >= 0
        if (!valid) throw FestivalApiException.InvalidResponse()
    }

    /**
     * This row's rank for a metric (web `getRankForMetric`).
     *
     * @param metric Rank By.
     * @return Rank, 0 when unranked or absent.
     */
    fun rank(metric: RankingMetric): Int = when (metric) {
        RankingMetric.Adjusted -> adjustedSkillRank
        RankingMetric.Weighted -> weightedRank
        RankingMetric.FcRate -> fcRateRank
        RankingMetric.TotalScore -> totalScoreRank
        RankingMetric.MaxScore -> maxScorePercentRank
    }

    /** Total Score rank over the field, 0 (best) to 1, or null when unranked. */
    val totalScorePercentile: Double?
        get() = if (totalScoreRank > 0 && totalRankedAccounts > 0) totalScoreRank.toDouble() / totalRankedAccounts else null

    /** Whether the placement is within the top 5% (gold). */
    val isTopFive: Boolean get() = totalScorePercentile?.let { it * 100 <= 5 } == true
}

/**
 * A single-account ranking read.
 *
 * @property ranking Row, or null when unranked (HTTP 404 means "not ranked yet", not a failure).
 */
data class PlayerInstrumentRankingPayload(val ranking: PlayerInstrumentRanking?)

// endregion

// region Rank history

/**
 * One daily snapshot from `GET /api/rankings/{instrument}/{accountId}/history`.
 *
 * @property snapshotDate UTC calendar day `yyyy-MM-dd` (a label, not an instant).
 * @property totalScoreRank Total Score rank (0 when unranked that day).
 * @property totalScore Total score.
 * @property rankedAccountCount Ranked field size.
 */
@Serializable
data class PlayerRankHistorySnapshot(
    val snapshotDate: String = "",
    val snapshotTakenAt: String? = null,
    val adjustedSkillRank: Int = 0,
    val weightedRank: Int = 0,
    val fcRateRank: Int = 0,
    val totalScoreRank: Int = -1,
    val maxScorePercentRank: Int = 0,
    val totalScore: Long? = null,
    val songsPlayed: Int? = null,
    val fullComboCount: Int? = null,
    val totalChartedSongs: Int? = null,
    val rankedAccountCount: Int? = null,
) {
    /** The snapshot day, or null for a malformed value. */
    val date: LocalDate?
        get() = try {
            if (snapshotDate.length == 10) LocalDate.parse(snapshotDate) else null
        } catch (_: DateTimeParseException) {
            null
        }
}

/**
 * Response for `/api/rankings/{instrument}/{accountId}/history`.
 *
 * @property instrument Service instrument ID.
 * @property accountId Account.
 * @property history Daily snapshots.
 */
@Serializable
data class PlayerRankHistory(
    val instrument: String = "",
    val accountId: String = "",
    val history: List<PlayerRankHistorySnapshot> = emptyList(),
) {
    /**
     * Reject another instrument/account, malformed dates, negative ranks or duplicate days.
     *
     * @param instrument Requested chart.
     * @param accountId Requested account.
     * @throws FestivalApiException.InvalidResponse when inconsistent.
     */
    fun validate(instrument: Instrument, accountId: String) {
        val valid = this.instrument == instrument.wireId && this.accountId.equals(accountId, ignoreCase = true) &&
            history.all { it.date != null && it.totalScoreRank >= 0 } &&
            history.map { it.snapshotDate }.toSet().size == history.size
        if (!valid) throw FestivalApiException.InvalidResponse()
    }

    /** Snapshots with a real Total Score rank, oldest first. */
    val rankedChronological: List<PlayerRankHistorySnapshot>
        get() = history.filter { it.totalScoreRank > 0 }.sortedBy { it.snapshotDate }
}

// endregion
