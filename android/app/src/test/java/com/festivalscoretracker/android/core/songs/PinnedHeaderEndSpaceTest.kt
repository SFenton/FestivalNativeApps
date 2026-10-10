package com.festivalscoretracker.android.core.songs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [PinnedHeaderEndSpace] (issue #560): the end of a sticky-header list leaves exactly the room the
 * last section push needs to finish, and nothing otherwise.
 *
 * Geometry: headers 40 px, rows 80 px, 4 px spacing, 16 px base end padding. Header A (index 0,
 * the first header) heads rows 1–5; header B (index 6) heads rows 7–8, the list's last items.
 * With the viewport ending at 244 px and no extra space, the list's last scroll position leaves B
 * 20 px below the pin line, pushing A half out (the reported rest state).
 */
class PinnedHeaderEndSpaceTest {
    private val spacing = 4
    private val base = 16
    private val last = 8

    private fun header(index: Int, key: String, offset: Int, size: Int = 40) = EdgeFadeItem(index, key, offset, size, isHeader = true)
    private fun row(index: Int, offset: Int, size: Int = 80) = EdgeFadeItem(index, "song$index", offset, size, isHeader = false)

    private fun extra(items: List<EdgeFadeItem>, viewportEnd: Int = 244, first: Any? = "header:a") =
        PinnedHeaderEndSpace.extra(items, 0, viewportEnd, base, spacing, last, first)

    /** The reported state: at the list end, B rests 20 px down and A is pushed half off. */
    @Test
    fun anUnfinishedPushAtTheEndGetsTheRemainingDistance() {
        val atEnd = listOf(header(0, "header:a", -20), row(5, -64), header(6, "header:b", 20), row(7, 64), row(8, 148))
        assertEquals(20, extra(atEnd))
    }

    /** Applied, the space lets B reach its pin line, and the value does not change (no feedback). */
    @Test
    fun theSpaceIsStableOnceApplied() {
        // At the new end: B pinned at its line, its first row right below it, A gone.
        assertEquals(20, extra(listOf(header(6, "header:b", 0), row(7, 44), row(8, 128))))
        // Scrolled back 10 px from there: A is pushed again and B sits 10 px down.
        assertEquals(20, extra(listOf(header(0, "header:a", -30), row(5, -74), header(6, "header:b", 10), row(7, 54), row(8, 138))))
    }

    /** The same answer from higher up, while A is pinned at rest and the last row is just visible. */
    @Test
    fun theSpaceIsKnownBeforeTheEndIsReached() {
        val above = listOf(header(0, "header:a", 0), row(4, -48), row(5, 36), header(6, "header:b", 120), row(7, 164), row(8, 248))
        assertEquals(20, extra(above))
    }

    /** An end where the incoming header rests at or below the pinned one's bottom needs no room. */
    @Test
    fun anEndOutsideAPushNeedsNoRoom() {
        // B rests 80 px down: A is fully pinned above it.
        assertEquals(0, extra(listOf(header(0, "header:a", 0), row(5, -24), header(6, "header:b", 80), row(7, 124), row(8, 208)), viewportEnd = 304))
        // B rests exactly A's height down: A pinned whole, B right below it.
        assertEquals(0, extra(listOf(header(0, "header:a", 0), row(5, -44), header(6, "header:b", 40), row(7, 84), row(8, 168)), viewportEnd = 264))
        // B rests at its pin line: the push already finished.
        assertEquals(0, extra(listOf(header(6, "header:b", 0), row(7, 44), row(8, 128)), viewportEnd = 224))
        // The last section is taller than the viewport: no header near the top at the end.
        assertEquals(0, extra(listOf(header(6, "header:b", 0), row(7, -100), row(8, -16)), viewportEnd = 80))
    }

    /** The reach is the pinned header's height, which can differ from the incoming one (text scaling). */
    @Test
    fun theReachIsThePinnedHeadersHeight() {
        val tall = listOf(header(0, "header:a", -10, size = 60), row(5, -64), header(6, "header:b", 50), row(7, 94), row(8, 178))
        assertEquals(50, extra(tall, viewportEnd = 274))
    }

    /** Unknown or header-free layouts. */
    @Test
    fun unknownAndHeaderFreeLayouts() {
        // The last row is not laid out: the end position is unknown, so the caller keeps its value.
        assertNull(extra(listOf(header(0, "header:a", 0), row(1, 44), row(2, 128))))
        // Title and Artist sorts have no sticky headers.
        assertEquals(0, extra(listOf(row(7, 0), row(8, 84)), first = null))
        // A short list whose first header is near the top: nothing is pinned above it.
        assertEquals(0, PinnedHeaderEndSpace.extra(listOf(row(0, 0, 10), header(1, "header:a", 14), row(2, 58)), 0, 600, base, spacing, 2, "header:a"))
    }
}
