package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade

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
 *   are hidden above it (the header has no backing, issue #91) and fade in over the ramp below it.
 * @property depth Ramp height in px below [top]: rows are clear at [top] and fully drawn [depth]
 *   below it; 0 is a hard cut.
 */
data class EdgeFade(val top: Float, val depth: Float)

/**
 * The cut and linear ramp under a pinned section header (scroll-edge R2, R3, R5; issues #49,
 * #308): rows scrolling under the header are hidden behind it, fully clear at its bottom edge,
 * and fully drawn [ScrollEdgeFade.TOP_DP] below it (the web's `useScrollMask`).
 *
 * The header has no backing (issue #91): rows never show through it because the list hides
 * everything above [EdgeFade.top] and redraws only the headers there ([headersOverEdge]), so the
 * next header slides up and pushes the pinned one out 1:1 without fading (issue #288).
 *
 * The ramp grows with the scroll, like the web's `min(scrollTop, distance)`: its depth is the
 * distance scrolled under the pinned header, capped by the room left above the incoming header
 * and by the full ramp. So nothing is dimmed at rest (R4), a section that has just pinned (after a
 * Quick Links jump or a push) shows its first row fully opaque (R8), and the ramp reaches 0 as the
 * incoming header arrives, so the handoff never snaps. Pure geometry: the UI reads it in the draw
 * phase only.
 */
object SongHeaderEdgeFade {
    /**
     * The edge under the header pinned at the viewport start, if any.
     *
     * A header is pinned when its offset is at or before [viewportStart] (a header being pushed
     * away has a negative offset). Sticky headers pin at the list's top edge, so the cut sits at
     * the pinned header's height.
     *
     * @param items Visible items (the pinned header included).
     * @param viewportStart Viewport start offset (`LazyListLayoutInfo.viewportStartOffset`).
     * @param spacing Gap between items in px.
     * @param fullDepth Full ramp in px ([ScrollEdgeFade.TOP_DP]); 0 keeps a hard cut (R7).
     * @return The edge, or null when nothing is pinned or nothing has scrolled under it yet
     *   (the header then sits at rest and draws itself).
     */
    fun edge(items: List<EdgeFadeItem>, viewportStart: Int, spacing: Int, fullDepth: Float): EdgeFade? {
        val pinned = pinned(items, viewportStart) ?: return null
        val top = pinned.size.toFloat()
        val scrolled = scrolledUnder(items, pinned, viewportStart, spacing)
        if (scrolled <= 0f) return null
        val incoming = items.firstOrNull { it.isHeader && it.index > pinned.index && it.offset > viewportStart }
        val room = incoming?.let { (it.offset - viewportStart) - top } ?: Float.POSITIVE_INFINITY
        return EdgeFade(top, ScrollEdgeFade.depth(minOf(scrolled, room), fullDepth))
    }

    /**
     * The header pinned at the viewport start: the first header whose offset is at or before
     * [viewportStart] (negative while the next header pushes it away), or a header resting
     * exactly there. TalkBack reads it before the rows beneath it (scroll-edge R5).
     *
     * @param items Visible items (the pinned header included).
     * @param viewportStart Viewport start offset.
     * @return The pinned header, or null when no header sits at the list's top edge.
     */
    fun pinned(items: List<EdgeFadeItem>, viewportStart: Int): EdgeFadeItem? =
        items.firstOrNull { it.isHeader && it.offset <= viewportStart }

    /**
     * How far the pinned header's section has scrolled under it: 0 when its first row still sits
     * right below the header, infinite once that row has left the viewport.
     */
    private fun scrolledUnder(items: List<EdgeFadeItem>, pinned: EdgeFadeItem, viewportStart: Int, spacing: Int): Float {
        // The row after the header sits `size + spacing` below the header's natural (unpinned) position.
        val next = items.firstOrNull { it.index == pinned.index + 1 }
        if (next == null || next.isHeader) return Float.POSITIVE_INFINITY
        return (viewportStart + pinned.size + spacing - next.offset).toFloat()
    }

    /**
     * Headers that reach above the bottom of the ramp and are redrawn whole and opaque over the
     * cut and the ramp: the pinned header (also while it is pushed away) and the next header on
     * its way up to push it. Without this the incoming header faded out inside the ramp like a row
     * and popped back opaque as it crossed the cut, instead of sliding up and pushing the pinned
     * one out (issue #288).
     *
     * @param items Visible items.
     * @param viewportStart Viewport start offset.
     * @param top The cut ([EdgeFade.top]) in px from the list's top edge.
     * @param depth Ramp depth in px below the cut (0 for a hard edge).
     * @return Headers with any part between the list's top edge and `top + depth`, in list order.
     */
    fun headersOverEdge(items: List<EdgeFadeItem>, viewportStart: Int, top: Float, depth: Float): List<EdgeFadeItem> =
        items.filter { it.isHeader && it.offset - viewportStart < top + depth && it.offset - viewportStart + it.size > 0 }
}

// endregion
