package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.EmptyRegion
import com.festivalscoretracker.android.core.shell.EmptyRegion.Item
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The empty-state region left by the items around it (issue #377, `empty-error-states` R2). */
class EmptyRegionTest {
    @Test
    fun fillsWhatTheControlsAboveLeave() {
        // Controls 0..120, 12 px gap, empty state natural 200 px tall; viewport content ends at 900.
        assertEquals(900 - 132, EmptyRegion.height(listOf(Item(0, 0, 120), Item(1, 132, 332)), index = 1, usableEnd = 900))
    }

    @Test
    fun leavesRoomForTrailingItemsAndTheirGap() {
        // A 48 px pager row 12 px below the state.
        val visible = listOf(Item(0, 0, 120), Item(1, 132, 332), Item(2, 344, 392))
        assertEquals(900 - 132 - 60, EmptyRegion.height(visible, index = 1, usableEnd = 900))
    }

    @Test
    fun ignoresScrollingWhileTheFirstItemIsVisible() {
        val scrolled = listOf(Item(0, -40, 80), Item(1, 92, 292))
        assertEquals(900 - 132, EmptyRegion.height(scrolled, index = 1, usableEnd = 900))
    }

    @Test
    fun anOnlyItemFillsTheViewport() {
        assertEquals(700, EmptyRegion.height(listOf(Item(0, 0, 50)), index = 0, usableEnd = 700))
    }

    @Test
    fun neverNegativeWhenControlsOutgrowTheViewport() {
        assertEquals(0, EmptyRegion.height(listOf(Item(0, 0, 1_000), Item(1, 1_012, 1_100)), index = 1, usableEnd = 900))
    }

    @Test
    fun unknownUntilLaidOut() {
        assertNull(EmptyRegion.height(listOf(Item(0, 0, 120)), index = 1, usableEnd = 900))
    }
}
