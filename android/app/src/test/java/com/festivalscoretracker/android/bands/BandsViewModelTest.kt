package com.festivalscoretracker.android.bands

import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.bands.bandProfile
import com.festivalscoretracker.android.data.bands.bandRankHistory
import com.festivalscoretracker.android.data.bands.bandSongExtremes
import com.festivalscoretracker.android.data.bands.playerBands
import com.festivalscoretracker.android.data.bands.songBandLeaderboard
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.BandDetailViewModel
import com.festivalscoretracker.android.presentation.bands.PlayerBandsViewModel
import com.festivalscoretracker.android.presentation.bands.SongBandLeaderboardViewModel
import com.festivalscoretracker.android.presentation.bands.loadClampedPage
import com.festivalscoretracker.android.presentation.valueOrNull
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BandsViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val transport = BandFixtures.install(FakeTransport.standard())
    private val api = FestivalApi("https://fixture.test", transport)
    private val backoff = ServiceRetryBackoff()

    private fun detailViewModel(type: String? = "Band_Duets", key: String? = BandFixtures.DUO_KEY) =
        BandDetailViewModel(type, key, api::bandProfile, api::bandRankHistory, api::bandSongExtremes, { api.catalog() }, backoff)

    // region Paging helper

    @Test
    fun clampedPageReloadsTheLastPageOnce() = runTest(main.dispatcher) {
        val requested = mutableListOf<Int>()
        var corrected: Int? = null
        val result = loadClampedPage(5, { page -> requested += page; page }, { 2 }) { corrected = it }
        assertEquals(2, result)
        assertEquals(listOf(5, 2), requested)
        assertEquals(2, corrected)
        assertEquals(1, loadClampedPage(1, { it }, { 3 }) { error("not corrected") })
    }

    // endregion

    // region Player bands

    @Test
    fun playerBandsPagesAndSwitchesGroups() = runTest(main.dispatcher) {
        val viewModel = PlayerBandsViewModel(BandFixtures.PLAYER, BandPaging.PAGE_SIZE, api::playerBands, backoff)
        assertTrue(viewModel.isValidAccount)
        advanceUntilIdle()
        assertEquals(25, viewModel.bands.value.valueOrNull!!.entries.size)
        viewModel.goTo(2)
        advanceUntilIdle()
        assertEquals(2, viewModel.page.value)
        assertEquals(5, viewModel.bands.value.valueOrNull!!.entries.size)
        viewModel.selectGroup(PlayerBandGroup.Trios)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertEquals(PlayerBandGroup.Trios, viewModel.group.value)
        assertEquals(2, viewModel.bands.value.valueOrNull!!.totalCount)
        val before = transport.requests.size
        viewModel.selectGroup(PlayerBandGroup.Trios)
        advanceUntilIdle()
        assertEquals(before, transport.requests.size)
        viewModel.goTo(9)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        viewModel.selectGroup(PlayerBandGroup.Duos)
        advanceUntilIdle()
        assertTrue(viewModel.bands.value.valueOrNull!!.entries.isEmpty())
        viewModel.goTo(0)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertTrue(transport.requests.last().url.contains("group=duos"))
    }

    @Test
    fun invalidAccountMakesNoRequest() = runTest(main.dispatcher) {
        val viewModel = PlayerBandsViewModel("not/valid", 25, api::playerBands, backoff)
        advanceUntilIdle()
        assertFalse(viewModel.isValidAccount)
        assertEquals(LoadState.Loading, viewModel.bands.value)
        assertTrue(transport.sent("/api/player/not/valid/bands").isEmpty())
    }

    @Test
    fun playerBandsFailureAndRetry() = runTest(main.dispatcher) {
        var fail = true
        val viewModel = PlayerBandsViewModel(BandFixtures.PLAYER, 25, { a, g, p, s -> if (fail) throw FestivalApiException.HttpStatus(500) else api.playerBands(a, g, p, s) }, backoff)
        advanceUntilIdle()
        assertTrue(viewModel.bands.value is LoadState.Failed)
        fail = false
        viewModel.retry()
        advanceUntilIdle()
        assertEquals(30, viewModel.bands.value.valueOrNull!!.totalCount)
    }

    @Test
    fun lateResponseForAnOldGroupIsDiscarded() = runTest(main.dispatcher) {
        val gate = CompletableDeferred<Unit>()
        val viewModel = PlayerBandsViewModel(BandFixtures.PLAYER, 25, { a, g, p, s ->
            if (g == PlayerBandGroup.All) gate.await()
            api.playerBands(a, g, p, s)
        }, backoff)
        viewModel.selectGroup(PlayerBandGroup.Quads)
        advanceUntilIdle()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(2, viewModel.bands.value.valueOrNull!!.totalCount)
    }

    // endregion

    // region Band detail

    @Test
    fun unresolvableRouteMakesNoRequest() = runTest(main.dispatcher) {
        listOf(detailViewModel(null, BandFixtures.DUO_KEY), detailViewModel("Band_Duets", null), detailViewModel("Band_X", "a"), detailViewModel("Band_Duets", "../x")).forEach {
            assertFalse(it.isResolvable)
            assertNull(it.bandType)
        }
        advanceUntilIdle()
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun detailLoadsThenHistoryAndSongsWithCatalogueTitles() = runTest(main.dispatcher) {
        val viewModel = detailViewModel()
        assertTrue(viewModel.isResolvable)
        assertEquals(BandType.Duets, viewModel.bandType)
        advanceUntilIdle()
        assertEquals(BandFixtures.DUO_ID, viewModel.detail.value.valueOrNull!!.bandId)
        assertEquals(4, viewModel.history.value.valueOrNull!!.history.size)
        val songs = viewModel.songs.value.valueOrNull!!
        assertEquals("Alpha Tune", songs.songsById["s-alpha"]!!.title)
        assertNull(songs.songsById["s-missing"])
        assertEquals(BandRankingMetric.TotalScore, viewModel.metric.value)
        val count = transport.requests.size
        viewModel.selectMetric(BandRankingMetric.FcRate)
        assertEquals(BandRankingMetric.FcRate, viewModel.metric.value)
        assertEquals(count, transport.requests.size)
        viewModel.retryHistory()
        viewModel.retrySongs()
        advanceUntilIdle()
        assertTrue(viewModel.history.value is LoadState.Loaded)
        assertTrue(viewModel.songs.value is LoadState.Loaded)
    }

    @Test
    fun unrankedTeamIsNotFoundAndSkipsSections() = runTest(main.dispatcher) {
        val viewModel = detailViewModel(key = "${BandFixtures.DUO_KEY}x")
        advanceUntilIdle()
        assertEquals(ServiceIssue.NotFound, (viewModel.detail.value as LoadState.Failed).issue)
        assertEquals(LoadState.Loading, viewModel.history.value)
        assertTrue(transport.requests.none { "/history" in it.url || "/songs" in it.url })
        viewModel.retry()
        advanceUntilIdle()
        assertTrue(viewModel.detail.value is LoadState.Failed)
    }

    @Test
    fun catalogueFailureFallsBackToUnknownSongs() = runTest(main.dispatcher) {
        transport.on("/api/songs", status = 500) { "{}" }
        val viewModel = detailViewModel()
        advanceUntilIdle()
        assertTrue(viewModel.songs.value.valueOrNull!!.songsById.isEmpty())
    }

    // endregion

    // region Song band leaderboard

    @Test
    fun songBoardSwitchesSizeAndPages() = runTest(main.dispatcher) {
        val viewModel = SongBandLeaderboardViewModel("s-alpha", BandType.Duets, { api.catalog(it) }, api::songBandLeaderboard, backoff)
        advanceUntilIdle()
        assertEquals("Alpha Tune", viewModel.song.value.valueOrNull!!.title)
        assertEquals(25, viewModel.board.value.valueOrNull!!.entries.size)
        viewModel.goTo(2)
        advanceUntilIdle()
        assertEquals(26, viewModel.board.value.valueOrNull!!.entries.first().rank)
        viewModel.selectBandType(BandType.Quad)
        advanceUntilIdle()
        assertEquals(1, viewModel.page.value)
        assertEquals(BandType.Quad, viewModel.bandType.value)
        assertTrue(viewModel.board.value.valueOrNull!!.entries.isEmpty())
        val count = transport.requests.size
        viewModel.selectBandType(BandType.Quad)
        assertEquals(count, transport.requests.size)
        viewModel.selectBandType(BandType.Trios)
        viewModel.goTo(7)
        advanceUntilIdle()
        assertEquals(2, viewModel.page.value)
        viewModel.retry()
        viewModel.retrySong()
        advanceUntilIdle()
        assertTrue(viewModel.board.value is LoadState.Loaded)
    }

    // endregion
}
