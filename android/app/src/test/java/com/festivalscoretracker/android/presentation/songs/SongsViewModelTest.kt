package com.festivalscoretracker.android.presentation.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.songs.SongsPreferencesState
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongsViewModel
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.presentation.profile.SelectedProfileStatus
import com.festivalscoretracker.android.presentation.shop.ShopStore
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.SongsFixtures
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SongsViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val songs = listOf(
        Fixtures.song("b", "Beta", year = 2001),
        Fixtures.song("a", "Alpha", year = 2010),
        Fixtures.song("c", "Gamma", year = 1999, lead = null),
    )
    private val payload = CatalogPayload(SongsResponse(3, 15, songs), 7)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "P")

    private class Inputs {
        val settings = MutableStateFlow<AppSettings?>(AppSettings())
        val prefs = MutableStateFlow(SongsPreferencesState())
        val shop = MutableStateFlow<LoadState<ShopPayload>>(LoadState.Loading)
        val profile = MutableStateFlow(SelectedProfileState())
        val publication = MutableStateFlow<Int?>(7)
    }

    private fun viewModel(inputs: Inputs, load: suspend (Boolean) -> CatalogPayload = { payload }) = SongsViewModel(
        load, inputs.settings, inputs.prefs, inputs.shop, inputs.profile, inputs.publication, ServiceRetryBackoff(),
        computeDispatcher = main.dispatcher,
    )

    private fun available(vararg scores: com.festivalscoretracker.android.core.profile.PlayerScore, observed: Int = 7): SelectedProfileState {
        val profile = SongsFixtures.profile(*scores, observed = observed)
        return SelectedProfileState(player, SelectedProfileStatus.Available, profile, scoreIndex = profile.profile.scoreIndex())
    }

    @Test
    fun listSortsSearchesAndCountsLoads() = runTest(main.dispatcher) {
        val inputs = Inputs()
        var loads = 0
        val vm = viewModel(inputs) { loads++; payload }
        advanceUntilIdle()
        val state = vm.uiState.value
        assertEquals(listOf("a", "b", "c"), state.rows.map { it.song.songId })
        assertEquals(listOf("A", "B", "G"), state.sections.map { it.label })
        assertEquals(3, state.totalSongs)
        assertFalse(state.sortChanged)
        assertFalse(state.hasPlayer)

        vm.onSearchChange("gam")
        assertEquals("gam", vm.searchInput.value)
        advanceTimeBy(100)
        assertEquals(3, vm.uiState.value.rows.size)
        advanceUntilIdle()
        assertEquals(listOf("c"), vm.uiState.value.rows.map { it.song.songId })
        vm.onSearchChange("zzz")
        advanceUntilIdle()
        assertEquals("No songs match your search.", vm.uiState.value.emptyMessage)
        vm.onSearchChange("")
        advanceUntilIdle()

        inputs.settings.value = AppSettings(songSort = SongSortMode.Year, songSortAscending = false)
        advanceUntilIdle()
        assertEquals(listOf("a", "b", "c"), vm.uiState.value.rows.map { it.song.songId })
        assertTrue(vm.uiState.value.sortChanged)

        vm.refresh()
        advanceUntilIdle()
        vm.retry()
        advanceUntilIdle()
        assertEquals(3, loads)
    }

    @Test
    fun failureSurfacesIssue() = runTest(main.dispatcher) {
        val vm = viewModel(Inputs()) { throw FestivalApiException.HttpStatus(404) }
        advanceUntilIdle()
        assertEquals(LoadState.Failed(ServiceIssue.NotFound), vm.uiState.value.catalog)
        assertTrue(vm.uiState.value.rows.isEmpty())
    }

    @Test
    fun shopSortAndHighlightsNeedSamePublication() = runTest(main.dispatcher) {
        val inputs = Inputs()
        inputs.settings.value = AppSettings(songSort = SongSortMode.Shop)
        val vm = viewModel(inputs)
        advanceUntilIdle()
        assertEquals(SongSortMode.Title, vm.uiState.value.effectiveSort)
        assertTrue(vm.uiState.value.notices.single().contains("until Item Shop data loads"))

        inputs.shop.value = LoadState.Loaded(SongsFixtures.shop(SongsFixtures.offer("c", isNew = true), SongsFixtures.offer("b", leaving = true)))
        advanceUntilIdle()
        val live = vm.uiState.value
        assertEquals(SongSortMode.Shop, live.effectiveSort)
        assertEquals(listOf("b", "c", "a"), live.rows.map { it.song.songId })
        assertEquals(listOf("Leaving Tomorrow", "In Shop", "Not In Shop"), live.headers.map { it.label })
        assertTrue(live.notices.isEmpty())
        assertEquals(com.festivalscoretracker.android.core.shop.ShopHighlight.LeavingTomorrow, live.rows[0].highlight)

        // A Shop feed from a newer publication never decorates older rows.
        inputs.shop.value = LoadState.Loaded(SongsFixtures.shop(SongsFixtures.offer("c", isNew = true), observed = 8))
        inputs.publication.value = 8
        advanceUntilIdle()
        assertTrue(vm.uiState.value.notices.single().contains("update together"))
        assertTrue(vm.uiState.value.rows.all { it.highlight == null })

        inputs.settings.value = AppSettings(songSort = SongSortMode.Shop, hideShop = true)
        advanceUntilIdle()
        assertTrue(vm.uiState.value.hideShop)
        assertTrue(vm.uiState.value.notices.single().contains("hidden"))
    }

    @Test
    fun selectedPlayerChipsFiltersAndPauses() = runTest(main.dispatcher) {
        val inputs = Inputs()
        inputs.settings.value = AppSettings(selectedPlayer = player)
        inputs.profile.value = SelectedProfileState(player, SelectedProfileStatus.Loading)
        val vm = viewModel(inputs)
        advanceUntilIdle()
        assertTrue(vm.uiState.value.hasPlayer)
        assertEquals("Loading scores", vm.uiState.value.rows[0].scoreState)

        inputs.profile.value = available(SongsFixtures.score("a", Instrument.Lead, 1000, fc = true))
        advanceUntilIdle()
        assertEquals(9, vm.uiState.value.rows.first { it.song.songId == "a" }.chips.size)

        inputs.prefs.value = SongsPreferencesState(playerFilter = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)))
        advanceUntilIdle()
        assertEquals(listOf("a"), vm.uiState.value.rows.map { it.song.songId })
        assertTrue(vm.uiState.value.filtersApplied)
        assertEquals("No songs match the filters.", vm.uiState.value.emptyMessage)

        // Scores observed in another publication pause chips and filters.
        inputs.profile.value = available(SongsFixtures.score("a", Instrument.Lead, 1000), observed = 6)
        advanceUntilIdle()
        val paused = vm.uiState.value
        assertEquals(3, paused.rows.size)
        assertEquals("Player scores paused until songs update", paused.rows[0].scoreState)
        assertEquals(2, paused.notices.size)

        inputs.profile.value = SelectedProfileState(player, SelectedProfileStatus.Syncing)
        advanceUntilIdle()
        assertEquals("Scores syncing", vm.uiState.value.rows[0].scoreState)
        inputs.profile.value = SelectedProfileState(player, SelectedProfileStatus.Failed, issue = ServiceIssue.NotFound)
        advanceUntilIdle()
        assertEquals("Scores unavailable", vm.uiState.value.rows[0].scoreState)

        inputs.prefs.value = SongsPreferencesState(playerFilter = null)
        advanceUntilIdle()
        assertTrue(vm.uiState.value.invalidSavedFilter)
        assertTrue(vm.uiState.value.rows.isEmpty())
    }

    @Test
    fun scoreAdapterMapsEveryStatus() {
        assertEquals(SongScoreSource.NONE, SelectedProfileState().songScoreSource(7, 7))
        assertEquals(SongScoreSource.LOADING, SelectedProfileState(player, SelectedProfileStatus.None).songScoreSource(7, 7))
        assertEquals(SongScoreSource.SYNCING, SelectedProfileState(player, SelectedProfileStatus.Syncing).songScoreSource(7, 7))
        assertEquals("Scores unavailable", SelectedProfileState(player, SelectedProfileStatus.Failed).songScoreSource(7, 7).rowState)
        val live = available(SongsFixtures.score("a", Instrument.Bass, 5, fc = false)).songScoreSource(7, 7)
        assertTrue(live.available)
        val detail = live.detail!!("a", Instrument.Bass)!!
        assertEquals(5L, detail.score)
        assertEquals(987_000.0, detail.accuracy!!, 0.0)
        assertEquals("2026-09-01T12:00:00Z", detail.lastPlayedAt)
        assertNull(live.detail!!("a", Instrument.Lead))
        assertNull(live.detail!!("zzz", Instrument.Lead))
        assertEquals(SongScoreSource.PAUSED, available(observed = 6).songScoreSource(7, 7))
        assertEquals(SongScoreSource.PAUSED, available().songScoreSource(7, 8))
        val validFirst = SongsFixtures.score("a", Instrument.Lead, 1).copy(validLastPlayedAt = "2026-01-01T00:00:00Z").toSongDetail()
        assertEquals("2026-01-01T00:00:00Z", validFirst.lastPlayedAt)
    }

    @Test
    fun shopStoreLoadsOnceAndReloadsOnNewPublication() = runTest(main.dispatcher) {
        var loads = 0
        val publications = MutableStateFlow<Int?>(7)
        val scope = CoroutineScope(coroutineContext + SupervisorJob())
        val store = ShopStore({ loads++; SongsFixtures.shop(observed = publications.value ?: 0) }, publications, ServiceRetryBackoff(), scope)
        assertEquals(LoadState.Loading, store.state.value)
        store.ensureStarted()
        store.ensureStarted()
        advanceUntilIdle()
        assertEquals(1, loads)
        assertEquals(7, (store.state.value as LoadState.Loaded).value.observedPublicationId)
        publications.value = 8
        advanceUntilIdle()
        assertEquals(2, loads)
        store.refresh()
        advanceUntilIdle()
        store.retry()
        advanceUntilIdle()
        assertEquals(4, loads)
        scope.cancel()
    }
}
