package com.festivalscoretracker.android.core.shell

// region Empty region

/**
 * Pure sizing for an empty state that sits among other items of a lazy list or grid (pattern
 * `empty-error-states` R2, issue #377): the state takes the part of the visible viewport the
 * items before it (page controls) and after it (an inline pager) leave, so its text centres in
 * the usable result region on every window height instead of in a fixed-height block.
 *
 * Offsets use the lazy layout's item coordinates: 0 is the start of the content (after the
 * leading content padding) when the list is not scrolled.
 */
object EmptyRegion {
    /**
     * One visible lazy item's main-axis extent.
     *
     * @property index Item index.
     * @property start Main-axis offset of the item's start.
     * @property end Main-axis offset of the item's end (start + size).
     */
    data class Item(val index: Int, val start: Int, val end: Int)

    /**
     * Main-axis size for the empty-state item at [index].
     *
     * The space taken before it is measured from the content's first item, so it does not
     * change while the list is scrolled; the space after it runs to the end of the last visible
     * trailing item, item spacing included.
     *
     * @param visible Visible items (any order).
     * @param index The empty state's item index.
     * @param usableEnd Viewport end less the trailing content padding.
     * @return Height in px (never negative), or null while the item has not been laid out yet.
     */
    fun height(visible: List<Item>, index: Int, usableEnd: Int): Int? {
        val self = visible.firstOrNull { it.index == index } ?: return null
        val contentStart = visible.firstOrNull { it.index == 0 }?.start ?: 0
        val before = self.start - contentStart
        val after = visible.filter { it.index > index }.maxOfOrNull { it.end }?.let { (it - self.end).coerceAtLeast(0) } ?: 0
        return (usableEnd - before - after).coerceAtLeast(0)
    }
}

// endregion
