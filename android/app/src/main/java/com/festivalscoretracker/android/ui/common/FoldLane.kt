package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridScope
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp

// region Fold lane

/**
 * Width of the leading pane while the enclosing grid splits its columns at a separating
 * vertical hinge (book posture half-open), or null when it does not. Hinge-splitting grids
 * (`AdaptiveCardGrid`, Suggestions, Item Shop) provide it; their full-line items read it
 * through [FoldLane] so titles, subtitles and messages stay on their side of the fold
 * (issue #343). Material 3: "Never place interactive content or critical information across
 * the hinge area."
 */
val LocalFoldLane = compositionLocalOf<Dp?> { null }

/**
 * Provides [LocalFoldLane] to a hinge-splitting grid's items.
 *
 * @param leadingPane Leading pane width when split at a hinge, or null.
 * @param content The grid.
 */
@Composable
fun ProvideFoldLane(leadingPane: Dp?, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalFoldLane provides leadingPane, content = content)
}

/**
 * A full-line slot that keeps its content in the leading pane while the grid splits at a
 * hinge and fills the line otherwise. It reflows when the posture changes (unfolding flat
 * widens it again) without recreating its content.
 *
 * @param modifier Modifier for the slot.
 * @param content Slot content.
 */
@Composable
fun FoldLane(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val lane = LocalFoldLane.current
    // Lazy grids give full-line items a fixed width; wrapContentWidth frees the lane to be narrower.
    val width = if (lane != null) Modifier.fillMaxWidth().wrapContentWidth(Alignment.Start).width(lane) else Modifier.fillMaxWidth()
    Box(modifier.then(width)) { content() }
}

/**
 * A [StaggeredGridItemSpan.FullLine] item wrapped in [FoldLane]: use it for every full-line
 * header, subtitle or message in a hinge-splitting staggered grid.
 *
 * @param key Stable key.
 * @param contentType Content type, or null.
 * @param content Item content.
 */
fun LazyStaggeredGridScope.foldLaneItem(key: Any, contentType: Any? = null, content: @Composable () -> Unit) {
    item(key = key, contentType = contentType, span = StaggeredGridItemSpan.FullLine) { FoldLane(content = content) }
}

// endregion
