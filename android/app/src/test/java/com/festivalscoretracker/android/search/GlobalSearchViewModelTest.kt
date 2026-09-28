package com.festivalscoretracker.android.search

import androidx.lifecycle.SavedStateHandle
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
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

    private fun model(
        players: Recorder = Recorder { listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player")) },
        catalog: suspend () -> List<Song> = { songs },
        selected: String? = null,
        saved: SavedStateHandle = SavedStateHandle(),
        backoff: ServiceRetryBackoff = ServiceRetryBackoff { 0L },
    ) = GlobalSearchViewModel(catalog, players::search, { selected }, backoff, saved)

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
        assertEquals(GlobalSearchResults.ENTER_QUERY_HINT, vm.ui.hint)
        vm.onQueryChange(" a ")
        settle()
        assertTrue(vm.ui.isShortQuery)
        assertEquals(GlobalSearchResults.ENTER_QUERY_HINT, vm.ui.hint)
        assertTrue(players.queries.isEmpty())
        assertFalse(vm.ui.isBusy)
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
        assertEquals("1 song, 1 player", vm.ui.announcement)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showPlayersSection)
        assertNull(vm.ui.hint)
        // Retyping the same settled text does nothing.
        vm.onQueryChange("alph")
        settle()
        assertEquals(1, players.queries.size)
    }

    @Test
    fun songsShowBeforePlayersAndLateResultsAreDropped() = runTest(main.dispatcher) {
        val first = CompletableDeferred<List<PlayerSearchResult>>()
        val players = Recorder { query -> if (query == "alpha") first.await() else listOf(PlayerSearchResult(Fixtures.ACCOUNT_B, "Beta Player")) }
        val vm = model(players)
        vm.onQueryChange("alpha")
        settle()
        assertEquals(SectionPhase.Loaded, vm.ui.songsPhase)
        assertEquals(SectionPhase.Loading, vm.ui.playersPhase)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showPlayersSection)
        assertNull(vm.ui.announcement)
        vm.onQueryChange("beta")
        settle()
        first.complete(listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Late")))
        advanceUntilIdle()
        assertEquals(listOf("Beta Player"), vm.ui.players.map { it.displayName })
        assertEquals(listOf("s-beta"), vm.ui.songs.map { it.songId })
    }

    @Test
    fun emptyEverythingOffersRetry() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val vm = model(players)
        vm.onQueryChange("zzz")
        settle()
        assertEquals(GlobalSearchResults.NO_RESULTS, vm.ui.hint)
        assertTrue(vm.ui.canRetryAll)
        assertFalse(vm.ui.showPlayersSection)
        assertEquals(GlobalSearchResults.NO_RESULTS, vm.ui.announcement)
        vm.retry()
        advanceUntilIdle()
        assertEquals(2, players.queries.size)
        // Scoped views: Songs says "No songs found.", Players shows its own empty row.
        vm.toggleScope(SearchScope.Songs)
        assertEquals(GlobalSearchResults.NO_SONGS, vm.ui.hint)
        vm.toggleScope(SearchScope.Players)
        assertNull(vm.ui.hint)
        assertTrue(vm.ui.showPlayersSection)
        assertEquals(SectionPhase.Empty, vm.ui.playersPhase)
        vm.toggleScope(SearchScope.Players)
        assertEquals(SearchScope.All, vm.ui.scope)
    }

    @Test
    fun playerFailureKeepsSongsAndRetries() = runTest(main.dispatcher) {
        var fail = true
        val players = Recorder { if (fail) throw IOException("down") else listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Alpha Player")) }
        val vm = model(players)
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertEquals(SectionPhase.Failed, vm.ui.playersPhase)
        assertEquals(ServiceIssue.Offline, vm.ui.playersIssue)
        assertTrue(vm.ui.showSongsSection)
        assertTrue(vm.ui.showPlayersSection)
        assertEquals("1 song, player search failed", vm.ui.announcement)
        fail = false
        vm.retry()
        advanceUntilIdle()
        assertEquals(SectionPhase.Loaded, vm.ui.playersPhase)
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
        assertEquals("1 song, player search failed", vm.ui.announcement)
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
        assertEquals("song search failed, 1 player", vm.ui.announcement)
    }

    @Test
    fun bandsScopeNeverRequestsAndHidesResults() = runTest(main.dispatcher) {
        val players = Recorder { emptyList() }
        val vm = model(players)
        vm.toggleScope(SearchScope.Bands)
        vm.onQueryChange("alpha")
        settle()
        advanceUntilIdle()
        assertTrue(vm.ui.isBandsScope)
        assertNull(vm.ui.hint)
        assertFalse(vm.ui.showSongsSection)
        assertFalse(vm.ui.showPlayersSection)
        assertFalse(vm.ui.isBusy)
        // Only the account search ran (players, not bands); nothing band-shaped exists in the engine.
        assertEquals(listOf("alpha/10"), players.queries)
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
        val players = Recorder { emptyList() }
        val vm = model(players)
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
        vm.retry()
        runCurrent()
        assertEquals(1, players.queries.size)
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
    }
}
