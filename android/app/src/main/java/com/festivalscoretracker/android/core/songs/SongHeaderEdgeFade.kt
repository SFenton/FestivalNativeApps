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
 * Where rows fade out below the pinned section header.
 *
 * @property top Top of the fade band in px from the list's top edge (the pinned header's bottom).
 * @property strength 0 = no fade (hard edge), 1 = full fade.
 */
data class EdgeFade(val top: Float, val strength: Float)

/**
 * The soft edge under a pinned Songs section header (issue #49, port of the iOS
 * `SectionBarEdgeFade`, issue #10): rows scrolling under the header fade out over a short
 * eased band below it instead of being cut off hard at its bottom edge.
 *
 * The band starts at the pinned header's resting bottom, which does not move while the next
 * header pushes the current one away, so headers and rows pass through the same band without
 * any jump. It appears gradually over the first [DEPTH_DP] of scrolling after the first header
 * pins, so the rows below it never fade at once. Pure geometry: the UI reads it in the draw
 * phase only.
 */
object SongHeaderEdgeFade {
    /** Fade depth below the header (iOS `SectionBarEdgeFade`: 28 pt). */
    const val DEPTH_DP = 28f

    /** Mask alpha stops through the band: smoothstep at 0, ¼, ½, ¾ and 1 (iOS uses the same easing). */
    val STOPS: List<Pair<Float, Float>> = listOf(0f, 0.25f, 0.5f, 0.75f, 1f).map { it to smoothstep(it) }

    /**
     * Whether the fade is drawn. Increase Contrast (system high-contrast text or the app toggle)
     * and the app's Reduce Transparency keep the solid, hard edge, as on iOS: the header never
     * sits next to see-through rows in those modes.
     *
     * @param increaseContrast Increase Contrast is on.
     * @param reduceTransparency Reduce Transparency is on.
     * @return Whether to fade.
     */
    fun isEnabled(increaseContrast: Boolean, reduceTransparency: Boolean): Boolean = !increaseContrast && !reduceTransparency

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
     * @param depth Fade depth in px.
     * @return The fade, or null for a hard edge (nothing pinned or not scrolled under yet).
     */
    fun edge(items: List<EdgeFadeItem>, viewportStart: Int, firstHeaderKey: Any?, spacing: Int, depth: Float): EdgeFade? {
        if (depth <= 0f) return null
        val pinned = items.firstOrNull { it.isHeader && it.offset <= viewportStart } ?: return null
        val top = pinned.size.toFloat()
        if (pinned.key != firstHeaderKey) return EdgeFade(top, 1f)
        // The first header's rows: ramp in over the first `depth` px scrolled under it. The row
        // after the header sits `size + spacing` below the header's natural (unpinned) position.
        val next = items.firstOrNull { it.index == pinned.index + 1 && !it.isHeader } ?: return EdgeFade(top, 1f)
        val scrolled = viewportStart + pinned.size + spacing - next.offset
        val strength = (scrolled / depth).coerceIn(0f, 1f)
        return if (strength > 0f) EdgeFade(top, strength) else null
    }

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
