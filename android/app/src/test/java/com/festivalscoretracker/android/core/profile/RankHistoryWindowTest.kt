package com.festivalscoretracker.android.core.profile

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Web `useChartPagination`/`RankHistoryChart` port: window, colours, domain and plot. */
class RankHistoryWindowTest {
    private fun day(n: Int, rank: Int = 10 + n, score: Long? = 1_000L * n, field: Int? = 100) =
        PlayerRankHistorySnapshot(snapshotDate = "2026-09-%02d".format(n), totalScoreRank = rank, totalScore = score, rankedAccountCount = field)

    private val ten = (1..10).map { day(it) }

    @Test
    fun windowShowsNewestBarsAndPagesWithoutSelection() {
        var w = RankHistoryWindow(ten, maxBars = 4)
        assertEquals(listOf(7, 8, 9, 10), w.visible.map { it.date!!.dayOfMonth })
        assertTrue(w.needsPagination)
        assertTrue(w.forwardDisabled)
        assertFalse(w.backDisabled)
        w = w.backEntry()
        assertEquals(5, w.pageStart)
        w = w.backPage()
        assertEquals(listOf(2, 3, 4, 5), w.visible.map { it.date!!.dayOfMonth })
        w = w.backPage()
        assertEquals(0, w.pageStart)
        assertTrue(w.backDisabled)
        w = w.forwardPage().forwardEntry()
        assertEquals(5, w.pageStart)
        w = w.swiped(-100)
        assertEquals(0, w.offset)
        w = w.swiped(2)
        assertEquals(2, w.offset)
        assertFalse(RankHistoryWindow(ten, maxBars = 20).needsPagination)
        assertEquals(1, RankHistoryWindow(ten, maxBars = 0).visible.size)
    }

    @Test
    fun selectionTogglesAndNavigatesAcrossPages() {
        var w = RankHistoryWindow(ten, maxBars = 4).toggle(1)
        assertEquals(7, w.selected)
        assertEquals("2026-09-08", w.selectedPoint!!.snapshotDate)
        assertNull(w.toggle(1).selected)
        assertEquals(w, w.toggle(9))
        w = w.backEntry().backEntry().backEntry()
        assertEquals(4, w.selected)
        assertEquals(4, w.pageStart)
        w = w.backPage()
        assertEquals(0, w.selected)
        assertTrue(w.backDisabled)
        w = w.forwardPage().forwardPage().forwardPage()
        assertEquals(9, w.selected)
        assertTrue(w.forwardDisabled)
        assertEquals(9, w.resized(2).selected)
        assertEquals(8, w.resized(2).pageStart)
        assertEquals(10, RankHistoryWindow(ten, 3).resized(0).let { it.pageEnd })
        assertNull(RankHistoryWindow(emptyList(), 3).backEntry().selectedPoint)
    }

    @Test
    fun barsFitTheWidth() {
        assertEquals(1, RankHistoryWindow.barsFor(10f))
        assertEquals(6, RankHistoryWindow.barsFor(280f))
    }

    @Test
    fun colorsMatchTheWebScale() {
        assertEquals(0xDC2828, RankHistoryColors.accuracy(0.0))
        assertEquals(0x2ECC71, RankHistoryColors.accuracy(150.0))
        assertEquals(RankHistoryColors.UNKNOWN, RankHistoryColors.rank(0, 100))
        assertEquals(RankHistoryColors.UNKNOWN, RankHistoryColors.rank(5, 0))
        assertEquals(RankHistoryColors.accuracy(99.0), RankHistoryColors.rank(1, 100))
    }

    @Test
    fun plotUsesThePaddedRankDomainAndVisibleScoreMaximum() {
        assertEquals(1 to 100, RankHistoryPlot.rankDomain(emptyList()))
        assertEquals(10 to 21, RankHistoryPlot.rankDomain(listOf(11, 20, 0)))
        assertEquals(1 to 4, RankHistoryPlot.rankDomain(listOf(1, 3)))
        val window = RankHistoryWindow(ten, maxBars = 4).toggle(3)
        val plot = RankHistoryPlot.build(window, totalAccounts = 50, locale = Locale.US)
        assertEquals(4, plot.bars.size)
        assertEquals(0.125f, plot.bars[0].bar.x, 1e-6f)
        assertEquals(1f, plot.bars[3].bar.height, 1e-6f)
        assertEquals(0.7f, plot.bars[0].bar.height, 1e-6f)
        assertTrue(plot.bars[3].selected && plot.line[3].highlight)
        assertEquals(RankHistoryColors.rank(17, 100), plot.bars[0].color)
        assertEquals(listOf("10K", "5K", "0"), plot.scoreTicks.map { it.label })
        assertEquals("#10", plot.rankTicks.first().label)
        val single = RankHistoryPlot.build(RankHistoryWindow(listOf(day(1, score = null, field = null)), 4), 0, Locale.US)
        assertEquals(0.5f, single.bars.single().bar.x)
        assertTrue(single.scoreTicks.isEmpty())
        assertEquals(RankHistoryColors.UNKNOWN, single.bars.single().color)
    }

    @Test
    fun datesRecentListAndCompactNumbers() {
        assertEquals("Sep 3, 2026", RankHistoryPlot.displayDate(day(3), Locale.US))
        assertEquals("bad", RankHistoryPlot.displayDate(PlayerRankHistorySnapshot(snapshotDate = "bad"), Locale.US))
        assertEquals(listOf(10, 9, 8, 7, 6), RankHistoryPlot.recent(ten).map { it.date!!.dayOfMonth })
        assertEquals("950", ProfileFormatting.compact(950, Locale.US))
        assertEquals("12K", ProfileFormatting.compact(12_345, Locale.US))
        assertEquals("1.2M", ProfileFormatting.compact(1_299_999, Locale.US))
        assertEquals("3.4B", ProfileFormatting.compact(3_400_000_000, Locale.US))
        assertEquals(3, ChartGeometry.bandAt(99f, 4, 100f))
        assertNull(ChartGeometry.bandAt(-1f, 4, 100f))
        assertNull(ChartGeometry.bandAt(10f, 0, 100f))
        assertEquals(ChartRect(40f, 50f, 20f, 50f), ChartGeometry.bandBar(ChartBar(0.5f, 0.5f), 4, 100f, 100f, 72f))
        assertEquals(ChartRect(45f, 0f, 10f, 100f), ChartGeometry.bandBar(ChartBar(0.5f, 1f), 1, 100f, 100f, 10f))
    }
}
