package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.profile.ProfileColumns
import com.festivalscoretracker.android.core.profile.ProfileGridSpec
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.ui.common.ProvideFoldLane
import com.festivalscoretracker.android.ui.common.rememberMeasuredBounds
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import com.festivalscoretracker.android.ui.common.shellPosture
import com.festivalscoretracker.android.ui.rivals.SpecCells
import kotlin.math.roundToInt

// region Fold-aware grid

/**
 * The player page's row-major card grid: columns of at least [minColumn] (up to [maxColumns]),
 * or one column per panel with the gaps on every separating vertical hinge (book fold
 * half-open, a partly folded tri-fold), so no card straddles a fold. The hinges come from
 * Jetpack WindowManager; device names never participate.
 *
 * Cards fill each line start to end and start at the line's top edge, however far the page
 * scrolls (`hinge-columns` R8, #584: a masonry grid let side-by-side sections drift apart).
 * Full-width rows (identity, Overview, headings) span the whole line flat or in landscape; in
 * book posture the caller keeps them to the leading panel ([FoldLane][com.festivalscoretracker.android.ui.common.FoldLane])
 * or lets a tall one fill one panel, told by the `splitAtFold` argument of [content].
 *
 * @param state Scroll state (shared with Quick Links).
 * @param contentPadding Padding inside the scrolling area.
 * @param modifier Modifier (horizontal page padding belongs here, outside the columns).
 * @param minColumn Minimum column width.
 * @param maxColumns Upper bound on columns without hinges.
 * @param content Items; its argument is whether the columns split at a fold (book posture).
 */
@Composable
fun ProfileGrid(
    state: LazyGridState,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
    minColumn: Dp = 340.dp,
    maxColumns: Int = 3,
    content: LazyGridScope.(splitAtFold: Boolean) -> Unit,
) {
    val density = LocalDensity.current
    val hinges = shellPosture().hingeList
        .filter { it.isSeparating && it.isVertical }
        .map { it.bounds.left.roundToInt() to it.bounds.right.roundToInt() }
    var bounds by rememberMeasuredBounds()
    val gutter = with(density) { 16.dp.roundToPx() }
    val grid = bounds?.let { (start, width) ->
        ProfileColumns.resolve(start, width, hinges, with(density) { minColumn.roundToPx() }, gutter, maxColumns)
    } ?: ProfileGridSpec(ColumnSpec(listOf(0), gutter), splitAtFold = false)
    // One column under TalkBack or at large text (see rememberSingleColumn).
    val singleColumn = rememberSingleColumn()
    val cells = remember(grid.spec, bounds == null, singleColumn) { if (bounds == null || singleColumn) GridCells.Fixed(1) else SpecCells(grid.spec) }
    // Full-width rows stay in the leading panel while the columns split at a fold.
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val leadingPane = if (bounds == null || singleColumn || !grid.splitAtFold) null else grid.spec.leadingPane(rtl)?.let { with(density) { it.toDp() } }
    ProvideFoldLane(leadingPane) {
        LazyVerticalGrid(
            columns = cells,
            state = state,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(with(density) { grid.spec.spacing.toDp() }),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = modifier
                .fillMaxSize()
                .onGloballyPositioned { coordinates ->
                    val next = coordinates.positionInWindow().x.roundToInt() to coordinates.size.width
                    if (next != bounds) bounds = next
                }
                .testTag("fst.player.available"),
            content = { content(leadingPane != null) },
        )
    }
}

// endregion
