package com.festivalscoretracker.android.core.scrolledge

// region Scroll edge ramps

/**
 * The ramps of every Android scroll-edge fade (`.agents/patterns/scroll-edge.md`): content is
 * fully clear at a pinned edge and fully drawn a ramp away from it (R2).
 *
 * Both follow the web's `useScrollMask` (40 px linear,
 * `FortniteFestivalWeb/src/hooks/ui/useScrollMask.ts`): top edges (pinned section titles) directly,
 * and bottom chrome (a board's pager and pinned footer) because the web board's
 * `useLeaderboardFooterScrollMargin` ends `Page.tsx`'s masked viewport at the footer. The ramps
 * grow with the scroll like the web's `min(scrollTop, distance)`, so nothing is dimmed at rest
 * (R4). These are their only definitions on Android (R3, issues #308, #190).
 */
object ScrollEdgeFade {
    /** Web `useScrollMask` `DEFAULT_SIZE`: the ramp below a pinned top edge, in dp. */
    const val TOP_DP = 40f

    /** Web board footer edge (`useScrollMask` `DEFAULT_SIZE` at the footer): the ramp above bottom chrome, in dp. */
    const val BOTTOM_DP = 40f

    /**
     * Whether edges are hard cuts instead of ramps (R7): Increase Contrast (the app toggle or the
     * system contrast level), system High contrast text, Reduce Transparency, or Reduce Motion (the
     * app toggle or system Remove animations; Android has no system reduce-transparency setting,
     * so issue #157 treats it as the stand-in). Content is still never drawn behind the chrome.
     *
     * @param increaseContrast Increase Contrast is on.
     * @param highContrastText System High contrast text is on.
     * @param reduceTransparency Reduce Transparency is on.
     * @param removeAnimations Reduce Motion / Remove animations is on.
     * @return True for a hard edge.
     */
    fun isHardEdge(
        increaseContrast: Boolean,
        highContrastText: Boolean = false,
        reduceTransparency: Boolean = false,
        removeAnimations: Boolean = false,
    ): Boolean = increaseContrast || highContrastText || reduceTransparency || removeAnimations

    /**
     * The ramp depth for how far content has moved toward an edge: it grows from 0 with the
     * scroll and stops at [full] (the web's `min(scrollTop, distance)`).
     *
     * @param scrolled Distance in px that content has scrolled under the edge (top) or still runs
     *   past it (bottom); [Float.POSITIVE_INFINITY] when that is far away.
     * @param full The full ramp in px; 0 for a hard edge.
     * @return A depth in 0..[full]; 0 for a non-positive or NaN input.
     */
    fun depth(scrolled: Float, full: Float): Float {
        if (full.isNaN() || full <= 0f || scrolled.isNaN()) return 0f
        return scrolled.coerceIn(0f, full)
    }
}

// endregion
