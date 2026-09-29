package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.ChartTick
import com.festivalscoretracker.android.core.profile.PlayerRankHistorySnapshot
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.RankHistoryPlot
import com.festivalscoretracker.android.core.profile.RankHistoryWindow
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
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
 * @property rankedAccountCount Field size that day (bar colour), or null.
 */
data class RankHistoryPoint(val date: LocalDate, val rank: Int, val value: Double, val synthetic: Boolean, val rankedAccountCount: Int? = null)

/**
 * One row of the "latest snapshots" list under the chart, or the selected bar's detail.
 *
 * @property date "Sep 27, 2026".
 * @property rank "#1,234".
 * @property value Metric value text.
 * @property latest Newest row (accent treatment, like the web's best card).
 */
data class RankHistoryRow(val date: String, val rank: String, val value: String, val latest: Boolean)

/**
 * Data for the Leaderboards rank-history card (web
 * `pages/leaderboards/components/RankHistoryChart.tsx`): every day's rank and value
 * for the Rank By metric, windowed, swiped, paged and tapped exactly like the
 * profile chart by reusing its [RankHistoryWindow] / [RankHistoryPlot] on [snapshots]
 * (the metric's rank and scaled value in the Total Score slots), plus the five
 * newest days as rows. Pure data, so Compose draws it without per-frame work.
 *
 * @property metric Rank By metric.
 * @property points Daily points, oldest first.
 * @property snapshots [points] shaped for the shared window and plot.
 * @property rows Newest five days, newest first.
 * @property summary Screen-reader sentence.
 */
data class RankHistoryChart(
    val metric: RankingMetric,
    val points: List<RankHistoryPoint>,
    val snapshots: List<PlayerRankHistorySnapshot>,
    val rows: List<RankHistoryRow>,
    val summary: String,
) {
    /** Field size for bar colours (latest known). */
    val totalAccounts: Int get() = points.lastOrNull { it.rankedAccountCount != null }?.rankedAccountCount ?: 0

    /** Divisor from the plot's stored bar values back to the metric's units. */
    val valueScale: Double get() = if (metric == RankingMetric.TotalScore) 1.0 else VALUE_SCALE

    /**
     * The plot for a window: web rank and value axes, bars on the value axis, value
     * labels in the metric's format (web `formatValueTick`).
     *
     * @param window Visible window over [snapshots].
     * @param locale Locale.
     * @return Geometry.
     */
    fun plot(window: RankHistoryWindow, locale: Locale = Locale.getDefault()): RankHistoryPlot =
        RankHistoryPlot.build(window, totalAccounts, locale, valueScale) { axisText(it, metric, locale) }

    /**
     * Value-axis labels for a window: Recharts' nice ticks from zero over the visible
     * values (the same axis [plot] scales the bars to).
     *
     * @param window Visible window over [snapshots].
     * @param locale Locale.
     * @return Ticks, highest first (empty when every visible value is zero).
     */
    fun valueTicks(window: RankHistoryWindow, locale: Locale = Locale.getDefault()): List<ChartTick> = plot(window, locale).scoreTicks

    /**
     * The selected bar's detail line.
     *
     * @param window Window with a selection.
     * @param locale Locale.
     * @return Detail, or null without a selection.
     */
    fun detail(window: RankHistoryWindow, locale: Locale = Locale.getDefault()): RankHistoryRow? =
        window.selected?.let(points::getOrNull)?.let { row(it, metric, latest = false, locale = locale) }

    /**
     * Accessible description of a window ("Sep 21, 2026: #14. …").
     *
     * @param window Visible window.
     * @param locale Locale.
     * @return Text.
     */
    fun windowDescription(window: RankHistoryWindow, locale: Locale = Locale.getDefault()): String {
        val visible = points.subList(window.pageStart, window.pageEnd)
        if (visible.isEmpty()) return "Rank history chart. $summary"
        return buildString {
            append("Rank history chart, ").append(day(visible.first().date, locale)).append(" to ").append(day(visible.last().date, locale)).append(". ")
            visible.forEach { append(day(it.date, locale)).append(": ").append(RankingFormatting.rankLabel(it.rank, locale)).append(". ") }
        }
    }

    companion object {
        /** Days requested (web default). */
        const val DAYS = 30

        /** Rows under the chart (web `getRecentRankHistoryPoints`). */
        const val RECENT_ROWS = 5

        /** Fractional metrics are scaled to whole numbers for the shared plot's Long values. */
        private const val VALUE_SCALE = 1_000_000.0

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
                    result += RankHistoryPoint(day, snapshot.rank(metric), snapshot.value(metric), synthetic = day != date, snapshot.rankedAccountCount)
                    day = day.plusDays(1)
                }
            }
            return result
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
         * Short value-axis label (web `formatValueTick`): compact totals, whole percents.
         *
         * @param value Metric value.
         * @param metric Rank By metric.
         * @param locale Locale.
         * @return Text.
         */
        fun axisText(value: Double, metric: RankingMetric, locale: Locale = Locale.getDefault()): String = when (metric) {
            RankingMetric.TotalScore -> ProfileFormatting.valueTick(value)
            RankingMetric.FcRate, RankingMetric.MaxScore -> "${String.format(Locale.US, "%.0f", value * 100)}%"
            RankingMetric.Adjusted, RankingMetric.Weighted -> String.format(Locale.US, "%.2f", value)
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
            val points = points(history, metric, today).filter { it.rank > 0 }
            if (points.isEmpty()) return null
            val scale = if (metric == RankingMetric.TotalScore) 1.0 else VALUE_SCALE
            val snapshots = points.map {
                PlayerRankHistorySnapshot(
                    snapshotDate = it.date.toString(),
                    totalScoreRank = it.rank,
                    totalScore = (it.value * scale).toLong().coerceAtLeast(0L),
                    rankedAccountCount = it.rankedAccountCount,
                )
            }
            val rows = points.asReversed().take(RECENT_ROWS).mapIndexed { i, p -> row(p, metric, latest = i == 0, locale = locale) }
            val delta = points.first().rank - points.last().rank
            val trend = when {
                delta > 0 -> "up ${NumberFormat.getIntegerInstance(locale).format(delta)} places"
                delta < 0 -> "down ${NumberFormat.getIntegerInstance(locale).format(-delta)} places"
                else -> "unchanged"
            }
            val summary = "${metric.label} rank over ${points.size} days. Latest ${RankingFormatting.rankLabel(points.last().rank, locale)}, $trend."
            return RankHistoryChart(metric, points, snapshots, rows, summary)
        }

        private fun day(date: LocalDate, locale: Locale): String = date.format(DateTimeFormatter.ofPattern("MMM d, yyyy", locale))

        private fun row(point: RankHistoryPoint, metric: RankingMetric, latest: Boolean, locale: Locale): RankHistoryRow =
            RankHistoryRow(day(point.date, locale), RankingFormatting.rankLabel(point.rank, locale), valueText(point.value, metric, locale), latest)
    }
}

// endregion
