package com.festivalscoretracker.android.core.songs

// region Pinned section header edge fade

/**
 * One laid-out list item, as the Songs list reports it (`LazyListItemInfo`).
 *
 * @property index Item index in the list.
 * @property key Item key.
 * @property offset Main-axis offset in px, relative to the list's viewport start.
 * @property size Main-axis size in px.
 * @property isHeader Whether it is a sticky section header.
 */
data class EdgeFadeItem(val index: Int, val key: Any, val offset: Int, val size: Int, val isHeader: Boolean)

/**
 * Where rows are cut and fade out below the pinned section header.
 *
 * @property top The pinned header's resting bottom edge in px from the list's top edge: rows
 *   are hidden above it (the header has no backing, issue #91) and fade in over the band below it.
 * @property strength Band strength: 0 = no fade (hard edge), 1 = full fade.
 */
data class EdgeFade(val top: Float, val strength: Float)

/**
 * The cut and soft edge under a pinned Songs section header (issue #49, port of the iOS
 * `SectionBarEdgeFade`, issue #10): rows scrolling under the header are hidden behind it and
 * fade out over a short eased band below it instead of being cut off hard at its bottom edge.
 *
 * The header has no backing (issue #91, iOS operator batch 7): rows never show through it
 * because the list hides everything above [EdgeFade.top] and redraws only the headers there
 * ([headersOverEdge]).
 *
 * The band starts at the pinned header's resting bottom, which does not move while the next
 * header pushes the current one away. Rows fade through it; headers in it are redrawn opaque,
 * so the next header slides up and pushes the pinned one out without fading or jumping. It appears gradually over the first [DEPTH_DP] of scrolling after the first header
 * pins, so the rows below it never fade at once. Pure geometry: the UI reads it in the draw
 * phase only.
 */
object SongHeaderEdgeFade {
    /** Fade depth below the header (iOS `SectionBarEdgeFade`: 28 pt). */
    const val DEPTH_DP = 28f

    /** Mask alpha stops through the band: smoothstep at 0, ¼, ½, ¾ and 1 (iOS uses the same easing). */
    val STOPS: List<Pair<Float, Float>> = listOf(0f, 0.25f, 0.5f, 0.75f, 1f).map { it to smoothstep(it) }

    /**
     * Whether the fade band is drawn. Increase Contrast (system contrast level or high-contrast
     * text, or the app toggle), the app's Reduce Transparency and Remove animations (the app's
     * Reduce Motion or the system switch; Android has no system reduce-transparency setting, so
     * issue #157 treats it as the stand-in) keep a hard edge (depth 0), as on iOS: rows are still
     * hidden under the header, but never half see-through beside it.
     *
     * @param increaseContrast Increase Contrast or system high-contrast text is on.
     * @param reduceTransparency Reduce Transparency is on.
     * @param removeAnimations Reduce Motion / Remove animations is on.
     * @return Whether to fade.
     */
    fun isEnabled(increaseContrast: Boolean, reduceTransparency: Boolean, removeAnimations: Boolean = false): Boolean =
        !increaseContrast && !reduceTransparency && !removeAnimations

    /**
     * The fade under the header pinned at the viewport start, if any.
     *
     * A header is pinned when its offset is at or before [viewportStart] (a header being pushed
     * away has a negative offset). Sticky headers pin at the list's top edge, so the band starts
     * at the pinned header's height.
     *
     * @param items Visible items (the pinned header included).
     * @param viewportStart Viewport start offset (`LazyListLayoutInfo.viewportStartOffset`).
     * @param firstHeaderKey Key of the list's first header; its fade ramps in as it pins.
     * @param spacing Gap between items in px.
     * @param depth Fade depth in px; 0 keeps a hard edge (accessibility modes, [isEnabled]).
     * @return The edge, or null when nothing is pinned or nothing has scrolled under it yet
     *   (the header then sits at rest and draws itself).
     */
    fun edge(items: List<EdgeFadeItem>, viewportStart: Int, firstHeaderKey: Any?, spacing: Int, depth: Float): EdgeFade? {
        if (firstHeaderKey == null) return null
        val pinned = items.firstOrNull { it.isHeader && it.offset <= viewportStart } ?: return null
        val top = pinned.size.toFloat()
        if (pinned.key != firstHeaderKey) return EdgeFade(top, 1f)
        // The first header's rows: ramp in over the first `depth` px scrolled under it. The row
        // after the header sits `size + spacing` below the header's natural (unpinned) position.
        val next = items.firstOrNull { it.index == pinned.index + 1 && !it.isHeader } ?: return EdgeFade(top, 1f)
        val scrolled = viewportStart + pinned.size + spacing - next.offset
        if (scrolled <= 0) return null
        return EdgeFade(top, if (depth > 0f) (scrolled / depth).coerceIn(0f, 1f) else 1f)
    }

    /**
     * Headers that reach above the bottom of the fade band and are redrawn whole and opaque over
     * the cut and the band: the pinned header (also while it is pushed away) and the next header
     * on its way up to push it. Without this the incoming header faded out inside the band like a
     * row and popped back opaque as it crossed the cut, instead of sliding up and pushing the
     * pinned one out (issue #288).
     *
     * @param items Visible items.
     * @param viewportStart Viewport start offset.
     * @param top The cut ([EdgeFade.top]) in px from the list's top edge.
     * @param depth Fade band depth in px below the cut (0 for a hard edge).
     * @return Headers with any part between the list's top edge and `top + depth`, in list order.
     */
    fun headersOverEdge(items: List<EdgeFadeItem>, viewportStart: Int, top: Float, depth: Float): List<EdgeFadeItem> =
        items.filter { it.isHeader && it.offset - viewportStart < top + depth && it.offset - viewportStart + it.size > 0 }

    /**
     * Mask alpha at a stop, scaled by the fade strength (1 = unchanged row).
     *
     * @param stopAlpha Full-strength alpha at the stop.
     * @param strength Fade strength.
     * @return Mask alpha.
     */
    fun maskAlpha(stopAlpha: Float, strength: Float): Float = 1f - strength.coerceIn(0f, 1f) * (1f - stopAlpha)

    private fun smoothstep(t: Float): Float = t * t * (3f - 2f * t)
}

// endregion
