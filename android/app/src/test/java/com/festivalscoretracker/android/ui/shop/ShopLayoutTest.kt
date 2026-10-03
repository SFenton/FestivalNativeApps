package com.festivalscoretracker.android.ui.shop

import org.junit.Assert.assertEquals
import org.junit.Test

/** Item Shop layout metrics: web column breakpoints and the M3 / web 1040 dp content cap. */
class ShopLayoutTest {
    @Test
    fun columnsFollowTheWebBreakpoints() {
        assertEquals(2, shopGridColumns(599f))
        assertEquals(3, shopGridColumns(600f))
        assertEquals(4, shopGridColumns(860f))
        assertEquals(5, shopGridColumns(1100f))
    }

    @Test
    fun sideMarginIsSixteenUntilTheContentReachesTheCapThenCentres() {
        assertEquals(16f, shopSideMargin(411f), 0f)
        assertEquals(16f, shopSideMargin(1072f), 0f)
        assertEquals(20f, shopSideMargin(1080f), 0f)
        assertEquals(440f, shopSideMargin(1920f), 0f)
        assertEquals(SHOP_CONTENT_MAX_WIDTH_DP, 1920f - 2 * shopSideMargin(1920f), 0f)
    }
}
