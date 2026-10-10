package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.StatGridColumns
import com.festivalscoretracker.android.core.profile.StatTilePlacement
import com.festivalscoretracker.android.core.profile.StatTileSpans
import kotlin.math.roundToInt

// region Stat tile grid

/**
 * One line of a tile's text, in the exact style the tile draws it, so the grid can tell
 * whether it fits one slot.
 *
 * @property text Text as drawn (already uppercased if the tile uppercases it).
 * @property style Drawn style, including weight and letter spacing.
 */
@Immutable
data class StatTileText(val text: String, val style: TextStyle)

/**
 * The one stat-tile grid (pattern `stat-tile-grid`): equal-width columns, a tile whose
 * text would wrap in one slot spans two so it stays on one line (owner, #591), and every
 * tile in the grid takes the tallest tile's height. Tiles keep their source order, which
 * is also TalkBack's reading order ([StatTileSpans.pack]). Text that doesn't fit even two
 * slots (accessibility font sizes) wraps; tiles never truncate it.
 *
 * Profile Statistics, Band Detail and the Statistics first-run demos all use it; they only
 * supply their column rule, their tile, the text it draws and its horizontal padding.
 *
 * @param items Tiles in source (web) order.
 * @param columns Column count for the grid's width in dp.
 * @param texts The texts [tile] draws on one line each, in their drawn styles.
 * @param inset The tile's horizontal padding around its text, both sides together.
 * @param modifier Modifier.
 * @param spacing Gap between tiles, both axes.
 * @param maxRows Rows to show; later tiles are left out (first-run demos fit the stage).
 * @param tile One tile; apply the given modifier, which carries nothing the tile must keep.
 */
@Composable
internal fun <T> StatTileGrid(
    items: List<T>,
    columns: (widthDp: Float) -> Int,
    texts: (T) -> List<StatTileText>,
    inset: Dp,
    modifier: Modifier = Modifier,
    spacing: Dp = StatGridColumns.SPACING_DP.dp,
    maxRows: Int = Int.MAX_VALUE,
    tile: @Composable (item: T, index: Int, modifier: Modifier) -> Unit,
) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val count = columns(maxWidth.value).coerceAtLeast(1)
        val density = LocalDensity.current
        val fonts = LocalFontFamilyResolver.current
        val measurer = rememberTextMeasurer()
        val widthPx = constraints.maxWidth.toFloat()
        val gapPx = with(density) { spacing.toPx() }
        val insetPx = with(density) { inset.toPx() }
        val slotPx = (widthPx - gapPx * (count - 1)) / count
        val placements = remember(items, count, slotPx, gapPx, insetPx, density, fonts, maxRows) {
            val slotText = StatTileSpans.textWidth(slotPx, gapPx, insetPx, span = 1)
            val spans = items.map { item ->
                val widest = texts(item).maxOfOrNull { line ->
                    measurer.measure(AnnotatedString(line.text), line.style, maxLines = 1, softWrap = false).size.width.toFloat()
                } ?: 0f
                StatTileSpans.span(widest, slotText, count)
            }
            StatTileSpans.pack(spans, count).filter { it.row < maxRows }
        }
        StatTileGridLayout(placements, count, gapPx) {
            placements.forEach { placement -> tile(items[placement.index], placement.index, Modifier) }
        }
    }
}

/**
 * Places [placements]' tiles (one child each, in order) on [columns] equal columns, every
 * tile as tall as the tallest one at its width.
 */
@Composable
private fun StatTileGridLayout(placements: List<StatTilePlacement>, columns: Int, gapPx: Float, content: @Composable () -> Unit) {
    Layout(content) { measurables, constraints ->
        val width = constraints.maxWidth
        val slot = (width - gapPx * (columns - 1)) / columns
        fun start(column: Int) = (column * (slot + gapPx)).roundToInt()
        fun end(column: Int) = (column * (slot + gapPx) + slot).roundToInt()
        val widths = placements.map { end(it.column + it.span - 1) - start(it.column) }
        val height = measurables.zip(widths).maxOfOrNull { (child, w) -> child.minIntrinsicHeight(w) } ?: 0
        val placeables = measurables.zip(widths).map { (child, w) -> child.measure(Constraints.fixed(w, height)) }
        val rows = StatTileSpans.rows(placements)
        val total = if (rows == 0) 0 else rows * height + ((rows - 1) * gapPx).roundToInt()
        layout(width, total) {
            placeables.zip(placements).forEach { (placeable, p) ->
                placeable.place(start(p.column), (p.row * (height + gapPx)).roundToInt())
            }
        }
    }
}

// endregion
