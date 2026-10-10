package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.layout.WideColumnLines
import com.festivalscoretracker.android.core.layout.WideColumns
import com.festivalscoretracker.android.core.rivals.HingeColumns
import kotlin.math.roundToInt

// region Wide columns

/**
 * A page list's resolved `wide-columns` layout.
 *
 * @property columns 1 or 2.
 * @property widths Cell widths from the start edge to the end edge.
 * @property spacing Gap between cells (the hinge's width when the columns meet at a fold).
 * @property leadingPane The leading column's width while split at a separating hinge, for
 *   [ProvideFoldLane] (full-line items stay on their side of the fold), else null.
 */
@Immutable
data class WideColumnsLayout(val columns: Int, val widths: List<Dp>, val spacing: Dp, val leadingPane: Dp?)

/**
 * Resolves [WideColumns] for a full-width page list from the window (size, Jetpack
 * WindowManager fold via [shellPosture]) and the list's own measured bounds. One column under
 * TalkBack or at large text ([rememberSingleColumn]).
 *
 * @param listWidth The list's width, side padding included.
 * @param listLeftPx The list's left edge in window pixels.
 * @param startPadding The list's start content padding.
 * @param endPadding The list's end content padding.
 * @return The layout for this composition.
 */
@Composable
fun rememberWideColumns(listWidth: Dp, listLeftPx: Int, startPadding: Dp, endPadding: Dp): WideColumnsLayout {
    val density = LocalDensity.current
    val window = currentWindowSize()
    val singleColumn = rememberSingleColumn()
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val folds = shellPosture().hingeList.filter { it.isVertical }
    return with(density) {
        val leftPad = (if (rtl) endPadding else startPadding).roundToPx()
        val rightPad = (if (rtl) startPadding else endPadding).roundToPx()
        val contentStart = listLeftPx + leftPad
        val contentWidth = (listWidth.roundToPx() - leftPad - rightPad).coerceAtLeast(1)
        val minColumn = WideColumns.MIN_COLUMN_DP.dp.roundToPx()
        val gutter = WideColumns.SPACING_DP.dp.roundToPx()
        // Book posture: a separating fold that leaves room for a column on each side.
        val hinge = folds.firstOrNull { fold ->
            fold.isSeparating && HingeColumns.resolve(
                contentStart, contentWidth, fold.bounds.left.roundToInt(), fold.bounds.right.roundToInt(), minColumn, gutter, maxColumns = 2,
            ).split
        }
        val columns = WideColumns.count(
            windowWidthDp = window.width.toDp().value,
            windowHeightDp = window.height.toDp().value,
            contentWidthDp = contentWidth.toDp().value,
            unfolded = folds.isNotEmpty(),
            bookSplit = hinge != null,
            singleColumn = singleColumn,
        )
        val spec = WideColumns.spec(
            columns, contentStart, contentWidth, hinge?.bounds?.left?.roundToInt(), hinge?.bounds?.right?.roundToInt(), minColumn, gutter,
        )
        val widths = spec.widths.map { it.toDp() }
        WideColumnsLayout(spec.count, if (rtl) widths.reversed() else widths, spec.spacing.toDp(), spec.leadingPane(rtl)?.toDp())
    }
}

/**
 * One row-major line of a wide-columns list: its cells side by side at [layout]'s widths (a
 * short last line keeps its cell at column width). Each cell is sized by its own box, so a
 * full-width row component works unchanged. The line is one traversal group, so TalkBack
 * reads its start cell, then its end cell, then the next line.
 *
 * @param count Cells in this line.
 * @param layout The list's layout.
 * @param modifier Modifier for the line.
 * @param cell Draws cell `index`, filling its column.
 */
@Composable
fun WideColumnsLine(count: Int, layout: WideColumnsLayout, modifier: Modifier = Modifier, cell: @Composable (index: Int) -> Unit) {
    Row(modifier.fillMaxWidth().semantics { isTraversalGroup = true }, horizontalArrangement = Arrangement.spacedBy(layout.spacing)) {
        layout.widths.forEachIndexed { index, width ->
            if (index < count) Box(Modifier.width(width)) { cell(index) } else Spacer(Modifier.width(width))
        }
    }
}

/**
 * Keeps the reader's place when the list's lines change shape (rotating, folding, TalkBack or
 * text size flipping the column count): the first visible header or row stays first, at the
 * same offset. Lazy keys alone keep it only from two columns to one (a line's key is its first
 * row's), not from one to two.
 *
 * @param listState The list's state.
 * @param lines The current lines.
 */
@Composable
fun KeepPlaceAcrossColumnChanges(listState: LazyListState, lines: WideColumnLines) {
    val place = remember(listState) { ReaderPlace() }
    LaunchedEffect(lines) {
        val before = place.lines
        if (before != null && before.columns != lines.columns && before.rowCount == lines.rowCount) {
            listState.scrollToItem(before.reflow(place.index, lines), place.offset)
        }
        place.lines = lines
        snapshotFlow { listState.firstVisibleItemIndex to listState.firstVisibleItemScrollOffset }.collect { (index, offset) ->
            place.index = index
            place.offset = offset
        }
    }
}

/** The first visible item, in the lines it was observed in. */
private class ReaderPlace {
    var lines: WideColumnLines? = null
    var index = 0
    var offset = 0
}

// endregion
