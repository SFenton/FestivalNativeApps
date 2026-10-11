package com.festivalscoretracker.android.ui.rivals

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.core.rivals.HingeColumns
import com.festivalscoretracker.android.ui.common.ProvideFoldLane
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import kotlin.math.roundToInt
import com.festivalscoretracker.android.ui.common.rememberMeasuredBounds
import com.festivalscoretracker.android.ui.common.shellPosture

// region Adaptive card grid

/**
 * Grid cells with precomputed widths (so a column boundary can sit on a hinge).
 *
 * @property spec Column widths and spacing.
 */
internal class SpecCells(private val spec: ColumnSpec) : GridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): List<Int> {
        val total = spec.widths.sum() + spec.spacing * (spec.count - 1)
        if (total == availableSize) return spec.widths
        // Width changed since the spec was measured (one frame): fall back to equal columns.
        val count = spec.count
        val width = (availableSize - spacing * (count - 1)).coerceAtLeast(count) / count
        return List(count) { width }
    }

    override fun equals(other: Any?): Boolean = other is SpecCells && other.spec == spec

    override fun hashCode(): Int = spec.hashCode()
}

/**
 * The row-major card grid for Rivals/Compete (`hinge-columns` R8, #584): 1–[maxColumns]
 * columns of at least [minColumn], or exactly two columns meeting at a separating vertical
 * hinge (book/passport foldables half-open) so no card straddles the fold. Cards fill each
 * line start to end and every card in a line starts at the line's top edge, however far the
 * page scrolls (a masonry grid let the columns drift apart). Only the WindowManager hinge
 * and the grid's own window bounds are used. Full-line items (section headers, messages)
 * belong in `foldLaneItem`: they span every column, and keep their content in the leading
 * pane while split.
 *
 * @param contentPadding Padding inside the scrolling area (top clears the app bar, bottom the nav bar).
 * @param modifier Modifier.
 * @param minColumn Minimum column width.
 * @param maxColumns Upper bound on columns.
 * @param horizontalPadding Side gutter outside the columns.
 * @param state Scroll state.
 * @param testTag Test tag for the grid.
 * @param content Grid items.
 */
@Composable
fun AdaptiveCardGrid(
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
    minColumn: Dp = 360.dp,
    maxColumns: Int = 3,
    horizontalPadding: Dp = 16.dp,
    state: LazyGridState = rememberLazyGridState(),
    testTag: String? = null,
    content: LazyGridScope.() -> Unit,
) {
    val density = LocalDensity.current
    val hinge = shellPosture().hingeList.firstOrNull { it.isSeparating && it.isVertical }
    var bounds by rememberMeasuredBounds()
    val gutter = with(density) { 16.dp.roundToPx() }
    val spec = bounds?.let { (start, width) ->
        HingeColumns.resolve(
            contentStart = start,
            contentWidth = width,
            hingeStart = hinge?.bounds?.left?.roundToInt(),
            hingeEnd = hinge?.bounds?.right?.roundToInt(),
            minColumn = with(density) { minColumn.roundToPx() },
            gutter = gutter,
            maxColumns = maxColumns,
        )
    } ?: ColumnSpec(listOf(0), gutter)
    // One column under TalkBack or at large text (see rememberSingleColumn).
    val singleColumn = rememberSingleColumn()
    val cells = remember(spec, singleColumn) { if (bounds == null || singleColumn) GridCells.Fixed(1) else SpecCells(spec) }
    // Full-line items (foldLaneItem) stay in the leading pane while the columns split at the hinge.
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val leadingPane = if (bounds == null || singleColumn) null else spec.leadingPane(rtl)?.let { with(density) { it.toDp() } }
    ProvideFoldLane(leadingPane) {
        LazyVerticalGrid(
            columns = cells,
            state = state,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(with(density) { spec.spacing.toDp() }),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = modifier
                .fillMaxSize()
                .padding(horizontal = horizontalPadding)
                .onGloballyPositioned { coordinates ->
                    val next = coordinates.positionInWindow().x.roundToInt() to coordinates.size.width
                    if (next != bounds) bounds = next
                }
                .let { if (testTag != null) it.testTag(testTag) else it },
            content = content,
        )
    }
}

// endregion
