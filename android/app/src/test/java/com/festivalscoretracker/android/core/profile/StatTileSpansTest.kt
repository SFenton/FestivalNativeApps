package com.festivalscoretracker.android.core.profile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [StatTileSpans]: pattern `stat-tile-grid` span and packing rules (#591). */
class StatTileSpansTest {
    private fun spans(placements: List<StatTilePlacement>) = placements.map { Triple(it.row, it.column, it.span) }

    @Test
    fun textThatFitsOneSlotTakesOne() {
        assertEquals(1, StatTileSpans.span(textWidth = 100f, slotTextWidth = 120f, columns = 2))
        assertEquals(1, StatTileSpans.span(textWidth = 120f, slotTextWidth = 120f, columns = 2))
        assertEquals(1, StatTileSpans.span(textWidth = 120.4f, slotTextWidth = 120f, columns = 2))
    }

    @Test
    fun textThatWouldWrapTakesTwo() {
        assertEquals(2, StatTileSpans.span(textWidth = 121f, slotTextWidth = 120f, columns = 2))
        assertEquals(2, StatTileSpans.span(textWidth = 121f, slotTextWidth = 120f, columns = 4))
    }

    @Test
    fun textTooWideForTwoSlotsStillTakesTwoAndWraps() {
        assertEquals(StatTileSpans.MAX_SPAN, StatTileSpans.span(textWidth = 900f, slotTextWidth = 120f, columns = 4))
    }

    @Test
    fun oneColumnGridNeverSpans() {
        assertEquals(1, StatTileSpans.span(textWidth = 900f, slotTextWidth = 120f, columns = 1))
    }

    @Test
    fun textWidthCoversTheGapBetweenSlots() {
        assertEquals(130f, StatTileSpans.textWidth(slotWidth = 186f, spacing = 8f, inset = 56f, span = 1))
        assertEquals(324f, StatTileSpans.textWidth(slotWidth = 186f, spacing = 8f, inset = 56f, span = 2))
        assertEquals(0f, StatTileSpans.textWidth(slotWidth = 20f, spacing = 8f, inset = 56f, span = 1))
    }

    @Test
    fun singleTilesFillRowsInOrder() {
        val placed = StatTileSpans.pack(listOf(1, 1, 1, 1, 1), columns = 2)
        assertEquals(listOf(Triple(0, 0, 1), Triple(0, 1, 1), Triple(1, 0, 1), Triple(1, 1, 1), Triple(2, 0, 1)), spans(placed))
        assertEquals(3, StatTileSpans.rows(placed))
    }

    @Test
    fun wideTileTakesARowOnPhonesAndTheTileBeforeItWidens() {
        // Overview at two columns with a wrapping FULL COMBOS: Songs Played widens, no hole.
        val placed = StatTileSpans.pack(listOf(1, 2, 1, 1, 1), columns = 2)
        assertEquals(listOf(Triple(0, 0, 2), Triple(1, 0, 2), Triple(2, 0, 1), Triple(2, 1, 1), Triple(3, 0, 1)), spans(placed))
        assertEquals(listOf(0, 1, 2, 3, 4), placed.map { it.index })
    }

    @Test
    fun wideTileFitsBesideOthersOnWideGrids() {
        val placed = StatTileSpans.pack(listOf(1, 2, 1, 1, 1), columns = 4)
        assertEquals(listOf(Triple(0, 0, 1), Triple(0, 1, 2), Triple(0, 3, 1), Triple(1, 0, 1), Triple(1, 1, 1)), spans(placed))
    }

    @Test
    fun wideTileThatDoesNotFitTheRowsEndStartsTheNextRow() {
        val placed = StatTileSpans.pack(listOf(1, 1, 1, 2), columns = 4)
        assertEquals(listOf(Triple(0, 0, 1), Triple(0, 1, 1), Triple(0, 2, 2), Triple(1, 0, 2)), spans(placed))
    }

    @Test
    fun lastRowKeepsItsTrailingSlotsEmpty() {
        val placed = StatTileSpans.pack(listOf(2, 1), columns = 2)
        assertEquals(listOf(Triple(0, 0, 2), Triple(1, 0, 1)), spans(placed))
    }

    @Test
    fun noRowBeforeTheLastHasAHole() {
        for (columns in 1..4) {
            val placed = StatTileSpans.pack(listOf(1, 2, 2, 1, 1, 2, 1, 2, 2, 1), columns)
            val rows = StatTileSpans.rows(placed)
            (0 until rows - 1).forEach { row ->
                assertEquals("row $row at $columns columns", columns, placed.filter { it.row == row }.sumOf { it.span })
            }
            assertEquals((0..9).toList(), placed.map { it.index })
        }
    }

    @Test
    fun spansWiderThanTheGridAreClamped() {
        val placed = StatTileSpans.pack(listOf(2, 1), columns = 1)
        assertEquals(listOf(Triple(0, 0, 1), Triple(1, 0, 1)), spans(placed))
        assertTrue(StatTileSpans.pack(emptyList(), columns = 2).isEmpty())
        assertEquals(0, StatTileSpans.rows(emptyList()))
    }
}
