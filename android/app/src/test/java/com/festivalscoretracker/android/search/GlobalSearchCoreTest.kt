package com.festivalscoretracker.android.search

import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.search.GlobalSearchLayout
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.PxRect
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.SearchPresentation
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.search.ShellShortcut
import com.festivalscoretracker.android.core.search.ShellShortcuts
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure global-search rules: scopes, matching, routing, announcements, layout geometry, shortcuts. */
class GlobalSearchCoreTest {
    private val songs = listOf(
        Fixtures.song("s1", "Alpha Tune", artist = "Band One"),
        Fixtures.song("s2", "Beta Song", artist = "Alpha Crew"),
        Fixtures.song("s3", "Échos d'été", artist = "Band Three"),
        Fixtures.song("s4", "Rock-n-Roll (Live)", artist = "Band Four"),
    )

    @Test
    fun scopesToggleParseAndOrder() {
        assertEquals(listOf(SearchScope.Songs, SearchScope.Players, SearchScope.Bands), SearchScope.chips)
        assertEquals(SearchScope.Songs, SearchScope.Songs.toggledFrom(SearchScope.All))
        assertEquals(SearchScope.All, SearchScope.Songs.toggledFrom(SearchScope.Songs))
        assertEquals(SearchScope.Players, SearchScope.Players.toggledFrom(SearchScope.Songs))
        assertEquals(SearchScope.Bands, SearchScope.parse("BANDS"))
        assertEquals(SearchScope.All, SearchScope.parse("nope"))
        assertEquals(SearchScope.All, SearchScope.parse(null))
        assertEquals("players", SearchScope.Players.token)
    }

    @Test
    fun queryRules() {
        assertEquals("ab", GlobalSearchResults.normalize("  ab "))
        assertEquals("", GlobalSearchResults.normalize(null))
        assertFalse(GlobalSearchResults.isSearchable(" a "))
        assertTrue(GlobalSearchResults.isSearchable("ab"))
        assertTrue(GlobalSearchResults.canSearchPlayers(" ab "))
        assertFalse(GlobalSearchResults.canSearchPlayers("a"))
        assertFalse(GlobalSearchResults.canSearchPlayers("a‮b"))
        assertFalse(GlobalSearchResults.canSearchPlayers("x".repeat(201)))
    }

    @Test
    fun songsMatchTitleArtistAccentsAndPunctuationInCatalogueOrder() {
        assertEquals(listOf("s1", "s2"), GlobalSearchResults.matchSongs(songs, "alpha").map { it.songId })
        assertEquals(listOf("s3"), GlobalSearchResults.matchSongs(songs, "echos dete").map { it.songId })
        assertEquals(listOf("s3"), GlobalSearchResults.matchSongs(songs, "ÉCHOS").map { it.songId })
        assertEquals(listOf("s4"), GlobalSearchResults.matchSongs(songs, "rock n roll live").map { it.songId })
        assertTrue(GlobalSearchResults.matchSongs(songs, "a").isEmpty())
        val many = (1..30).map { Fixtures.song("m$it", "Match $it") }
        assertEquals(20, GlobalSearchResults.matchSongs(many, "match").size)
        assertEquals(3, GlobalSearchResults.matchSongs(many, "match", limit = 3).size)
        val result = GlobalSearchResults.matchSongs(songs, "beta").single()
        assertEquals("Beta Song by Alpha Crew", result.accessibleName)
        assertEquals(SearchDestination.Push(SongDetailRoute("s2")), result.destination)
    }

    @Test
    fun playersMarkSelectedAndRoute() {
        val rows = listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "One"), PlayerSearchResult(Fixtures.ACCOUNT_B, "Two"))
        val players = GlobalSearchResults.players(rows, Fixtures.ACCOUNT_B.uppercase())
        assertFalse(players[0].isSelected)
        assertTrue(players[1].isSelected)
        assertEquals(SearchDestination.Push(PlayerRoute(Fixtures.ACCOUNT_A, "One")), players[0].destination)
        assertEquals(SearchDestination.Section(FestivalSection.Statistics), players[1].destination)
        assertEquals("Player", players[0].subtitle)
        assertEquals("Selected player · Statistics", players[1].subtitle)
        assertEquals("One", players[0].accessibleName)
        assertEquals("Two, selected player, opens Statistics", players[1].accessibleName)
        assertEquals(10, GlobalSearchResults.players(List(15) { PlayerSearchResult(Fixtures.ACCOUNT_A, "P$it") }, null).size)
    }

    @Test
    fun announcements() {
        assertEquals("3 songs, 10 players", GlobalSearchResults.announcement(3, 10))
        assertEquals("1 song, 1 player", GlobalSearchResults.announcement(1, 1))
        assertEquals(GlobalSearchResults.NO_RESULTS, GlobalSearchResults.announcement(0, 0))
        assertEquals("2 songs, player search failed", GlobalSearchResults.announcement(2, null))
        assertEquals("song search failed, 0 players", GlobalSearchResults.announcement(null, 0))
        assertEquals(BandRankingsRoute("Band_Duets"), GlobalSearchResults.bandRankings)
    }

    @Test
    fun presentationByWindowWidth() {
        assertEquals(SearchPresentation.FullScreen, GlobalSearchLayout.presentation(411))
        assertEquals(SearchPresentation.FullScreen, GlobalSearchLayout.presentation(599))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(600))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(839))
        assertEquals(SearchPresentation.Persistent, GlobalSearchLayout.presentation(840))
        assertEquals(SearchPresentation.Persistent, GlobalSearchLayout.presentation(1600))
    }

    @Test
    fun fullScreenGrowsFromTheRequester() {
        val icon = PxRect(900, 100, 1000, 200)
        val anchor = GlobalSearchLayout.anchor(SearchPresentation.FullScreen, icon, 1080, 2400, 2.625f)
        assertEquals(icon, anchor.anchor)
        assertNull(anchor.maxPanelHeight)
    }

    @Test
    fun dockedIsEndAlignedCappedAndInsideTheWindow() {
        // 720 dp window at density 2: docked panel 720 dp wide would not fit; it fills minus gaps.
        val anchor = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(1300, 60, 1396, 156), 1440, 2000, 2f)
        assertEquals(1424, anchor.anchor.right)
        assertEquals(1440 - 32, anchor.anchor.width)
        assertEquals(112, anchor.anchor.height)
        assertEquals(52, anchor.anchor.top)
        assertEquals(2000 * 2 / 3, anchor.maxPanelHeight)
        // Wide window: 720 dp max, end aligned with the requester.
        val wide = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(1500, 60, 1596, 156), 2000, 1200, 1f)
        assertEquals(720, wide.anchor.width)
        assertEquals(1596, wide.anchor.right)
        assertEquals(80, wide.anchor.top)
    }

    @Test
    fun persistentKeepsTheBarWidthButNeverBelowTheMinimum() {
        val bar = PxRect(1200, 20, 1600, 76)
        val anchor = GlobalSearchLayout.anchor(SearchPresentation.Persistent, bar, 2560, 1600, 1f)
        assertEquals(bar, anchor.anchor)
        val narrow = GlobalSearchLayout.anchor(SearchPresentation.Persistent, PxRect(1400, 20, 1600, 76), 2560, 1600, 1f)
        assertEquals(360, narrow.anchor.width)
        assertEquals(1600, narrow.anchor.right)
    }

    @Test
    fun dockedPanelStaysOnTheRequestersSideOfAVerticalHinge() {
        val hinge = PxRect(1038, 0, 1038, 2152)
        // Requester in the left pane: panel clamped to the left pane.
        val left = GlobalSearchLayout.anchor(SearchPresentation.Persistent, PxRect(600, 20, 1000, 76), 2076, 2152, 1f, verticalHinge = hinge)
        assertTrue(left.anchor.right <= 1038 - 8)
        assertTrue(left.anchor.left >= 8)
        // Requester in the right pane: panel never crosses back over the hinge.
        val right = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(1900, 20, 1996, 116), 2076, 2152, 1f, verticalHinge = hinge)
        assertTrue(right.anchor.left >= 1038 + 8)
        assertEquals(1996, right.anchor.right)
    }

    @Test
    fun tabletopHingeCapsThePanelAboveTheFold() {
        val hinge = PxRect(0, 1100, 2152, 1100)
        val anchor = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(2000, 40, 2096, 136), 2152, 2076, 1f, horizontalHinge = hinge)
        assertEquals(1100 - anchor.anchor.top - 8, anchor.maxPanelHeight)
        // A hinge above the anchor (not possible for a top bar, but guarded) falls back to 2/3.
        val above = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(2000, 1200, 2096, 1296), 2152, 2076, 1f, horizontalHinge = hinge)
        assertEquals(2076 * 2 / 3, above.maxPanelHeight)
        // Full screen ignores the fold (compact windows have no tabletop split).
        assertNull(GlobalSearchLayout.anchor(SearchPresentation.FullScreen, PxRect(0, 0, 10, 10), 100, 100, 1f, horizontalHinge = hinge).maxPanelHeight)
    }

    @Test
    fun shortcuts() {
        assertEquals(ShellShortcut.OpenSearch, ShellShortcuts.resolve(ShellShortcuts.KEYCODE_K, ctrl = true))
        assertEquals(ShellShortcut.FindInPage, ShellShortcuts.resolve(ShellShortcuts.KEYCODE_F, ctrl = true))
        assertEquals(ShellShortcut.OpenSearch, ShellShortcuts.resolve(ShellShortcuts.KEYCODE_SEARCH, ctrl = false))
        assertNull(ShellShortcuts.resolve(ShellShortcuts.KEYCODE_SEARCH, ctrl = true))
        assertNull(ShellShortcuts.resolve(ShellShortcuts.KEYCODE_K, ctrl = false))
        assertNull(ShellShortcuts.resolve(ShellShortcuts.KEYCODE_K, ctrl = true, shift = true))
        assertNull(ShellShortcuts.resolve(ShellShortcuts.KEYCODE_F, ctrl = true, alt = true))
        assertNull(ShellShortcuts.resolve(ShellShortcuts.KEYCODE_F, ctrl = true, meta = true))
        assertNull(ShellShortcuts.resolve(29, ctrl = true))
    }

    @Test
    fun debugLaunchSearchExtras() {
        val launch = DebugLaunch.parse(mapOf("FST_DEBUG_SEARCH" to "alpha", "FST_DEBUG_SEARCH_SCOPE" to "bands"))
        assertEquals("alpha", launch.searchQuery)
        assertEquals(SearchScope.Bands, launch.searchScope)
        assertNull(DebugLaunch.parse(mapOf("FST_DEBUG_SEARCH_SCOPE" to "all")).searchScope)
        assertEquals(PxRect(1, 2, 11, 22).width, 10)
        assertEquals(PxRect(1, 2, 11, 22).height, 20)
    }
}
