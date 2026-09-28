package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.profile.PlayerHistoryResponse
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.profile.PlayerScoreSortMode
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.presentation.ProfileSearchScope
import com.festivalscoretracker.android.presentation.ProfileSearchState
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.time.ZoneOffset
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileViewModelsTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val storeJob = Job()
    private val playerA = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val playerB = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player")
    private val settings = MutableStateFlow<AppSettings?>(AppSettings())
    private val publications = MutableStateFlow<Int?>(7)
    private val profileReads = mutableListOf<String>()
    private var header: Int? = 7
    private var profileFailure: Exception? = null
    private var syncing = false
    private var rankFailure: Exception? = null
    private var rankMissing = false
    private var historyFailure: Exception? = null
    private val selected = mutableListOf<SelectedPlayer?>()

    @After
    fun tearDown() = storeJob.cancel()

    private fun payload(account: String): PlayerProfilePayload {
        val json = if (syncing) ProfileFixtures.syncing(account) else ProfileFixtures.profile(account)
        val profile = FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), json)
        return PlayerProfilePayload(profile, if (syncing) PlayerProfileState.Syncing else PlayerProfileState.Available, header, 7)
    }

    private val reads = ProfileReads(
        profile = { account ->
            profileReads += account
            profileFailure?.let { throw it }
            payload(account)
        },
        ranking = { _, account ->
            rankFailure?.let { throw it }
            PlayerInstrumentRankingPayload(
                if (rankMissing) null else FestivalApi.JSON.decodeFromString(PlayerInstrumentRanking.serializer(), ProfileFixtures.ranking(account, rank = 8, total = 500)),
            )
        },
        rankHistory = { instrument, account ->
            historyFailure?.let { throw it }
            FestivalApi.JSON.decodeFromString(PlayerRankHistory.serializer(), ProfileFixtures.rankHistory(account, instrument.wireId))
        },
    )

    private fun store(scope: CoroutineScope): SelectedProfileStore =
        SelectedProfileStore(reads.profile, publications, ServiceRetryBackoff()).also { store ->
            store.start(CoroutineScope(scope.coroutineContext + storeJob), settings.map { it?.selectedPlayer })
        }

    private fun viewModel(store: SelectedProfileStore, accountId: String?) = PlayerProfileViewModel(
        accountId = accountId,
        routeDisplayName = "Route Name",
        reads = reads,
        store = store,
        settings = settings,
        publications = publications,
        backoff = ServiceRetryBackoff(),
        onSelect = { player -> selected += player; settings.value = settings.value?.copy(selectedPlayer = player) },
        onDeselect = { selected += null; settings.value = settings.value?.copy(selectedPlayer = null) },
    )

    // region Player profile

    @Test
    fun viewedProfileSelectsAndDeselectsWithoutNavigatingOrRereading() = runTest(main.dispatcher) {
        val store = store(this)
        val vm = viewModel(store, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        var state = vm.state.value
        assertEquals(ProfilePhase.Loaded, state.phase)
        assertEquals("Synthetic Player", state.displayName)
        assertEquals(PlayerIdentityAction.Select, state.identity)
        assertEquals("Select Profile", state.selectLabel)
        assertEquals(listOf("Songs Played", "Full Combos", "Gold Stars", "Avg Accuracy", "Best Rank"), state.overview.map { it.label })
        assertEquals("3", state.overview.first().value)
        assertEquals(Instrument.entries.size, state.instruments.size)
        assertTrue(state.instruments.first { it.instrument == Instrument.Lead }.hasScores)
        assertFalse(state.instruments.first { it.instrument == Instrument.Drums }.hasScores)

        vm.ensureInstrument(Instrument.Lead)
        vm.ensureInstrument(Instrument.Drums)
        advanceUntilIdle()
        val rank = vm.ranks.value[Instrument.Lead] as RankLoad.Available
        assertEquals("#8", rank.tiles.first().value)
        assertTrue(rank.tiles.last().gold)
        assertNotNull((vm.rankHistories.value[Instrument.Lead] as RankHistoryLoad.Loaded).chart)
        assertNull(vm.ranks.value[Instrument.Drums])

        vm.select()
        advanceUntilIdle()
        assertEquals(listOf<SelectedPlayer?>(playerA), selected)
        state = vm.state.value
        assertTrue(state.isSelected)
        assertEquals(PlayerIdentityAction.Deselect, state.identity)
        assertEquals(SelectedProfileStatus.Available, store.state.value.status)
        assertEquals(1, profileReads.size)

        vm.deselect()
        advanceUntilIdle()
        assertEquals(null, selected.last())
        assertEquals(PlayerIdentityAction.Select, vm.state.value.identity)
        assertEquals(ProfilePhase.Loaded, vm.state.value.phase)
        assertEquals(1, profileReads.size)
    }

    @Test
    fun switchUnverifiedAndChangedReadsGateSelection() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = playerB)
        val store = store(this)
        val vm = viewModel(store, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals(PlayerIdentityAction.Switch, vm.state.value.identity)
        assertEquals("Switch to This Profile", vm.state.value.selectLabel)
        publications.value = 8
        advanceUntilIdle()
        assertEquals(PlayerIdentityAction.Changed, vm.state.value.identity)
        assertNotNull(vm.state.value.identityNotice)
        vm.select()
        assertTrue(selected.isEmpty())
        vm.deselect()
        assertTrue(selected.isEmpty())

        header = null
        publications.value = 7
        vm.retry()
        advanceUntilIdle()
        assertEquals(PlayerIdentityAction.Unverified, vm.state.value.identity)
        assertTrue(vm.state.value.identityNotice!!.contains("paused"))
    }

    @Test
    fun statisticsFollowsTheSelectionAndResetsPerAccount() = runTest(main.dispatcher) {
        val store = store(this)
        val vm = viewModel(store, null)
        advanceUntilIdle()
        assertTrue(vm.followsSelection)
        assertEquals(ProfilePhase.NoAccount, vm.state.value.phase)
        settings.value = AppSettings(selectedPlayer = playerA)
        advanceUntilIdle()
        assertEquals(ProfilePhase.Loaded, vm.state.value.phase)
        assertTrue(vm.state.value.isSelected)
        vm.ensureInstrument(Instrument.Lead)
        advanceUntilIdle()
        assertNotNull(vm.ranks.value[Instrument.Lead])

        settings.value = AppSettings(selectedPlayer = playerB)
        advanceUntilIdle()
        assertEquals(Fixtures.ACCOUNT_B, vm.state.value.accountId)
        assertTrue(vm.ranks.value.isEmpty())
        assertEquals(listOf(Fixtures.ACCOUNT_A, Fixtures.ACCOUNT_B), profileReads)

        settings.value = AppSettings(selectedPlayer = playerB, visibleInstruments = setOf(Instrument.Bass))
        advanceUntilIdle()
        assertEquals(listOf(Instrument.Bass), vm.state.value.instruments.map { it.instrument })

        profileFailure = FestivalApiException.HttpStatus(403)
        vm.retry()
        advanceUntilIdle()
        assertTrue(vm.state.value.phase is ProfilePhase.Failed)
        profileFailure = null
        vm.retry()
        advanceUntilIdle()
        assertEquals(ProfilePhase.Loaded, vm.state.value.phase)
    }

    @Test
    fun failuresSyncingAndSectionRetries() = runTest(main.dispatcher) {
        val store = store(this)
        profileFailure = FestivalApiException.PublicReadFrozen("scrape", "1")
        val vm = viewModel(store, Fixtures.ACCOUNT_A)
        advanceTimeBy(100)
        val frozen = vm.state.value.phase as ProfilePhase.Failed
        assertTrue(frozen.issue is ServiceIssue.ScrapeInProgress)
        assertNotNull(frozen.countdown)
        profileFailure = null
        syncing = true
        advanceTimeBy(120_000)
        advanceUntilIdle()
        assertEquals(ProfilePhase.Syncing, vm.state.value.phase)
        assertEquals(PlayerIdentityAction.None, vm.state.value.identity)

        syncing = false
        vm.retry()
        advanceUntilIdle()
        rankMissing = true
        historyFailure = FestivalApiException.HttpStatus(500)
        vm.ensureInstrument(Instrument.Lead)
        advanceUntilIdle()
        assertEquals(RankLoad.Unranked, vm.ranks.value[Instrument.Lead])
        assertTrue(vm.rankHistories.value[Instrument.Lead] is RankHistoryLoad.Failed)
        rankMissing = false
        rankFailure = FestivalApiException.HttpStatus(500)
        vm.retryRank(Instrument.Lead)
        advanceUntilIdle()
        assertTrue(vm.ranks.value[Instrument.Lead] is RankLoad.Failed)
        historyFailure = null
        vm.retryRankHistory(Instrument.Lead)
        advanceUntilIdle()
        assertTrue(vm.rankHistories.value[Instrument.Lead] is RankHistoryLoad.Loaded)
        assertEquals("Lead: x", PlayerStatTile("Lead", "x").announcement)
    }

    // endregion

    // region Score history

    private fun historyViewModel(respond: suspend (String) -> PlayerHistoryPayload, calls: MutableList<String>) = PlayerHistoryViewModel(
        songId = "s-alpha",
        instrument = Instrument.Lead,
        read = { account, _, _ -> calls += account; respond(account) },
        findSong = { id -> Fixtures.song(id, "Alpha Tune") },
        settings = settings,
        backoff = ServiceRetryBackoff(),
        zone = ZoneOffset.UTC,
        locale = Locale.US,
    )

    private fun history(account: String) = PlayerHistoryPayload(
        FestivalApi.JSON.decodeFromString(PlayerHistoryResponse.serializer(), ProfileFixtures.history(account)),
        PlayerHistoryState.Available,
    )

    @Test
    fun historyStatesSortAndPerAccountReset() = runTest(main.dispatcher) {
        val calls = mutableListOf<String>()
        var respond: suspend (String) -> PlayerHistoryPayload = { history(it) }
        val vm = historyViewModel({ respond(it) }, calls)
        advanceUntilIdle()
        assertEquals(HistoryPhase.NoPlayer, vm.state.value.phase)
        assertTrue(calls.isEmpty())
        assertEquals("Alpha Tune", vm.state.value.songTitle)

        settings.value = AppSettings(selectedPlayer = playerA)
        advanceUntilIdle()
        var state = vm.state.value
        assertEquals(HistoryPhase.Loaded, state.phase)
        assertEquals(2, state.rows.size)
        assertTrue(state.rows.first().isHighScore)
        assertEquals("Jan 5, 2024", state.rows.first().date)
        assertEquals("850,000", state.rows.first().score)
        assertEquals("99.1%", state.rows.first().accuracy)
        assertEquals("Season 40", state.rows.first().season)
        assertTrue(state.rows.first().announcement.contains("personal best"))
        assertNotNull(state.chart)

        vm.sortBy(PlayerScoreSortMode.Date)
        vm.setAscending(true)
        state = vm.state.value
        assertEquals(700_000L, state.rows.first().entry.newScore)
        assertTrue(state.rows.last().isHighScore)
        vm.resetSort()
        assertEquals(PlayerScoreSortMode.Score, vm.state.value.sortMode)
        assertFalse(vm.state.value.ascending)

        respond = { PlayerHistoryPayload(PlayerHistoryResponse(accountId = it), PlayerHistoryState.Unregistered) }
        settings.value = AppSettings(selectedPlayer = playerB)
        advanceUntilIdle()
        assertEquals(HistoryPhase.Unregistered, vm.state.value.phase)
        assertEquals(listOf(Fixtures.ACCOUNT_A, Fixtures.ACCOUNT_B), calls)

        respond = { PlayerHistoryPayload(PlayerHistoryResponse(accountId = it), PlayerHistoryState.Syncing) }
        vm.retry()
        advanceUntilIdle()
        assertEquals(HistoryPhase.Syncing, vm.state.value.phase)
        respond = { PlayerHistoryPayload(PlayerHistoryResponse(accountId = it), PlayerHistoryState.Available) }
        vm.retry()
        advanceUntilIdle()
        assertEquals(HistoryPhase.Empty, vm.state.value.phase)
        respond = { throw FestivalApiException.HttpStatus(500) }
        vm.retry()
        advanceUntilIdle()
        assertTrue(vm.state.value.phase is HistoryPhase.Failed)
        var attempts = 0
        respond = { attempts++; if (attempts == 1) throw FestivalApiException.PublicReadFrozen("publish", "1") else history(it) }
        vm.retry()
        advanceTimeBy(100)
        assertNotNull((vm.state.value.phase as HistoryPhase.Failed).countdown)
        advanceTimeBy(120_000)
        advanceUntilIdle()
        assertEquals(HistoryPhase.Loaded, vm.state.value.phase)

        settings.value = AppSettings(selectedPlayer = null)
        advanceUntilIdle()
        assertEquals(HistoryPhase.NoPlayer, vm.state.value.phase)
    }

    // endregion

    // region Search scope

    @Test
    fun bandScopeNeverSearches() = runTest(main.dispatcher) {
        var calls = 0
        val vm = ProfileSearchViewModel { calls++; listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "x")) }
        vm.setScope(ProfileSearchScope.Bands)
        vm.onQueryChange("band name")
        advanceUntilIdle()
        assertEquals(ProfileSearchState.BandsUnavailable, vm.state.value)
        assertEquals(ProfileSearchScope.Bands, vm.scope.value)
        assertEquals(0, calls)
        assertEquals("Find Band", ProfileSearchScope.Bands.placeholder)
        vm.setScope(ProfileSearchScope.Players)
        advanceUntilIdle()
        assertTrue(vm.state.value is ProfileSearchState.Results)
        assertEquals(1, calls)
    }

    // endregion
}
