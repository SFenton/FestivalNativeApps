package com.festivalscoretracker.android.ui.shop

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/** Item Shop layout metrics: the M3 / web 1040 dp content cap and grid card text room. Hinge columns: `ShopColumnPolicyTest`. */
class ShopLayoutTest {
    @Test
    fun sideMarginIsSixteenUntilTheContentReachesTheCapThenCentres() {
        assertEquals(16f, shopSideMargin(411f), 0f)
        assertEquals(16f, shopSideMargin(1072f), 0f)
        assertEquals(20f, shopSideMargin(1080f), 0f)
        assertEquals(440f, shopSideMargin(1920f), 0f)
        assertEquals(SHOP_CONTENT_MAX_WIDTH_DP, 1920f - 2 * shopSideMargin(1920f), 0f)
    }

    @Test
    fun cardTextSplitsTheTileRoomTwoThirdsToTheTitleAndKeepsOneLineEach() {
        val (title, artist) = shopCardTextHeights(150.dp, 40.dp, 32.dp, badge = false)
        assertEquals(128.dp - artist, title)
        assertEquals(128.dp / 3, artist)
        // A Leaving Tomorrow pill shrinks the room, but each text keeps at least one line.
        val (badgeTitle, badgeArtist) = shopCardTextHeights(150.dp, 40.dp, 32.dp, badge = true)
        assertEquals(32.dp, badgeArtist)
        assertEquals(40.dp, badgeTitle)
    }
}