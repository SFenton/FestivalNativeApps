package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.ChartBar
import com.festivalscoretracker.android.core.profile.ChartPoint
import com.festivalscoretracker.android.core.profile.ChartTick
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.ceil
import kotlinx.serialization.Serializable

// region Wire

/**
 * One daily snapshot of `GET /api/rankings/{instrument}/{accountId}/history?days=`
 * (a pure read, `FSTService/Api/RankingsEndpoints.cs:392-413`), with every metric's
 * rank and value (web `RankHistoryEntry`). Values are optional on the wire.
 */
@Serializable
data class RankHistorySnapshot(
    val snapshotDate: String = "",
    val adjustedSkillRank: Int = 0,
    val weightedRank: Int = 0,
    val fcRateRank: Int = 0,
    val totalScoreRank: Int = 0,
    val maxScorePercentRank: Int = 0,
    val adjustedSkillRating: Double? = null,
    val weightedRating: Double? = null,
    val fcRate: Double? = null,
    val totalScore: Long? = null,
    val maxScorePercent: Double? = null,
    val rawSkillRating: Double? = null,
    val rawWeightedRating: Double? = null,
    val rawMaxScorePercent: Double? = null,
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

    /**
     * Rank for a metric (web `getRankField`).
     *
     * @param metric Rank By metric.
     * @return Rank, 0 when unranked.
     */
    fun rank(metric: RankingMetric): Int = when (metric) {
        RankingMetric.Adjusted -> adjustedSkillRank
        RankingMetric.Weighted -> weightedRank
        RankingMetric.FcRate -> fcRateRank
        RankingMetric.TotalScore -> totalScoreRank
        RankingMetric.MaxScore -> maxScorePercentRank
    }

    /**
     * Value for a metric (web `getValueField`: raw percentile first).
     *
     * @param metric Rank By metric.
     * @return Value, 0 when missing.
     */
    fun value(metric: RankingMetric): Double = when (metric) {
        RankingMetric.Adjusted -> rawSkillRating ?: adjustedSkillRating ?: 0.0
        RankingMetric.Weighted -> rawWeightedRating ?: weightedRating ?: 0.0
        RankingMetric.FcRate -> fcRate ?: 0.0
        RankingMetric.TotalScore -> (totalScore ?: 0L).toDouble()
        RankingMetric.MaxScore -> rawMaxScorePercent ?: maxScorePercent ?: 0.0
    }
}

/**
 * Response for `/api/rankings/{instrument}/{accountId}/history`.
 *
 * @property instrument Service instrument ID.
 * @property accountId Account.
 * @property history Daily snapshots (sparse; missing days carry forward).
 */
@Serializable
data class RankHistoryResponse(
    val instrument: String = "",
    val accountId: String = "",
    val history: List<RankHistorySnapshot> = emptyList(),
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
            history.all { it.date != null && RankingMetric.entries.all { metric -> it.rank(metric) >= 0 } } &&
            history.map { it.snapshotDate }.toSet().size == history.size
        if (!valid) throw FestivalApiException.InvalidResponse()
    }
}

// endregion

// region Chart model

/**
 * One charted day (web `RankHistoryChartPoint`).
 *
 * @property date Day.
 * @property rank Rank for the metric.
 * @property value Value for the metric.
 * @property synthetic Carried forward over a missing day.
 */
data class RankHistoryPoint(val date: LocalDate, val rank: Int, val value: Double, val synthetic: Boolean)

/**
 * One row of the "latest snapshots" list under the chart.
 *
 * @property date "Sep 27, 2026".
 * @property rank "#1,234".
 * @property value Metric value text.
 * @property latest Newest row (accent treatment, like the web's best card).
 */
data class RankHistoryRow(val date: String, val rank: String, val value: String, val latest: Boolean)

/**
 * Geometry and text for the Leaderboards rank-history card (web
 * `pages/leaderboards/components/RankHistoryChart.tsx`): metric value bars under a
 * rank line (#1 on top) on one date axis, and the five newest days as rows. Pure
 * data, so Compose draws it without per-frame work.
 *
 * @property bars Value bars, oldest first.
 * @property rankLine Rank points (y 0 = best rank on the axis).
 * @property rankTicks Rank grid lines, best first.
 * @property startLabel First day on the axis.
 * @property endLabel Last day on the axis.
 * @property rows Newest five days, newest first.
 * @property summary Screen-reader sentence.
 */
data class RankHistoryChart(
    val bars: List<ChartBar>,
    val rankLine: List<ChartPoint>,
    val rankTicks: List<ChartTick>,
    val startLabel: String,
    val endLabel: String,
    val rows: List<RankHistoryRow>,
    val summary: String,
) {
    companion object {
        /** Days requested (web default). */
        const val DAYS = 30

        /** Rows under the chart (web `getRecentRankHistoryPoints`). */
        const val RECENT_ROWS = 5

        /**
         * Carry-forward gap filling (web `fillRankHistoryGaps`): every missing day,
         * including trailing days through [today], repeats the previous snapshot.
         *
         * @param history Snapshots in any order (malformed dates dropped).
         * @param metric Rank By metric.
         * @param today Local calendar day.
         * @return Daily points, oldest first.
         */
        fun points(history: List<RankHistorySnapshot>, metric: RankingMetric, today: LocalDate): List<RankHistoryPoint> {
            val dated = history.mapNotNull { snapshot -> snapshot.date?.let { it to snapshot } }.sortedBy { it.first }
            val result = mutableListOf<RankHistoryPoint>()
            dated.forEachIndexed { index, (date, snapshot) ->
                val end = dated.getOrNull(index + 1)?.first ?: today.plusDays(1)
                var day = date
                while (day == date || day < end) {
                    result += RankHistoryPoint(day, snapshot.rank(metric), snapshot.value(metric), synthetic = day != date)
                    day = day.plusDays(1)
                }
            }
            return result
        }

        /**
         * Rank axis padded by 10 % either side, never above #1 (web `getRankHistoryDomain`).
         *
         * @param ranks Ranks (non-positive ignored).
         * @return Best and worst axis ranks.
         */
        fun rankDomain(ranks: List<Int>): Pair<Int, Int> {
            val ranked = ranks.filter { it > 0 }
            if (ranked.isEmpty()) return 1 to 100
            val low = ranked.min()
            val high = ranked.max()
            val pad = ceil((high - low) * 0.1).toInt()
            val best = maxOf(1, low - pad)
            // A flat line still needs a non-empty axis.
            return best to maxOf(high + pad, best + 1)
        }

        /**
         * Value text for a metric (web `formatDetailValue`, with the rows' percentile text).
         *
         * @param value Metric value.
         * @param metric Rank By metric.
         * @param locale Locale.
         * @return Text.
         */
        fun valueText(value: Double, metric: RankingMetric, locale: Locale = Locale.getDefault()): String = when (metric) {
            RankingMetric.FcRate, RankingMetric.MaxScore -> {
                val percent = value * 100
                if (percent % 1.0 == 0.0) "${String.format(Locale.US, "%.0f", percent)}%" else "${String.format(Locale.US, "%.1f", percent)}%"
            }
            RankingMetric.TotalScore -> NumberFormat.getIntegerInstance(locale).format(value.toLong())
            RankingMetric.Adjusted, RankingMetric.Weighted -> RankingFormatting.percentile(value)
        }

        /**
         * Build the card from a response.
         *
         * @param history Snapshots.
         * @param metric Rank By metric.
         * @param today Local calendar day (trailing carry-forward).
         * @param locale Locale.
         * @return Chart, or null when no day has a rank for the metric.
         */
        fun build(history: List<RankHistorySnapshot>, metric: RankingMetric, today: LocalDate, locale: Locale = Locale.getDefault()): RankHistoryChart? {
            val points = points(history, metric, today)
            if (points.none { it.rank > 0 }) return null
            val (best, worst) = rankDomain(points.map { it.rank })
            val span = (worst - best).toFloat()
            fun x(i: Int) = if (points.size == 1) 0.5f else i.toFloat() / (points.size - 1)
            val maxValue = points.maxOf { it.value }
            val bars = if (maxValue <= 0) emptyList() else points.mapIndexed { i, p -> ChartBar(x(i), (p.value / maxValue).toFloat().coerceIn(0f, 1f)) }
            val line = points.mapIndexedNotNull { i, p ->
                if (p.rank <= 0) null else ChartPoint(x(i), ((p.rank - best) / span).coerceIn(0f, 1f), highlight = i == points.lastIndex)
            }
            val step = maxOf(1, ceil((worst - best) / 3.0).toInt())
            val ticks = (best..worst step step).map { ChartTick((it - best) / span, RankingFormatting.rankLabel(it, locale)) }
            val axis = DateTimeFormatter.ofPattern("M/d/yy", locale)
            val long = DateTimeFormatter.ofPattern("MMM d, yyyy", locale)
            val rows = points.asReversed().take(RECENT_ROWS).mapIndexed { i, p ->
                RankHistoryRow(p.date.format(long), RankingFormatting.rankLabel(p.rank, locale), valueText(p.value, metric, locale), latest = i == 0)
            }
            val ranked = points.filter { it.rank > 0 }
            val delta = ranked.first().rank - ranked.last().rank
            val trend = when {
                delta > 0 -> "up ${NumberFormat.getIntegerInstance(locale).format(delta)} places"
                delta < 0 -> "down ${NumberFormat.getIntegerInstance(locale).format(-delta)} places"
                else -> "unchanged"
            }
            val summary = "${metric.label} rank over ${points.size} days. Latest ${RankingFormatting.rankLabel(ranked.last().rank, locale)}, $trend."
            return RankHistoryChart(bars, line, ticks, points.first().date.format(axis), points.last().date.format(axis), rows, summary)
        }
    }
}

// endregion
