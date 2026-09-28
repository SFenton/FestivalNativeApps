package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Tile actions (web `withProfileSwitch`) and top songs on the player page model. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileActionsTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val storeJob = Job()
    private val settings = MutableStateFlow<AppSettings?>(AppSettings())
    private val publications = MutableStateFlow<Int?>(7)
    private var header: Int? = 7
    private var catalogFailure: Exception? = null
    private var catalogReads = 0
    private var bandsFailure: Exception? = null
    private val bandReads = mutableListOf<String>()
    private val presets = mutableListOf<SongsPreset>()
    private val selected = mutableListOf<SelectedPlayer?>()

    @After
    fun tearDown() = storeJob.cancel()

    private val rows = listOf(
        ProfileFixtures.score("s-alpha", "01", fc = true, stars = 6, rank = 1, total = 200),
        ProfileFixtures.score("s-beta", "01", rank = 30, total = 200),
        ProfileFixtures.score("s-gamma", "02", rank = 9, total = 10),
    )

    private val reads = ProfileReads(
        profile = { account ->
            val profile = FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), ProfileFixtures.profile(account, rows = rows))
            PlayerProfilePayload(profile, PlayerProfileState.Available, header, 7)
        },
        ranking = { _, account ->
            PlayerInstrumentRankingPayload(FestivalApi.JSON.decodeFromString(PlayerInstrumentRanking.serializer(), ProfileFixtures.ranking(account)))
        },
        rankHistory = { instrument, account ->
            FestivalApi.JSON.decodeFromString(PlayerRankHistory.serializer(), ProfileFixtures.rankHistory(account, instrument.wireId))
        },
        catalog = {
            catalogReads++
            catalogFailure?.let { throw it }
            listOf(Song("s-alpha", "Alpha Song", "Alpha Artist", year = 2021, albumArt = "alpha.jpg"))
        },
        bands = { account ->
            bandReads += account
            bandsFailure?.let { throw it }
            PlayerBandListResponse(accountId = account, totalCount = 0)
        },
    )

    private fun viewModel(scope: CoroutineScope, accountId: String?): PlayerProfileViewModel {
        val store = SelectedProfileStore(reads.profile, publications, ServiceRetryBackoff())
        store.start(CoroutineScope(scope.coroutineContext + storeJob), settings.map { it?.selectedPlayer })
        return PlayerProfileViewModel(
            accountId = accountId,
            routeDisplayName = null,
            reads = reads,
            store = store,
            settings = settings,
            publications = publications,
            backoff = ServiceRetryBackoff(),
            onSelect = { player -> selected += player; settings.value = settings.value?.copy(selectedPlayer = player) },
            onDeselect = { selected += null; settings.value = settings.value?.copy(selectedPlayer = null) },
            saveSongsPreset = { presets += it },
            artworkUrl = { raw -> raw?.let { "https://art/$it" } },
        )
    }

    private val lead = SongsPreset.ForInstrument(SongScoreFilterKind.HasScores, Instrument.Lead)

    @Test
    fun tilesCarryTheWebActions() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val state = vm.state.value
        val visible = Instrument.entries.toSet()
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasScores, visible)), state.overview[0].action)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasFCs, visible)), state.overview[1].action)
        assertNull(state.overview[2].action)
        assertNull(state.overview[3].action)
        assertEquals(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), state.overview[4].action)
        val leadTiles = state.instruments.first { it.instrument == Instrument.Lead }.stats
        assertEquals(PlayerTileAction.FilterSongs(lead), leadTiles[0].action)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.ForInstrument(SongScoreFilterKind.HasFCs, Instrument.Lead)), leadTiles[1].action)
        // Avg Stars: a 6-star and a 5-star row average 5.5 (web formatClamped2).
        assertEquals(PlayerStatTile("Avg Stars", "5.5"), leadTiles[5])
        assertEquals(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), leadTiles[6].action)
        // Bass has no full combo, so its FC tile is flat (the web omits the card).
        val bassTiles = state.instruments.first { it.instrument == Instrument.Bass }.stats
        assertNull(bassTiles[1].action)
        vm.ensureInstrument(Instrument.Lead)
        advanceUntilIdle()
        val rank = vm.ranks.value[Instrument.Lead] as RankLoad.Available
        assertEquals(PlayerTileAction.OpenRankings(Instrument.Lead), rank.tiles[0].action)
    }

    @Test
    fun topSongsUseTheCatalogueAndFallBackWithoutIt() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val leadTop = vm.state.value.topSongs.first { it.instrument == Instrument.Lead }
        assertEquals(listOf("s-alpha", "s-beta"), leadTop.top.map { it.songId })
        assertEquals("Alpha Song", leadTop.top[0].title)
        assertEquals("https://art/alpha.jpg", leadTop.top[0].artUrl)
        assertEquals("s-beta", leadTop.top[1].title)
        assertTrue(vm.state.value.topSongs.first { it.instrument == Instrument.Drums }.isEmpty)
        assertEquals(Instrument.entries.size, vm.state.value.topSongs.size)
        // Hiding a chart drops its card; the catalogue is read once.
        settings.value = settings.value?.withInstrumentVisible(Instrument.Drums, false)
        advanceUntilIdle()
        assertFalse(vm.state.value.topSongs.any { it.instrument == Instrument.Drums })
        assertEquals(1, catalogReads)
    }

    @Test
    fun catalogueFailureKeepsSongIds() = runTest(main.dispatcher) {
        catalogFailure = IOException("offline")
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals("s-alpha", vm.state.value.topSongs.first { it.instrument == Instrument.Lead }.top[0].title)
    }

    @Test
    fun viewedPlayerIsSelectedBeforeNavigating() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertTrue(vm.state.value.canRun(PlayerTileAction.FilterSongs(lead)))
        val result = vm.run(PlayerTileAction.FilterSongs(lead))
        assertEquals(ProfileActionResult.Navigate(SongsTab), result)
        assertEquals(Fixtures.ACCOUNT_A, selected.single()?.accountId)
        assertEquals(listOf<SongsPreset>(lead), presets)
        advanceUntilIdle()
        // Now selected: later actions navigate without selecting again.
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertEquals(
            ProfileActionResult.Navigate(FullRankingsRoute("Solo_Bass", "totalscore")),
            vm.run(PlayerTileAction.OpenRankings(Instrument.Bass)),
        )
        assertEquals(1, selected.size)
    }

    @Test
    fun anotherSelectedPlayerNeedsConfirmation() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"))
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals(PlayerIdentityAction.Switch, vm.state.value.identity)
        assertEquals(ProfileActionResult.ConfirmSwitch, vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertTrue(selected.isEmpty())
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), confirmedSwitch = true))
        assertEquals(Fixtures.ACCOUNT_A, selected.single()?.accountId)
    }

    @Test
    fun pausedSelectionWithholdsOnlySongsFilters() = runTest(main.dispatcher) {
        header = null
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val state = vm.state.value
        assertEquals(PlayerIdentityAction.Unverified, state.identity)
        assertFalse(state.canRun(PlayerTileAction.FilterSongs(lead)))
        assertTrue(state.canRun(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertEquals(ProfileActionResult.Unavailable, vm.run(PlayerTileAction.FilterSongs(lead)))
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertTrue(selected.isEmpty())
        assertTrue(presets.isEmpty())
    }

    @Test
    fun failedSelectionDoesNotApplyTheFilter() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        // The publication advanced after the state was built but before the tap landed.
        publications.value = 8
        assertEquals(PlayerIdentityAction.Select, vm.state.value.identity)
        assertEquals(ProfileActionResult.Unavailable, vm.run(PlayerTileAction.FilterSongs(lead)))
        assertTrue(presets.isEmpty())
        assertTrue(selected.isEmpty())
    }

    @Test
    fun bandsPreviewLoadsOnceRetriesAndResetsPerAccount() = runTest(main.dispatcher) {
        val vm = viewModel(this, null)
        advanceUntilIdle()
        // Statistics with no selection reads nothing.
        vm.ensureBands()
        assertNull(vm.bands.value)
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        advanceUntilIdle()
        bandsFailure = IOException("offline")
        vm.ensureBands()
        advanceUntilIdle()
        assertTrue(vm.bands.value is BandsLoad.Failed)
        vm.ensureBands()
        advanceUntilIdle()
        assertEquals(1, bandReads.size)
        bandsFailure = null
        vm.retryBands()
        advanceUntilIdle()
        assertEquals(PlayerBandListResponse(accountId = Fixtures.ACCOUNT_A), (vm.bands.value as BandsLoad.Loaded).bands)
        // Another selected account resets the preview until its section is shown again.
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other"))
        advanceUntilIdle()
        assertNull(vm.bands.value)
        assertEquals(listOf(Fixtures.ACCOUNT_A, Fixtures.ACCOUNT_A), bandReads)
    }

    @Test
    fun statisticsRunsActionsWithoutSelecting() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val vm = viewModel(this, null)
        advanceUntilIdle()
        assertTrue(vm.state.value.isSelected)
        assertEquals(ProfileActionResult.Navigate(SongsTab), vm.run(PlayerTileAction.FilterSongs(lead)))
        assertTrue(selected.isEmpty())
        assertEquals(1, presets.size)
    }
}
