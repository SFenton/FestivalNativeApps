package com.festivalscoretracker.android.core.profile

import org.junit.Assert.assertEquals
import org.junit.Test

/** [StatGridColumns]: adaptive stat-tile columns, including the large-text exception. */
class StatGridColumnsTest {
    @Test
    fun phonesGetTwoColumnsAndWideGridsUpToFour() {
        assertEquals(2, StatGridColumns.count(300f))
        assertEquals(2, StatGridColumns.count(379f))
        assertEquals(3, StatGridColumns.count(460f))
        assertEquals(4, StatGridColumns.count(2_000f))
    }

    @Test
    fun largeTextWidensTilesAndMayDropToOneColumn() {
        // 200% on a 316 dp "largest display size" phone: one column.
        assertEquals(1, StatGridColumns.count(284f, fontScale = 2f))
        // Slightly large text keeps the two-column phone minimum.
        assertEquals(2, StatGridColumns.count(284f, fontScale = 1.15f))
        // Wide grids still get several columns at 200%.
        assertEquals(3, StatGridColumns.count(900f, fontScale = 2f))
    }
}
