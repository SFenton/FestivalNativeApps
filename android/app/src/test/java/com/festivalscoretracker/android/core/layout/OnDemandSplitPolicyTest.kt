package com.festivalscoretracker.android.core.layout

import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.SettingsTab
import com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.shell.PxSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Where and when Android list pages open sub-pages beside themselves, like the iPhone Duo (#583). */
class OnDemandSplitPolicyTest {
    private val density = 2f

    private fun px(dp: Int) = (dp * density).toInt()

    private fun context(
        widthDp: Int,
        heightDp: Int,
        container: PxSpan = PxSpan(0, px(widthDp)),
        safe: PxSpan? = null,
        hinge: PxSpan? = null,
        fontScale: Float = 1f,
        rtl: Boolean = false,
    ) = SplitContext(px(widthDp), px(heightDp), density, fontScale, container, safe, hinge, rtl)

    // region Window conditions

    @Test
    fun landscapeTabletSplitsAtTheMidpointWithNoBand() {
        assertEquals(SplitGeometry(px(640), 0, px(640), hinge = false), OnDemandSplitPolicy.geometry(context(1280, 800)))
    }

    @Test
    fun portraitTabletStaysOnePage() {
        assertNull(OnDemandSplitPolicy.geometry(context(800, 1280)))
    }

    @Test
    fun landscapePhoneIsTooShortToSplit() {
        assertNull(OnDemandSplitPolicy.geometry(context(891, 411)))
    }

    @Test
    fun compactWidthStaysOnePage() {
        assertNull(OnDemandSplitPolicy.geometry(context(599, 500)))
    }

    @Test
    fun eachPaneNeedsTheMinimumWidth() {
        assertNull(OnDemandSplitPolicy.geometry(context(700, 500)))
        val geometry = OnDemandSplitPolicy.geometry(context(720, 500))
        assertEquals(px(OnDemandSplitPolicy.MIN_PANE_WIDTH_DP), geometry?.leadingPx)
    }

    @Test
    fun largeTextScalesTheMinimumPaneWidth() {
        assertTrue(OnDemandSplitPolicy.geometry(context(1280, 800, fontScale = 1.2f)) != null)
        assertNull(OnDemandSplitPolicy.geometry(context(1280, 800, fontScale = 2f)))
        assertTrue(OnDemandSplitPolicy.geometry(context(1600, 900, fontScale = 2f)) != null)
    }

    // endregion

    // region Band position

    @Test
    fun midpointIsTheContainersFreeSpaceBesideARail() {
        // An 80 dp rail on the left: the container starts after it.
        val geometry = OnDemandSplitPolicy.geometry(context(1280, 800, container = PxSpan(px(80), px(1280))))!!
        assertEquals(px(600), geometry.leadingPx)
        assertEquals(px(600), geometry.trailingPx)
    }

    @Test
    fun midpointExcludesSideSystemBarsAndCutouts() {
        // A 48 dp navigation bar on the right edge in landscape.
        val geometry = OnDemandSplitPolicy.geometry(context(1280, 800, safe = PxSpan(0, px(1232))))!!
        assertEquals(px(616), geometry.leadingPx)
        assertEquals(px(664), geometry.trailingPx)
    }

    @Test
    fun bookPostureSplitsAtTheFoldWhateverTheAspect() {
        // A book-style foldable's inner screen is about square, so not landscape.
        val hinge = PxSpan(px(420), px(424))
        val geometry = OnDemandSplitPolicy.geometry(context(844, 880, hinge = hinge))!!
        assertTrue(geometry.hinge)
        assertEquals(px(420), geometry.leadingPx)
        assertEquals(px(4), geometry.bandPx)
        assertEquals(px(420), geometry.trailingPx)
    }

    @Test
    fun aFoldOutsideTheContainerIsIgnored() {
        assertNull(OnDemandSplitPolicy.geometry(context(844, 880, container = PxSpan(px(430), px(844)), hinge = PxSpan(px(420), px(424)))))
    }

    @Test
    fun bookPostureSplitsBesideARailDownToTheFoldPaneMinimum() {
        // Pixel Fold-like inner screen with an 80 dp rail: 340 dp beside the fold still splits.
        val geometry = OnDemandSplitPolicy.geometry(context(841, 701, container = PxSpan(px(80), px(841)), hinge = PxSpan(px(420), px(420))))!!
        assertEquals(px(340), geometry.leadingPx)
        // A fold that leaves less than 240 dp on one side does not.
        assertNull(OnDemandSplitPolicy.geometry(context(700, 880, container = PxSpan(px(120), px(700)), hinge = PxSpan(px(350), px(350)))))
    }

    @Test
    fun largeTextBesideAFoldNeedsTheTextScaledMinimum() {
        assertNull(OnDemandSplitPolicy.geometry(context(844, 880, fontScale = 1.5f, hinge = PxSpan(px(420), px(424)))))
    }

    @Test
    fun rightToLeftPutsTheListOnTheRight() {
        val geometry = OnDemandSplitPolicy.geometry(context(1280, 800, safe = PxSpan(0, px(1232)), rtl = true))!!
        assertEquals(px(664), geometry.leadingPx)
        assertEquals(px(616), geometry.trailingPx)
    }

    @Test
    fun freeMidFallsBackToTheContainerWhenTheSafeSpanMissesIt() {
        assertEquals(150, OnDemandSplitPolicy.freeMid(PxSpan(100, 200), PxSpan(300, 400)))
        assertEquals(150, OnDemandSplitPolicy.freeMid(PxSpan(100, 200), null))
    }

    // endregion

    // region Pages

    @Test
    fun listPagesAcceptTheDuosSubPages() {
        assertTrue(SplitListPage.SongDetail.accepts(SongLeaderboardRoute("s", "Solo_Guitar")))
        assertTrue(SplitListPage.SongDetail.accepts(SongBandLeaderboardRoute("s", "Band_Duets")))
        assertTrue(SplitListPage.SongDetail.accepts(PlayerHistoryRoute("s", "Solo_Guitar")))
        assertFalse(SplitListPage.SongDetail.accepts(PlayerRoute("a")))
        assertTrue(SplitListPage.Leaderboards.accepts(FullRankingsRoute("Solo_Guitar")))
        assertTrue(SplitListPage.Leaderboards.accepts(BandRankingsRoute("Band_Duets")))
        assertFalse(SplitListPage.Leaderboards.accepts(PlayerRoute("a")))
        assertTrue(SplitListPage.Rivals.accepts(RivalDetailRoute("r")))
        assertFalse(SplitListPage.Rivals.accepts(AllRivalsRoute("all")))
        assertTrue(SplitListPage.Compete.accepts(RivalDetailRoute("r")))
        // Compete's View All and rankings push full width (#369).
        assertFalse(SplitListPage.Compete.accepts(FullRankingsRoute("Solo_Guitar")))
        assertFalse(SplitListPage.Compete.accepts(AllRivalsRoute("all")))
    }

    @Test
    fun onlyTheDuosListPagesSplit() {
        assertEquals(SplitListPage.SongDetail, OnDemandSplitPolicy.page(SongDetailRoute::class))
        assertEquals(SplitListPage.Leaderboards, OnDemandSplitPolicy.page(LeaderboardsTab::class))
        assertEquals(SplitListPage.Leaderboards, OnDemandSplitPolicy.page(LeaderboardsRoute::class))
        assertEquals(SplitListPage.Rivals, OnDemandSplitPolicy.page(RivalsTab::class))
        assertEquals(SplitListPage.Rivals, OnDemandSplitPolicy.page(AllRivalsRoute::class))
        assertEquals(SplitListPage.Compete, OnDemandSplitPolicy.page(CompeteTab::class))
        // Songs uses two columns instead (#581); Settings keeps its own list/detail (#371).
        assertNull(OnDemandSplitPolicy.page(SongsTab::class))
        assertNull(OnDemandSplitPolicy.page(SettingsTab::class))
        assertNull(OnDemandSplitPolicy.page(FullRankingsRoute::class))
    }

    @Test
    fun theOpenItemsSubPagesStayInThePaneAndOthersCoverTheSplit() {
        assertTrue(OnDemandSplitPolicy.opensInPane(RivalryRoute("r", "common")))
        assertTrue(OnDemandSplitPolicy.opensInPane(SongLeaderboardRoute("s", "Solo_Bass")))
        assertTrue(OnDemandSplitPolicy.opensInPane(FullRankingsRoute("Solo_Guitar", page = 2)))
        assertFalse(OnDemandSplitPolicy.opensInPane(PlayerRoute("a")))
        assertFalse(OnDemandSplitPolicy.opensInPane(SongDetailRoute("s")))
        assertFalse(OnDemandSplitPolicy.opensInPane(StatisticsRoute))
    }

    // endregion

    // region Window changes

    private fun list(page: SplitListPage) = SplitStackItem(page, null)

    private fun sub(route: com.festivalscoretracker.android.core.nav.AppRoute) = SplitStackItem(null, route)

    private val other = SplitStackItem(null, null)

    @Test
    fun expandingMovesAListPagesAcceptedSubPagesIntoItsPane() {
        assertEquals(1, OnDemandSplitPolicy.expandCut(listOf(other, list(SplitListPage.SongDetail), sub(SongLeaderboardRoute("s", "Solo_Guitar")))))
        assertEquals(0, OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.Rivals), sub(RivalDetailRoute("r")), sub(RivalryRoute("r", "common")))))
        assertEquals(0, OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.Leaderboards), sub(FullRankingsRoute("Solo_Guitar")), sub(FullRankingsRoute("Solo_Bass")))))
    }

    @Test
    fun expandingUsesTheTopmostListPage() {
        val stack = listOf(list(SplitListPage.Leaderboards), sub(FullRankingsRoute("Solo_Guitar")), list(SplitListPage.SongDetail), sub(PlayerHistoryRoute("s", "Solo_Guitar")))
        assertEquals(2, OnDemandSplitPolicy.expandCut(stack))
    }

    @Test
    fun expandingLeavesOtherStacksAlone() {
        assertNull(OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.SongDetail))))
        assertNull(OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.SongDetail), other)))
        assertNull(OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.Compete), sub(FullRankingsRoute("Solo_Guitar")))))
        // A full page (a profile) on top keeps the stack as it is; Back returns to it.
        assertNull(OnDemandSplitPolicy.expandCut(listOf(list(SplitListPage.Leaderboards), sub(FullRankingsRoute("Solo_Guitar")), other)))
    }

    // endregion
}
