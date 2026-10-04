package com.festivalscoretracker.android.core.shop

import kotlin.math.max
import kotlin.math.roundToInt

// region Hinge-aware Shop columns

/**
 * Cross-axis cells of the Item Shop grid or list.
 *
 * @property sizes Cell widths in pixels, left to right.
 * @property positions Cell left edges in pixels, relative to the content's left edge.
 * @property startPaneColumns Cells on the leading side of a separating hinge (all cells without one).
 */
data class ShopColumns(val sizes: List<Int>, val positions: List<Int>, val startPaneColumns: Int) {
    /** Number of cells per row. */
    val count: Int get() = sizes.size

    /** True when a separating hinge splits the rows into two panes. */
    val split: Boolean get() = startPaneColumns < count
}

/**
 * Pure column policy for the Item Shop (`fst.songs.shop`): the web's width-based column
 * count, extended for book/passport foldables half-open. When a separating vertical hinge
 * crosses the content, each row splits at the hinge into a leading and a trailing pane with
 * their own column counts, so no card or row straddles the fold (Material 3: "Never place
 * interactive content or critical information across the hinge area"). Reading order stays
 * row by row, leading pane first. Device names and pixel heuristics never participate; the
 * hinge comes from Jetpack WindowManager.
 */
object ShopColumnPolicy {
    /**
     * Web grid columns (`ShopPage`): 5 from 1100, 4 from 860, 3 from 600 CSS px, else 2.
     *
     * @param widthDp Content (or pane) width in dp.
     * @return Columns.
     */
    fun gridColumns(widthDp: Float): Int = when {
        widthDp >= 1100f -> 5
        widthDp >= 860f -> 4
        widthDp >= 600f -> 3
        else -> 2
    }

    /**
     * Resolve the cells of one row.
     *
     * @param available Content width in pixels (inside the side padding).
     * @param gutter Normal gap between cells in pixels.
     * @param hingeStart Separating vertical hinge left edge relative to the content's left edge, or null.
     * @param hingeEnd Hinge right edge relative to the content's left edge (equal to [hingeStart] for a zero-width fold).
     * @param minPane Smallest pane in pixels worth splitting for; a hinge leaving less on either side is ignored.
     * @param uniform Give every cell the narrower pane's cell width (square grid cards stay one size across the fold).
     * @param columnsFor Cells for a pane (or the whole content) of the given pixel width; at least one.
     * @return Cell sizes and positions.
     */
    fun resolve(
        available: Int,
        gutter: Int,
        hingeStart: Int?,
        hingeEnd: Int?,
        minPane: Int,
        uniform: Boolean = false,
        columnsFor: (Int) -> Int,
    ): ShopColumns {
        val width = max(available, 1)
        if (hingeStart != null && hingeEnd != null && hingeEnd >= hingeStart) {
            val gap = max(hingeEnd - hingeStart, gutter)
            val left = ((hingeStart + hingeEnd) / 2.0 - gap / 2.0).roundToInt()
            val rightStart = left + gap
            val right = width - rightStart
            if (left >= minPane && right >= minPane) {
                var leading = pane(left, gutter, columnsFor(left), 0)
                var trailing = pane(right, gutter, columnsFor(right), rightStart)
                if (uniform) {
                    val cell = minOf(leading.first.min(), trailing.first.min())
                    leading = fixed(leading.first.size, cell, gutter, 0)
                    trailing = fixed(trailing.first.size, cell, gutter, rightStart)
                }
                return ShopColumns(leading.first + trailing.first, leading.second + trailing.second, leading.first.size)
            }
        }
        val (sizes, positions) = pane(width, gutter, columnsFor(width), 0)
        return ShopColumns(sizes, positions, sizes.size)
    }

    private fun fixed(count: Int, cell: Int, gutter: Int, offset: Int): Pair<List<Int>, List<Int>> =
        List(count) { cell } to List(count) { index -> offset + index * (cell + gutter) }

    private fun pane(width: Int, gutter: Int, columns: Int, offset: Int): Pair<List<Int>, List<Int>> {
        val count = columns.coerceIn(1, max(1, (width + gutter) / (gutter + 1)))
        val cell = max((width - gutter * (count - 1)) / count, 1)
        val remainder = max(width - gutter * (count - 1) - cell * count, 0)
        val sizes = List(count) { index -> cell + if (index < remainder) 1 else 0 }
        var x = offset
        val positions = sizes.map { size -> x.also { x += size + gutter } }
        return sizes to positions
    }
}

// endregion
