package com.festivalscoretracker.android.core.shell

// region Minimize on scroll

/**
 * "Minimize on scroll" for a pinned floating toolbar (issue #84, the Android port of iOS #42's
 * `tabBarMinimizeBehavior(.onScrollDown)`): the toolbar stays on screen, but its field-shaped
 * control (Songs search) shrinks to an icon once the content has scrolled [thresholdPx] toward its
 * end and expands again after the same travel back, or at once at the top. Travel restarts on every
 * change of direction, so small finger jitter never toggles it.
 *
 * @property thresholdPx Scroll travel in one direction that flips the state.
 */
class FloatingToolbarMinimizer(private val thresholdPx: Float) {
    /** Whether the field-shaped control shows as an icon. */
    var minimized: Boolean = false
        private set

    private var travel = 0f

    /**
     * Follow one scroll step.
     *
     * @param consumedY Pixels the content scrolled (negative = toward the end of the content,
     *   the nested-scroll sign).
     * @param allowed False while minimizing is not allowed (TalkBack on, search open): the
     *   toolbar expands and travel resets.
     * @return The new [minimized] value.
     */
    fun onScroll(consumedY: Float, allowed: Boolean = true): Boolean {
        if (!allowed) return expand()
        if (consumedY < 0f) {
            travel = travel.coerceAtMost(0f) + consumedY
            if (travel <= -thresholdPx) minimized = true
        } else if (consumedY > 0f) {
            travel = travel.coerceAtLeast(0f) + consumedY
            if (travel >= thresholdPx) minimized = false
        }
        return minimized
    }

    /**
     * Expand at once (content back at its top, a new page, TalkBack on).
     *
     * @return The new [minimized] value (false).
     */
    fun expand(): Boolean {
        minimized = false
        travel = 0f
        return minimized
    }

    companion object {
        /** Scroll travel that flips the state. */
        const val THRESHOLD_DP = 24
    }
}

// endregion

// region Keyboard lift

/** Keeps a floating toolbar that holds a focused text field above the on-screen keyboard. */
object FloatingToolbarLift {
    /**
     * How far to raise the toolbar so it clears the keyboard.
     *
     * The toolbar floats in the content area, which ends above the bottom navigation bar and the
     * system navigation; the keyboard covers that strip first, so only the rest of its height
     * lifts the toolbar.
     *
     * @param imeBottomPx Keyboard height from the window bottom (0 when hidden).
     * @param gapBelowContentPx Distance from the content area's bottom to the window bottom.
     * @return Upward offset in pixels (never negative).
     */
    fun liftPx(imeBottomPx: Int, gapBelowContentPx: Int): Int = (imeBottomPx - gapBelowContentPx.coerceAtLeast(0)).coerceAtLeast(0)
}

// endregion
