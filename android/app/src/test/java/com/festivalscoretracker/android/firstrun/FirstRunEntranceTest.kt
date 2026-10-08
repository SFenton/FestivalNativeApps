package com.festivalscoretracker.android.firstrun

import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoFit
import com.festivalscoretracker.android.core.firstrun.FirstRunEntrance
import com.festivalscoretracker.android.core.firstrun.FirstRunInfiniteScroll
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunShopPattern
import com.festivalscoretracker.android.core.firstrun.FirstRunStillDemoData
import com.festivalscoretracker.android.core.firstrun.InstrumentSectionsFit
import com.festivalscoretracker.android.core.firstrun.RivalGroupsFit
import com.festivalscoretracker.android.core.firstrun.SortFit
import com.festivalscoretracker.android.core.shop.ShopPulse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The web first-run entrance cadence, demo fitting, Shop pulse patterns and infinite scroll (issue #380). */
class FirstRunEntranceTest {
    private val allIds = FirstRunPageKey.entries.flatMap { page -> FirstRunCatalog.slides(page, compact = true) + FirstRunCatalog.slides(page, compact = false) }.map { it.id }.toSet()

    // region Entrance

    @Test
    fun webConstants() {
        assertEquals(400, FirstRunEntrance.FADE_MS)
        assertEquals(125, FirstRunEntrance.STAGGER_MS)
        assertEquals(80, FirstRunEntrance.ROW_MS)
        assertEquals(60, FirstRunEntrance.GRID_MS)
        assertEquals(30f, FirstRunEntrance.SCROLL_DP_PER_SECOND)
    }

    @Test
    fun titleAndDescriptionFollowTheDemoCascade() {
        assertEquals(6 * 125, FirstRunEntrance.titleDelay("shop-overview"))
        assertEquals(7 * 125, FirstRunEntrance.descriptionDelay("shop-overview"))
        assertEquals(125, FirstRunEntrance.titleDelay("statistics-select-profile"))
        // Slides without a web count use the web default of 3.
        assertEquals(3, FirstRunEntrance.staggerCount("songs-sort"))
        assertEquals(375, FirstRunEntrance.titleDelay("unknown"))
        allIds.forEach { assertTrue(it, FirstRunEntrance.descriptionDelay(it) > FirstRunEntrance.titleDelay(it)) }
    }

    @Test
    fun staggerCountsNameRealSlides() {
        FirstRunEntrance.STAGGER_COUNTS.keys.forEach { assertTrue("$it is a catalogue slide", it in allIds) }
    }

    @Test
    fun rowsCascadeAtTheWebStepPerSlide() {
        assertEquals(60, FirstRunEntrance.rowInterval("shop-overview"))
        assertEquals(80, FirstRunEntrance.rowInterval("shop-new-items"))
        assertEquals(80, FirstRunEntrance.rowInterval("leaderboards-your-rank"))
        assertEquals(125, FirstRunEntrance.rowInterval("songs-song-list"))
        assertEquals(0, FirstRunEntrance.rowDelay("songs-song-list", 0))
        assertEquals(250, FirstRunEntrance.rowDelay("songs-song-list", 2))
        assertEquals(160, FirstRunEntrance.rowDelay("shop-highlighting", 1, lead = 1))
        assertEquals(0, FirstRunEntrance.rowDelay("songs-song-list", 0, lead = -3))
    }

    // endregion

    // region Fitting

    @Test
    fun rowCandidatesTryTheMostRowsFirst() {
        assertEquals(listOf(5, 4, 3, 2, 1), FirstRunDemoFit.rowCandidates(5))
        assertEquals(listOf(3, 2), FirstRunDemoFit.rowCandidates(3, min = 2))
        assertEquals(listOf(1), FirstRunDemoFit.rowCandidates(0))
    }

    @Test
    fun scaleShrinksOnlyOverflowingDemos() {
        assertEquals(1f, FirstRunDemoFit.scale(200f, 220f), 0f)
        assertEquals(1f, FirstRunDemoFit.scale(220f, 220f), 0f)
        assertEquals(0.5f, FirstRunDemoFit.scale(440f, 220f), 0.0001f)
        assertEquals(1f, FirstRunDemoFit.scale(0f, 220f), 0f)
        assertEquals(1f, FirstRunDemoFit.scale(300f, 0f), 0f)
    }

    @Test
    fun yourRankKeepsThePlayerInTheWindow() {
        assertEquals(2..6, FirstRunDemoFit.around(size = 9, player = 4, slots = 5))
        assertEquals(0..2, FirstRunDemoFit.around(size = 9, player = 0, slots = 3))
        assertEquals(6..8, FirstRunDemoFit.around(size = 9, player = 8, slots = 3))
        assertEquals(0..3, FirstRunDemoFit.around(size = 4, player = 2, slots = 10))
        assertEquals(4..4, FirstRunDemoFit.around(size = 9, player = 4, slots = 0))
        assertTrue(FirstRunDemoFit.around(size = 0, player = 0, slots = 3).isEmpty())
        val window = FirstRunDemoFit.around(FirstRunStillDemoData.NEIGHBOURHOOD.size, FirstRunStillDemoData.PLAYER_INDEX, 3)
        assertTrue(FirstRunStillDemoData.PLAYER_INDEX in window)
    }

    @Test
    fun shopGridTakesTheMostColumnsWithTwoRows() {
        val phone = FirstRunDemoFit.squareGrid(328f)
        assertEquals(5, phone.columns)
        assertEquals(3, phone.rows)
        assertTrue(phone.rows >= 2)
        assertTrue(phone.rows * phone.sideDp + (phone.rows - 1) * 8f <= FirstRunDemoFit.FRAME_DP)
        assertEquals(phone.columns * phone.rows, phone.count)
        // Too wide for two rows of squares at any column count: one row of two, capped at the frame.
        val wide = FirstRunDemoFit.squareGrid(600f)
        assertEquals(2, wide.columns)
        assertEquals(1, wide.rows)
        assertEquals(FirstRunDemoFit.FRAME_DP, wide.sideDp)
        val narrow = FirstRunDemoFit.squareGrid(600f, heightDp = 100f)
        assertEquals(2, narrow.columns)
        assertEquals(1, narrow.rows)
        assertEquals(100f, narrow.sideDp)
    }

    @Test
    fun sortCandidatesDropTheDirectionBeforeTheLastMode() {
        val candidates = FirstRunDemoFit.sortCandidates(3)
        assertEquals(
            listOf(
                SortFit(3, true), SortFit(2, true), SortFit(1, true),
                SortFit(3, false), SortFit(2, false), SortFit(1, false),
            ),
            candidates,
        )
    }

    /** Web `RivalsOverviewDemo`: labelled groups of 3 → 1, then the compact single card. */
    @Test
    fun rivalGroupCandidatesEndOnTheCompactSingleCard() {
        assertEquals(
            listOf(RivalGroupsFit(3), RivalGroupsFit(2), RivalGroupsFit(1), RivalGroupsFit(1, labels = false, single = true)),
            FirstRunDemoFit.rivalGroupCandidates(),
        )
    }

    /** Web `RivalsInstrumentsDemo`: sections with both cards, then one section's single card. */
    @Test
    fun instrumentSectionCandidatesEndOnOneSingleCardSection() {
        assertEquals(
            listOf(InstrumentSectionsFit(3, 2), InstrumentSectionsFit(2, 2), InstrumentSectionsFit(1, 2), InstrumentSectionsFit(1, 1)),
            FirstRunDemoFit.instrumentSectionCandidates(3),
        )
    }

    // endregion

    // region Shop patterns

    @Test
    fun shopPulsePatternsMatchTheWeb() {
        assertEquals(listOf(ShopPulse.InShop, null, ShopPulse.InShop), (0..2).map { FirstRunShopPattern.pulse("shop-highlighting", it, 3) })
        assertEquals(listOf(ShopPulse.New, ShopPulse.InShop, null, ShopPulse.New), (0..3).map { FirstRunShopPattern.pulse("shop-new-items", it, 4) })
        assertEquals(listOf(ShopPulse.LeavingTomorrow, ShopPulse.LeavingTomorrow, ShopPulse.InShop), (0..2).map { FirstRunShopPattern.pulse("songs-leaving-tomorrow", it, 3) })
        assertEquals(listOf(ShopPulse.LeavingTomorrow, ShopPulse.InShop, null), (0..2).map { FirstRunShopPattern.pulse("shop-leaving-tomorrow", it, 3) })
        assertNull(FirstRunShopPattern.pulse("songs-song-list", 0, 3))
    }

    // endregion

    // region Infinite scroll

    @Test
    fun infiniteScrollMovesAtThirtyDpPerSecondAndWraps() {
        assertEquals(0f, FirstRunInfiniteScroll.offset(0L, 300f))
        assertEquals(0f, FirstRunInfiniteScroll.offset(1_000L, 0f))
        assertEquals(30f, FirstRunInfiniteScroll.offset(1_000L, 300f), 0.001f)
        assertEquals(15f, FirstRunInfiniteScroll.offset(10_500L, 300f), 0.001f)
        repeat(50) { assertTrue(FirstRunInfiniteScroll.offset(it * 997L, 120f) < 120f) }
    }

    // endregion

    // region Still data

    @Test
    fun stillDemoDataIsConsistent() {
        assertEquals(1, FirstRunStillDemoData.NEIGHBOURHOOD.count { it.isPlayer })
        assertTrue(FirstRunStillDemoData.NEIGHBOURHOOD.zipWithNext().all { (a, b) -> a.rank < b.rank && a.score >= b.score })
        assertTrue(FirstRunStillDemoData.TOP_SCORES.zipWithNext().all { (a, b) -> a.score >= b.score })
        assertTrue(FirstRunStillDemoData.TOP_SCORES.all { it.accuracy in 0.0..100.0 && it.stars in 1..6 })
        assertTrue(FirstRunStillDemoData.HISTORY.all { it.accuracy in 0.0..100.0 && it.daysAgo >= 0 })
        assertTrue(FirstRunStillDemoData.DRILL_DOWN.any { it.clickable })
        assertFalse(FirstRunStillDemoData.OVERVIEW.isEmpty())
        assertTrue(FirstRunStillDemoData.PERCENTILES.zipWithNext().all { (a, b) -> a.first < b.first && a.second <= b.second })
    }

    // endregion
}
