package com.festivalscoretracker.android.core.songs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SongHeaderEdgeFadeTest {
    private val depth = 28f
    private val spacing = 4

    private fun header(index: Int, key: String, offset: Int, size: Int = 40) = EdgeFadeItem(index, key, offset, size, isHeader = true)
    private fun row(index: Int, offset: Int, size: Int = 80) = EdgeFadeItem(index, "song$index", offset, size, isHeader = false)

    @Test
    fun noPinnedHeaderKeepsTheHardEdge() {
        // List at the top: the first header sits below the search field.
        val items = listOf(row(0, 0, 60), header(1, "header:a", 64), row(2, 108))
        assertNull(SongHeaderEdgeFade.edge(items, 0, "header:a", spacing, depth))
        assertNull(SongHeaderEdgeFade.edge(emptyList(), 0, "header:a", spacing, depth))
        assertNull(SongHeaderEdgeFade.edge(items, 0, null, spacing, depth))
    }

    @Test
    fun firstHeaderRampsInOverTheDepth() {
        // Just pinned: its first row still sits right under it, so nothing fades yet.
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 44)), 0, "header:a", spacing, depth))
        // Scrolled 14 px under it: half strength.
        val half = SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 30)), 0, "header:a", spacing, depth)
        assertEquals(EdgeFade(40f, 0.5f), half)
        // Far past it: full strength, clamped.
        val full = SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, -200), row(3, -116)), 0, "header:a", spacing, depth)
        assertEquals(EdgeFade(40f, 1f), full)
    }

    @Test
    fun firstHeaderWithoutItsNextRowVisibleIsFull() {
        val items = listOf(row(5, -60), header(1, "header:a", 0), row(6, 24))
        assertEquals(EdgeFade(40f, 1f), SongHeaderEdgeFade.edge(items, 0, "header:a", spacing, depth))
    }

    @Test
    fun laterHeadersFadeFullyFromTheirRestingEdge() {
        val items = listOf(header(9, "header:b", 0, 36), row(12, 10), row(13, 94))
        assertEquals(EdgeFade(36f, 1f), SongHeaderEdgeFade.edge(items, 0, "header:a", spacing, depth))
    }

    @Test
    fun pushedHeaderKeepsTheBandAtItsRestingHeight() {
        // The next header pushes the pinned one up; the band stays at the header height.
        val items = listOf(header(9, "header:b", -12), row(20, -60), header(21, "header:c", 32))
        assertEquals(EdgeFade(40f, 1f), SongHeaderEdgeFade.edge(items, 0, "header:a", spacing, depth))
    }

    @Test
    fun negativeViewportStartFromContentPadding() {
        val items = listOf(header(1, "header:a", -24), row(2, -24 + 44 - 28))
        assertEquals(EdgeFade(40f, 1f), SongHeaderEdgeFade.edge(items, -24, "header:a", spacing, depth))
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", -24), row(2, 20)), -24, "header:a", spacing, depth))
    }

    @Test
    fun zeroDepthKeepsAHardCut() {
        // Accessibility modes: rows are still hidden under the header, with no fade band.
        assertEquals(EdgeFade(40f, 1f), SongHeaderEdgeFade.edge(listOf(header(9, "header:b", 0)), 0, "header:a", spacing, 0f))
        assertEquals(EdgeFade(40f, 1f), SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 30)), 0, "header:a", spacing, 0f))
        assertNull(SongHeaderEdgeFade.edge(listOf(header(1, "header:a", 0), row(2, 44)), 0, "header:a", spacing, 0f))
    }

    @Test
    fun noHeadersMeansNoEdge() {
        assertNull(SongHeaderEdgeFade.edge(listOf(header(9, "header:b", 0)), 0, null, spacing, depth))
    }

    @Test
    fun headersOverTheEdgeAreThePinnedAndPushingOnes() {
        // Pinned header pushed up 12 px by the next one; a row and a later header sit lower.
        val pinned = header(9, "header:b", -12)
        val pushing = header(21, "header:c", 28)
        val items = listOf(pinned, row(20, -60), pushing, row(22, 72), header(30, "header:d", 400))
        assertEquals(listOf(pinned, pushing), SongHeaderEdgeFade.headersOverEdge(items, 0, 40f, depth))
        // A header scrolled fully above the list's top edge, or starting below the band, is not redrawn.
        assertEquals(emptyList<EdgeFadeItem>(), SongHeaderEdgeFade.headersOverEdge(listOf(header(1, "header:a", -40), header(2, "header:e", 68)), 0, 40f, depth))
        // Offsets are measured from the viewport start (content padding before the first item).
        assertEquals(listOf(header(1, "header:a", -24)), SongHeaderEdgeFade.headersOverEdge(listOf(header(1, "header:a", -24), row(2, 20)), -24, 40f, depth))
    }

    @Test
    fun incomingHeaderInsideTheBandIsRedrawnBeforeItReachesTheCut() {
        // Issue #288: the next header is still wholly below the cut (40) but inside the 28 px band,
        // so it is drawn opaque instead of fading out like a row, and keeps sliding up unfaded.
        val pinned = header(9, "header:b", 0)
        for (offset in 41..67) {
            val incoming = header(21, "header:c", offset)
            assertEquals(listOf(pinned, incoming), SongHeaderEdgeFade.headersOverEdge(listOf(pinned, row(20, offset - 84), incoming), 0, 40f, depth))
        }
        // Rows in the band are never redrawn.
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

    @Test
    fun accessibilityModesKeepTheHardEdge() {
        assertTrue(SongHeaderEdgeFade.isEnabled(increaseContrast = false, reduceTransparency = false))
        assertFalse(SongHeaderEdgeFade.isEnabled(increaseContrast = true, reduceTransparency = false))
        assertFalse(SongHeaderEdgeFade.isEnabled(increaseContrast = false, reduceTransparency = true))
        assertFalse(SongHeaderEdgeFade.isEnabled(increaseContrast = true, reduceTransparency = true))
    }

    @Test
    fun stopsAreAnEasedRampFromTransparentToOpaque() {
        val stops = SongHeaderEdgeFade.STOPS
        assertEquals(listOf(0f, 0.25f, 0.5f, 0.75f, 1f), stops.map { it.first })
        assertEquals(0f, stops.first().second, 0f)
        assertEquals(0.15625f, stops[1].second, 1e-6f)
        assertEquals(0.5f, stops[2].second, 1e-6f)
        assertEquals(0.84375f, stops[3].second, 1e-6f)
        assertEquals(1f, stops.last().second, 0f)
        assertEquals(SongHeaderEdgeFade.DEPTH_DP, 28f, 0f)
    }

    @Test
    fun maskAlphaScalesWithStrength() {
        assertEquals(1f, SongHeaderEdgeFade.maskAlpha(0f, 0f), 0f)
        assertEquals(0.5f, SongHeaderEdgeFade.maskAlpha(0f, 0.5f), 1e-6f)
        assertEquals(0f, SongHeaderEdgeFade.maskAlpha(0f, 1f), 0f)
        assertEquals(0f, SongHeaderEdgeFade.maskAlpha(0f, 2f), 0f)
        assertEquals(1f, SongHeaderEdgeFade.maskAlpha(1f, 1f), 0f)
    }
}
