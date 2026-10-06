package com.festivalscoretracker.android.core.rankings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BoardFooterEdgeFadeTest {
    private val depth = 40f

    @Test
    fun depthMatchesTheWebScrollFade() {
        assertEquals(36f, BoardFooterEdgeFade.DEPTH_DP)
    }

    @Test
    fun rampIsLinearFromOpaqueToClearAtTheFooter() {
        assertEquals(listOf(0f to 1f, 1f to 0f), BoardFooterEdgeFade.STOPS)
    }

    @Test
    fun maskAlphaScalesTheRampByStrength() {
        assertEquals(0f, BoardFooterEdgeFade.maskAlpha(0f, 1f))
        assertEquals(1f, BoardFooterEdgeFade.maskAlpha(1f, 1f))
        assertEquals(0.5f, BoardFooterEdgeFade.maskAlpha(0f, 0.5f))
        assertEquals(1f, BoardFooterEdgeFade.maskAlpha(0f, 0f))
        assertEquals(0f, BoardFooterEdgeFade.maskAlpha(-1f, 2f))
    }

    @Test
    fun accessibilityModesKeepAHardEdge() {
        assertTrue(BoardFooterEdgeFade.isEnabled(increaseContrast = false, reduceTransparency = false))
        assertFalse(BoardFooterEdgeFade.isEnabled(increaseContrast = true, reduceTransparency = false))
        assertFalse(BoardFooterEdgeFade.isEnabled(increaseContrast = false, reduceTransparency = true))
    }

    @Test
    fun remainingScrollIsUnboundedUntilTheLastItemIsLaidOut() {
        assertEquals(Float.POSITIVE_INFINITY, BoardFooterEdgeFade.remainingScroll(27, 20, 900, 60, 200, 1000))
        assertEquals(0f, BoardFooterEdgeFade.remainingScroll(0, -1, 0, 0, 0, 1000))
    }

    @Test
    fun remainingScrollCountsTheBottomPadding() {
        // Last row ends at 980, plus 200 px padding = 1180 against a 1000 px viewport end.
        assertEquals(180f, BoardFooterEdgeFade.remainingScroll(27, 26, 920, 60, 200, 1000))
        // Scrolled past the end (overscroll) never goes negative.
        assertEquals(0f, BoardFooterEdgeFade.remainingScroll(27, 26, 700, 60, 200, 1000))
    }

    @Test
    fun strengthEasesOutOverTheLastDepth() {
        assertEquals(1f, BoardFooterEdgeFade.strength(Float.POSITIVE_INFINITY, depth))
        assertEquals(1f, BoardFooterEdgeFade.strength(80f, depth))
        assertEquals(0.5f, BoardFooterEdgeFade.strength(20f, depth))
        assertEquals(0f, BoardFooterEdgeFade.strength(0f, depth))
        assertEquals(0f, BoardFooterEdgeFade.strength(Float.NaN, depth))
        assertEquals(0f, BoardFooterEdgeFade.strength(80f, 0f))
    }

    @Test
    fun edgeSitsAtTheFooterTop() {
        assertEquals(FooterFade(1700f, 1f), BoardFooterEdgeFade.edge(2000, 300, 500f, depth))
        assertEquals(FooterFade(1700f, 0.25f), BoardFooterEdgeFade.edge(2000, 300, 10f, depth))
        assertEquals(FooterFade(0f, 1f), BoardFooterEdgeFade.edge(200, 300, 500f, depth))
    }

    @Test
    fun noFooterNoEdge() {
        assertNull(BoardFooterEdgeFade.edge(2000, 0, 500f, depth))
        assertNull(BoardFooterEdgeFade.edge(0, 300, 500f, depth))
    }
}
