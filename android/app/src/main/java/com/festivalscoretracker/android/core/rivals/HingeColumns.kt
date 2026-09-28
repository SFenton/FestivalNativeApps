package com.festivalscoretracker.android.core.rivals

import kotlin.math.max
import kotlin.math.roundToInt

// region Hinge-aware columns

/**
 * Column widths for a card grid (hub sections, rival categories, long rival lists).
 *
 * @property widths Column widths in pixels, left to right.
 * @property spacing Gap between columns in pixels (the hinge width when split at a fold).
 */
data class ColumnSpec(val widths: List<Int>, val spacing: Int) {
    /** Number of columns. */
    val count: Int get() = widths.size
}

/**
 * Pure column policy (Windows `MasonryLayout`: minimum column width, 1–[maxColumns]
 * columns), extended for foldables: when a separating vertical hinge crosses the
 * content, exactly two columns meet at the hinge so no card straddles the fold
 * (Material guidance for book/passport foldables). Device names or pixel heuristics
 * never participate; the hinge comes from Jetpack WindowManager.
 */
object HingeColumns {
    /**
     * Resolve columns for the content's current window bounds.
     *
     * @param contentStart Content's left edge in window pixels.
     * @param contentWidth Content width in pixels.
     * @param hingeStart Separating vertical hinge left edge in window pixels, or null.
     * @param hingeEnd Hinge right edge in window pixels (equal to [hingeStart] for a zero-width fold).
     * @param minColumn Minimum column width in pixels.
     * @param gutter Normal gap between columns in pixels.
     * @param maxColumns Upper bound on columns.
     * @return Column widths and spacing (always at least one column).
     */
    fun resolve(
        contentStart: Int,
        contentWidth: Int,
        hingeStart: Int?,
        hingeEnd: Int?,
        minColumn: Int,
        gutter: Int,
        maxColumns: Int,
    ): ColumnSpec {
        val width = max(contentWidth, 1)
        if (hingeStart != null && hingeEnd != null) {
            val hingeWidth = max(hingeEnd - hingeStart, 0)
            val spacing = max(hingeWidth, gutter)
            val center = (hingeStart + hingeEnd) / 2.0 - contentStart
            val left = (center - spacing / 2.0).roundToInt()
            val right = width - left - spacing
            // Only split when the fold crosses the content with room for a column on each side.
            if (left >= minColumn / 2 && right >= minColumn / 2) return ColumnSpec(listOf(left, right), spacing)
        }
        val count = ((width + gutter) / (minColumn + gutter)).coerceIn(1, max(maxColumns, 1))
        val columnWidth = (width - gutter * (count - 1)) / count
        val remainder = width - gutter * (count - 1) - columnWidth * count
        return ColumnSpec(List(count) { index -> columnWidth + if (index < remainder) 1 else 0 }, gutter)
    }
}

// endregion
