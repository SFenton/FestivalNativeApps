package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.Immutable
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection

// region Pane insets

/**
 * Window insets seen by a pane that does not span the whole window: each horizontal
 * inset only counts for the part that reaches into the pane. A list pane on the left
 * of a landscape phone keeps its full width when the camera cutout sits on the right
 * (it reserved 54 dp there and cut the Songs title to "Son…", issue #101).
 *
 * @property base Window insets, measured from the window edges.
 * @property leftGapPx Distance from the window's left edge to the pane, in px.
 * @property rightGapPx Distance from the pane to the window's right edge, in px.
 */
@Immutable
class PaneInsets(
    private val base: WindowInsets,
    private val leftGapPx: Int,
    private val rightGapPx: Int,
) : WindowInsets {
    override fun getLeft(density: Density, layoutDirection: LayoutDirection): Int =
        (base.getLeft(density, layoutDirection) - leftGapPx).coerceAtLeast(0)

    override fun getRight(density: Density, layoutDirection: LayoutDirection): Int =
        (base.getRight(density, layoutDirection) - rightGapPx).coerceAtLeast(0)

    override fun getTop(density: Density): Int = base.getTop(density)

    override fun getBottom(density: Density): Int = base.getBottom(density)

    override fun equals(other: Any?): Boolean =
        other is PaneInsets && other.base == base && other.leftGapPx == leftGapPx && other.rightGapPx == rightGapPx

    override fun hashCode(): Int = (base.hashCode() * 31 + leftGapPx) * 31 + rightGapPx

    override fun toString(): String = "PaneInsets($base, left gap=$leftGapPx, right gap=$rightGapPx)"
}

// endregion
