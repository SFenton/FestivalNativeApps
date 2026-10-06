package com.festivalscoretracker.android.ui.rivals

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridScope
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.core.rivals.HingeColumns
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import kotlin.math.roundToInt
import com.festivalscoretracker.android.ui.common.rememberMeasuredBounds
import com.festivalscoretracker.android.ui.common.shellPosture

// region Adaptive card grid

/**
 * Staggered cells with precomputed widths (so a column boundary can sit on a hinge).
 *
 * @property spec Column widths and spacing.
 */
private class SpecCells(private val spec: ColumnSpec) : StaggeredGridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): IntArray {
        val total = spec.widths.sum() + spec.spacing * (spec.count - 1)
        if (total == availableSize) return spec.widths.toIntArray()
        // Width changed since the spec was measured (one frame): fall back to equal columns.
        val count = spec.count
        val width = (availableSize - spacing * (count - 1)).coerceAtLeast(count) / count
        return IntArray(count) { width }
    }

    override fun equals(other: Any?): Boolean = other is SpecCells && other.spec == spec

    override fun hashCode(): Int = spec.hashCode()
}

/**
 * A masonry card grid for Rivals/Compete: 1–[maxColumns] columns of at least
 * [minColumn], or exactly two columns meeting at a separating vertical hinge
 * (book/passport foldables half-open) so no card straddles the fold. Only the
 * WindowManager hinge and the grid's own window bounds are used.
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
    state: LazyStaggeredGridState = rememberLazyStaggeredGridState(),
    testTag: String? = null,
    content: LazyStaggeredGridScope.() -> Unit,
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
    val cells = remember(spec, singleColumn) { if (bounds == null || singleColumn) StaggeredGridCells.Fixed(1) else SpecCells(spec) }
    LazyVerticalStaggeredGrid(
        columns = cells,
        state = state,
        contentPadding = contentPadding,
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(with(density) { spec.spacing.toDp() }),
        verticalItemSpacing = 16.dp,
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

// endregion
