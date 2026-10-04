package com.festivalscoretracker.android.core.shop

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [ShopColumnPolicy]: web column counts, and no Shop card or row straddles a separating hinge. */
class ShopColumnPolicyTest {
    private val grid: (Int) -> Int = { px -> ShopColumnPolicy.gridColumns(px.toFloat()) }

    @Test
    fun webColumnBreakpoints() {
        assertEquals(2, ShopColumnPolicy.gridColumns(599f))
        assertEquals(3, ShopColumnPolicy.gridColumns(600f))
        assertEquals(3, ShopColumnPolicy.gridColumns(859f))
        assertEquals(4, ShopColumnPolicy.gridColumns(860f))
        assertEquals(4, ShopColumnPolicy.gridColumns(1099f))
        assertEquals(5, ShopColumnPolicy.gridColumns(1100f))
    }

    @Test
    fun withoutHingeCellsShareTheWidthEvenly() {
        val columns = ShopColumnPolicy.resolve(available = 700, gutter = 10, hingeStart = null, hingeEnd = null, minPane = 240, columnsFor = grid)
        assertEquals(listOf(227, 227, 226), columns.sizes)
        assertEquals(listOf(0, 237, 474), columns.positions)
        assertEquals(3, columns.startPaneColumns)
        assertFalse(columns.split)
        assertEquals(700, columns.positions.last() + columns.sizes.last())
    }

    @Test
    fun zeroWidthFoldSplitsTheRowWithAGutterOnTheFold() {
        // Book Fold half-open: a zero-width fold at 380 px of a 760 px content area.
        val columns = ShopColumnPolicy.resolve(available = 760, gutter = 10, hingeStart = 380, hingeEnd = 380, minPane = 240, columnsFor = grid)
        assertTrue(columns.split)
        assertEquals(2, columns.startPaneColumns)
        assertEquals(4, columns.count)
        assertNothingStraddles(columns, 380, 380)
        assertEquals(375, columns.positions[1] + columns.sizes[1])
        assertEquals(385, columns.positions[2])
        assertEquals(760, columns.positions.last() + columns.sizes.last())
    }

    @Test
    fun physicalHingeWiderThanTheGutterBecomesTheGap() {
        val columns = ShopColumnPolicy.resolve(available = 1000, gutter = 10, hingeStart = 480, hingeEnd = 540, minPane = 240, columnsFor = { 1 })
        assertEquals(listOf(480, 460), columns.sizes)
        assertEquals(listOf(0, 540), columns.positions)
        assertEquals(1, columns.startPaneColumns)
        assertNothingStraddles(columns, 480, 540)
    }

    @Test
    fun offCentreHingeGivesEachPaneItsOwnColumnCount() {
        val columns = ShopColumnPolicy.resolve(available = 1500, gutter = 10, hingeStart = 900, hingeEnd = 900, minPane = 240, columnsFor = grid)
        assertEquals(4, columns.startPaneColumns)
        assertEquals(6, columns.count)
        assertNothingStraddles(columns, 900, 900)
    }

    @Test
    fun hingeOutsideOrTooCloseToAnEdgeDoesNotSplit() {
        listOf(-10 to -10, 100 to 100, 700 to 700, 900 to 900).forEach { (start, end) ->
            val columns = ShopColumnPolicy.resolve(available = 760, gutter = 10, hingeStart = start, hingeEnd = end, minPane = 240, columnsFor = grid)
            assertFalse("hinge $start", columns.split)
            assertEquals(3, columns.count)
        }
        val inverted = ShopColumnPolicy.resolve(available = 760, gutter = 10, hingeStart = 400, hingeEnd = 380, minPane = 240, columnsFor = grid)
        assertFalse(inverted.split)
    }

    @Test
    fun uniformGridCellsKeepOneCardSizeAcrossUnequalPanes() {
        // A navigation rail makes the leading pane narrower than the trailing one.
        val columns = ShopColumnPolicy.resolve(available = 700, gutter = 10, hingeStart = 300, hingeEnd = 300, minPane = 240, uniform = true, columnsFor = { 2 })
        assertEquals(listOf(142, 142, 142, 142), columns.sizes)
        assertEquals(listOf(0, 152, 305, 457), columns.positions)
        assertNothingStraddles(columns, 300, 300)
    }

    @Test
    fun narrowPaneNeverAsksForMoreCellsThanFit() {
        val columns = ShopColumnPolicy.resolve(available = 5, gutter = 10, hingeStart = null, hingeEnd = null, minPane = 240, columnsFor = { 4 })
        assertEquals(1, columns.count)
        assertEquals(listOf(5), columns.sizes)
        val empty = ShopColumnPolicy.resolve(available = 0, gutter = 10, hingeStart = null, hingeEnd = null, minPane = 240, columnsFor = { 0 })
        assertEquals(listOf(1), empty.sizes)
    }

    private fun assertNothingStraddles(columns: ShopColumns, hingeStart: Int, hingeEnd: Int) {
        columns.sizes.indices.forEach { index ->
            val left = columns.positions[index]
            val right = left + columns.sizes[index]
            assertTrue("cell $index [$left, $right) crosses [$hingeStart, $hingeEnd]", right <= hingeStart || left >= hingeEnd)
            if (index > 0) assertTrue("cells overlap", left >= columns.positions[index - 1] + columns.sizes[index - 1])
        }
    }
}
