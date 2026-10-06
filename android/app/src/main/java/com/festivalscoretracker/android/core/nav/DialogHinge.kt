package com.festivalscoretracker.android.core.nav

// region Dialog hinge side

/**
 * Keeps a centred modal dialog on one side of a **separating** fold or hinge (half-open book or
 * tabletop posture). Material 3: "Never place interactive content or critical information
 * across the hinge area." A dialog is centred in the window, so on a half-open foldable it
 * straddles the hinge unless it is confined to one side. A flat fold is not separating. The side
 * comes from the shared [HingeSide] rule; this object only centres the dialog in it.
 */
object DialogHinge {
    /**
     * The part of the window a dialog should be centred in: the [HingeSide] of the hinge within
     * [safe] (the window minus system bars and cutouts).
     *
     * @param safe The window's safe area.
     * @param hinge The hinge bounds, in the same coordinates.
     * @param vertical The hinge runs top to bottom.
     * @param separating WindowManager reports the hinge as separating.
     * @param rtl Right-to-left layout (leading side is on the right).
     * @return The area to centre the dialog in, or null to keep the ordinary centred dialog.
     */
    fun area(safe: HingeSide.Rect, hinge: HingeSide.Rect, vertical: Boolean, separating: Boolean, rtl: Boolean): HingeSide.Rect? =
        HingeSide.keep(safe, hinge, vertical, separating, rtl)

    /**
     * Top-left offset that centres a measured dialog in [area].
     *
     * @param area The area from [area], already translated to the dialog window's coordinates.
     * @param width Measured dialog width.
     * @param height Measured dialog height.
     * @return The x and y offset.
     */
    fun place(area: HingeSide.Rect, width: Float, height: Float): Pair<Float, Float> =
        (area.left + (area.width - width) / 2f) to (area.top + (area.height - height) / 2f)
}

// endregion
