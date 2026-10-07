package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade

// region Board footer edge fade

/**
 * Where board rows are cut and fade out above the floating "your rank" footer and pager.
 *
 * @property cut The footer's top edge in px from the list's top edge: rows are hidden below it
 *   and fade out over the ramp above it.
 * @property depth Ramp height in px above the cut: rows are clear at the cut and fully drawn
 *   [depth] above it; 0 is a hard cut (end of the list, or an accessibility mode).
 */
data class FooterFade(val cut: Float, val depth: Float)

/**
 * The bottom edge of the paginated boards' rows above their floating player-score footer and
 * pager (issues #93, #329, the web board pages' `useScrollMask`): rows scrolling down to the footer fade out over a
 * linear [ScrollEdgeFade.BOTTOM_DP] ramp ending at its top edge and stay hidden beneath it, so the
 * footer floats over the page background without an opaque band (scroll-edge R2, R3).
 *
 * The ramp shrinks with the remaining scroll and is gone at the end of the list, so the last row is
 * never faded (R4). Accessibility modes keep the cut with no ramp (R7). Pure geometry: the UI
 * reads it in the draw phase only.
 */
object BoardFooterEdgeFade {
    /**
     * Content still below the viewport end, in px.
     *
     * @param totalItems Item count.
     * @param lastVisibleIndex Index of the last laid-out item, or -1 when none.
     * @param lastOffset That item's offset (`LazyListItemInfo.offset`).
     * @param lastSize That item's size.
     * @param afterContentPadding List bottom content padding in px.
     * @param viewportEnd `LazyListLayoutInfo.viewportEndOffset`.
     * @return Remaining scroll in px (never negative), or [Float.POSITIVE_INFINITY] when later
     *   items are not laid out yet.
     */
    fun remainingScroll(totalItems: Int, lastVisibleIndex: Int, lastOffset: Int, lastSize: Int, afterContentPadding: Int, viewportEnd: Int): Float {
        if (lastVisibleIndex < 0) return 0f
        if (lastVisibleIndex < totalItems - 1) return Float.POSITIVE_INFINITY
        return (lastOffset + lastSize + afterContentPadding - viewportEnd).coerceAtLeast(0).toFloat()
    }

    /**
     * The edge above a footer of [footerHeight] px at the bottom of a [viewportHeight] px list.
     *
     * @param viewportHeight List height in px.
     * @param footerHeight Footer height in px, bottom inset included; 0 = not measured yet.
     * @param remaining Remaining scroll in px ([remainingScroll]).
     * @param fullDepth The full ramp in px ([ScrollEdgeFade.BOTTOM_DP]); 0 keeps a hard cut.
     * @return The edge, or null when there is no footer to fade under.
     */
    fun edge(viewportHeight: Int, footerHeight: Int, remaining: Float, fullDepth: Float): FooterFade? {
        if (footerHeight <= 0 || viewportHeight <= 0) return null
        val cut = (viewportHeight - footerHeight).coerceAtLeast(0).toFloat()
        return FooterFade(cut, ScrollEdgeFade.depth(remaining, fullDepth))
    }
}

// endregion
