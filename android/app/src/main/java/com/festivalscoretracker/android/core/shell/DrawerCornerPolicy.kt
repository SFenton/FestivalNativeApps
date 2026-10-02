package com.festivalscoretracker.android.core.shell

import kotlin.math.max
import kotlin.math.min

// region Drawer corners

/**
 * One rounded display corner as the window reports it (`WindowInsets.getRoundedCorner`, API 31+),
 * in window pixels.
 *
 * @property radius Corner radius.
 * @property centerX Arc centre, x, in window coordinates.
 * @property centerY Arc centre, y, in window coordinates.
 */
data class DisplayCorner(val radius: Float, val centerX: Float, val centerY: Float)

/**
 * The window's rounded display corners by physical position. A null corner is square, unreported
 * or not touched by this window (split screen, freeform).
 *
 * @property topLeft Top-left corner.
 * @property topRight Top-right corner.
 * @property bottomRight Bottom-right corner.
 * @property bottomLeft Bottom-left corner.
 */
data class DisplayCorners(
    val topLeft: DisplayCorner? = null,
    val topRight: DisplayCorner? = null,
    val bottomRight: DisplayCorner? = null,
    val bottomLeft: DisplayCorner? = null,
) {
    /** True when no corner is rounded, so the platform default shape applies unchanged. */
    val isEmpty: Boolean get() = topLeft == null && topRight == null && bottomRight == null && bottomLeft == null
}

/**
 * Corner radii by physical position, in pixels.
 *
 * @property topLeft Top-left radius.
 * @property topRight Top-right radius.
 * @property bottomRight Bottom-right radius.
 * @property bottomLeft Bottom-left radius.
 */
data class CornerRadii(val topLeft: Float, val topRight: Float, val bottomRight: Float, val bottomLeft: Float)

/**
 * A rectangle in window pixels.
 *
 * @property left Left edge.
 * @property top Top edge.
 * @property right Right edge.
 * @property bottom Bottom edge.
 */
data class WindowRect(val left: Float, val top: Float, val right: Float, val bottom: Float)

/**
 * Modal drawer corners concentric with the display corners (issue #55, Android check of Apple
 * #17). Each sheet corner shares its arc centre with the display corner at the same position, so
 * its radius is the display radius minus the sheet's inset from that display corner. The
 * edge-attached start corners therefore take the display radius, and a corner too far from its
 * display corner keeps Material's default (`DrawerDefaults.shape`: square start, large end), which
 * is also the minimum, like Apple's `ConcentricRectangle(minimum:)`.
 */
object DrawerCornerPolicy {
    /**
     * Where the resting modal sheet sits in the window: attached to the container's start edge,
     * full container height.
     *
     * @param container The composition's bounds in window pixels.
     * @param sheetWidth Laid-out sheet width.
     * @param sheetHeight Laid-out sheet height.
     * @param rtl Right-to-left layout (sheet on the right).
     * @return The sheet's bounds in window pixels.
     */
    fun sheetBounds(container: WindowRect, sheetWidth: Float, sheetHeight: Float, rtl: Boolean): WindowRect {
        val left = if (rtl) container.right - sheetWidth else container.left
        return WindowRect(left, container.top, left + sheetWidth, container.top + sheetHeight)
    }

    /**
     * Radius concentric with [corner] for a sheet corner at ([x], [y]), or null when the sheet
     * corner is not inside that display corner's arc (no shared centre is possible).
     *
     * @param corner Display corner at the same physical position, or null when square.
     * @param x Sheet corner x in window pixels.
     * @param y Sheet corner y in window pixels.
     * @param right The corner is on the right edge.
     * @param bottom The corner is on the bottom edge.
     * @return Concentric radius in pixels, at most the display radius, or null.
     */
    fun concentricRadius(corner: DisplayCorner?, x: Float, y: Float, right: Boolean, bottom: Boolean): Float? {
        if (corner == null || corner.radius <= 0f) return null
        val dx = if (right) x - corner.centerX else corner.centerX - x
        val dy = if (bottom) y - corner.centerY else corner.centerY - y
        val radius = min(min(dx, dy), corner.radius)
        return radius.takeIf { it > 0f }
    }

    /**
     * Physical corner radii for the modal drawer sheet.
     *
     * @param corners The window's display corners.
     * @param sheet Sheet bounds in window pixels ([sheetBounds]).
     * @param defaults Material's default radii, mapped to physical corners; also each corner's minimum.
     * @return Radii: the larger of the concentric radius and the default.
     */
    fun radii(corners: DisplayCorners, sheet: WindowRect, defaults: CornerRadii): CornerRadii {
        fun resolve(corner: DisplayCorner?, x: Float, y: Float, right: Boolean, bottom: Boolean, default: Float): Float =
            max(concentricRadius(corner, x, y, right, bottom) ?: 0f, default)
        return CornerRadii(
            topLeft = resolve(corners.topLeft, sheet.left, sheet.top, right = false, bottom = false, defaults.topLeft),
            topRight = resolve(corners.topRight, sheet.right, sheet.top, right = true, bottom = false, defaults.topRight),
            bottomRight = resolve(corners.bottomRight, sheet.right, sheet.bottom, right = true, bottom = true, defaults.bottomRight),
            bottomLeft = resolve(corners.bottomLeft, sheet.left, sheet.bottom, right = false, bottom = true, defaults.bottomLeft),
        )
    }
}

// endregion
