package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridScope
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
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
import com.festivalscoretracker.android.core.profile.ProfileColumns
import com.festivalscoretracker.android.core.profile.ProfileGridSpec
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.ui.common.rememberScreenReaderOn
import kotlin.math.roundToInt

// region Fold-aware grid

/**
 * Staggered cells with precomputed widths, so column gaps can sit on hinges.
 *
 * @property spec Column widths and spacing.
 */
private class ProfileCells(private val spec: ColumnSpec) : StaggeredGridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): IntArray {
        val total = spec.widths.sum() + spec.spacing * (spec.count - 1)
        if (total == availableSize) return spec.widths.toIntArray()
        // The width changed since the spec was measured (one frame): equal columns until re-measured.
        val count = spec.count
        val width = (availableSize - spacing * (count - 1)).coerceAtLeast(count) / count
        return IntArray(count) { width }
    }

    override fun equals(other: Any?): Boolean = other is ProfileCells && other.spec == spec

    override fun hashCode(): Int = spec.hashCode()
}

/**
 * The player page's masonry grid: columns of at least [minColumn] (up to [maxColumns]),
 * or one column per panel with the gaps on every separating vertical hinge
 * (book fold half-open, a partly folded tri-fold), so no card straddles a fold. The
 * hinges come from Jetpack WindowManager; device names never participate.
 *
 * @param state Scroll state (shared with Quick Links).
 * @param contentPadding Padding inside the scrolling area.
 * @param modifier Modifier (horizontal page padding belongs here, outside the columns).
 * @param minColumn Minimum column width.
 * @param maxColumns Upper bound on columns without hinges.
 * @param content Items; the argument is true when columns are split at a fold, so full-width rows must stay in one lane.
 */
@Composable
fun ProfileGrid(
    state: LazyStaggeredGridState,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
    minColumn: Dp = 340.dp,
    maxColumns: Int = 3,
    content: LazyStaggeredGridScope.(splitAtFold: Boolean) -> Unit,
) {
    val density = LocalDensity.current
    val hinges = currentWindowAdaptiveInfo().windowPosture.hingeList
        .filter { it.isSeparating && it.isVertical }
        .map { it.bounds.left.roundToInt() to it.bounds.right.roundToInt() }
    var bounds by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    val gutter = with(density) { 16.dp.roundToPx() }
    val grid = bounds?.let { (start, width) ->
        ProfileColumns.resolve(start, width, hinges, with(density) { minColumn.roundToPx() }, gutter, maxColumns)
    } ?: ProfileGridSpec(ColumnSpec(listOf(0), gutter), splitAtFold = false)
    // One column under TalkBack (see rememberScreenReaderOn): no side-by-side cards to skip.
    val screenReader = rememberScreenReaderOn()
    val cells = remember(grid.spec, bounds == null, screenReader) { if (bounds == null || screenReader) StaggeredGridCells.Fixed(1) else ProfileCells(grid.spec) }
    LazyVerticalStaggeredGrid(
        columns = cells,
        state = state,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(with(density) { grid.spec.spacing.toDp() }),
        verticalItemSpacing = 16.dp,
        modifier = modifier
            .fillMaxSize()
            .onGloballyPositioned { coordinates ->
                val next = coordinates.positionInWindow().x.roundToInt() to coordinates.size.width
                if (next != bounds) bounds = next
            }
            .testTag("fst.player.available"),
    ) {
        content(grid.splitAtFold && !screenReader)
    }
}

// endregion
