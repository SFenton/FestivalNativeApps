package com.festivalscoretracker.android.core.nav

import kotlin.math.max

// region Sheet hinge side

/**
 * Keeps a modal bottom sheet on one side of a **separating** fold or hinge (half-open book or
 * tabletop posture, or a physical hinge). Material 3: "Never place interactive content or
 * critical information across the hinge area." A flat fold is not separating, so a sheet
 * stays centred on an unfolded device.
 */
object SheetHinge {
    /**
     * Extra outer padding for the sheet surface, in window pixels (physical left/right).
     *
     * @property left Padding before the sheet's left edge.
     * @property right Padding after the sheet's right edge.
     * @property top Padding above the sheet, added below its normal top offset.
     */
    data class Insets(val left: Float = 0f, val right: Float = 0f, val top: Float = 0f) {
        companion object {
            /** No hinge: the sheet keeps Material's centred placement. */
            val NONE = Insets()
        }
    }

    /**
     * Padding that confines the sheet to one side of a separating hinge.
     *
     * A vertical hinge (book posture) keeps the sheet on the wider side, the leading side on a
     * tie (where the Songs list and its page tools sit). A horizontal hinge (tabletop) keeps it in
     * the lower half, [gapPx] below the hinge as below the status bar.
     *
     * @param windowWidthPx Window width.
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
        if (!separating) return Insets.NONE
        if (!vertical) return Insets(top = max(0f, bottom + gapPx - sheetTopPx))
        if (left <= 0f || right >= windowWidthPx) return Insets.NONE
        val leftSide = left
        val rightSide = windowWidthPx - right
        val keepLeft = if (leftSide == rightSide) !rtl else leftSide > rightSide
        return if (keepLeft) Insets(right = windowWidthPx - left) else Insets(left = right)
    }
}

// endregion
