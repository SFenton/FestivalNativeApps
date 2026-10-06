package com.festivalscoretracker.android.core.nav

import kotlin.math.max

// region Sheet hinge side

/**
 * Keeps a modal bottom sheet on one side of a **separating** fold or hinge (half-open book or
 * tabletop posture, or a physical hinge). Material 3: "Never place interactive content or
 * critical information across the hinge area." A flat fold is not separating, so a sheet
 * stays centred on an unfolded device. The side comes from the shared [HingeSide] rule; this
 * object only turns it into sheet padding.
 */
object SheetHinge {
    /**
     * Extra outer padding for the sheet surface, in window pixels (physical left/right).
     *
     * @property left Padding before the sheet's left edge.
     * @property right Padding after the sheet's right edge.
     * @property top Padding above the sheet, added below its normal top offset.
     * @property bottom Padding below the sheet (only when the window ends inside the hinge).
     */
    data class Insets(val left: Float = 0f, val right: Float = 0f, val top: Float = 0f, val bottom: Float = 0f) {
        companion object {
            /** No hinge: the sheet keeps Material's centred placement. */
            val NONE = Insets()
        }
    }

    /**
     * Padding that confines the sheet to the [HingeSide] of a separating hinge in the window:
     * the wider or leading side in book posture, below the hinge in tabletop, [gapPx] below it
     * as below the status bar.
     *
     * @param windowWidthPx Window width.
     * @param windowHeightPx Window height.
     * @param left Hinge left edge in window coordinates.
     * @param right Hinge right edge.
     * @param top Hinge top edge.
     * @param bottom Hinge bottom edge.
     * @param vertical The hinge runs top to bottom.
     * @param separating WindowManager reports the hinge as separating.
     * @param rtl Right-to-left layout (leading side is on the right).
     * @param sheetTopPx The sheet's normal top offset (status bar plus gap).
     * @param gapPx Gap kept between the hinge and the sheet's top edge.
     * @return Padding for the sheet surface, or [Insets.NONE].
     */
    fun insets(
        windowWidthPx: Float,
        windowHeightPx: Float,
        left: Float,
        right: Float,
        top: Float,
        bottom: Float,
        vertical: Boolean,
        separating: Boolean,
        rtl: Boolean,
        sheetTopPx: Float,
        gapPx: Float,
    ): Insets {
        val side = HingeSide.padding(
            page = HingeSide.Rect(0f, 0f, windowWidthPx, windowHeightPx),
            hinge = HingeSide.Rect(left, top, right, bottom),
            vertical = vertical,
            separating = separating,
            rtl = rtl,
        )
        if (side == HingeSide.Padding.NONE) return Insets.NONE
        val sheetTop = if (side.top > 0f) max(0f, side.top + gapPx - sheetTopPx) else 0f
        return Insets(left = side.left, right = side.right, top = sheetTop, bottom = side.bottom)
    }
}

// endregion
