package com.festivalscoretracker.android.core.rankings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BoardFooterEdgeFadeTest {
    private val depth = 40f

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
    fun edgeSitsAtTheFooterTopWithTheFullRampMidList() {
        assertEquals(FooterFade(1700f, 40f), BoardFooterEdgeFade.edge(2000, 300, Float.POSITIVE_INFINITY, depth))
        assertEquals(FooterFade(1700f, 40f), BoardFooterEdgeFade.edge(2000, 300, 500f, depth))
        assertEquals(FooterFade(0f, 40f), BoardFooterEdgeFade.edge(200, 300, 500f, depth))
    }

    /** R4: the ramp shrinks 1:1 with the remaining scroll, so the last row is never faded. */
    @Test
    fun rampShrinksToNothingAtTheEndOfTheList() {
        assertEquals(FooterFade(1700f, 38f), BoardFooterEdgeFade.edge(2000, 300, 38f, depth))
        assertEquals(FooterFade(1700f, 10f), BoardFooterEdgeFade.edge(2000, 300, 10f, depth))
        assertEquals(FooterFade(1700f, 0f), BoardFooterEdgeFade.edge(2000, 300, 0f, depth))
        assertEquals(FooterFade(1700f, 0f), BoardFooterEdgeFade.edge(2000, 300, Float.NaN, depth))
    }

    /** R7: a hard edge still cuts the rows at the footer's top (no leak), with no ramp. */
    @Test
    fun hardEdgeKeepsTheCut() {
        assertEquals(FooterFade(1700f, 0f), BoardFooterEdgeFade.edge(2000, 300, 500f, 0f))
    }

    @Test
    fun noFooterNoEdge() {
        assertNull(BoardFooterEdgeFade.edge(2000, 0, 500f, depth))
        assertNull(BoardFooterEdgeFade.edge(0, 300, 500f, depth))
    }
}
