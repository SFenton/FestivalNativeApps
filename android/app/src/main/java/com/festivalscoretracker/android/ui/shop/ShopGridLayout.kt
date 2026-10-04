package com.festivalscoretracker.android.ui.shop

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

// region Hinge split

/**
 * Shop grid columns split at separating vertical hinges: equal square tiles,
 * no tile across a fold.
 *
 * @property cell Tile width in pixels.
 * @property positions Left edge of each column in pixels, relative to the grid's content area.
 */
internal data class ShopGridSplit(val cell: Int, val positions: List<Int>)

/**
 * Columns for the Shop grid when a separating vertical hinge (book or passport fold
 * half-open, a partly folded tri-fold) crosses it. M3 says never to place interactive
 * content across a hinge. The panels between hinges share one tile size; each panel
 * holds as many tiles as fit, packed against its hinge(s), so tiles mirror across the
 * fold. Hinge bounds come from Jetpack WindowManager, never device names.
 *
 * @param gridStart Content area's left edge in window pixels.
 * @param gridWidth Content area width in pixels.
 * @param hinges Separating vertical hinges as (left, right) window pixels.
 * @param gap Normal gap between tiles in pixels (the minimum gap at a hinge).
 * @param columns Columns the grid would use without hinges.
 * @param minCell Smallest acceptable tile width in pixels.
 * @return The split, or null when no hinge crosses the grid with room for a tile on each side.
 */
internal fun shopGridSplit(
    gridStart: Int,
    gridWidth: Int,
    hinges: List<Pair<Int, Int>>,
    gap: Int,
    columns: Int,
    minCell: Int,
): ShopGridSplit? {
    // Separators (start, end) relative to the content area, left to right.
    val separators = hinges
        .map { (left, right) ->
            val width = max(right - left, 0)
            val spacing = max(width, gap)
            val center = (left + right) / 2 - gridStart
            center - spacing / 2 to center - spacing / 2 + spacing
        }
        .filter { (start, end) -> start >= minCell && end <= gridWidth - minCell }
        .sortedBy { it.first }
    if (separators.isEmpty()) return null
    val panels = buildList {
        var start = 0
        separators.forEach { (left, right) ->
            add(start to left)
            start = right
        }
        add(start to gridWidth)
    }
    if (panels.any { (start, end) -> end - start < minCell }) return null
    val narrowest = panels.minOf { (start, end) -> end - start }
    var perPanel = max(1, (columns + panels.size - 1) / panels.size)
    fun cellFor(count: Int) = (narrowest - gap * (count - 1)) / count
    while (perPanel > 1 && cellFor(perPanel) < minCell) perPanel--
    val cell = cellFor(perPanel)
    val positions = panels.flatMapIndexed { index, (start, end) ->
        val count = max(1, (end - start + gap) / (cell + gap))
        val used = count * cell + (count - 1) * gap
        // Pack against the hinge: first panel right, last panel left, middle panels centred.
        val first = when (index) {
            0 -> end - used
            panels.lastIndex -> start
            else -> start + (end - start - used) / 2
        }
        List(count) { first + it * (cell + gap) }
    }
    return ShopGridSplit(cell, positions)
}

// endregion

// region Grid cells and arrangement

/**
 * Equal [ShopGridSplit.cell] tiles for each split column, or [fallback] equal columns
 * for one frame while the measured width differs from the split's.
 *
 * @property split Hinge split.
 * @property width Content width the split was computed for, in pixels.
 * @property fallback Columns without the split.
 */
internal class ShopSplitCells(private val split: ShopGridSplit, private val width: Int, private val fallback: Int) : GridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): List<Int> {
        if (availableSize == width) return List(split.positions.size) { split.cell }
        val cell = (availableSize - spacing * (fallback - 1)).coerceAtLeast(fallback) / fallback
        return List(fallback) { cell }
    }

    override fun equals(other: Any?): Boolean = other is ShopSplitCells && other.split == split && other.width == width && other.fallback == fallback

    override fun hashCode(): Int = 31 * (31 * split.hashCode() + width) + fallback
}

/**
 * Places split columns at [ShopGridSplit.positions] (mirrored in right-to-left order);
 * any other line uses plain [gap] spacing.
 *
 * @property split Hinge split.
 * @property gap Normal spacing.
 */
internal class ShopSplitArrangement(private val split: ShopGridSplit, private val gap: Dp) : Arrangement.Horizontal {
    override val spacing: Dp = gap

    override fun Density.arrange(totalSize: Int, sizes: IntArray, layoutDirection: LayoutDirection, outPositions: IntArray) {
        if (sizes.size != split.positions.size) {
            with(Arrangement.spacedBy(gap)) { arrange(totalSize, sizes, layoutDirection, outPositions) }
            return
        }
        val last = split.positions.lastIndex
        sizes.indices.forEach { index ->
            val position = if (layoutDirection == LayoutDirection.Rtl) split.positions[last - index] else split.positions[index]
            outPositions[index] = min(position, max(totalSize - sizes[index], 0))
        }
    }
}

// endregion

// region Card text

/**
 * Height caps for a grid card's title and artist. Large text wraps inside the fixed
 * square tile, so without caps a long title pushes the artist past the tile's bottom
 * edge. The title gets about two thirds of the room and the artist the rest, each at
 * least one line; both then end in an ellipsis instead of clipping.
 *
 * @param tile Tile height.
 * @param titleLine One title line.
 * @param artistLine One artist line.
 * @param badge Whether a large-text Leaving Tomorrow pill takes the tile's top.
 * @return Title and artist maximum heights.
 */
internal fun shopCardTextHeights(tile: Dp, titleLine: Dp, artistLine: Dp, badge: Boolean): Pair<Dp, Dp> {
    // Scrim padding (10 dp top and bottom) and the 2 dp gap; the pill is ~36 dp at 2x plus its 10 dp inset.
    val room = tile - 22.dp - if (badge) 56.dp else 0.dp
    val artist = maxOf(room / 3, artistLine)
    val title = maxOf(room - artist, titleLine)
    return title to artist
}

// endregion
