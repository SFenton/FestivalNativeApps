package com.festivalscoretracker.android.core.nav

import kotlin.math.max

// region Dialog hinge side

/**
 * Keeps a centred modal dialog on one side of a **separating** fold or hinge (half-open book or
 * tabletop posture). Material 3: "Never place interactive content or critical information
 * across the hinge area." A dialog is centred in the window, so on a half-open foldable it
 * straddles the hinge unless it is confined to one side. A flat fold is not separating.
 */
object DialogHinge {
    /**
     * A rectangle in screen pixels.
     *
     * @property left Left edge.
     * @property top Top edge.
     * @property right Right edge.
     * @property bottom Bottom edge.
     */
    data class Area(val left: Float, val top: Float, val right: Float, val bottom: Float) {
        /** Width (never negative). */
        val width: Float get() = max(0f, right - left)

        /** Height (never negative). */
        val height: Float get() = max(0f, bottom - top)
    }

    /**
     * The part of the window a dialog should be centred in.
     *
     * A vertical hinge (book posture) keeps the wider side, the leading side on a tie (as
     * [SheetHinge]); a horizontal hinge (tabletop) keeps the lower half, where the device rests
     * and the user can reach. The result is intersected with [safe] (the window minus system
     * bars and cutouts).
     *
     * @param safe The window's safe area.
     * @param hinge The hinge bounds, in the same coordinates.
     * @param vertical The hinge runs top to bottom.
     * @param separating WindowManager reports the hinge as separating.
     * @param rtl Right-to-left layout (leading side is on the right).
     * @return The area to centre the dialog in, or null to keep the ordinary centred dialog.
     */
    fun area(safe: Area, hinge: Area, vertical: Boolean, separating: Boolean, rtl: Boolean): Area? {
        if (!separating) return null
        if (vertical) {
            if (hinge.left <= safe.left || hinge.right >= safe.right) return null
            val leftSide = hinge.left - safe.left
            val rightSide = safe.right - hinge.right
            val keepLeft = if (leftSide == rightSide) !rtl else leftSide > rightSide
            return if (keepLeft) safe.copy(right = hinge.left) else safe.copy(left = hinge.right)
        }
        if (hinge.top <= safe.top || hinge.bottom >= safe.bottom) return null
        return safe.copy(top = hinge.bottom)
    }

    /**
     * Top-left offset that centres a measured dialog in [area].
     *
     * @param area The area from [area], already translated to the dialog window's coordinates.
     * @param width Measured dialog width.
     * @param height Measured dialog height.
     * @return The x and y offset.
     */
    fun place(area: Area, width: Float, height: Float): Pair<Float, Float> =
        (area.left + (area.width - width) / 2f) to (area.top + (area.height - height) / 2f)
}

// endregion
