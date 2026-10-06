package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.songs.SongHeaderEdgeFade

// region Board footer edge fade

/**
 * Where board rows are cut and fade out above the floating "your rank" footer.
 *
 * @property cut The footer's top edge in px from the list's top edge: rows are hidden below it
 *   and fade out over the band above it.
 * @property strength Band strength: 0 = no fade (hard edge), 1 = full fade.
 */
data class FooterFade(val cut: Float, val strength: Float)

/**
 * The soft bottom edge of a board's rows above its floating player-score footer and pager
 * (issue #93; scroll-edge bottom chrome, web `useScrollFade`): rows scrolling down to the
 * footer fade out linearly over [DEPTH_DP] ending at its top edge and stay hidden beneath it,
 * so the footer floats over the page background without an opaque band.
 *
 * The band weakens over the last [DEPTH_DP] of scrolling and is gone at the end of the list
 * (web `atBottom`), so the last row is never faded. This is Android's only bottom-chrome ramp
 * (scroll-edge R3). Pure geometry: the UI reads it in the draw phase only.
 */
object BoardFooterEdgeFade {
    /** Fade depth above the footer (web `useScrollFade` `DEFAULT_DISTANCE`: 36 px; Apple `ScrollEdgeFade.distance`). */
    const val DEPTH_DP = 36f

    /**
     * Full-strength mask alpha down the band, as (position, alpha): position 0 is [DEPTH_DP]
     * above the footer, 1 is the footer's top edge. Linear, opaque to clear (web `.fadeBottom`
     * 36 px gradient; Apple `ScrollEdgeFade.bottom`), never the Songs header easing (issue #190).
     */
    val STOPS: List<Pair<Float, Float>> = listOf(0f to 1f, 1f to 0f)

    /**
     * Mask alpha at a stop, scaled by the fade strength (1 = unchanged row).
     *
     * @param stopAlpha Full-strength alpha at the stop ([STOPS]).
     * @param strength Fade strength ([strength]).
     * @return Mask alpha in 0..1.
     */
    fun maskAlpha(stopAlpha: Float, strength: Float): Float =
        1f - strength.coerceIn(0f, 1f) * (1f - stopAlpha.coerceIn(0f, 1f))

    /**
     * Whether the fade band is drawn: Increase Contrast and Reduce Transparency keep a hard edge,
     * as under the Songs headers ([SongHeaderEdgeFade.isEnabled]).
     *
     * @param increaseContrast Increase Contrast is on.
     * @param reduceTransparency Reduce Transparency is on.
     * @return Whether to fade.
     */
    fun isEnabled(increaseContrast: Boolean, reduceTransparency: Boolean): Boolean =
        SongHeaderEdgeFade.isEnabled(increaseContrast, reduceTransparency)

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
     * Fade strength: full while more than [depth] remains to scroll, easing to 0 at the end.
     *
     * @param remaining Remaining scroll in px ([remainingScroll]).
     * @param depth Fade depth in px.
     * @return Strength in 0..1.
     */
    fun strength(remaining: Float, depth: Float): Float {
        if (depth <= 0f || remaining.isNaN()) return 0f
        return (remaining / depth).coerceIn(0f, 1f)
    }

    /**
     * The edge above a footer of [footerHeight] px at the bottom of a [viewportHeight] px list.
     *
     * @param viewportHeight List height in px.
     * @param footerHeight Footer height in px, bottom inset included; 0 = not measured yet.
     * @param remaining Remaining scroll in px.
     * @param depth Fade depth in px; 0 keeps a hard edge.
     * @return The edge, or null when there is no footer to fade under.
     */
    fun edge(viewportHeight: Int, footerHeight: Int, remaining: Float, depth: Float): FooterFade? {
        if (footerHeight <= 0 || viewportHeight <= 0) return null
        val cut = (viewportHeight - footerHeight).coerceAtLeast(0).toFloat()
        return FooterFade(cut, strength(remaining, depth))
    }
}

// endregion
