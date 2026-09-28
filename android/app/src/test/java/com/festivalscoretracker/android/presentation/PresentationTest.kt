package com.festivalscoretracker.android.presentation

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import java.io.IOException
import kotlin.random.Random
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** In-memory preferences store for view model tests. */
class InMemoryPreferences(initial: Preferences = emptyPreferences()) : DataStore<Preferences> {
    private val state = MutableStateFlow(initial)

    /** Current stored value. */
    val current: Preferences get() = state.value
    override val data: Flow<Preferences> = state
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
        transform(state.value).also { state.value = it }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PresentationTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val songs = listOf(
        Fixtures.song("b", "Beta", year = 2001),
        Fixtures.song("a", "Alpha", year = 2010),
        Fixtures.song("c", "Gamma", year = 1999, lead = null),
    )
    private val payload = CatalogPayload(SongsResponse(3, 15, songs), 7)

    // region Retrying loader

    @Test
    fun loaderSucceedsFailsAndRetries() = runTest(main.dispatcher) {
        var fail = true
        val loader = RetryingLoader(this, "k", ServiceRetryBackoff()) { if (fail) throw FestivalApiException.HttpStatus(500) else 5 }
        assertEquals(LoadState.Loading, loader.state.value)
        loader.ensureStarted()
        advanceUntilIdle()
        assertEquals(LoadState.Failed(ServiceIssue.Other("The service is temporarily unavailable. Try again.")), loader.state.value)
        fail = false
        loader.ensureStarted()
        advanceUntilIdle()
        assertTrue(loader.state.value is LoadState.Failed)
        loader.retry()
        advanceUntilIdle()
        assertEquals(LoadState.Loaded(5), loader.state.value)
        assertEquals(5, loader.state.value.valueOrNull)
        assertNull(LoadState.Loading.valueOrNull)
    }

    @Test
    fun scrapeFreezeCountsDownThenRetriesAutomatically() = runTest(main.dispatcher) {
        var calls = 0
        val loader = RetryingLoader(this, "k", ServiceRetryBackoff { testScheduler.currentTime }) {
            calls++
            if (calls == 1) throw FestivalApiException.PublicReadFrozen("scrape", "3") else "ok"
        }
        loader.retry()
        runCurrent()
        assertEquals(LoadState.Failed(ServiceIssue.ScrapeInProgress(3), 3), loader.state.value)
        advanceTimeBy(1_001)
        assertEquals(LoadState.Failed(ServiceIssue.ScrapeInProgress(3), 2), loader.state.value)
        advanceUntilIdle()
        assertEquals(LoadState.Loaded("ok"), loader.state.value)
        assertEquals(2, calls)
    }

    @Test
    fun refreshKeepsContentAndNewerLoadWins() = runTest(main.dispatcher) {
        val gate = CompletableDeferred<Int>()
        var first = true
        val loader = RetryingLoader(this, "k", ServiceRetryBackoff()) { refresh ->
            if (first) {
                first = false
                1
            } else if (refresh) {
                gate.await()
            } else {
                3
            }
        }
        loader.retry()
        advanceUntilIdle()
        loader.refresh()
        runCurrent()
        assertEquals(LoadState.Loaded(1, refreshing = true), loader.state.value)
        loader.retry()
        advanceUntilIdle()
        gate.complete(2)
        advanceUntilIdle()
        assertEquals(LoadState.Loaded(3), loader.state.value)
    }

    // endregion

    // region Shell

    @Test
    fun shellAppliesDebugOverrideInMemoryAndPersistsSelections() = runTest(main.dispatcher) {
        val store = InMemoryPreferences()
        val repository = SettingsRepository(store)
        val debug = SelectedPlayer(Fixtures.ACCOUNT_B, "Debug Player")
        val shell = ShellViewModel(repository, DebugLaunch(profile = debug))
        advanceUntilIdle()
        assertEquals(debug, shell.settings.value?.selectedPlayer)
        assertEquals(ProfileKind.Player, shell.profileKind(shell.settings.value))
        assertNull(SettingsRepository.decode(store.current).selectedPlayer)
        shell.deselectPlayer()
        advanceUntilIdle()
        assertNull(shell.settings.value?.selectedPlayer)
        assertEquals(ProfileKind.None, shell.profileKind(shell.settings.value))
        assertEquals(ProfileKind.None, shell.profileKind(null))
        val chosen = SelectedPlayer(Fixtures.ACCOUNT_A, "Chosen")
        shell.selectPlayer(chosen)
        shell.setInstrumentVisible(Instrument.Bass, false)
        shell.setSongSort(SongSortMode.Artist, false)
        shell.setIncreaseContrast(true)
        shell.setReduceMotion(true)
        advanceUntilIdle()
        val settings = shell.settings.value!!
        assertEquals(chosen, settings.selectedPlayer)
        assertFalse(Instrument.Bass in settings.visibleInstruments)
        assertEquals(SongSortMode.Artist, settings.songSort)
        assertTrue(settings.increaseContrast && settings.reduceMotion)

        val anonymous = ShellViewModel(repository, DebugLaunch(anonymous = true))
        advanceUntilIdle()
        assertNull(anonymous.settings.value?.selectedPlayer)
        val plain = ShellViewModel(repository, DebugLaunch.NONE)
        advanceUntilIdle()
        assertEquals(chosen, plain.settings.value?.selectedPlayer)
    }

    @Test
    fun unreadableSettingsFallBackToDefaults() = runTest(main.dispatcher) {
        val failing = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { throw IOException("disk") }
            override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences) = emptyPreferences()
        }
        val shell = ShellViewModel(SettingsRepository(failing), DebugLaunch.NONE)
        advanceUntilIdle()
        assertEquals(AppSettings(), shell.settings.value)
    }

    // endregion

    // region Song detail and leaderboard

    @Test
    fun songDetailResolvesByIdOrTitleAndLoadsPreviewsLazily() = runTest(main.dispatcher) {
        val api = FestivalApi("https://fixture.test", FakeTransport.standard())
        var boardCalls = 0
        val load: suspend (String, Instrument, Int, Int, Double?) -> com.festivalscoretracker.android.data.LeaderboardPayload = { id, instrument, page, top, _ ->
            boardCalls++
            api.leaderboard(id, instrument, page, top)
        }
        val byTitle = SongDetailViewModel("alpha tune", { api.catalog(it) }, load, ServiceRetryBackoff())
        advanceUntilIdle()
        val song = (byTitle.song.value as LoadState.Loaded).value
        assertEquals("s-alpha", song.songId)
        assertEquals(0, boardCalls)
        val preview = byTitle.preview(song, Instrument.Lead)
        assertSame(preview, byTitle.preview(song, Instrument.Lead))
        advanceUntilIdle()
        assertEquals(10, (preview.value as LoadState.Loaded).value.leaderboard.entries.size)
        assertEquals(1, boardCalls)
        byTitle.retryPreview(Instrument.Lead)
        byTitle.retryPreview(Instrument.Bass)
        advanceUntilIdle()
        assertEquals(2, boardCalls)

        val missing = SongDetailViewModel("nope", { api.catalog(it) }, load, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(LoadState.Failed(ServiceIssue.NotFound), missing.song.value)
        missing.retry()
        advanceUntilIdle()
        assertTrue(missing.song.value is LoadState.Failed)
    }

    @Test
    fun songLeaderboardCorrectsPagesAndNavigates() = runTest(main.dispatcher) {
        val api = FestivalApi("https://fixture.test", FakeTransport.standard())
        val viewModel = SongLeaderboardViewModel("s-alpha", Instrument.Lead, 9, { api.catalog(it) }, api::leaderboard, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(3, viewModel.page.value)
        assertEquals(51, (viewModel.board.value as LoadState.Loaded).value.leaderboard.entries.first().rank)
        assertEquals("Alpha Tune", (viewModel.song.value as LoadState.Loaded).value.title)
        viewModel.goTo(2)
        advanceUntilIdle()
        assertEquals(26, (viewModel.board.value as LoadState.Loaded).value.leaderboard.entries.first().rank)
        viewModel.goTo(-1)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        viewModel.retry()
        advanceUntilIdle()
        assertEquals(Instrument.Lead, viewModel.instrument)
    }

    // endregion

    // region Profile search

    @Test
    fun profileSearchDebouncesValidatesAndRetries() = runTest(main.dispatcher) {
        var fail = true
        var calls = 0
        val viewModel = ProfileSearchViewModel { query ->
            calls++
            if (fail) throw IOException("offline")
            listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Result for $query"))
        }
        advanceUntilIdle()
        assertEquals(ProfileSearchState.Hint, viewModel.state.value)
        viewModel.onQueryChange("s")
        advanceUntilIdle()
        assertEquals(ProfileSearchState.Hint, viewModel.state.value)
        viewModel.onQueryChange(" syn ")
        assertEquals(" syn ", viewModel.query.value)
        advanceUntilIdle()
        assertEquals(ProfileSearchState.Failed(ServiceIssue.Offline), viewModel.state.value)
        fail = false
        viewModel.retry()
        advanceUntilIdle()
        assertEquals(ProfileSearchState.Results(listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Result for syn"))), viewModel.state.value)
        assertEquals(2, calls)
    }

    // endregion

    // region Background

    @Test
    fun backgroundPolicyModes() {
        assertEquals(BackgroundMode.None, BackgroundPolicy.mode(false, false, dataSaver = true, visible = true))
        assertEquals(BackgroundMode.Still, BackgroundPolicy.mode(true, false, false, true))
        assertEquals(BackgroundMode.Still, BackgroundPolicy.mode(false, true, false, true))
        assertEquals(BackgroundMode.Still, BackgroundPolicy.mode(false, false, false, visible = false))
        assertEquals(BackgroundMode.Animated, BackgroundPolicy.mode(false, false, false, true))
        assertEquals(10, BackgroundPolicy.PRESETS.size)
        assertTrue(BackgroundPolicy.PRESETS.all { it.scale <= 1.18f && kotlin.math.abs(it.dx) <= 18f && kotlin.math.abs(it.dy) <= 18f })
        val many = (0 until 150).map { Fixtures.song("s$it", "T$it").copy(albumArt = "art$it.jpg") } + Fixtures.song("dup", "D").copy(albumArt = "art1.jpg")
        val covers = BackgroundPolicy.pickCovers(many, { it?.let { raw -> "https://cdn/$raw" } }, Random(1))
        assertEquals(100, covers.size)
        assertEquals(covers.size, covers.toSet().size)
    }

    @Test
    fun backgroundControllerLoadsOncePerPublicationAndStacksFocus() = runTest(main.dispatcher) {
        var publication = 7
        var fail = false
        val controller = BackgroundController(
            loadCatalog = {
                if (fail) throw IOException("offline")
                CatalogPayload(SongsResponse(1, null, listOf(Fixtures.song("a", "A").copy(albumArt = "a.jpg"))), publication)
            },
            artworkUrl = { raw -> raw?.let { "https://cdn/$it" } },
            random = Random(3),
        )
        controller.start(this)
        advanceUntilIdle()
        assertEquals(listOf("https://cdn/a.jpg"), controller.covers.value)
        val before = controller.covers.value
        controller.start(this)
        advanceUntilIdle()
        assertSame(before, controller.covers.value)
        publication = 8
        controller.start(this)
        advanceUntilIdle()
        fail = true
        controller.start(this)
        advanceUntilIdle()
        assertEquals(1, controller.covers.value.size)

        assertNull(controller.pushFocus(null))
        val first = controller.pushFocus("one.jpg")
        val second = controller.pushFocus("two.jpg")
        assertNotNull(first)
        assertEquals("https://cdn/two.jpg", controller.focus.value)
        controller.popFocus(second)
        assertEquals("https://cdn/one.jpg", controller.focus.value)
        controller.popFocus(null)
        controller.popFocus(first)
        assertNull(controller.focus.value)
    }

    // endregion
}
