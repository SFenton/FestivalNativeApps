package com.festivalscoretracker.android.core.scrolledge

// region Scroll edge ramps

/**
 * The ramps of every Android scroll-edge fade (`.agents/patterns/scroll-edge.md`): content is
 * fully clear at a pinned edge and fully drawn a ramp away from it (R2).
 *
 * Top edges (pinned section titles) and board bottom chrome (the leaderboard footer and pager)
 * both follow the web's `useScrollMask` (40 px, `FortniteFestivalWeb/src/hooks/ui/useScrollMask.ts`):
 * `Page.tsx` masks every board with it, and `useLeaderboardFooterScrollMargin` ends that viewport
 * at the floating footer (issue #329; `useScrollFade`'s 36 px belongs to lists, not boards). Both
 * ramps are linear and grow with the scroll like the web's `min(scrollTop, distance)`, so nothing
 * is dimmed at rest (R4). These are their only definitions on Android (R3, issue #308).
 */
object ScrollEdgeFade {
    /** Web `useScrollMask` `DEFAULT_SIZE`: the ramp below a pinned top edge, in dp. */
    const val TOP_DP = 40f

    /** Web `useScrollMask` `DEFAULT_SIZE` on the board pages: the ramp above a board's footer and pager, in dp. */
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
