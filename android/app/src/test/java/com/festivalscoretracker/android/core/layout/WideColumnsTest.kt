package com.festivalscoretracker.android.core.layout

import com.festivalscoretracker.android.core.rivals.ColumnSpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The `wide-columns` policy and its line mapping (#581). */
class WideColumnsTest {
    // region Count

    @Test
    fun portraitPhoneKeepsOneColumn() {
        assertEquals(1, WideColumns.count(411f, 923f, 367f, unfolded = false, bookSplit = false, singleColumn = false))
    }

    @Test
    fun wideLandscapePhoneShowsTwoColumns() {
        assertEquals(2, WideColumns.count(891f, 411f, 803f, unfolded = false, bookSplit = false, singleColumn = false))
    }

    @Test
    fun compactLandscapeTooNarrowForTwoColumnsKeepsOne() {
        assertEquals(1, WideColumns.count(640f, 360f, 596f, unfolded = false, bookSplit = false, singleColumn = false))
        assertEquals(2, WideColumns.count(700f, 360f, WideColumns.MIN_TWO_COLUMN_DP.toFloat(), unfolded = false, bookSplit = false, singleColumn = false))
    }

    @Test
    fun portraitTabletKeepsOneColumn() {
        assertEquals(1, WideColumns.count(800f, 1280f, 756f, unfolded = false, bookSplit = false, singleColumn = false))
    }

    @Test
    fun flatUnfoldedFoldableShowsTwoColumnsEvenWhenTallerThanWide() {
        assertEquals(2, WideColumns.count(851f, 882f, 807f, unfolded = true, bookSplit = false, singleColumn = false))
    }

    @Test
    fun bookPostureAlwaysSplitsAtTheFold() {
        assertEquals(2, WideColumns.count(600f, 900f, 556f, unfolded = true, bookSplit = true, singleColumn = false))
    }

    @Test
    fun screenReaderAndLargeTextKeepOneColumn() {
        assertEquals(1, WideColumns.count(891f, 411f, 803f, unfolded = false, bookSplit = false, singleColumn = true))
        assertEquals(1, WideColumns.count(851f, 882f, 807f, unfolded = true, bookSplit = true, singleColumn = true))
    }

    @Test
    fun minimumTwoColumnWidthHoldsTwoMinimumColumnsAndTheGap() {
        assertEquals(WideColumns.MIN_COLUMN_DP * 2 + WideColumns.SPACING_DP, WideColumns.MIN_TWO_COLUMN_DP)
    }

    // endregion

    // region Spec

    @Test
    fun oneColumnFillsTheContent() {
        assertEquals(ColumnSpec(listOf(700), 12), WideColumns.spec(1, 0, 700, null, null, 320, 12))
    }

    @Test
    fun flatSplitsAtTheContentMidpoint() {
        val spec = WideColumns.spec(2, 40, 1001, null, null, 320, 12)
        assertEquals(listOf(495, 494), spec.widths)
        assertEquals(12, spec.spacing)
        assertFalse(spec.split)
        assertNull(spec.leadingPane(rtl = false))
    }

    @Test
    fun bookPostureColumnsMeetAtTheFold() {
        val spec = WideColumns.spec(2, 0, 1000, 500, 520, 320, 12)
        assertEquals(listOf(500, 480), spec.widths)
        assertEquals(20, spec.spacing)
        assertTrue(spec.split)
        assertEquals(500, spec.leadingPane(rtl = false))
        assertEquals(480, spec.leadingPane(rtl = true))
    }

    @Test
    fun zeroWidthFoldUsesTheGutter() {
        val spec = WideColumns.spec(2, 0, 1000, 506, 506, 320, 12)
        assertEquals(listOf(500, 488), spec.widths)
        assertEquals(12, spec.spacing)
    }

    @Test
    fun foldNearTheEdgeFallsBackToTheMidpoint() {
        val spec = WideColumns.spec(2, 0, 1000, 100, 100, 320, 12)
        assertEquals(listOf(494, 494), spec.widths)
        assertFalse(spec.split)
    }

    @Test
    fun narrowTwoColumnContentStillSplitsInHalves() {
        assertEquals(listOf(194, 194), WideColumns.spec(2, 0, 400, null, null, 320, 12).widths)
    }

    // endregion

    // region Lines

    @Test
    fun oneColumnMatchesTheFlatListIndices() {
        val lines = WideColumnLines.build(rowCount = 6, headerStarts = listOf(0, 2, 5), breaks = emptyList(), columns = 1, leading = 2)
        assertEquals(9, lines.lines.size)
        listOf(0, 2, 5).forEachIndexed { ordinal, first -> assertEquals(2 + first + ordinal, lines.itemOfHeader(ordinal)) }
        assertEquals(2 + 3 + 2, lines.itemOfRow(3))
    }

    @Test
    fun twoColumnsChunkRowMajor() {
        val lines = WideColumnLines.build(rowCount = 5, headerStarts = emptyList(), breaks = emptyList(), columns = 2, leading = 1)
        assertEquals(listOf(WideLine.Cells(0, 2), WideLine.Cells(2, 4), WideLine.Cells(4, 5)), lines.lines)
        assertEquals(1, lines.itemOfRow(0))
        assertEquals(1, lines.itemOfRow(1))
        assertEquals(2, lines.itemOfRow(3))
        assertEquals(3, lines.itemOfRow(4))
        assertEquals(5, lines.rowCount)
    }

    @Test
    fun headersSpanBothColumnsAndRestartTheLine() {
        val lines = WideColumnLines.build(rowCount = 5, headerStarts = listOf(0, 3), breaks = emptyList(), columns = 2, leading = 0)
        assertEquals(
            listOf(WideLine.Header(0), WideLine.Cells(0, 2), WideLine.Cells(2, 3), WideLine.Header(1), WideLine.Cells(3, 5)),
            lines.lines,
        )
        assertEquals(0, lines.itemOfHeader(0))
        assertEquals(3, lines.itemOfHeader(1))
        assertNull(lines.itemOfHeader(2))
    }

    @Test
    fun rowsBeforeTheFirstHeaderFormTheirOwnGroup() {
        val lines = WideColumnLines.build(rowCount = 4, headerStarts = listOf(1), breaks = emptyList(), columns = 2, leading = 0)
        assertEquals(listOf(WideLine.Cells(0, 1), WideLine.Header(0), WideLine.Cells(1, 3), WideLine.Cells(3, 4)), lines.lines)
    }

    @Test
    fun emptyTrailingHeadersStillAppear() {
        val lines = WideColumnLines.build(rowCount = 2, headerStarts = listOf(0, 2), breaks = emptyList(), columns = 2, leading = 0)
        assertEquals(listOf(WideLine.Header(0), WideLine.Cells(0, 2), WideLine.Header(1)), lines.lines)
        assertEquals(2, lines.itemOfHeader(1))
    }

    @Test
    fun sectionsStartALineSoJumpsLandOnTheirFirstRow() {
        val lines = WideColumnLines.build(rowCount = 6, headerStarts = emptyList(), breaks = listOf(0, 3, 4), columns = 2, leading = 0)
        assertEquals(listOf(WideLine.Cells(0, 2), WideLine.Cells(2, 3), WideLine.Cells(3, 4), WideLine.Cells(4, 6)), lines.lines)
        assertEquals(2, lines.itemOfRow(3))
        assertEquals(3, lines.itemOfRow(4))
    }

    @Test
    fun firstRowOfItemCoversLeadingHeadersLinesAndTheEnd() {
        val lines = WideColumnLines.build(rowCount = 5, headerStarts = listOf(0, 3), breaks = emptyList(), columns = 2, leading = 1)
        assertEquals(0, lines.firstRowOfItem(0))
        assertEquals(0, lines.firstRowOfItem(1))
        assertEquals(2, lines.firstRowOfItem(3))
        assertEquals(3, lines.firstRowOfItem(4))
        assertEquals(3, lines.firstRowOfItem(5))
        assertEquals(4, lines.firstRowOfItem(99))
    }

    @Test
    fun noRows() {
        val lines = WideColumnLines.build(rowCount = 0, headerStarts = emptyList(), breaks = emptyList(), columns = 2, leading = 1)
        assertTrue(lines.lines.isEmpty())
        assertEquals(0, lines.firstRowOfItem(0))
        assertEquals(0, lines.firstRowOfItem(3))
        assertEquals(1, lines.itemOfRow(0))
    }

    @Test
    fun outOfRangeBreaksAreIgnoredAndColumnsAreAtLeastOne() {
        val lines = WideColumnLines.build(rowCount = 2, headerStarts = emptyList(), breaks = listOf(-1, 7), columns = 0, leading = 0)
        assertEquals(1, lines.columns)
        assertEquals(listOf(WideLine.Cells(0, 1), WideLine.Cells(1, 2)), lines.lines)
    }

    // endregion

    // region Reflow

    @Test
    fun reflowKeepsTheFirstRowWhenWidening() {
        val one = WideColumnLines.build(rowCount = 6, headerStarts = listOf(0, 3), breaks = emptyList(), columns = 1, leading = 1)
        val two = WideColumnLines.build(rowCount = 6, headerStarts = listOf(0, 3), breaks = emptyList(), columns = 2, leading = 1)
        // Row 1 (the second cell of the first line) lands on that line.
        assertEquals(two.itemOfRow(1), one.reflow(one.itemOfRow(1), two))
        assertEquals(two.itemOfRow(5), one.reflow(one.itemOfRow(5), two))
        // A header lands on the same header; a leading notice stays put.
        assertEquals(two.itemOfHeader(1), one.reflow(one.itemOfHeader(1)!!, two))
        assertEquals(0, one.reflow(0, two))
    }

    @Test
    fun reflowKeepsTheLineStartWhenNarrowing() {
        val two = WideColumnLines.build(rowCount = 6, headerStarts = emptyList(), breaks = emptyList(), columns = 2, leading = 0)
        val one = WideColumnLines.build(rowCount = 6, headerStarts = emptyList(), breaks = emptyList(), columns = 1, leading = 0)
        assertEquals(4, two.reflow(two.itemOfRow(4), one))
        assertEquals(5, two.reflow(99, one))
    }

    @Test
    fun reflowOfAHeaderMissingFromTheNewLinesFallsBackToItsRow() {
        val from = WideColumnLines.build(rowCount = 4, headerStarts = listOf(0, 2), breaks = emptyList(), columns = 1, leading = 0)
        val to = WideColumnLines.build(rowCount = 4, headerStarts = listOf(0), breaks = emptyList(), columns = 2, leading = 0)
        assertEquals(to.itemOfRow(2), from.reflow(from.itemOfHeader(1)!!, to))
    }

    // endregion
}
