package com.festivalscoretracker.android.core.bands

import kotlin.math.max
import kotlin.math.min

// region Adaptive geometry

/**
 * Pure adaptive geometry for band pages (all values in dp, unit-tested).
 *
 * Material 3 window classes decide *whether* content splits (expanded width ≥ 840 dp,
 * or a separating hinge such as a half-open book fold); a vertical fold or hinge
 * reported by Jetpack WindowManager decides *where*, so no card, pane or gutter
 * ever straddles the crease.
 */
object BandLayout {
    /** Expanded window-width breakpoint. */
    const val EXPANDED_WIDTH = 840f

    /** Minimum band card width. */
    const val CARD_MIN = 320f

    /** Outer content margin and half-gutter around a hinge. */
    const val EDGE = 16f

    /** Gutter between cards without a hinge. */
    const val GUTTER = 12f

    /** Gap between panes without a hinge. */
    const val PANE_GAP = 24f

    /** Narrowest side a hinge may leave for a pane or column. */
    const val MIN_SIDE = 200f

    /**
     * A vertical fold/hinge in content coordinates.
     *
     * @property left Leading edge.
     * @property right Trailing edge (equal to [left] for a zero-width fold).
     * @property separating Whether WindowManager reports it as separating (half-open, or a physical hinge).
     */
    data class Hinge(val left: Float, val right: Float, val separating: Boolean)

    /**
     * Two-pane decision.
     *
     * @property twoPane Whether content splits.
     * @property leadingWidth Leading pane width when split at a hinge, else null (equal weights).
     * @property gap Gap between panes.
     */
    data class Panes(val twoPane: Boolean, val leadingWidth: Float?, val gap: Float)

    /**
     * Card grid geometry.
     *
     * @property columns Column count.
     * @property start Leading content padding.
     * @property end Trailing content padding.
     * @property gutter Gap between columns.
     */
    data class Grid(val columns: Int, val start: Float, val end: Float, val gutter: Float)

    /**
     * Convert a window-space vertical hinge into content coordinates.
     *
     * @param windowLeft Hinge leading edge in the window.
     * @param windowRight Hinge trailing edge in the window.
     * @param contentLeft Content box's leading edge in the window.
     * @param contentWidth Content width.
     * @param separating WindowManager `isSeparating`.
     * @return The hinge, or null when it leaves less than [MIN_SIDE] on either side of the content.
     */
    fun hingeInContent(windowLeft: Float, windowRight: Float, contentLeft: Float, contentWidth: Float, separating: Boolean): Hinge? {
        val left = windowLeft - contentLeft
        val right = windowRight - contentLeft
        if (left < MIN_SIDE || right > contentWidth - MIN_SIDE) return null
        return Hinge(left, right, separating)
    }

    /**
     * Whether and where Band Detail splits into panes.
     *
     * @param windowWidth Window width.
     * @param hinge Vertical hinge in content coordinates.
     * @return Panes.
     */
    fun panes(windowWidth: Float, hinge: Hinge?): Panes {
        val split = windowWidth >= EXPANDED_WIDTH || hinge?.separating == true
        return when {
            !split -> Panes(false, null, 0f)
            hinge != null -> Panes(true, hinge.left, hinge.right - hinge.left)
            else -> Panes(true, null, PANE_GAP)
        }
    }

    /**
     * Card grid: as many ≥ [CARD_MIN] columns as fit; with a separating hinge, or a
     * fold when two columns fit anyway, exactly two columns whose gutter is the hinge.
     *
     * @param contentWidth Content width.
     * @param hinge Vertical hinge in content coordinates.
     * @return Grid geometry.
     */
    fun grid(contentWidth: Float, hinge: Hinge?): Grid {
        val fit = max(1, ((contentWidth - 2 * EDGE + GUTTER) / (CARD_MIN + GUTTER)).toInt())
        if (hinge != null && (hinge.separating || fit == 2)) {
            val column = min(hinge.left, contentWidth - hinge.right) - 2 * EDGE
            return Grid(2, hinge.left - EDGE - column, contentWidth - hinge.right - EDGE - column, hinge.right - hinge.left + 2 * EDGE)
        }
        return Grid(fit, EDGE, EDGE, GUTTER)
    }
}

// endregion
