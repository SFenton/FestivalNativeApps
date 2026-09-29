package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import java.time.ZoneId
import java.time.ZonedDateTime

// region Points

/**
 * One bar of the Song Detail score-history chart (web `ChartPoint`, `hooks/chart/useChartData.ts`).
 *
 * @property dateKey Achieved-or-recorded ISO date (identity with [score]).
 * @property dateLabel Web short label `M/D/YY`.
 * @property score New score.
 * @property accuracyPercent Accuracy 0–100 (history accuracy is in ten-thousandths of a percent).
 * @property isFullCombo Explicit full combo.
 * @property stars Stars, or null.
 * @property season Season, or null.
 * @property difficulty Game difficulty (0 Easy … 3 Expert), or null.
 */
data class SongHistoryPoint(
    val dateKey: String,
    val dateLabel: String,
    val score: Long,
    val accuracyPercent: Double,
    val isFullCombo: Boolean,
    val stars: Int? = null,
    val season: Int? = null,
    val difficulty: Int? = null,
) {
    /** Gold bar: a full combo at 100% (web `isGold`). */
    val isGold: Boolean get() = isFullCombo && accuracyPercent >= 100.0
}

// endregion

// region Chart model

/** Pure data rules for the Song Detail score-history card (web `ScoreHistoryChart` + `GraphCard`). */
object SongHistoryChart {
    /** Web `MIN_BAR_WIDTH`. */
    const val MIN_BAR_DP = 96f

    /** Web `BAR_GAP`. */
    const val BAR_GAP_DP = 8f

    /** Rows listed under the chart (web top five). */
    const val TOP_COUNT = 5

    /**
     * Drop scores over the CHOpt threshold while Filter Invalid Scores is on (web
     * `filterHistory`: `newScore ≤ maxScore × (1 + leeway%)`; unknown maxima keep the row).
     *
     * @param entries History rows.
     * @param song Song (maximum scores).
     * @param leeway Leeway percent, or null when filtering is off.
     * @return Kept rows.
     */
    fun valid(entries: List<ScoreHistoryEntry>, song: Song?, leeway: Double?): List<ScoreHistoryEntry> {
        if (leeway == null) return entries
        return entries.filter { entry ->
            val chart = Instrument.fromWireId(entry.instrument) ?: return@filter true
            val max = InvalidScorePolicy.threshold(song, chart, leeway) ?: return@filter true
            entry.newScore <= max
        }
    }

    /**
     * Rows per chart (web `instrumentCounts`).
     *
     * @param entries History rows.
     * @return Count per chart.
     */
    fun counts(entries: List<ScoreHistoryEntry>): Map<Instrument, Int> =
        entries.mapNotNull { Instrument.fromWireId(it.instrument) }.groupingBy { it }.eachCount()

    /**
     * Charts the selector offers: visible charts with history, in chart order.
     *
     * @param counts Rows per chart.
     * @param visible Settings-visible charts.
     * @return Charts.
     */
    fun available(counts: Map<Instrument, Int>, visible: Set<Instrument>): List<Instrument> =
        Instrument.entries.filter { it in visible && (counts[it] ?: 0) > 0 }

    /**
     * Web auto-select: keep a current chart that has history, else Lead, else the first with history.
     *
     * @param current Current choice, or null.
     * @param available Charts with history.
     * @return Chart, or null without history.
     */
    fun resolve(current: Instrument?, available: List<Instrument>): Instrument? = when {
        current != null && current in available -> current
        Instrument.Lead in available -> Instrument.Lead
        else -> available.firstOrNull()
    }

    /**
     * One chart's points, oldest first, with the web's `M/D/YY` labels in [zone].
     *
     * @param entries History rows.
     * @param instrument Chart.
     * @param zone Display zone.
     * @return Points.
     */
    fun points(entries: List<ScoreHistoryEntry>, instrument: Instrument, zone: ZoneId = ZoneId.systemDefault()): List<SongHistoryPoint> =
        entries.filter { it.instrument == instrument.wireId }
            .mapNotNull { entry -> entry.displayDate?.let { entry to it } }
            .sortedBy { it.second }
            .map { (entry, instant) ->
                val date = ZonedDateTime.ofInstant(instant, zone)
                SongHistoryPoint(
                    dateKey = entry.dateKey,
                    dateLabel = "${date.monthValue}/${date.dayOfMonth}/${date.year.toString().takeLast(2)}",
                    score = entry.newScore,
                    accuracyPercent = ((entry.accuracy ?: 0.0) / ACCURACY_SCALE).coerceIn(0.0, 100.0),
                    isFullCombo = entry.isFullCombo == true,
                    stars = entry.stars,
                    season = entry.season,
                    difficulty = entry.difficulty?.toInt(),
                )
            }

    /**
     * Top scores listed under the chart (web: highest first, five).
     *
     * @param points Points.
     * @return Up to [TOP_COUNT] points.
     */
    fun top(points: List<SongHistoryPoint>): List<SongHistoryPoint> = points.sortedByDescending { it.score }.take(TOP_COUNT)

    /**
     * Bars that fit a plot (web `useChartDimensions`).
     *
     * @param plotWidthDp Plot width without axes.
     * @return At least one bar.
     */
    fun maxBars(plotWidthDp: Float): Int = maxOf(1, ((plotWidthDp + BAR_GAP_DP) / (MIN_BAR_DP + BAR_GAP_DP)).toInt())

    /** History accuracy scale: ten-thousandths of a percent. */
    private const val ACCURACY_SCALE = 10_000.0
}

// endregion

// region Paging

/**
 * Offset paging over the newest-last points with optional point selection (web
 * `useChartPagination`): offset 0 shows the newest page; stepping with a selection
 * moves the selection and follows it across pages.
 *
 * @property size Points.
 * @property maxBars Bars per page.
 * @property offset Points hidden after the page (0 = newest page).
 * @property selected Selected point index, or null.
 */
data class SongHistoryPaging(val size: Int, val maxBars: Int, val offset: Int = 0, val selected: Int? = null) {
    /** Largest useful offset. */
    val maxOffset: Int get() = maxOf(0, size - maxBars)

    private val clamped: Int get() = offset.coerceIn(0, maxOffset)

    /** One past the last visible index. */
    val pageEnd: Int get() = size - clamped

    /** First visible index. */
    val pageStart: Int get() = maxOf(0, pageEnd - maxBars)

    /** Whether paging controls show. */
    val needsPaging: Boolean get() = size > maxBars

    /** Back (older) disabled. */
    val backDisabled: Boolean get() = selected?.let { it <= 0 } ?: (clamped >= maxOffset)

    /** Forward (newer) disabled. */
    val forwardDisabled: Boolean get() = selected?.let { it >= size - 1 } ?: (clamped <= 0)

    /**
     * Toggle a bar's selection.
     *
     * @param index Point index.
     * @return Updated paging.
     */
    fun toggle(index: Int): SongHistoryPaging = copy(selected = if (selected == index) null else index)

    /**
     * Step by [delta] points (±1 entry or ±[maxBars] page): moves the selection when
     * there is one, else the window.
     *
     * @param delta Negative = older.
     * @return Updated paging.
     */
    fun step(delta: Int): SongHistoryPaging {
        if (size == 0) return this
        val current = selected ?: return copy(offset = (clamped - delta).coerceIn(0, maxOffset))
        val target = (current + delta).coerceIn(0, size - 1)
        val nextOffset = when {
            target in pageStart until pageEnd -> clamped
            target < pageStart -> minOf(size - target - maxBars, maxOffset)
            else -> maxOf(size - target - 1, 0)
        }
        return copy(selected = target, offset = nextOffset)
    }

    /**
     * Re-fit after the width or data changes, keeping the newest page anchored.
     *
     * @param size New point count.
     * @param maxBars New bars per page.
     * @return Updated paging.
     */
    fun resized(size: Int, maxBars: Int): SongHistoryPaging =
        SongHistoryPaging(size, maxBars, offset.coerceIn(0, maxOf(0, size - maxBars)), selected?.takeIf { it < size })
}

// endregion
