package com.festivalscoretracker.android.core.shell

// region Floating toolbar placement

/**
 * A horizontal span in window pixels, `left` inclusive and `right` exclusive.
 *
 * @property left Left edge.
 * @property right Right edge.
 */
data class PxSpan(val left: Int, val right: Int)

/**
 * Space the floating toolbar keeps from the shell content area's left and right edges.
 *
 * @property left Inset from the content area's left edge, in pixels.
 * @property right Inset from the content area's right edge, in pixels.
 */
data class ToolbarInsets(val left: Int, val right: Int)

/**
 * Where the shell's one floating toolbar may sit horizontally at every window size
 * (`page-tools-and-nav-chrome` R4, owner-approved variant #576).
 *
 * The toolbar is end-aligned inside a region that is:
 * - the content area (right of a rail or drawer, never under it);
 * - narrowed to the pane of the page that owns the toolbar, so in a list-detail split the list's
 *   tools float over the list, not over the detail;
 * - kept off the left/right system bars and camera cutout (safe drawing area);
 * - on one side of a separating vertical hinge: the end side of it when the hinge crosses the
 *   region (Material 3: "Never place interactive content or critical information across the
 *   hinge area").
 */
object FloatingToolbarPlacement {
    /**
     * Insets that bound the toolbar's region inside the content area.
     *
     * @param content Shell content area.
     * @param pane The owning page's pane, or null when unknown (the whole content area).
     * @param safe The window's safe drawing span (between left and right system bars/cutouts).
     * @param hinge A separating vertical hinge, if any.
     * @param rtl Right-to-left layout: the end side of a hinge is its left.
     * @param marginPx Gap kept from each bound (M3 floating toolbar margin).
     * @return Left and right insets from the content area's edges.
     */
    fun insets(content: PxSpan, pane: PxSpan?, safe: PxSpan, hinge: PxSpan?, rtl: Boolean, marginPx: Int): ToolbarInsets {
        var left = maxOf(content.left, pane?.left ?: content.left, safe.left)
        var right = minOf(content.right, pane?.right ?: content.right, safe.right)
        // A pane that does not overlap the content (stale bounds mid-transition) falls back to it.
        if (right <= left) {
            left = maxOf(content.left, safe.left)
            right = minOf(content.right, safe.right)
        }
        if (hinge != null && hinge.left < right && hinge.right > left) {
            if (rtl) right = hinge.left else left = hinge.right
        }
        return ToolbarInsets(left = left - content.left + marginPx, right = content.right - right + marginPx)
    }
}

// endregion
