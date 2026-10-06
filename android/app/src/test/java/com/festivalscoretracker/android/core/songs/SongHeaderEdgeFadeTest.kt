package com.festivalscoretracker.android.core.songs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SongHeaderEdgeFadeTest {
    private val depth = 40f
    private val spacing = 4

    private fun header(index: Int, key: String, offset: Int, size: Int = 40) = EdgeFadeItem(index, key, offset, size, isHeader = true)
    private fun row(index: Int, offset: Int, size: Int = 80) = EdgeFadeItem(index, "song$index", offset, size, isHeader = false)

    @Test
    fun noPinnedHeaderMeansNoEdge() {
        // List at the top: the first header sits below a notice row.
        val items = listOf(row(0, 0, 60), header(1, "header:a", 64), row(2, 108))
        assertNull(SongHeaderEdgeFade.edge(items, 0, spacing, depth))
        assertNull(SongHeaderEdgeFade.edge(emptyList(), 0, spacing, depth))
    }

    @Test
    fun rampGrowsWithTheScrollUnderTheFirstHeader() {
        // R4: just pinned, its first row still sits right under it, so nothing is cut or dimmed.
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 44)), 0, spacing, depth))
        // Scrolled 14 px under it: rows are clear at the cut and opaque 14 px below it.
        assertEquals(EdgeFade(40f, 14f), SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 30)), 0, spacing, depth))
        // Far past it: the full 40 px ramp, never deeper.
        assertEquals(EdgeFade(40f, 40f), SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, -200), row(3, -116)), 0, spacing, depth))
    }

    @Test
    fun rampIsFullOnceTheSectionsFirstRowHasLeft() {
        val items = listOf(header(1, "header:a", 0), row(6, 24))
        assertEquals(EdgeFade(40f, 40f), SongHeaderEdgeFade.edge(items, 0, spacing, depth))
    }

    /** R8 / section-jump-landing R3: a section that has just pinned (a Quick Links landing) shows its first row unfaded. */
    @Test
    fun laterSectionsLandWithTheirFirstRowOpaque() {
        assertNull(SongHeaderEdgeFade.edge(listOf(header(9, "header:b", 0, 36), row(10, 40)), 0, spacing, depth))
        assertEquals(EdgeFade(36f, 20f), SongHeaderEdgeFade.edge(listOf(header(9, "header:b", 0, 36), row(10, 20)), 0, spacing, depth))
    }

    @Test
    fun incomingHeaderCapsTheRampSoTheHandoffNeverSnaps() {
        val pinned = header(1, "header:a", 0)
        val deep = row(5, -100)
        assertEquals(EdgeFade(40f, 40f), SongHeaderEdgeFade.edge(listOf(pinned, deep, header(21, "header:c", 100)), 0, spacing, depth))
        assertEquals(EdgeFade(40f, 30f), SongHeaderEdgeFade.edge(listOf(pinned, deep, header(21, "header:c", 70)), 0, spacing, depth))
        assertEquals(EdgeFade(40f, 0f), SongHeaderEdgeFade.edge(listOf(pinned, deep, header(21, "header:c", 40)), 0, spacing, depth))
        // Scroll the incoming header from 90 px up to its pin line, then on under it: the ramp never
        // grows while the header approaches, reaches 0 as it pushes, and only grows again once rows
        // of the new section scroll under it.
        val depths = (90 downTo -40).map { y ->
            val items = if (y > 0) {
                listOf(header(1, "header:a", minOf(0, y - 40)), deep, header(21, "header:c", y), row(22, y + 44))
            } else {
                listOf(header(21, "header:c", 0), row(22, y + 44))
            }
            SongHeaderEdgeFade.edge(items, 0, spacing, depth)?.depth ?: 0f
        }
        val approach = depths.take(91)
        assertTrue("never grows while the incoming header approaches", approach.zipWithNext().all { (a, b) -> b <= a })
        assertEquals(0f, depths[90], 0f)
        val after = depths.drop(90)
        assertTrue("grows from 0 once the new section scrolls", after.zipWithNext().all { (a, b) -> b >= a })
        assertEquals(40f, after.last(), 0f)
    }

    @Test
    fun pushedHeaderKeepsTheCutAtItsRestingHeight() {
        // The next header pushes the pinned one up; the cut stays at the header height, no ramp.
        val items = listOf(header(9, "header:b", -12), row(20, -60), header(21, "header:c", 32))
        assertEquals(EdgeFade(40f, 0f), SongHeaderEdgeFade.edge(items, 0, spacing, depth))
    }

    @Test
    fun emptySectionUsesTheIncomingHeaderAsItsLimit() {
        assertEquals(EdgeFade(40f, 20f), SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), header(2, "header:b", 60)), 0, spacing, depth))
    }

    @Test
    fun negativeViewportStartFromContentPadding() {
        val items = listOf(header(1, "header:a", -24), row(2, -24 + 44 - 28))
        assertEquals(EdgeFade(40f, 28f), SongHeaderEdgeFade.edge(items, -24, spacing, depth))
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", -24), row(2, 20)), -24, spacing, depth))
    }

    @Test
    fun zeroDepthKeepsAHardCut() {
        // R7: rows are still hidden under the header, with no ramp.
        assertEquals(EdgeFade(40f, 0f), SongHeaderEdgeFade.edge(listOf(header(9, "header:b", 0)), 0, spacing, 0f))
        assertEquals(EdgeFade(40f, 0f), SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 30)), 0, spacing, 0f))
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 44)), 0, spacing, 0f))
    }

    @Test
    fun headersOverTheEdgeAreThePinnedAndPushingOnes() {
        // Pinned header pushed up 12 px by the next one; a row and a later header sit lower.
        val pinned = header(9, "header:b", -12)
        val pushing = header(21, "header:c", 28)
        val items = listOf(pinned, row(20, -60), pushing, row(22, 72), header(30, "header:d", 400))
        assertEquals(listOf(pinned, pushing), SongHeaderEdgeFade.headersOverEdge(items, 0, 40f, depth))
        // A header scrolled fully above the list's top edge, or starting below the ramp, is not redrawn.
        assertEquals(emptyList<EdgeFadeItem>(), SongHeaderEdgeFade.headersOverEdge(listOf(header(1, "header:a", -40), header(2, "header:e", 80)), 0, 40f, depth))
        // Offsets are measured from the viewport start (content padding before the first item).
        assertEquals(listOf(header(1, "header:a", -24)), SongHeaderEdgeFade.headersOverEdge(listOf(header(1, "header:a", -24), row(2, 20)), -24, 40f, depth))
    }

    @Test
    fun incomingHeaderInsideTheRampIsRedrawnBeforeItReachesTheCut() {
        // Issue #288: the next header is still wholly below the cut (40) but inside the 40 px ramp,
        // so it is drawn opaque instead of fading out like a row, and keeps sliding up unfaded.
        val pinned = header(9, "header:b", 0)
        for (offset in 41..79) {
            val incoming = header(21, "header:c", offset)
            assertEquals(listOf(pinned, incoming), SongHeaderEdgeFade.headersOverEdge(listOf(pinned, row(20, offset - 84), incoming), 0, 40f, depth))
        }
        // Rows in the ramp are never redrawn.
        assertEquals(listOf(pinned), SongHeaderEdgeFade.headersOverEdge(listOf(pinned, row(10, 44)), 0, 40f, depth))
    }

    @Test
    fun hardEdgeRedrawsOnlyHeadersAboveTheCut() {
        // Accessibility modes (depth 0): a header starting at the cut is drawn normally, unmasked.
        val pinned = header(9, "header:b", -12)
        val incoming = header(21, "header:c", 28)
        assertEquals(listOf(pinned, incoming), SongHeaderEdgeFade.headersOverEdge(listOf(pinned, incoming), 0, 40f, 0f))
        assertEquals(listOf(header(9, "header:b", 0)), SongHeaderEdgeFade.headersOverEdge(listOf(header(9, "header:b", 0), header(21, "header:c", 40)), 0, 40f, 0f))
    }
}
