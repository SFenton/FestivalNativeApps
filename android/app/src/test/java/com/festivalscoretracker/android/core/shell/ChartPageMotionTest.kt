package com.festivalscoretracker.android.core.shell

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** `load-transition` R11 (#593): when a paged chart slides, snaps or stays, and what it draws mid-slide. */
class ChartPageMotionTest {
    private val page = ChartPage(start = 4, bands = 4, count = 12)

    @Test
    fun onlyAPageChangeOfTheSameChartSlides() {
        assertEquals(ChartPageMotion.Plan.None, ChartPageMotion.plan(page, page, reduceMotion = false))
        assertEquals(ChartPageMotion.Plan.Slide, ChartPageMotion.plan(page, page.copy(start = 8), reduceMotion = false))
        assertEquals(ChartPageMotion.Plan.Slide, ChartPageMotion.plan(page, page.copy(start = 3), reduceMotion = false))
        // First draw, a resize (band count) and new data (point count) re-fit at once.
        assertEquals(ChartPageMotion.Plan.Snap, ChartPageMotion.plan(null, page, reduceMotion = false))
        assertEquals(ChartPageMotion.Plan.Snap, ChartPageMotion.plan(page, page.copy(bands = 3), reduceMotion = false))
        assertEquals(ChartPageMotion.Plan.Snap, ChartPageMotion.plan(page, page.copy(count = 13), reduceMotion = false))
        // Remove animations / in-app Reduce Motion page at once (R6).
        assertEquals(ChartPageMotion.Plan.Snap, ChartPageMotion.plan(page, page.copy(start = 8), reduceMotion = true))
        assertEquals(400, ChartPageMotion.SLIDE_MILLIS)
    }

    @Test
    fun restingSlotsAreExactlyTheWindow() {
        val slots = ChartPageMotion.slots(4f, 4, 12)
        assertEquals(listOf(4, 5, 6, 7), slots.map { it.index })
        assertEquals(listOf(0.125f, 0.375f, 0.625f, 0.875f), slots.map { it.x })
        assertEquals(listOf(0.5f), ChartPageMotion.slots(0f, 1, 1).map { it.x })
        assertTrue(ChartPageMotion.slots(0f, 4, 0).isEmpty())
        assertTrue(ChartPageMotion.slots(0f, 0, 4).isEmpty())
    }

    @Test
    fun midSlideSlotsCoverEveryPointPartlyInViewPlusOneEachSide() {
        val slots = ChartPageMotion.slots(5.5f, 4, 12)
        assertEquals((4..10).toList(), slots.map { it.index })
        // Point 6 is half a band right of the start: its centre is at band 1.
        assertEquals(1f / 4, slots.first { it.index == 6 }.x, 1e-6f)
        assertTrue(slots.first().x < 0f)
        assertTrue(slots.last().x > 1f)
        // Clamped to the chart's points at its ends.
        assertEquals((0..3).toList(), ChartPageMotion.slots(0.25f, 2, 12).map { it.index })
        assertEquals((8..11).toList(), ChartPageMotion.slots(9.75f, 2, 12).map { it.index })
    }

    @Test
    fun datesTrailTheirBarsAndValuesClampToThePlot() {
        assertEquals(0f, ChartPageMotion.labelShift(8, 8f), 1e-6f)
        // Sliding forward from 4 to 8: halfway, the target's dates sit two bands right of their rest.
        assertEquals(2f, ChartPageMotion.labelShift(8, 6f), 1e-6f)
        assertEquals(-1.5f, ChartPageMotion.labelShift(0, 1.5f), 1e-6f)
        assertEquals(0.5f, ChartPageMotion.height(50.0, 100.0), 1e-6f)
        assertEquals(1f, ChartPageMotion.height(150.0, 100.0), 1e-6f)
        assertEquals(0f, ChartPageMotion.height(-5.0, 100.0), 1e-6f)
        assertEquals(0f, ChartPageMotion.height(50.0, 0.0), 1e-6f)
    }
}
