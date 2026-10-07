package com.festivalscoretracker.android.core.scrolledge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrollEdgeFadeTest {
    /**
     * R3: the web's `useScrollMask` 40 px ramp at the top and above a board's footer (issue #329:
     * `Page.tsx` masks the board pages with it, not with `useScrollFade`'s 36 px).
     */
    @Test
    fun rampsMatchTheWeb() {
        assertEquals(40f, ScrollEdgeFade.TOP_DP)
        assertEquals(40f, ScrollEdgeFade.BOTTOM_DP)
    }

    @Test
    fun everyAccessibilityModeGivesAHardEdge() {
        assertFalse(ScrollEdgeFade.isHardEdge(increaseContrast = false))
        assertTrue(ScrollEdgeFade.isHardEdge(increaseContrast = true))
        assertTrue(ScrollEdgeFade.isHardEdge(increaseContrast = false, highContrastText = true))
        assertTrue(ScrollEdgeFade.isHardEdge(increaseContrast = false, reduceTransparency = true))
        assertTrue(ScrollEdgeFade.isHardEdge(increaseContrast = false, removeAnimations = true))
    }

    @Test
    fun depthFollowsTheScrollUpToTheFullRamp() {
        assertEquals(0f, ScrollEdgeFade.depth(0f, 40f))
        assertEquals(14f, ScrollEdgeFade.depth(14f, 40f))
        assertEquals(40f, ScrollEdgeFade.depth(400f, 40f))
        assertEquals(40f, ScrollEdgeFade.depth(Float.POSITIVE_INFINITY, 40f))
    }

    @Test
    fun depthIsZeroForAHardEdgeOrBadInput() {
        assertEquals(0f, ScrollEdgeFade.depth(-5f, 40f))
        assertEquals(0f, ScrollEdgeFade.depth(20f, 0f))
        assertEquals(0f, ScrollEdgeFade.depth(20f, -1f))
        assertEquals(0f, ScrollEdgeFade.depth(Float.NaN, 40f))
        assertEquals(0f, ScrollEdgeFade.depth(20f, Float.NaN))
    }
}