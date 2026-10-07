package com.festivalscoretracker.android.search

import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.search.GlobalSearchLayout
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSearchResults.Count
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
    fun bandsRouteToTheBandPageAndCapAtTen() {
        val entry = PlayerBandEntry(
            bandId = "band-1",
            teamKey = "${Fixtures.ACCOUNT_A}:${Fixtures.ACCOUNT_B}",
            bandType = "Band_Trios",
            appearanceCount = 1,
            members = listOf(BandMember(Fixtures.ACCOUNT_A, "One"), BandMember(Fixtures.ACCOUNT_B, "Two")),
        )
        val band = GlobalSearchResults.bands(listOf(entry)).single()
        assertEquals("band-1", band.key)
        assertEquals(SearchDestination.Push(BandRoute("band-1", "One + Two", "Band_Trios", entry.teamKey)), band.destination)
        assertEquals("One + Two, Trios, 1 appearance", band.accessibleName)
        // A row without a band ID routes by its team key (same as player-bands rows).
        val keyed = GlobalSearchResults.bands(listOf(entry.copy(bandId = ""))).single()
        assertEquals(SearchDestination.Push(BandRoute(entry.teamKey, "One + Two", "Band_Trios", entry.teamKey)), keyed.destination)
        assertEquals(10, GlobalSearchResults.bands(List(15) { entry.copy(bandId = "b$it") }).size)
        assertEquals("Search songs, players, or bands", GlobalSearchResults.PLACEHOLDER)
    }

    @Test
    fun announcements() {
        assertEquals("3 songs, 10 players", GlobalSearchResults.announcement(Count.Of(3), Count.Of(10)))
        assertEquals("1 song, 1 player, 1 band", GlobalSearchResults.announcement(Count.Of(1), Count.Of(1), Count.Of(1)))
        assertEquals("1 song, 0 players, 2 bands", GlobalSearchResults.announcement(Count.Of(1), Count.Of(0), Count.Of(2)))
        assertEquals(GlobalSearchResults.NO_RESULTS, GlobalSearchResults.announcement(Count.Of(0), Count.Of(0), Count.Of(0)))
        assertEquals("2 songs, player search failed, 0 bands", GlobalSearchResults.announcement(Count.Of(2), Count.Failed, Count.Of(0)))
        assertEquals("0 songs, 0 players, band search failed", GlobalSearchResults.announcement(Count.Of(0), Count.Of(0), Count.Failed))
        assertEquals("song search failed, 0 players", GlobalSearchResults.announcement(Count.Failed, Count.Of(0)))
    }

    @Test
    fun presentationByWindowWidth() {
        assertEquals(SearchPresentation.FullScreen, GlobalSearchLayout.presentation(411))
        assertEquals(SearchPresentation.FullScreen, GlobalSearchLayout.presentation(599))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(600))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(839))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(840))
        assertEquals(SearchPresentation.Docked, GlobalSearchLayout.presentation(1600))
    }

    @Test
    fun fullScreenGrowsFromTheRequester() {
        // A 48 dp icon at density 2 grows into a 56 dp field centred on it.
        val icon = PxRect(900, 100, 996, 196)
        val anchor = GlobalSearchLayout.anchor(SearchPresentation.FullScreen, icon, 1080, 2400, 2f)
        assertEquals(PxRect(900, 92, 996, 204), anchor.anchor)
        assertNull(anchor.maxPanelHeight)
    }

    @Test
    fun fullScreenFieldGrowsWithTheFontScale() {
        // Font scale 1.0 (24 sp line at density 2): 48 + 64 = 112 px, Material's 56 dp minimum.
        assertEquals(112, GlobalSearchLayout.fieldHeight(48f, 2f))
        // Font scale 2.0 (about 48 sp line): 96 + 64 = 160 px, taller than the minimum.
        assertEquals(160, GlobalSearchLayout.fieldHeight(96f, 2f))
        val icon = PxRect(900, 100, 996, 196)
        val tall = GlobalSearchLayout.anchor(SearchPresentation.FullScreen, icon, 1080, 2400, 2f, fullScreenFieldHeight = 160)
        assertEquals(PxRect(900, 68, 996, 228), tall.anchor)
        // Never below the minimum, and the docked anchor keeps its 56 dp height.
        assertEquals(112, GlobalSearchLayout.anchor(SearchPresentation.FullScreen, icon, 1080, 2400, 2f, fullScreenFieldHeight = 10).anchor.height)
        assertEquals(112, GlobalSearchLayout.anchor(SearchPresentation.Docked, icon, 1440, 2000, 2f, fullScreenFieldHeight = 160).anchor.height)
    }

    @Test
    fun scopeChipsShareTheRowOnlyWhenEveryLabelFits() {
        // 360 dp at density 1: (360 - 32 - 16) / 3 = 104 px share, 18 px chip chrome each.
        assertTrue(GlobalSearchLayout.scopeChipsFitEqually(listOf(40f, 52f, 38f), 360, 1f))
        assertTrue(GlobalSearchLayout.scopeChipsFitEqually(listOf(86f, 86f, 86f), 360, 1f))
        // Issue #141: "Players" at font scale 2 needs more than its share, so the row scrolls.
        assertFalse(GlobalSearchLayout.scopeChipsFitEqually(listOf(80f, 87f, 76f), 360, 1f))
        assertFalse(GlobalSearchLayout.scopeChipsFitEqually(listOf(160f, 180f, 150f), 720, 2f))
        assertTrue(GlobalSearchLayout.scopeChipsFitEqually(listOf(160f, 172f, 150f), 720, 2f))
        assertTrue(GlobalSearchLayout.scopeChipsFitEqually(emptyList(), 0, 1f))
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
    fun dockedPanelStaysOnTheRequestersSideOfAVerticalHinge() {
        val hinge = PxRect(1038, 0, 1038, 2152)
        // Requester in the left pane: panel clamped to the left pane.
        val left = GlobalSearchLayout.anchor(SearchPresentation.Docked, PxRect(900, 20, 996, 116), 2076, 2152, 1f, verticalHinge = hinge)
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
