package com.festivalscoretracker.android.core.profile

import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

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

/**
 * A pixel rectangle.
 *
 * @property left Left edge.
 * @property top Top edge.
 * @property width Width.
 * @property height Height.
 */
data class ChartRect(val left: Float, val top: Float, val width: Float, val height: Float)

/**
 * A pixel position.
 *
 * @property x Horizontal pixels.
 * @property y Vertical pixels from the top.
 */
data class ChartOffset(val x: Float, val y: Float)

/**
 * Unit-to-pixel mapping for the profile charts, kept pure so canvas code only draws
 * what these functions return (the draw lambdas have no logic of their own).
 */
object ChartGeometry {
    /** Bars take at most this share of the chart height, leaving room for the rank line. */
    const val BAR_HEIGHT_SHARE = 0.45f

    /** Slot width per bar relative to the bar (gaps between bars). */
    const val BAR_SLOT = 1.6f

    /** Thinnest bar in pixels. */
    const val MIN_BAR_WIDTH = 2f

    /** Shortest visible percentile bar as a share of the track. */
    const val MIN_PERCENTILE_FRACTION = 0.02f

    /**
     * Horizontal position with an end inset, so end points and bars stay inside the canvas.
     *
     * @param x Unit x (0–1).
     * @param width Canvas width.
     * @param pad Inset on each side.
     * @return Pixel x.
     */
    fun x(x: Float, width: Float, pad: Float): Float = pad + x * (width - 2 * pad)

    /**
     * Width of each Total Score bar.
     *
     * @param count Bars.
     * @param width Canvas width.
     * @param maxWidth Widest bar in pixels.
     * @return Bar width between [MIN_BAR_WIDTH] and [maxWidth].
     */
    fun barWidth(count: Int, width: Float, maxWidth: Float): Float =
        (width / (count.coerceAtLeast(1) * BAR_SLOT)).coerceIn(MIN_BAR_WIDTH, maxWidth.coerceAtLeast(MIN_BAR_WIDTH))

    /**
     * A bar's rectangle, bottom-aligned.
     *
     * @param bar Unit bar.
     * @param width Canvas width.
     * @param height Canvas height.
     * @param barWidth Bar width ([barWidth]).
     * @param pad Horizontal inset.
     * @return Pixel rectangle.
     */
    fun bar(bar: ChartBar, width: Float, height: Float, barWidth: Float, pad: Float): ChartRect {
        val h = bar.height * height * BAR_HEIGHT_SHARE
        return ChartRect(x(bar.x, width, pad) - barWidth / 2, height - h, barWidth, h)
    }

    /**
     * A line point in pixels.
     *
     * @param point Unit point.
     * @param width Canvas width.
     * @param height Canvas height.
     * @param pad Horizontal inset.
     * @return Pixel position.
     */
    fun point(point: ChartPoint, width: Float, height: Float, pad: Float): ChartOffset = ChartOffset(x(point.x, width, pad), point.y * height)

    /**
     * Top offset of a y-axis label so the last label still fits above the bottom edge.
     *
     * @param tick Tick.
     * @param chartHeight Chart height.
     * @param labelHeight Label line height.
     * @return Offset from the top, in the same unit as the inputs.
     */
    fun labelTop(tick: ChartTick, chartHeight: Float, labelHeight: Float): Float = tick.y * (chartHeight - labelHeight)

    /** Share of each band a category bar fills (web `barCategoryGap="10%"`). */
    const val BAND_FILL = 0.8f

    /**
     * A category bar centred in its band, bottom-aligned (rank-history chart).
     *
     * @param bar Unit bar (x = band centre).
     * @param count Bands.
     * @param width Canvas width.
     * @param height Canvas height.
     * @param maxWidth Widest bar in pixels.
     * @return Pixel rectangle.
     */
    fun bandBar(bar: ChartBar, count: Int, width: Float, height: Float, maxWidth: Float): ChartRect {
        val w = minOf(width / count.coerceAtLeast(1) * BAND_FILL, maxWidth)
        val h = bar.height * height
        return ChartRect(bar.x * width - w / 2, height - h, w, h)
    }

    /**
     * The band under a horizontal position (tap hit-testing).
     *
     * @param x Pixel x.
     * @param count Bands.
     * @param width Canvas width.
     * @return Band index, or null outside the canvas.
     */
    fun bandAt(x: Float, count: Int, width: Float): Int? {
        if (count <= 0 || width <= 0f || x < 0f || x > width) return null
        return (x / width * count).toInt().coerceIn(0, count - 1)
    }

    /**
     * Category-axis label positions (web Recharts `XAxis interval="preserveStartEnd"`, ticks
     * at each band's centre): every label is centred under its band, pinned inside
     * `[0, totalWidth]` only when centring would clip it at an edge, and labels that would
     * collide with a shown neighbour are hidden. The newest (last) label always shows, the
     * first shows unless it collides with the last, and the rest fill in left to right.
     *
     * @param widths Measured label widths, one per band, left to right.
     * @param plotLeft Left edge of the bands within the axis row.
     * @param plotWidth Width the bands share (`plotWidth / widths.size` per band).
     * @param totalWidth Width of the whole axis row (labels may extend into the gutters).
     * @param gap Minimum space between two shown labels.
     * @return Left edge of each label, or null for a hidden label.
     */
    fun bandLabelLefts(widths: List<Float>, plotLeft: Float, plotWidth: Float, totalWidth: Float, gap: Float): List<Float?> {
        val count = widths.size
        if (count == 0) return emptyList()
        val lefts = widths.mapIndexed { i, w ->
            val centre = plotLeft + plotWidth * (i + 0.5f) / count
            (centre - w / 2).coerceIn(0f, maxOf(0f, totalWidth - w))
        }
        val shown = arrayOfNulls<Float>(count)
        val last = count - 1
        shown[last] = lefts[last]
        val lastLeft = lefts[last]
        var right = Float.NEGATIVE_INFINITY
        for (i in 0 until last) {
            val fits = lefts[i] >= right + gap && lefts[i] + widths[i] + gap <= lastLeft
            if (fits) {
                shown[i] = lefts[i]
                right = lefts[i] + widths[i]
            }
        }
        return shown.toList()
    }

    /**
     * Visible share of a percentile bar's track (never zero, never over full).
     *
     * @param fraction Count relative to the largest band.
     * @return Fraction in `[MIN_PERCENTILE_FRACTION, 1]`.
     */
    fun percentileFraction(fraction: Float): Float = fraction.coerceIn(MIN_PERCENTILE_FRACTION, 1f)
}

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
 * @property snapshots Ranked snapshots, oldest first (the interactive chart's data).
 * @property totalAccounts Latest ranked field size (bar colours), or 0 when unknown.
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
    val snapshots: List<PlayerRankHistorySnapshot> = emptyList(),
    val totalAccounts: Int = 0,
) {
    companion object {
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
            val axis = RankHistoryPlot.rankAxis(ranked.map { it.totalScoreRank })
            fun y(rank: Double) = axis.fraction(rank).toFloat()
            fun x(i: Int) = if (ranked.size == 1) 0.5f else i.toFloat() / (ranked.size - 1)
            val line = ranked.mapIndexed { i, r -> ChartPoint(x(i), y(r.totalScoreRank.toDouble()), i == ranked.lastIndex) }
            val maxScore = ranked.maxOf { it.totalScore ?: 0L }
            val bars = if (maxScore <= 0) emptyList() else ranked.mapIndexed { i, r -> ChartBar(x(i), (r.totalScore ?: 0L).toFloat() / maxScore) }
            val latest = ranked.last()
            val field = latest.rankedAccountCount?.let { " of " + ProfileFormatting.count(it.toLong(), locale) } ?: ""
            val day = DateTimeFormatter.ofPattern("MMM d", locale)
            fun label(s: PlayerRankHistorySnapshot) = s.date?.format(day) ?: s.snapshotDate
            return RankHistoryChartModel(
                rankLine = line,
                rankTicks = axis.ticks.map { ChartTick(y(it), ProfileFormatting.rank(it.toInt(), locale)) },
                scoreBars = bars,
                headline = ProfileFormatting.rank(latest.totalScoreRank, locale) + field,
                totalScoreLine = latest.totalScore?.let { "Total Score " + ProfileFormatting.count(it, locale) },
                startLabel = label(ranked.first()),
                endLabel = label(latest),
                summary = rankTrend(ranked, locale),
                snapshots = ranked,
                totalAccounts = latest.rankedAccountCount ?: 0,
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
