package com.festivalscoretracker.android.core.shell

import kotlin.math.ceil
import kotlin.math.floor

// region Chart page motion

/**
 * A paged chart's window: [bands] bars starting at point [start] of [count].
 *
 * @property start First visible point index.
 * @property bands Bars the plot shows at once (its band count).
 * @property count Points in the whole chart.
 */
data class ChartPage(val start: Int, val bands: Int, val count: Int)

/**
 * One point drawn while a paged chart's window slides.
 *
 * @property index Point index into the whole chart.
 * @property x Band centre as a fraction of the plot width (outside 0–1 while it slides in or out).
 */
data class ChartSlot(val index: Int, val x: Float)

/**
 * Pure rules for paging a graph card's chart (`load-transition` R12, issue #593): a pager tap,
 * drag or swipe slides the window to its new start the way iOS `PlayerProfileCharts`
 * `move(to:)` slides its x domain, over the web `CHART_ANIM_DURATION`. A resize or new data
 * re-fits at once (iOS: "the data-change animation is for paging, not for a measurement"), and
 * reduced motion pages at once (R6).
 */
object ChartPageMotion {
    /** Slide length (web `CHART_ANIM_DURATION` 400 ms; Material 3 "Medium 4 | 400ms"). */
    const val SLIDE_MILLIS = 400

    /** How a chart moves from one window to the next. */
    enum class Plan {
        /** Same window: nothing moves. */
        None,

        /** Jump straight to the new window (first draw, resize, new data or reduced motion). */
        Snap,

        /** Slide the window to its new start. */
        Slide,
    }

    /**
     * How to reach [to] from the window last drawn.
     *
     * @param from The window drawn before, or null on the first draw.
     * @param to The new window.
     * @param reduceMotion Remove animations or the in-app Reduce Motion.
     * @return [Plan.Slide] only when the same chart pages to a new start.
     */
    fun plan(from: ChartPage?, to: ChartPage, reduceMotion: Boolean): Plan = when {
        from == to -> Plan.None
        from == null || from.bands != to.bands || from.count != to.count || reduceMotion -> Plan.Snap
        else -> Plan.Slide
    }

    /**
     * The points to draw with the window's first band at [position] (fractional mid-slide).
     * At rest these are exactly the window's points; mid-slide they include the points
     * partly in view and, for a continuous line, one more on each side. The plot clips
     * whatever falls outside it.
     *
     * @param position Fractional start index.
     * @param bands Bars the plot shows at once.
     * @param count Points in the whole chart.
     * @return Slots left to right.
     */
    fun slots(position: Float, bands: Int, count: Int): List<ChartSlot> {
        if (count <= 0 || bands <= 0) return emptyList()
        val resting = position == floor(position)
        val first = if (resting) position.toInt() else floor(position).toInt() - 1
        val last = if (resting) position.toInt() + bands - 1 else ceil(position + bands).toInt()
        return (first.coerceAtLeast(0)..last.coerceAtMost(count - 1)).map { ChartSlot(it, (it - position + 0.5f) / bands) }
    }

    /**
     * How far, in bands, the date row still trails the window it is laid out for. The row
     * places the target window's labels (`chart-date-axis` R1, R5, R6) and shifts them by
     * this much, so each date moves with its bar and settles on it.
     *
     * @param target The window's start once the slide ends.
     * @param position Current fractional start.
     * @return Bands to shift right (negative: left); 0 at rest.
     */
    fun labelShift(target: Int, position: Float): Float = target - position

    /**
     * A value's height as a share of the plot under a sliding axis top: 0 without a top,
     * never above the plot.
     *
     * @param value Value in axis units.
     * @param top Current axis top.
     * @return Height fraction 0–1.
     */
    fun height(value: Double, top: Double): Float = if (top <= 0.0) 0f else (value / top).toFloat().coerceIn(0f, 1f)
}

// endregion
