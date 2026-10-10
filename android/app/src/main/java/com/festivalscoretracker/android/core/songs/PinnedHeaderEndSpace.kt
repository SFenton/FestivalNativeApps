package com.festivalscoretracker.android.core.songs

// region Pinned section header end space

/**
 * Room at the end of a sticky-header list so the last section push can finish (issue #560).
 *
 * Compose pins a sticky header at the viewport start and pushes it out as the next header
 * arrives: the pinned header sits at `next.offset - pinned.size`. When the list's last scroll
 * position puts the next header between the pin line and the pinned header's height, the list
 * cannot scroll any further, so the pinned title rests half pushed off the top and the next one
 * floats just under it (section-headers R4/R5). The fix adds exactly the distance that next header
 * still has to travel to its pin line to the list's end padding, so it can finish the push and pin
 * whole. A list whose end already rests outside a push needs no room (0), and rows stay reachable
 * because the space only ever grows the scroll range.
 *
 * The result is the same at any scroll position once the list's last item is laid out, also
 * after the space was added, because it is measured against [baseEndPadding] (the padding without
 * the space), so applying it never feeds back into the next measurement. Pure geometry.
 */
object PinnedHeaderEndSpace {
    /**
     * Extra end padding in px for the list's current layout.
     *
     * Only headers laid out at their natural position count: one below the viewport start, or one
     * at or above it whose first row still sits right below it. A pinned header that rows scroll
     * under, or one being pushed away, is not at its natural place.
     *
     * @param items Laid-out items, in any order (the pinned header included).
     * @param viewportStart Viewport start offset (`LazyListLayoutInfo.viewportStartOffset`).
     * @param viewportEnd Viewport end offset (`LazyListLayoutInfo.viewportEndOffset`).
     * @param baseEndPadding The list's end content padding in px without the extra space.
     * @param spacing Gap between items in px.
     * @param lastIndex Index of the list's last item (`totalItemsCount - 1`).
     * @param firstHeaderKey Key of the list's first header (nothing is pinned above it), or null
     *   when the list has no headers.
     * @return The extra space in px (0 when the end needs none), or null when the last item is not
     *   laid out, so the end position is unknown and the caller keeps its previous value.
     */
    fun extra(
        items: List<EdgeFadeItem>,
        viewportStart: Int,
        viewportEnd: Int,
        baseEndPadding: Int,
        spacing: Int,
        lastIndex: Int,
        firstHeaderKey: Any?,
    ): Int? {
        if (firstHeaderKey == null) return 0
        val last = items.firstOrNull { it.index == lastIndex } ?: return null
        // How far the content still moves before the last item rests on the base end padding.
        val remaining = (last.offset + last.size) - (viewportEnd - baseEndPadding)
        val sorted = items.sortedBy { it.index }
        val incoming = sorted.firstOrNull { item ->
            item.isHeader && natural(item, sorted, viewportStart, spacing) && item.offset - remaining - viewportStart > 0
        } ?: return 0
        if (incoming.key == firstHeaderKey) return 0
        val atEnd = incoming.offset - remaining - viewportStart
        val reach = sorted.lastOrNull { it.isHeader && it.index < incoming.index }?.size ?: incoming.size
        return if (atEnd < reach) atEnd else 0
    }

    /** Whether [header] is laid out where the list's flow puts it, not pinned or pushed. */
    private fun natural(header: EdgeFadeItem, items: List<EdgeFadeItem>, viewportStart: Int, spacing: Int): Boolean {
        if (header.offset > viewportStart) return true
        val next = items.firstOrNull { it.index == header.index + 1 } ?: return false
        return next.offset == header.offset + header.size + spacing
    }
}

// endregion
