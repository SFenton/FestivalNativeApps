package com.festivalscoretracker.android.core.profile

// region Stat tile spans

/**
 * Where one tile sits in a stat-tile grid (pattern `stat-tile-grid`).
 *
 * @property index The tile's position in the source (web) order.
 * @property row Grid row, from 0.
 * @property column First column the tile covers, from 0.
 * @property span Columns the tile covers (1 or more).
 */
data class StatTilePlacement(val index: Int, val row: Int, val column: Int, val span: Int)

/**
 * Span and packing rules for stat-tile grids (pattern `stat-tile-grid` R1–R3; owner, #591):
 * a tile whose one-line text would not fit one slot takes two, so its title stays on one
 * line and every tile keeps the grid's height. Tiles keep their source order.
 */
object StatTileSpans {
    /** Most slots one tile takes; text that doesn't fit two wraps (R1). */
    const val MAX_SPAN = 2

    /** Rounding slack in px, so text that measures exactly the slot width still fits. */
    private const val FIT_SLACK = 0.5f

    /**
     * Slots a tile takes.
     *
     * @param textWidth The tile's widest text, measured on one line (px).
     * @param slotTextWidth Text width inside a one-slot tile (px).
     * @param columns Grid columns.
     * @return 1 when the text fits one slot or the grid has one column, else [MAX_SPAN]
     *   (capped at [columns]).
     */
    fun span(textWidth: Float, slotTextWidth: Float, columns: Int): Int =
        if (columns < 2 || textWidth <= slotTextWidth + FIT_SLACK) 1 else MAX_SPAN.coerceAtMost(columns)

    /**
     * Text width inside a tile covering [span] slots.
     *
     * @param slotWidth One slot's width (px).
     * @param spacing Gap between slots (px).
     * @param inset The tile's horizontal padding, both sides together (px).
     * @param span Slots covered.
     * @return Width left for text (px, never negative).
     */
    fun textWidth(slotWidth: Float, spacing: Float, inset: Float, span: Int): Float =
        (slotWidth * span + spacing * (span - 1) - inset).coerceAtLeast(0f)

    /**
     * Places tiles row by row in source order (R2). A tile that doesn't fit the slots left
     * in its row starts the next row, and the row's last tile widens to the row's end, so
     * no row before the last has a hole. The last row keeps its trailing empty slots.
     *
     * @param spans Each tile's span, in source order.
     * @param columns Grid columns (at least 1).
     * @return One placement per tile, in reading order (row-major, which is source order).
     */
    fun pack(spans: List<Int>, columns: Int): List<StatTilePlacement> {
        val cols = columns.coerceAtLeast(1)
        val out = ArrayList<StatTilePlacement>(spans.size)
        var row = 0
        var column = 0
        spans.forEachIndexed { index, raw ->
            val span = raw.coerceIn(1, cols)
            if (column + span > cols) {
                widenLast(out, cols)
                row++
                column = 0
            }
            out += StatTilePlacement(index, row, column, span)
            column += span
            if (column == cols) {
                row++
                column = 0
            }
        }
        return out
    }

    /**
     * Rows a packing takes.
     *
     * @param placements From [pack].
     * @return Row count (0 when empty).
     */
    fun rows(placements: List<StatTilePlacement>): Int = placements.maxOfOrNull { it.row + 1 } ?: 0

    /** Widens the last placed tile to its row's end. */
    private fun widenLast(out: MutableList<StatTilePlacement>, columns: Int) {
        val last = out.lastOrNull() ?: return
        out[out.lastIndex] = last.copy(span = columns - last.column)
    }
}

// endregion
