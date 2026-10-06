package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.BandsRoute
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalSection.Compete
import com.festivalscoretracker.android.core.nav.FestivalSection.Leaderboards
import com.festivalscoretracker.android.core.nav.FestivalSection.Rivals
import com.festivalscoretracker.android.core.nav.FestivalSection.Settings
import com.festivalscoretracker.android.core.nav.FestivalSection.Songs
import com.festivalscoretracker.android.core.nav.FestivalSection.Statistics
import com.festivalscoretracker.android.core.nav.FestivalSection.Suggestions
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.NavigationLayout
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationPolicyTest {
    // region Tabs

    @Test
    fun tabsMirrorWebBottomNav() {
        assertEquals(listOf(Songs, Leaderboards, Settings), FestivalTabPolicy.sections(ProfileKind.None, false))
        assertEquals(listOf(Songs, Leaderboards, Settings), FestivalTabPolicy.sections(ProfileKind.None, true))
        assertEquals(listOf(Songs, Suggestions, Compete, Statistics, Settings), FestivalTabPolicy.sections(ProfileKind.Player, false))
        assertEquals(listOf(Songs, Suggestions, Leaderboards, Rivals, Statistics, Settings), FestivalTabPolicy.sections(ProfileKind.Player, true))
        assertEquals(listOf(Songs, Suggestions, Leaderboards, Statistics, Settings), FestivalTabPolicy.sections(ProfileKind.Band, false))
    }

    @Test
    fun resolveKeepsSlotEquivalents() {
        val anonymous = FestivalTabPolicy.sections(ProfileKind.None, false)
        val player = FestivalTabPolicy.sections(ProfileKind.Player, false)
        val wide = FestivalTabPolicy.sections(ProfileKind.Player, true)
        assertEquals(Leaderboards, FestivalTabPolicy.resolve(Compete, anonymous))
        assertEquals(Compete, FestivalTabPolicy.resolve(Leaderboards, player))
        assertEquals(Compete, FestivalTabPolicy.resolve(Rivals, player))
        assertEquals(Songs, FestivalTabPolicy.resolve(Statistics, anonymous))
        assertEquals(Songs, FestivalTabPolicy.resolve(Rivals, anonymous))
        assertEquals(Songs, FestivalTabPolicy.resolve(Compete, wide.filter { it != Leaderboards }))
        assertEquals(Settings, FestivalTabPolicy.resolve(Settings, anonymous))
        assertTrue(FestivalTabPolicy.resetsPathOnLeave(Statistics))
        assertFalse(FestivalTabPolicy.resetsPathOnLeave(Songs))
        assertEquals(Suggestions, FestivalSection.fromName("SUGGESTIONS"))
        assertNull(FestivalSection.fromName("manual"))
        assertNull(FestivalSection.fromName(null))
    }

    // endregion

    // region Layout

    @Test
    fun adaptiveLayoutByWindowSize() {
        assertEquals(NavigationLayout.BottomBar, AdaptiveLayoutPolicy.navigationLayout(393, 851))
        // Material 3: compact height (phone landscape) and tabletop keep a bottom bar.
        assertEquals(NavigationLayout.BottomBar, AdaptiveLayoutPolicy.navigationLayout(851, 393))
        assertEquals(NavigationLayout.BottomBar, AdaptiveLayoutPolicy.navigationLayout(500, 400))
        assertEquals(NavigationLayout.BottomBar, AdaptiveLayoutPolicy.navigationLayout(1038, 841, tabletop = true))
        assertEquals(NavigationLayout.Rail, AdaptiveLayoutPolicy.navigationLayout(600, 480))
        assertEquals(NavigationLayout.Rail, AdaptiveLayoutPolicy.navigationLayout(1199, 800))
        assertEquals(NavigationLayout.PermanentDrawer, AdaptiveLayoutPolicy.navigationLayout(1200, 800))
        assertEquals(NavigationLayout.BottomBar, AdaptiveLayoutPolicy.navigationLayout(1920, 470))
        assertEquals(NavigationLayout.Rail, AdaptiveLayoutPolicy.navigationLayout(840, 900))
        assertEquals(NavigationLayout.PermanentDrawer, AdaptiveLayoutPolicy.navigationLayout(1280, 800))
        assertTrue(AdaptiveLayoutPolicy.isRegularWidth(600))
        assertFalse(AdaptiveLayoutPolicy.isRegularWidth(599))
        // Issue #126: sheets move Reset into the header below 480 dp of height.
        assertTrue(AdaptiveLayoutPolicy.isCompactHeight(340))
        assertTrue(AdaptiveLayoutPolicy.isCompactHeight(479))
        assertFalse(AdaptiveLayoutPolicy.isCompactHeight(480))
        assertFalse(AdaptiveLayoutPolicy.isCompactHeight(891))
        assertTrue(AdaptiveLayoutPolicy.showsTwoPanes(840, false))
        assertTrue(AdaptiveLayoutPolicy.showsTwoPanes(700, true))
        assertFalse(AdaptiveLayoutPolicy.showsTwoPanes(700, false))
        // Large text: a fold alone no longer splits; the width must hold the text-scaled panes.
        assertFalse(AdaptiveLayoutPolicy.showsTwoPanes(673, true, fontScale = 2f))
        assertFalse(AdaptiveLayoutPolicy.showsTwoPanes(1280, false, fontScale = 2f))
        assertTrue(AdaptiveLayoutPolicy.showsTwoPanes(1280, false, fontScale = 1.3f))
        assertTrue(AdaptiveLayoutPolicy.showsTwoPanes(700, true, fontScale = 1.15f))
        assertEquals(400, AdaptiveLayoutPolicy.listPaneWidth(1000, null))
        assertEquals(320, AdaptiveLayoutPolicy.listPaneWidth(700, null))
        assertEquals(440, AdaptiveLayoutPolicy.listPaneWidth(1400, null))
        assertEquals(426, AdaptiveLayoutPolicy.listPaneWidth(900, 426))
        assertEquals(360, AdaptiveLayoutPolicy.listPaneWidth(900, 0))
        assertEquals(360, AdaptiveLayoutPolicy.listPaneWidth(900, 950))
        // A landscape phone's 54 dp camera inset is added on top of 40% of the usable width.
        assertEquals(401, AdaptiveLayoutPolicy.listPaneWidth(923, null, leadingInsetDp = 54))
        assertEquals(369, AdaptiveLayoutPolicy.listPaneWidth(923, null, leadingInsetDp = 0))
        assertEquals(369, AdaptiveLayoutPolicy.listPaneWidth(923, null, leadingInsetDp = -5))
        // A hinge fixes the split regardless of insets; the pane never takes more than half.
        assertEquals(426, AdaptiveLayoutPolicy.listPaneWidth(900, 426, leadingInsetDp = 54))
        assertEquals(420, AdaptiveLayoutPolicy.listPaneWidth(840, null, leadingInsetDp = 200))
        // Issues #101/#102: the permanent drawer widens to Material's 360 dp for large text.
        assertEquals(280, AdaptiveLayoutPolicy.permanentDrawerWidth(0.85f))
        assertEquals(280, AdaptiveLayoutPolicy.permanentDrawerWidth(1f))
        assertEquals(280, AdaptiveLayoutPolicy.permanentDrawerWidth(1.15f))
        assertEquals(360, AdaptiveLayoutPolicy.permanentDrawerWidth(1.3f))
        assertEquals(360, AdaptiveLayoutPolicy.permanentDrawerWidth(2f))
    }

    // endregion

    // region Debug launch

    @Test
    fun parsesDebugLaunchExtras() {
        val launch = DebugLaunch.parse(
            mapOf(
                "FST_DEBUG_TAB" to "settings",
                "FST_DEBUG_ROUTE" to "song:Alpha Tune",
                "FST_DEBUG_PROFILE" to "${Fixtures.ACCOUNT_A}:Synthetic Player",
                "FST_DEBUG_DRAWER" to "1",
                "FST_DEBUG_SHEET" to "profile",
                "FST_DEBUG_ANONYMOUS" to "1",
                "FST_DEBUG_FORCE_FREEZE" to "1",
                "FST_DEBUG_STILL_BACKGROUND" to "1",
                "FST_ORIGIN" to "http://10.0.2.2:8080",
            ),
        )
        assertEquals(Settings, launch.section)
        assertNull(launch.route)
        assertEquals("Alpha Tune", launch.songQuery)
        assertEquals("Synthetic Player", launch.profile?.displayName)
        assertTrue(launch.opensDrawer && launch.opensProfileSheet && launch.anonymous && launch.forceFreeze && launch.stillBackground)
        assertEquals("http://10.0.2.2:8080", launch.origin)
        val empty = DebugLaunch.parse(mapOf("FST_DEBUG_PROFILE" to "bad", "FST_ORIGIN" to " ", "FST_DEBUG_ROUTE" to "song:"))
        assertEquals(DebugLaunch.NONE, empty)
    }

    @Test
    fun parsesEveryRouteToken() {
        assertEquals(SongLeaderboardRoute("s1", "Solo_Bass", 3), DebugLaunch.parseRoute("songLeaderboard:s1:Solo_Bass:3"))
        assertEquals(SongLeaderboardRoute("s1", "Solo_Bass", 1), DebugLaunch.parseRoute("songLeaderboard:s1:Solo_Bass:x"))
        assertEquals(SongLeaderboardRoute("s1", "Solo_Bass", 1), DebugLaunch.parseRoute("songLeaderboard:s1:Solo_Bass:-4"))
        assertEquals(SongLeaderboardRoute("s1", "Solo_Bass", 2, navToPlayer = true), DebugLaunch.parseRoute("songLeaderboard:s1:Solo_Bass:2:reveal"))
        assertEquals(SongLeaderboardRoute("s1", "Solo_Bass", 2), DebugLaunch.parseRoute("songLeaderboard:s1:Solo_Bass:2:other"))
        assertNull(DebugLaunch.parseRoute("songLeaderboard:s1:Nope"))
        assertNull(DebugLaunch.parseRoute("songLeaderboard"))
        assertEquals(PlayerRoute("abc"), DebugLaunch.parseRoute("player:abc"))
        assertNull(DebugLaunch.parseRoute("player"))
        assertEquals(PlayerBandsRoute("abc"), DebugLaunch.parseRoute("playerBands:abc"))
        assertEquals(PlayerBandsRoute("abc", group = "trios"), DebugLaunch.parseRoute("playerBands:abc:trios"))
        assertEquals(LeaderboardsRoute, DebugLaunch.parseRoute("leaderboards"))
        assertEquals(FullRankingsRoute("Solo_Drums"), DebugLaunch.parseRoute("fullRankings:Solo_Drums"))
        assertEquals(FullRankingsRoute("Solo_Guitar"), DebugLaunch.parseRoute("fullRankings"))
        assertEquals(BandRankingsRoute("Band_Trios"), DebugLaunch.parseRoute("bandRankings:Band_Trios"))
        assertEquals(BandRankingsRoute("Band_Duets"), DebugLaunch.parseRoute("bandRankings"))
        assertEquals(ShopRoute, DebugLaunch.parseRoute("shop"))
        assertEquals(RivalsRoute, DebugLaunch.parseRoute("rivals"))
        assertEquals(StatisticsRoute, DebugLaunch.parseRoute("statistics"))
        assertEquals(SuggestionsRoute, DebugLaunch.parseRoute("suggestions"))
        assertEquals(CompeteRoute, DebugLaunch.parseRoute("compete"))
        assertEquals(BandsRoute, DebugLaunch.parseRoute("bands"))
        assertEquals(BandRoute("b1"), DebugLaunch.parseRoute("band:b1"))
        assertNull(DebugLaunch.parseRoute("band"))
        assertEquals(LicensesRoute, DebugLaunch.parseRoute("licenses"))
        assertNull(DebugLaunch.parseRoute("manual"))
        assertNull(DebugLaunch.parseRoute("song:x"))
    }

    // endregion
}
