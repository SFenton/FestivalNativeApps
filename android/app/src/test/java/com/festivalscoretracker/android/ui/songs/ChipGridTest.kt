package com.festivalscoretracker.android.ui.songs

import org.junit.Assert.assertEquals
import org.junit.Test

/** [ChipGrid]: balanced, centred chip rows (the Songs row status chips). */
class ChipGridTest {
    @Test
    fun nineChipsOnAPhoneWrapFivePlusFourCentred() {
        // 34 px chips, 4 px gaps, 200 px: 5 fit, so 9 → 2 rows of 5 + 4.
        val grid = ChipGrid(9, 200f, 34f, 4f)
        assertEquals(34f * 2 + 4f, grid.height)
        val rowFive = 5 * 34f + 4 * 4f
        assertEquals((200f - rowFive) / 2, grid.topLeft(0).x)
        assertEquals(0f, grid.topLeft(4).y)
        val rowFour = 4 * 34f + 3 * 4f
        assertEquals((200f - rowFour) / 2, grid.topLeft(5).x)
        assertEquals(38f, grid.topLeft(5).y)
    }

    @Test
    fun wideCardsUseOneRow() {
        val grid = ChipGrid(9, 1_000f, 34f, 4f)
        assertEquals(34f, grid.height)
        assertEquals(38f * 8, grid.topLeft(8).x - grid.topLeft(0).x)
    }

    @Test
    fun narrowWidthStillPlacesOnePerRow() {
        val grid = ChipGrid(3, 10f, 34f, 4f)
        assertEquals(3 * 34f + 2 * 4f, grid.height)
        assertEquals(76f, grid.topLeft(2).y)
    }
}
