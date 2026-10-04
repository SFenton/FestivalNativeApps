package com.festivalscoretracker.android.ui.shop

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test
    fun noSeparatingHingeOrAHingeOutsideTheGridKeepsTheNormalGrid() {
        assertNull(shopGridSplit(100, 700, emptyList(), 10, 3, 120))
        // A hinge too close to an edge to leave a tile on each side.
        assertNull(shopGridSplit(100, 700, listOf(150 to 150), 10, 3, 120))
        assertNull(shopGridSplit(100, 700, listOf(1000 to 1000), 10, 3, 120))
    }

    @Test
    fun bookFoldHalfOpenPacksEqualTilesAgainstBothSidesOfTheFold() {
        // Book fold half-open: content starts at x=112 (rail), 716 wide; zero-width fold at x=426.
        val split = shopGridSplit(112, 716, listOf(426 to 426), 10, 3, 120)!!
        // Fold at 314 in content: left panel 0..309, right panel 319..716.
        assertEquals(149, split.cell)
        assertEquals(listOf(1, 160, 319, 478), split.positions)
        val tiles = split.positions.map { it to it + split.cell }
        assertTrue("no tile crosses the fold", tiles.none { (start, end) -> start < 314 && end > 314 })
        assertTrue(tiles.all { (start, end) -> start >= 0 && end <= 716 })
    }

    @Test
    fun aWideHingeBecomesTheGapAndTriFoldPanelsCentreTheirTiles() {
        val wide = shopGridSplit(0, 1000, listOf(480 to 520), 10, 4, 120)!!
        assertEquals(listOf(0, 245, 520, 765), wide.positions)
        assertEquals(235, wide.cell)

        val tri = shopGridSplit(0, 900, listOf(300 to 300, 600 to 600), 10, 3, 120)!!
        assertEquals(290, tri.cell)
        assertEquals(listOf(5, 305, 605), tri.positions)
    }

    @Test
    fun splitCellsAndArrangementPlaceTilesAtTheSplitPositions() {
        val density = Density(1f)
        val split = ShopGridSplit(149, listOf(1, 160, 319, 478))
        val cells = ShopSplitCells(split, 716, 3)
        assertEquals(List(4) { 149 }, with(cells) { density.calculateCrossAxisCellSizes(716, 10) })
        // One frame at another width: equal fallback columns.
        assertEquals(List(3) { 200 }, with(cells) { density.calculateCrossAxisCellSizes(620, 10) })
        assertEquals(cells, ShopSplitCells(split, 716, 3))
        assertEquals(cells.hashCode(), ShopSplitCells(split, 716, 3).hashCode())

        val arrangement = ShopSplitArrangement(split, 10.dp)
        assertEquals(10.dp, arrangement.spacing)
        val out = IntArray(4)
        with(arrangement) { density.arrange(716, IntArray(4) { 149 }, LayoutDirection.Ltr, out) }
        assertEquals(listOf(1, 160, 319, 478), out.toList())
        with(arrangement) { density.arrange(716, IntArray(4) { 149 }, LayoutDirection.Rtl, out) }
        assertEquals(listOf(478, 319, 160, 1), out.toList())
        val fallback = IntArray(3)
        with(arrangement) { density.arrange(620, IntArray(3) { 200 }, LayoutDirection.Ltr, fallback) }
        assertEquals(listOf(0, 210, 420), fallback.toList())
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
