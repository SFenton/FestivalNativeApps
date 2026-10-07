package com.festivalscoretracker.android.search

import androidx.lifecycle.SavedStateHandle
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.presentation.search.SearchEmptyState
import com.festivalscoretracker.android.presentation.search.SectionPhase
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GlobalSearchViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val songs = listOf(
        Fixtures.song("s-alpha", "Alpha Tune", artist = "Band One"),
        Fixtures.song("s-beta", "Beta Song", artist = "Band Two"),
    )

    private class Recorder(var respond: suspend (String) -> List<PlayerSearchResult>) {
        val queries = mutableListOf<String>()
        suspend fun search(query: String, limit: Int): List<PlayerSearchResult> {
            queries += "$query/$limit"
            return respond(query)
        }
    }

    private class BandRecorder(var respond: suspend (String) -> List<PlayerBandEntry>) {
        val queries = mutableListOf<String>()
        suspend fun search(query: String, limit: Int): List<PlayerBandEntry> {
            queries += "$query/$limit"
            return respond(query)
        }
    }

    private val duo = PlayerBandEntry(
        bandId = "band-1",
        teamKey = "${Fixtures.ACCOUNT_A}:${Fixtures.ACCOUNT_B}",
        bandType = "Band_Duets",
        appearanceCount = 12,
        members = listOf(BandMember(Fixtures.ACCOUNT_A, "Alpha Player"), BandMember(Fixtures.ACCOUNT_B, "Beta Player")),
    )

    private fun model(
        players: Recorder = Recorder { listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player")) },
        catalog: suspend () -> List<Song> = { songs },
        selected: String? = null,
        saved: SavedStateHandle = SavedStateHandle(),
        backoff: ServiceRetryBackoff = ServiceRetryBackoff { 0L },
        bands: BandRecorder = BandRecorder { emptyList() },
    ) = GlobalSearchViewModel(catalog, players::search, bands::search, { selected }, backoff, saved)

    private fun TestScope.settle() {
        advanceTimeBy(GlobalSearchResults.DEBOUNCE_MS + 1)
        runCurrent()
    }

    private val GlobalSearchViewModel.ui: GlobalSearchUiState get() = state.value

    @Test
    fun shortQueryShowsHintWithoutRequests() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val vm = model(players)
        vm.open()
        assertTrue(vm.ui.expanded)
        assertEquals(GlobalSearchResults.ENTER_QUERY_HINT_ALL, vm.ui.hint)
        vm.onQueryChange(" a ")
        settle()
        assertTrue(vm.ui.isShortQuery)
        assertEquals(GlobalSearchResults.ENTER_QUERY_HINT_ALL, vm.ui.hint)
        assertTrue(players.queries.isEmpty())
        assertFalse(vm.ui.isBusy)
        // Issue #299: each scope names what it searches, Bands included.
        vm.toggleScope(SearchScope.Songs)
        assertEquals("Enter at least two characters to search for songs.", vm.ui.hint)
        vm.toggleScope(SearchScope.Players)
        assertEquals("Enter at least two characters to search for players.", vm.ui.hint)
        vm.toggleScope(SearchScope.Bands)
        assertEquals("Enter at least two characters to search for bands.", vm.ui.hint)
        vm.toggleScope(SearchScope.Bands)
        assertEquals("Enter at least two characters to search for songs, players, or bands.", vm.ui.hint)
        assertTrue(players.queries.isEmpty())
    }

    @Test
    fun fastTypingSendsOneDebouncedRequest() = runTest(main.dispatcher) {
        val players = Recorder { listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player")) }
        val vm = model(players)
        vm.onQueryChange("al")
        advanceTimeBy(100)
        vm.onQueryChange("alp")
        advanceTimeBy(100)
        vm.onQueryChange("alph ")
        assertTrue(vm.ui.debouncing)
        assertTrue(vm.ui.isBusy)
        advanceTimeBy(249)
        runCurrent()
        assertTrue(players.queries.isEmpty())
        settle()
        assertEquals(listOf("alph/10"), players.queries)
        assertEquals("alph", vm.ui.settledQuery)
        assertEquals(listOf("s-alpha"), vm.ui.songs.map { it.songId })
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        assertEquals("1 song, 1 player, 0 bands", vm.ui.announcement)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showPlayersSection)
        assertNull(vm.ui.hint)
        // Retyping the same settled text does nothing.
        vm.onQueryChange("alph")
        settle()
        assertEquals(1, players.queries.size)
    }

    @Test
    fun allWaitsForPlayersBehindOneSpinnerAndLateResultsAreDropped() = runTest(main.dispatcher) {
        val first = CompletableDeferred<List<PlayerSearchResult>>()
        val players = Recorder { query -> if (query == "alpha") first.await() else listOf(PlayerSearchResult(Fixtures.ACCOUNT_B, "Beta Player")) }
        val vm = model(players)
        vm.onQueryChange("alpha")
        settle()
        assertEquals(SectionPhase.Loaded, vm.ui.songsPhase)
        assertEquals(SectionPhase.Loading, vm.ui.playersPhase)
        // Issue #299: All shows the one centred spinner until players settle; Songs does not wait.
        assertTrue(vm.ui.isBusy)
        vm.toggleScope(SearchScope.Songs)
        assertFalse(vm.ui.isBusy)
        assertTrue(vm.ui.showSongsSection)
        vm.toggleScope(SearchScope.Players)
        assertTrue(vm.ui.isBusy)
        vm.toggleScope(SearchScope.Players)
        assertNull(vm.ui.announcement)
        vm.onQueryChange("beta")
        settle()
        first.complete(listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Late")))
        advanceUntilIdle()
        assertEquals(listOf("Beta Player"), vm.ui.players.map { it.displayName })
        assertEquals(listOf("s-beta"), vm.ui.songs.map { it.songId })
    }

    @Test
    fun emptyEverythingHasNoRetryButSearchRunsItAgain() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val vm = model(players)
        vm.onQueryChange("zzz")
        settle()
        assertNull(vm.ui.hint)
        assertEquals(
            SearchEmptyState(GlobalSearchResults.EMPTY_ALL_TITLE, GlobalSearchResults.EMPTY_ALL_SUBTITLE),
            vm.ui.emptyState,
        )
        assertFalse(vm.ui.showPlayersSection)
        assertEquals(GlobalSearchResults.NO_RESULTS, vm.ui.announcement)
        // An empty envelope may be a server timeout: the IME Search action runs the same text again.
        vm.submit()
        advanceUntilIdle()
        assertEquals(2, players.queries.size)
        // Scoped views: each shows its own centred title and subtitle.
        vm.toggleScope(SearchScope.Songs)
        assertEquals(
            SearchEmptyState(GlobalSearchResults.EMPTY_SONGS_TITLE, GlobalSearchResults.EMPTY_SONGS_SUBTITLE),
            vm.ui.emptyState,
        )
        vm.toggleScope(SearchScope.Players)
        assertNull(vm.ui.hint)
        assertFalse(vm.ui.showPlayersSection)
        assertEquals(SectionPhase.Empty, vm.ui.playersPhase)
        assertEquals(
            SearchEmptyState(GlobalSearchResults.EMPTY_PLAYERS_TITLE, GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE),
            vm.ui.emptyState,
        )
        vm.toggleScope(SearchScope.Players)
        assertEquals(SearchScope.All, vm.ui.scope)
    }

    @Test
    fun emptyPlayersWithSongsHideThePlayersSectionInAll() = runTest(main.dispatcher) {
        val vm = model(Recorder { emptyList() })
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Empty, vm.ui.playersPhase)
        // Web parity: All renders only sections with rows or an error, so no inline "No players found." row.
        assertTrue(vm.ui.showSongsSection)
        assertFalse(vm.ui.showPlayersSection)
        assertNull(vm.ui.emptyState)
        assertNull(vm.ui.hint)
        // The Players scope shows the centred empty state instead.
        vm.toggleScope(SearchScope.Players)
        assertEquals(GlobalSearchResults.EMPTY_PLAYERS_TITLE, vm.ui.emptyState?.title)
        // Songs with matches never shows an empty state.
        vm.toggleScope(SearchScope.Songs)
        assertNull(vm.ui.emptyState)
    }

    @Test
    fun playerFailureKeepsSongsAndSearchRunsItAgain() = runTest(main.dispatcher) {
        var fail = true
        val players = Recorder { if (fail) throw IOException("down") else listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player")) }
        // Bands found, so only the players failure makes Search run the query again.
        val vm = model(players, bands = BandRecorder { listOf(duo) })
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Failed, vm.ui.playersPhase)
        assertEquals(ServiceIssue.Offline, vm.ui.playersIssue)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showPlayersSection)
        assertEquals("1 song, player search failed, 1 band", vm.ui.announcement)
        fail = false
        vm.submit()
        advanceUntilIdle()
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        assertEquals(2, players.queries.size)
        // A settled, successful query is not run again.
        vm.submit()
        advanceUntilIdle()
        assertEquals(2, players.queries.size)
    }

    @Test
    fun scrapeFreezeCountsDownAndRetriesAutomatically() = runTest(main.dispatcher) {
        var frozen = true
        val players = Recorder {
            if (frozen) throw FestivalApiException.PublicReadFrozen("scrape", "2") else listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player"))
        }
        val vm = model(players)
        vm.onQueryChange("alpha")
        settle()
        runCurrent()
        assertTrue(vm.ui.playersIssue is ServiceIssue.ScrapeInProgress)
        assertEquals(2, vm.ui.playersCountdown)
        assertEquals("1 song, player search failed, 0 bands", vm.ui.announcement)
        frozen = false
        advanceTimeBy(2_001)
        runCurrent()
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        assertEquals(2, players.queries.size)
    }

    @Test
    fun catalogueFailureShowsSongsFailedButPlayersStillLoad() = runTest(main.dispatcher) {
        val vm = model(catalog = { throw IOException("x") })
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Failed, vm.ui.songsPhase)
        assertTrue(vm.ui.showSongsSection)
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        assertEquals("song search failed, 1 player, 0 bands", vm.ui.announcement)
    }

    @Test
    fun bandsSearchInParallelAndOpenTheBandPage() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val bands = BandRecorder { listOf(duo) }
        val vm = model(players, bands = bands)
        vm.toggleScope(SearchScope.Bands)
        vm.onQueryChange(" alpha ")
        settle()
        advanceUntilIdle()
        // Web useUnifiedSearch: one debounced players request and one bands request (pageSize 10).
        assertEquals(listOf("alpha/10"), players.queries)
        assertEquals(listOf("alpha/10"), bands.queries)
        assertNull(vm.ui.hint)
        assertTrue(vm.ui.showBandsSection)
        assertFalse(vm.ui.showSongsSection)
        assertFalse(vm.ui.showPlayersSection)
        assertFalse(vm.ui.isBusy)
        assertNull(vm.ui.emptyState)
        assertEquals("1 song, 0 players, 1 band", vm.ui.announcement)
        val band = vm.ui.bands.single()
        assertEquals("Alpha Player + Beta Player, Duos, 12 appearances", band.accessibleName)
        // No selected-band profile on Android: every band opens its Band page.
        assertEquals(
            SearchDestination.Push(BandRoute("band-1", "Alpha Player + Beta Player", "Band_Duets", duo.teamKey)),
            band.destination,
        )
        // Switching scope shows what was already fetched; no new request.
        vm.toggleScope(SearchScope.Bands)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showBandsSection)
        assertEquals(1, bands.queries.size)
    }

    @Test
    fun bandsScopeWaitsOnlyForBandsBehindOneSpinner() = runTest(main.dispatcher) {
        val pending = CompletableDeferred<List<PlayerBandEntry>>()
        val vm = model(bands = BandRecorder { pending.await() })
        vm.onQueryChange("alpha")
        settle()
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        assertEquals(SectionPhase.Loading, vm.ui.bandsPhase)
        // All waits for every scope; Players and Songs do not wait for bands; Bands does.
        assertTrue(vm.ui.isBusy)
        assertNull(vm.ui.announcement)
        vm.toggleScope(SearchScope.Players)
        assertFalse(vm.ui.isBusy)
        vm.toggleScope(SearchScope.Bands)
        assertTrue(vm.ui.isBusy)
        pending.complete(listOf(duo))
        advanceUntilIdle()
        assertFalse(vm.ui.isBusy)
        assertEquals("1 song, 1 player, 1 band", vm.ui.announcement)
    }

    @Test
    fun emptyBandsShowNoBandsFoundAndSearchRunsItAgain() = runTest(main.dispatcher) {
        val bands = BandRecorder { emptyList() }
        val vm = model(bands = bands)
        vm.toggleScope(SearchScope.Bands)
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Empty, vm.ui.bandsPhase)
        assertFalse(vm.ui.showBandsSection)
        assertEquals(
            SearchEmptyState(GlobalSearchResults.EMPTY_BANDS_TITLE, GlobalSearchResults.EMPTY_BANDS_SUBTITLE),
            vm.ui.emptyState,
        )
        vm.submit()
        advanceUntilIdle()
        assertEquals(2, bands.queries.size)
        // In All, empty bands simply leave no section, like empty players.
        vm.toggleScope(SearchScope.Bands)
        assertNull(vm.ui.emptyState)
        assertFalse(vm.ui.showBandsSection)
    }

    @Test
    fun bandFailureIsSeparateFromEmptyWithoutRetry() = runTest(main.dispatcher) {
        var fail = true
        val bands = BandRecorder { if (fail) throw IOException("down") else listOf(duo) }
        val vm = model(Recorder { emptyList() }, catalog = { emptyList() }, bands = bands)
        vm.toggleScope(SearchScope.Bands)
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Failed, vm.ui.bandsPhase)
        assertEquals(ServiceIssue.Offline, vm.ui.bandsIssue)
        assertTrue(vm.ui.showBandsSection)
        assertNull(vm.ui.emptyState)
        // All isn't "No results" when bands failed: the failure stays visible.
        vm.toggleScope(SearchScope.Bands)
        assertNull(vm.ui.emptyState)
        assertTrue(vm.ui.showBandsSection)
        assertEquals("0 songs, 0 players, band search failed", vm.ui.announcement)
        fail = false
        vm.submit()
        advanceUntilIdle()
        assertEquals(SectionPhase.Loaded, vm.ui.bandsPhase)
        assertEquals(2, bands.queries.size)
    }

    @Test
    fun bandScrapeFreezeCountsDownOnItsOwn() = runTest(main.dispatcher) {
        var frozen = true
        val bands = BandRecorder { if (frozen) throw FestivalApiException.PublicReadFrozen("scrape", "2") else listOf(duo) }
        val vm = model(bands = bands)
        vm.onQueryChange("alpha")
        settle()
        runCurrent()
        assertTrue(vm.ui.bandsIssue is ServiceIssue.ScrapeInProgress)
        assertEquals(2, vm.ui.bandsCountdown)
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        frozen = false
        advanceTimeBy(2_001)
        runCurrent()
        assertEquals(SectionPhase.Loaded, vm.ui.bandsPhase)
        assertEquals(2, bands.queries.size)
    }

    @Test
    fun selectedPlayerIsMarked() = runTest(main.dispatcher) {
        val vm = model(selected = Fixtures.ACCOUNT_A)
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertTrue(vm.ui.players.single().isSelected)
    }

    @Test
    fun submitSkipsDebounceAndClearResets() = runTest(main.dispatcher) {
        val players = Recorder { listOf(PlayerSearchResult(Fixtures.ACCOUNT_B, "Beta Player")) }
        val vm = model(players, bands = BandRecorder { listOf(duo) })
        vm.onQueryChange("beta")
        vm.submit()
        runCurrent()
        assertEquals(listOf("beta/10"), players.queries)
        vm.submit()
        runCurrent()
        assertEquals(1, players.queries.size)
        vm.clearQuery()
        assertEquals("", vm.ui.query)
        assertEquals(SectionPhase.Idle, vm.ui.songsPhase)
        vm.submit()
        runCurrent()
        assertEquals(1, players.queries.size)
    }

    @Test
    fun sectionTitlesShowOnlyInAll() {
        // Issue #348 (web SearchModal <h3> per category in All); a single scope stays untitled (#299).
        assertTrue(GlobalSearchUiState(scope = SearchScope.All).showsSectionTitles)
        SearchScope.chips.forEach { assertFalse(GlobalSearchUiState(scope = it).showsSectionTitles) }
    }

    @Test
    fun closeResetsQueryAndScope() = runTest(main.dispatcher) {
        val saved = SavedStateHandle()
        val vm = model(saved = saved)
        vm.open("alpha")
        vm.toggleScope(SearchScope.Players)
        advanceUntilIdle()
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
        vm.close()
        assertFalse(vm.ui.expanded)
        assertEquals("", vm.ui.query)
        assertEquals(SearchScope.All, vm.ui.scope)
        assertEquals(SectionPhase.Idle, vm.ui.playersPhase)
        assertEquals("", saved.get<String>("globalSearch.query"))
        assertEquals(false, saved.get<Boolean>("globalSearch.expanded"))
    }

    @Test
    fun savedStateRestoresAnOpenSearch() = runTest(main.dispatcher) {
        val saved = SavedStateHandle(mapOf("globalSearch.query" to "beta", "globalSearch.scope" to "songs", "globalSearch.expanded" to true))
        val players = Recorder { emptyList() }
        val vm = model(players, saved = saved)
        advanceUntilIdle()
        assertTrue(vm.ui.expanded)
        assertEquals(SearchScope.Songs, vm.ui.scope)
        assertEquals(listOf("s-beta"), vm.ui.songs.map { it.songId })
        assertEquals(listOf("beta/10"), players.queries)
        // Closed state restores without searching.
        val idle = model(players, saved = SavedStateHandle(mapOf("globalSearch.query" to "beta")))
        advanceUntilIdle()
        assertFalse(idle.ui.expanded)
        assertEquals(1, players.queries.size)
    }

    @Test
    fun invalidPlayerQueryIsEmptyWithoutRequest() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val vm = model(players)
        vm.onQueryChange("al‮pha")
        settle()
        advanceUntilIdle()
        assertTrue(players.queries.isEmpty())
        assertEquals(SectionPhase.Empty, vm.ui.playersPhase)
        assertEquals(SectionPhase.Empty, vm.ui.bandsPhase)
    }
}
