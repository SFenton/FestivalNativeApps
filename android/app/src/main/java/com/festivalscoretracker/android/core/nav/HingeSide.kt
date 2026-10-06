package com.festivalscoretracker.android.core.nav

import kotlin.math.max
import kotlin.math.min

// region Separating hinge side

/**
 * The one placement rule that keeps a surface on one side of a **separating** fold or hinge
 * (half-open book or tabletop posture, or a physical hinge). Material 3: "Never place
 * interactive content or critical information across the hinge area." A flat fold is not
 * separating, so surfaces keep their ordinary placement on an unfolded device.
 *
 * - A **vertical** hinge (book posture) keeps the wider side of the page, the leading side on a
 *   tie (where the app's lists and page tools sit).
 * - A **horizontal** hinge (tabletop) always keeps the part **below** the hinge, whichever half is
 *   larger: that is where the device rests and its controls are in reach. Only a page that ends
 *   inside the hinge (no lower part on this page) keeps the part above.
 *
 * Every consumer goes through [keep] or [padding] and only adapts the result to its own layout:
 * [SheetHinge] (bottom sheets), [DialogHinge] (centred dialogs) and the full-page service status
 * (`serviceStatusHingeSide`). Do not add another side rule.
 */
object HingeSide {
    /**
     * A rectangle in pixels; the page and the hinge must use the same coordinates.
     *
     * @property left Left edge.
     * @property top Top edge.
     * @property right Right edge.
     * @property bottom Bottom edge.
     */
    data class Rect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
        /** Width (never negative). */
        val width: Float get() = max(0f, right - left)

        /** Height (never negative). */
        val height: Float get() = max(0f, bottom - top)
    }

    /**
     * Physical (left/right, not start/end) padding that shrinks a page to its kept side.
     *
     * @property left Padding from the page's left edge.
     * @property top Padding from the page's top edge.
     * @property right Padding from the page's right edge.
     * @property bottom Padding from the page's bottom edge.
     */
    data class Padding(val left: Float = 0f, val top: Float = 0f, val right: Float = 0f, val bottom: Float = 0f) {
        companion object {
            /** No separating hinge crosses the page. */
            val NONE = Padding()
        }
    }

    /**
     * The part of [page] a surface should use beside a hinge.
     *
     * @param page The page (or window, or safe area) the surface lives in.
     * @param hinge The hinge bounds, in the same coordinates as [page].
     * @param vertical The hinge runs top to bottom.
     * @param separating WindowManager reports the hinge as separating.
     * @param rtl Right-to-left layout (leading side is on the right).
     * @return The kept part of [page], or null when the hinge is not separating or misses the page.
     */
    fun keep(page: Rect, hinge: Rect, vertical: Boolean, separating: Boolean, rtl: Boolean): Rect? {
        if (!separating || page.width <= 0f || page.height <= 0f) return null
        return if (vertical) keepBeside(page, hinge, rtl) else keepBelow(page, hinge)
    }

    /**
     * [keep] as padding from each edge of [page].
     *
     * @param page The page the surface lives in.
     * @param hinge The hinge bounds, in the same coordinates as [page].
     * @param vertical The hinge runs top to bottom.
     * @param separating WindowManager reports the hinge as separating.
     * @param rtl Right-to-left layout.
     * @return Padding to the kept side, or [Padding.NONE].
     */
    fun padding(page: Rect, hinge: Rect, vertical: Boolean, separating: Boolean, rtl: Boolean): Padding {
        val kept = keep(page, hinge, vertical, separating, rtl) ?: return Padding.NONE
        return Padding(
            left = kept.left - page.left,
            top = kept.top - page.top,
            right = page.right - kept.right,
            bottom = page.bottom - kept.bottom,
        )
    }

    /**
     * Book posture: the wider side, the leading side on a tie.
     *
     * @param page The page.
     * @param hinge The vertical hinge.
     * @param rtl Right-to-left layout.
     * @return The kept side, or null when the hinge misses the page.
     */
    private fun keepBeside(page: Rect, hinge: Rect, rtl: Boolean): Rect? {
        if (hinge.right <= page.left || hinge.left >= page.right) return null
        val before = max(0f, hinge.left - page.left)
        val after = max(0f, page.right - hinge.right)
        val keepRight = if (before == after) rtl else after > before
        return if (keepRight) page.copy(left = min(hinge.right, page.right)) else page.copy(right = max(hinge.left, page.left))
    }

    /**
     * Tabletop posture: below the hinge, or above it only when the page ends inside the hinge.
     *
     * @param page The page.
     * @param hinge The horizontal hinge.
     * @return The kept part, or null when the hinge misses the page.
     */
    private fun keepBelow(page: Rect, hinge: Rect): Rect? {
        if (hinge.bottom <= page.top || hinge.top >= page.bottom) return null
        return if (hinge.bottom < page.bottom) page.copy(top = hinge.bottom) else page.copy(bottom = max(hinge.top, page.top))
    }
}

// endregion
