package com.festivalscoretracker.android.core.profile

import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

// region Colours

/** Web chart colours (`@festival/theme`, `@festival/core/app/formatters`). */
object RankHistoryColors {
    /** Rank line and dots (web `Colors.accentBlueBright` #4C7DFF). */
    const val RANK_LINE: Int = 0x4C7DFF

    /** Unranked/unknown bar grey (web `rgb(127,140,141)`). */
    const val UNKNOWN: Int = 0x7F8C8D

    /** Bar fill opacity (web `fillOpacity={0.8}`). */
    const val BAR_ALPHA: Float = 0.8f

    /**
     * Web `accuracyColor`: red (220,40,40) at 0% to green (46,204,113) at 100%.
     *
     * @param percent 0–100 (clamped).
     * @return RGB as `0xRRGGBB`.
     */
    fun accuracy(percent: Double): Int {
        val t = (percent / 100).coerceIn(0.0, 1.0)
        val r = (220 * (1 - t) + 46 * t).roundToInt()
        val g = (40 * (1 - t) + 204 * t).roundToInt()
        val b = (40 * (1 - t) + 113 * t).roundToInt()
        return (r shl 16) or (g shl 8) or b
    }

    /**
     * Web `rankColor`: the bar colour for a rank in a field (better ranks greener).
     *
     * @param rank Rank.
     * @param totalAccounts Field size.
     * @return RGB as `0xRRGGBB`.
     */
    fun rank(rank: Int, totalAccounts: Int): Int =
        if (totalAccounts <= 0 || rank <= 0) UNKNOWN else accuracy((1 - rank.toDouble() / totalAccounts) * 100)
}

// endregion

// region Window

/**
 * The web `GraphCard` + `useChartPagination` state for the Rank History chart: a window
 * of at most [maxBars] snapshots ending [offset] snapshots before the newest, and an
 * optional selected snapshot. Pure and immutable; each action returns the next state.
 *
 * @property points Ranked snapshots, oldest first.
 * @property maxBars Bars that fit the chart width.
 * @property offset Snapshots hidden after the window (0 = newest visible).
 * @property selected Selected snapshot index into [points], or null.
 */
data class RankHistoryWindow(
    val points: List<PlayerRankHistorySnapshot>,
    val maxBars: Int,
    val offset: Int = 0,
    val selected: Int? = null,
) {
    /** Largest offset (oldest window). */
    val maxOffset: Int get() = maxOf(0, points.size - bars)

    private val bars: Int get() = maxBars.coerceAtLeast(1)
    private val clamped: Int get() = offset.coerceIn(0, maxOffset)

    /** First visible index (inclusive). */
    val pageStart: Int get() = maxOf(0, pageEnd - bars)

    /** Last visible index (exclusive). */
    val pageEnd: Int get() = points.size - clamped

    /** Visible snapshots, oldest first. */
    val visible: List<PlayerRankHistorySnapshot> get() = points.subList(pageStart, pageEnd)

    /** Whether the history is wider than the chart (shows the pager). */
    val needsPagination: Boolean get() = points.size > bars

    /** Whether "back" (older) is unavailable. */
    val backDisabled: Boolean get() = selected?.let { it <= 0 } ?: (clamped >= maxOffset)

    /** Whether "forward" (newer) is unavailable. */
    val forwardDisabled: Boolean get() = selected?.let { it >= points.size - 1 } ?: (clamped <= 0)

    /** The selected snapshot. */
    val selectedPoint: PlayerRankHistorySnapshot? get() = selected?.let(points::getOrNull)

    /**
     * Fit a new chart width (keeps the selection visible).
     *
     * @param bars Bars that now fit.
     * @return Updated window.
     */
    fun resized(bars: Int): RankHistoryWindow = copy(maxBars = bars.coerceAtLeast(1)).let { next -> next.selected?.let(next::navigate) ?: next }

    /**
     * Tap a visible bar: select it, or clear when it is already selected (web toggle).
     *
     * @param visibleIndex Index into [visible].
     * @return Updated window.
     */
    fun toggle(visibleIndex: Int): RankHistoryWindow {
        val index = pageStart + visibleIndex
        if (index !in points.indices) return this
        return copy(selected = if (selected == index) null else index)
    }

    /** One snapshot older (moves the selection when there is one). */
    fun backEntry(): RankHistoryWindow = step(-1)

    /** One snapshot newer. */
    fun forwardEntry(): RankHistoryWindow = step(1)

    /** One window older. */
    fun backPage(): RankHistoryWindow = step(-bars)

    /** One window newer. */
    fun forwardPage(): RankHistoryWindow = step(bars)

    /**
     * Swipe by whole bars (finger right = older, like dragging the chart).
     *
     * @param bars Signed bar count; positive moves to older snapshots.
     * @return Updated window (selection unchanged).
     */
    fun swiped(bars: Int): RankHistoryWindow = copy(offset = (clamped + bars).coerceIn(0, maxOffset))

    private fun step(delta: Int): RankHistoryWindow {
        val current = selected ?: return copy(offset = (clamped - delta).coerceIn(0, maxOffset))
        return navigate(current + delta)
    }

    /** Web `navigatePoint`: select an index and scroll the window to include it. */
    private fun navigate(target: Int): RankHistoryWindow {
        if (points.isEmpty()) return copy(selected = null, offset = 0)
        val index = target.coerceIn(0, points.size - 1)
        val offset = when {
            index in pageStart until pageEnd -> clamped
            index < pageStart -> minOf(points.size - index - bars, maxOffset)
            else -> maxOf(points.size - index - 1, 0)
        }
        return copy(selected = index, offset = offset)
    }

    companion object {
        /** Narrowest bar slot in dp (web uses 96 px beside two axes; phones show a readable handful). */
        const val MIN_BAR_DP = 40f

        /** Gap between bars in dp (web `BAR_GAP`). */
        const val BAR_GAP_DP = 8f

        /**
         * Bars that fit a plot (web `useChartDimensions`).
         *
         * @param plotWidthDp Plot width without axes.
         * @return At least one.
         */
        fun barsFor(plotWidthDp: Float): Int = maxOf(1, floor((plotWidthDp + BAR_GAP_DP) / (MIN_BAR_DP + BAR_GAP_DP)).toInt())
    }
}

// endregion

// region Plot

/**
 * Pixel-free geometry for the visible window: rank line on the web's padded, reversed
 * domain over all snapshots (#1 on top), Total Score bars scaled to the visible maximum.
 *
 * @property bars Bars left to right.
 * @property line Rank points left to right.
 * @property rankTicks Rank axis ticks, best first.
 * @property scoreTicks Score axis ticks, highest first.
 */
data class RankHistoryPlot(
    val bars: List<Bar>,
    val line: List<ChartPoint>,
    val rankTicks: List<ChartTick>,
    val scoreTicks: List<ChartTick>,
) {
    /**
     * One bar.
     *
     * @property bar Unit geometry (x centre, height fraction).
     * @property color Fill `0xRRGGBB` (web `rankColor`).
     * @property selected Whether this snapshot is selected.
     */
    data class Bar(val bar: ChartBar, val color: Int, val selected: Boolean)

    companion object {
        /**
         * Web `getRankHistoryDomain`: ranks ±10% (ceil), best at least 1; `[1, 100]` without ranks.
         *
         * @param ranks Ranks.
         * @return Best and worst.
         */
        fun rankDomain(ranks: List<Int>): Pair<Int, Int> {
            val ranked = ranks.filter { it > 0 }
            if (ranked.isEmpty()) return 1 to 100
            val min = ranked.min()
            val max = ranked.max()
            val pad = ceil((max - min) * 0.1).toInt()
            return maxOf(1, min - pad) to (max + pad).let { if (it == 0) 100 else it }
        }

        /**
         * Build the plot for a window.
         *
         * @param window Window.
         * @param totalAccounts Field size for bar colours (latest known).
         * @param locale Locale for tick labels.
         * @return Geometry.
         */
        fun build(window: RankHistoryWindow, totalAccounts: Int, locale: Locale = Locale.getDefault()): RankHistoryPlot {
            val visible = window.visible
            val (best, worst) = rankDomain(window.points.map { it.totalScoreRank })
            val span = maxOf(1, worst - best).toFloat()
            fun x(i: Int) = if (visible.size == 1) 0.5f else (i + 0.5f) / visible.size
            val maxScore = visible.maxOfOrNull { it.totalScore ?: 0L } ?: 0L
            val bars = visible.mapIndexed { i, s ->
                val height = if (maxScore <= 0) 0f else (s.totalScore ?: 0L).toFloat() / maxScore
                val field = s.rankedAccountCount ?: totalAccounts
                Bar(ChartBar(x(i), height), RankHistoryColors.rank(s.totalScoreRank, field), window.selected == window.pageStart + i)
            }
            val line = visible.mapIndexed { i, s -> ChartPoint(x(i), (s.totalScoreRank - best) / span, window.selected == window.pageStart + i) }
            val step = maxOf(1, ceil((worst - best) / 3.0).toInt())
            val rankTicks = (best..worst step step).map { ChartTick((it - best) / span, ProfileFormatting.rank(it, locale)) }
            val scoreTicks = if (maxScore <= 0) emptyList() else listOf(maxScore, maxScore / 2, 0L).map {
                ChartTick(1f - it.toFloat() / maxScore, ProfileFormatting.compact(it, locale))
            }
            return RankHistoryPlot(bars, line, rankTicks, scoreTicks)
        }

        /**
         * Web `formatRankHistoryDisplayDate` ("Sep 3, 2026").
         *
         * @param snapshot Snapshot.
         * @param locale Locale.
         * @return Label (the raw day when malformed).
         */
        fun displayDate(snapshot: PlayerRankHistorySnapshot, locale: Locale = Locale.getDefault()): String =
            snapshot.date?.format(DateTimeFormatter.ofPattern("MMM d, yyyy", locale)) ?: snapshot.snapshotDate

        /**
         * Web `getRecentRankHistoryPoints`: newest five first.
         *
         * @param points Snapshots, oldest first.
         * @return Up to five, newest first.
         */
        fun recent(points: List<PlayerRankHistorySnapshot>): List<PlayerRankHistorySnapshot> = points.asReversed().take(5)
    }
}

// endregion
