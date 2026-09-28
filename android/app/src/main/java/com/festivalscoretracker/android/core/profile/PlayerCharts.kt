package com.festivalscoretracker.android.core.profile

import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.ceil

// region Chart primitives

/**
 * A plotted point in unit coordinates: x 0 (left) … 1 (right), y 0 (top) … 1 (bottom).
 *
 * @property x Horizontal fraction.
 * @property y Vertical fraction from the top.
 * @property highlight Draw emphasized (personal best, latest).
 */
data class ChartPoint(val x: Float, val y: Float, val highlight: Boolean = false)

/**
 * A horizontal grid line and label.
 *
 * @property y Vertical fraction from the top.
 * @property label Axis text.
 */
data class ChartTick(val y: Float, val label: String)

/**
 * A vertical bar in unit coordinates.
 *
 * @property x Centre fraction.
 * @property height Height fraction from the bottom.
 */
data class ChartBar(val x: Float, val height: Float)

// endregion

// region Rank history chart

/**
 * Geometry for the rank-history card (web `RankHistoryChart`, Total Score): a rank
 * line with #1 on top on a padded axis that never shows "#0", over Total Score bars
 * on the same date axis. Pure data, so Compose draws it without per-frame work.
 *
 * @property rankLine Rank points, oldest first.
 * @property rankTicks Rank grid lines, best first.
 * @property scoreBars Total Score bars (empty when no snapshot has a score).
 * @property headline "#8 of 500".
 * @property totalScoreLine "Total Score 1,234", or null.
 * @property startLabel First day.
 * @property endLabel Last day.
 * @property summary Screen-reader trend sentence.
 */
data class RankHistoryChartModel(
    val rankLine: List<ChartPoint>,
    val rankTicks: List<ChartTick>,
    val scoreBars: List<ChartBar>,
    val headline: String,
    val totalScoreLine: String?,
    val startLabel: String,
    val endLabel: String,
    val summary: String,
) {
    companion object {
        /**
         * Padded rank axis (best ≥ 1) with up to four whole-number ticks, best first.
         *
         * @param ranks Charted ranks (all ≥ 1).
         * @return Best, worst and ticks.
         */
        fun rankAxis(ranks: Collection<Int>): Triple<Int, Int, List<Int>> {
            val low = ranks.minOrNull() ?: 1
            val high = ranks.maxOrNull() ?: 1
            val pad = maxOf(1, (high - low) / 8)
            val best = maxOf(1, low - pad)
            val worst = maxOf(best + 1, high + pad)
            val step = maxOf(1, ceil((worst - best) / 3.0).toInt())
            return Triple(best, worst, (best..worst step step).toList())
        }

        /**
         * First-to-latest movement summary for screen readers (lower rank is better).
         *
         * @param points Chronological ranked snapshots.
         * @param locale Locale.
         * @return Sentence.
         */
        fun rankTrend(points: List<PlayerRankHistorySnapshot>, locale: Locale = Locale.getDefault()): String {
            if (points.isEmpty()) return "No snapshots"
            val delta = points.first().totalScoreRank - points.last().totalScoreRank
            val trend = when {
                delta > 0 -> "up ${ProfileFormatting.count(delta.toLong(), locale)} places"
                delta < 0 -> "down ${ProfileFormatting.count(-delta.toLong(), locale)} places"
                else -> "unchanged"
            }
            val snapshots = if (points.size == 1) "1 daily snapshot" else "${points.size} daily snapshots"
            return "$snapshots. Latest rank ${ProfileFormatting.count(points.last().totalScoreRank.toLong(), locale)}, $trend."
        }

        /**
         * Build the chart from ranked snapshots.
         *
         * @param ranked Chronological snapshots with a positive Total Score rank.
         * @param locale Locale.
         * @return Geometry, or null when empty.
         */
        fun build(ranked: List<PlayerRankHistorySnapshot>, locale: Locale = Locale.getDefault()): RankHistoryChartModel? {
            if (ranked.isEmpty()) return null
            val (best, worst, ticks) = rankAxis(ranked.map { it.totalScoreRank })
            val span = (worst - best).toFloat()
            fun x(i: Int) = if (ranked.size == 1) 0.5f else i.toFloat() / (ranked.size - 1)
            val line = ranked.mapIndexed { i, r -> ChartPoint(x(i), (r.totalScoreRank - best) / span, i == ranked.lastIndex) }
            val maxScore = ranked.maxOf { it.totalScore ?: 0L }
            val bars = if (maxScore <= 0) emptyList() else ranked.mapIndexed { i, r -> ChartBar(x(i), (r.totalScore ?: 0L).toFloat() / maxScore) }
            val latest = ranked.last()
            val field = latest.rankedAccountCount?.let { " of " + ProfileFormatting.count(it.toLong(), locale) } ?: ""
            val day = DateTimeFormatter.ofPattern("MMM d", locale)
            fun label(s: PlayerRankHistorySnapshot) = s.date?.format(day) ?: s.snapshotDate
            return RankHistoryChartModel(
                rankLine = line,
                rankTicks = ticks.map { ChartTick((it - best) / span, ProfileFormatting.rank(it, locale)) },
                scoreBars = bars,
                headline = ProfileFormatting.rank(latest.totalScoreRank, locale) + field,
                totalScoreLine = latest.totalScore?.let { "Total Score " + ProfileFormatting.count(it, locale) },
                startLabel = label(ranked.first()),
                endLabel = label(latest),
                summary = rankTrend(ranked, locale),
            )
        }
    }
}

// endregion

// region Percentile bars

/**
 * One horizontal bar of the percentile card.
 *
 * @property label "Top 5%".
 * @property count Songs in the band.
 * @property fraction Length relative to the largest band.
 * @property gold Top-5% band.
 */
data class PercentileBar(val label: String, val count: Int, val fraction: Float, val gold: Boolean) {
    /** Screen-reader text. */
    val announcement: String get() = "$label: $count ${if (count == 1) "song" else "songs"}"

    companion object {
        /**
         * Build bars from non-empty buckets.
         *
         * @param buckets Buckets.
         * @return Bars, best first.
         */
        fun build(buckets: List<PlayerPercentileBucket>): List<PercentileBar> {
            val max = buckets.maxOfOrNull { it.count } ?: 1
            return buckets.map { PercentileBar(it.label, it.count, it.count.toFloat() / max, it.isTopFive) }
        }
    }
}

// endregion

// region Score history chart

/**
 * Score-over-time line for score history (a native addition; two or more dated rows).
 *
 * @property points Chronological points; the personal best is highlighted.
 * @property ticks Score grid lines, highest first.
 * @property startLabel First date.
 * @property endLabel Last date.
 * @property summary Screen-reader sentence.
 */
data class ScoreHistoryChartModel(
    val points: List<ChartPoint>,
    val ticks: List<ChartTick>,
    val startLabel: String,
    val endLabel: String,
    val summary: String,
) {
    companion object {
        /**
         * Build the chart from rows in any order.
         *
         * @param entries Rows for one song and chart.
         * @param zone Display time zone.
         * @param locale Locale.
         * @return Geometry, or null with fewer than two dated rows.
         */
        fun build(entries: List<ScoreHistoryEntry>, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): ScoreHistoryChartModel? {
            val dated = entries.mapNotNull { e -> e.displayDate?.let { e to it } }.sortedBy { it.second }
            if (dated.size < 2) return null
            val first = dated.first().second
            val spanMillis = maxOf(1L, Duration.between(first, dated.last().second).toMillis())
            val low = dated.minOf { it.first.newScore }
            val high = dated.maxOf { it.first.newScore }
            val pad = maxOf(1L, (high - low) / 8)
            val top = high + pad
            val bottom = maxOf(0L, low - pad)
            val range = maxOf(1L, top - bottom).toFloat()
            val bestIndex = dated.indices.maxByOrNull { dated[it].first.newScore } ?: 0
            val points = dated.mapIndexed { i, (e, at) ->
                ChartPoint(Duration.between(first, at).toMillis().toFloat() / spanMillis, (top - e.newScore) / range, i == bestIndex)
            }
            val ticks = listOf(top, (top + bottom) / 2, bottom).map { ChartTick((top - it) / range, ProfileFormatting.count(it, locale)) }
            val short = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(zone)
            val best = dated[bestIndex]
            return ScoreHistoryChartModel(
                points = points,
                ticks = ticks,
                startLabel = short.format(dated.first().second),
                endLabel = short.format(dated.last().second),
                summary = "${dated.size} score changes from ${short.format(first)} to ${short.format(dated.last().second)}. " +
                    "Best ${ProfileFormatting.count(best.first.newScore, locale)} on ${short.format(best.second)}.",
            )
        }
    }
}

// endregion
