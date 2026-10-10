package com.festivalscoretracker.android.core.layout

import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.core.rivals.HingeColumns

// region Wide columns

/**
 * Android's `wide-columns` policy (pattern `wide-columns`, Apple `WideColumns`): whether a
 * full-width page list lays its rows in two row-major columns. Songs adopted it first
 * (#581, owner: "two-col in landscape and unfolded like iPhone Duo").
 *
 * Two columns when the content holds two [MIN_COLUMN_DP] columns and the window is wider
 * than tall (landscape phones and tablets) or spans a vertical fold (an unfolded foldable,
 * flat or half-open), and always across a separating vertical hinge (book posture), where
 * the columns meet at the fold ([spec]). Portrait and compact windows keep one column, and
 * so does every window while a screen reader runs or at large text
 * (`rememberSingleColumn`). Unlike Apple's R1 there is no height-class requirement: the
 * owner asked for landscape phones too.
 */
object WideColumns {
    /** Gap between the two cells of a row (Apple `WideColumns.spacing`). */
    const val SPACING_DP = 12

    /** Narrowest column worth splitting into (Apple `WideColumns.minimumColumnWidth`). */
    const val MIN_COLUMN_DP = 320

    /** Narrowest content width (inside the list's side padding) that holds two columns. */
    const val MIN_TWO_COLUMN_DP = MIN_COLUMN_DP * 2 + SPACING_DP

    /**
     * Columns for a page list.
     *
     * Landscape comes from the window, never from the list's own frame (Apple R1: the
     * keyboard must not flip a shortened portrait page to two columns).
     *
     * @param windowWidthDp Window width.
     * @param windowHeightDp Window height.
     * @param contentWidthDp The list's content width (inside its side padding).
     * @param unfolded The window spans a vertical fold (flat or half-open).
     * @param bookSplit A separating vertical hinge crosses the list (book posture).
     * @param singleColumn Screen reader or large text (`rememberSingleColumn`).
     * @return 1 or 2.
     */
    fun count(
        windowWidthDp: Float,
        windowHeightDp: Float,
        contentWidthDp: Float,
        unfolded: Boolean,
        bookSplit: Boolean,
        singleColumn: Boolean,
    ): Int = when {
        singleColumn -> 1
        bookSplit -> 2
        (windowWidthDp > windowHeightDp || unfolded) && contentWidthDp >= MIN_TWO_COLUMN_DP -> 2
        else -> 1
    }

    /**
     * Column widths for [columns]: two meeting at a separating hinge when it leaves room on
     * each side (`hinge-columns` R1), else equal halves split at the content midpoint
     * (`hinge-columns` R7), through the shared [HingeColumns] policy.
     *
     * @param columns [count]'s result.
     * @param contentStart Content's left edge in window pixels.
     * @param contentWidth Content width in pixels.
     * @param hingeStart Separating vertical hinge left edge in window pixels, or null.
     * @param hingeEnd Hinge right edge in window pixels, or null.
     * @param minColumn [MIN_COLUMN_DP] in pixels.
     * @param gutter [SPACING_DP] in pixels.
     * @return Widths (left to right) and spacing; one column when [columns] is 1.
     */
    fun spec(columns: Int, contentStart: Int, contentWidth: Int, hingeStart: Int?, hingeEnd: Int?, minColumn: Int, gutter: Int): ColumnSpec {
        if (columns <= 1) return ColumnSpec(listOf(contentWidth.coerceAtLeast(1)), gutter)
        val split = HingeColumns.resolve(contentStart, contentWidth, hingeStart, hingeEnd, minColumn, gutter, maxColumns = 2)
        if (split.count == 2) return split
        // A book hinge too close to an edge for a column on each side: split at the content midpoint.
        val left = ((contentWidth - gutter) / 2).coerceAtLeast(0)
        return ColumnSpec(listOf(left, (contentWidth - gutter - left).coerceAtLeast(0)), gutter)
    }
}

/** One line of a wide-columns list: a full-width header or a row of up to `columns` cells. */
sealed interface WideLine {
    /**
     * A section header spanning every column (`wide-columns` R2).
     *
     * @property ordinal The header's index among the list's headers.
     */
    data class Header(val ordinal: Int) : WideLine

    /**
     * Consecutive rows [start] until [end] (exclusive), in row-major order.
     *
     * @property start First row index.
     * @property end Row index after the last.
     */
    data class Cells(val start: Int, val end: Int) : WideLine
}

/**
 * The lines of a list of rows laid out in [columns] row-major columns, with the list index
 * of every row, header and line, so Quick Links, the section index and scroll anchoring
 * address the same items in one or two columns. Rows chunk within each group (a header's
 * rows, or a section-index section), so every section starts a line and a jump lands on
 * its first row in the leading column.
 *
 * @property lines Lines in order.
 * @property leading List items before the first line (notices, the empty state).
 * @property columns Cells per line.
 */
class WideColumnLines private constructor(
    val lines: List<WideLine>,
    val leading: Int,
    val columns: Int,
    private val lineOfRow: IntArray,
    private val lineOfHeader: IntArray,
) {
    /** Number of rows. */
    val rowCount: Int get() = lineOfRow.size

    /**
     * List index of the line holding [row].
     *
     * @param row Row index.
     * @return The item index; [leading] for an unknown row.
     */
    fun itemOfRow(row: Int): Int = leading + (lineOfRow.getOrNull(row) ?: 0)

    /**
     * List index of header [ordinal].
     *
     * @param ordinal Header index.
     * @return The item index, or null for an unknown header.
     */
    fun itemOfHeader(ordinal: Int): Int? = lineOfHeader.getOrNull(ordinal)?.let { leading + it }

    /**
     * The row a list item stands for: a line's first row, the first row below a header,
     * row 0 for the leading items and the last row past the end.
     *
     * @param item List item index.
     * @return Row index (0 for a list without rows).
     */
    fun firstRowOfItem(item: Int): Int {
        val last = (lineOfRow.size - 1).coerceAtLeast(0)
        if (item < leading) return 0
        val from = item - leading
        if (from >= lines.size) return last
        for (index in from until lines.size) {
            val line = lines[index]
            if (line is WideLine.Cells) return line.start
        }
        return last
    }

    /**
     * Where list item [item] lands in [to] after a reflow (rotation, folding, a TalkBack or
     * text-size change): the same header, the line holding the same first row, or the same
     * leading item, so the reader keeps their place.
     *
     * @param item List index in these lines.
     * @param to The new lines.
     * @return List index in [to].
     */
    fun reflow(item: Int, to: WideColumnLines): Int {
        if (item < leading) return item.coerceAtMost(to.leading + to.lines.size - 1).coerceAtLeast(0)
        return when (val line = lines.getOrNull(item - leading)) {
            is WideLine.Header -> to.itemOfHeader(line.ordinal) ?: to.itemOfRow(firstRowOfItem(item))
            is WideLine.Cells -> to.itemOfRow(line.start)
            null -> (to.leading + to.lines.size - 1).coerceAtLeast(0)
        }
    }

    companion object {
        /**
         * Builds the lines.
         *
         * @param rowCount Number of rows.
         * @param headerStarts First row of each header, ascending (empty without headers).
         * @param breaks Further rows that start a line without a header (section-index sections).
         * @param columns Cells per line (at least 1).
         * @param leading List items before the first line.
         * @return The lines.
         */
        fun build(rowCount: Int, headerStarts: List<Int>, breaks: List<Int>, columns: Int, leading: Int): WideColumnLines {
            val perLine = columns.coerceAtLeast(1)
            val lines = ArrayList<WideLine>()
            val lineOfRow = IntArray(rowCount.coerceAtLeast(0))
            val lineOfHeader = IntArray(headerStarts.size)
            val starts = (headerStarts + breaks).filter { it in 0 until rowCount }.toSortedSet()
            var header = 0
            var row = 0
            while (true) {
                while (header < headerStarts.size && (headerStarts[header] <= row || row >= rowCount)) {
                    lineOfHeader[header] = lines.size
                    lines += WideLine.Header(header)
                    header++
                }
                if (row >= rowCount) break
                val groupEnd = starts.tailSet(row + 1).firstOrNull() ?: rowCount
                val end = minOf(row + perLine, groupEnd)
                for (index in row until end) lineOfRow[index] = lines.size
                lines += WideLine.Cells(row, end)
                row = end
            }
            return WideColumnLines(lines, leading, perLine, lineOfRow, lineOfHeader)
        }
    }
}

// endregion
