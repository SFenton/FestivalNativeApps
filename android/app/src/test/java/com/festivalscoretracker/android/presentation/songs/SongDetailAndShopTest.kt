package com.festivalscoretracker.android.presentation.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.songs.SongScoreDetail
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.paths.SongPathDataPayload
import com.festivalscoretracker.android.data.paths.SongPathImagePayload
import com.festivalscoretracker.android.data.songs.leaderboardPage
import com.festivalscoretracker.android.data.songs.leewayParameter
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.presentation.profile.SelectedProfileStatus
import com.festivalscoretracker.android.presentation.shop.ShopViewModel
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.songdetail.songDetailExtras
import java.util.Locale
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SongDetailAndShopTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val song = Fixtures.song("a", "Alpha")
    private val payload = CatalogPayload(SongsResponse(1, 15, listOf(song)), 7)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    // region Shop page

    @Test
    fun shopPageMatchesCatalogueAndKeepsOffersWhenCatalogueFails() = runTest(main.dispatcher) {
        val shop = MutableStateFlow<LoadState<ShopPayload>>(LoadState.Loading)
        val settings = MutableStateFlow<AppSettings?>(AppSettings())
        var fail = false
        val vm = ShopViewModel(shop, { if (fail) throw FestivalApiException.HttpStatus(500) else payload }, settings, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(LoadState.Loading, vm.uiState.value.shop)
        shop.value = LoadState.Loaded(SongsFixtures.shop(SongsFixtures.offer("a", isNew = true), SongsFixtures.offer("z", leaving = true)))
        advanceUntilIdle()
        val offers = vm.uiState.value.offers
        assertEquals(listOf("a", "z"), offers.map { it.offer.songId })
        assertEquals("a", offers[0].detailSongId)
        assertNull(offers[1].detailSongId)
        assertEquals(ShopHighlight.New, offers[0].highlight)
        assertEquals("Title z, Artist z · 2020, Leaving Tomorrow", offers[1].announcement)
        assertTrue(offers.all { it.officialUrl != null })
        assertFalse(vm.uiState.value.detailsUnavailable)

        settings.value = AppSettings(disableShopHighlighting = true)
        advanceUntilIdle()
        assertTrue(vm.uiState.value.offers.all { it.highlight == null })
        settings.value = AppSettings(hideShop = true)
        advanceUntilIdle()
        assertTrue(vm.uiState.value.hidden)

        fail = true
        vm.retryCatalog()
        advanceUntilIdle()
        assertTrue(vm.uiState.value.detailsUnavailable)
        assertEquals(2, vm.uiState.value.offers.size)
        assertNull(vm.uiState.value.offers[0].detailSongId)
    }

    // endregion

    // region Paths

    private fun image() = SongPathImagePayload(SongsFixtures.png(), 100, 200, 7, 7)

    private fun text(): SongPathDataPayload {
        val path = FestivalApi.JSON.decodeFromString(com.festivalscoretracker.android.core.paths.SongPathData.serializer(), SongsFixtures.pathJson)
        return SongPathDataPayload(path, path.activationRows(), 7, 7)
    }

    @Test
    fun pathsSelectionReloadsAndIgnoresStaleReplies() = runTest(main.dispatcher) {
        val calls = mutableListOf<String>()
        val gate = CompletableDeferred<Unit>()
        val vm = SongPathsViewModel(
            instruments = listOf(Instrument.Lead, Instrument.Bass),
            defaultDisplay = PathDisplayMode.Image,
            loadImage = { chart, difficulty ->
                calls += "image:${chart.name}:${difficulty.name}"
                if (chart == Instrument.Bass && difficulty == PathDifficulty.Expert) gate.await()
                if (difficulty == PathDifficulty.Easy) throw FestivalApiException.HttpStatus(404)
                if (difficulty == PathDifficulty.Medium) throw FestivalApiException.HttpStatus(500)
                image()
            },
            loadText = { chart, difficulty -> calls += "text:${chart.name}:${difficulty.name}"; text() },
        )
        advanceUntilIdle()
        assertTrue(vm.state.value.load is PathLoad.Image)
        assertEquals(Instrument.Lead, vm.state.value.instrument)
        assertEquals(PathDifficulty.Expert, vm.state.value.difficulty)

        vm.selectInstrument(Instrument.Bass)
        advanceUntilIdle()
        assertEquals(PathLoad.Loading, vm.state.value.load)
        vm.selectDifficulty(PathDifficulty.Hard)
        advanceUntilIdle()
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(vm.state.value.load is PathLoad.Image)
        assertEquals(PathDifficulty.Hard, vm.state.value.difficulty)

        vm.selectDifficulty(PathDifficulty.Easy)
        advanceUntilIdle()
        assertEquals(PathLoad.NotGenerated, vm.state.value.load)
        vm.selectDifficulty(PathDifficulty.Medium)
        advanceUntilIdle()
        assertTrue(vm.state.value.load is PathLoad.Failed)
        vm.selectDisplay(PathDisplayMode.Text)
        advanceUntilIdle()
        assertEquals(3, (vm.state.value.load as PathLoad.Text).data.rows.size)
        vm.retry()
        advanceUntilIdle()
        // No-op selections do not reload.
        val before = calls.size
        vm.selectDisplay(PathDisplayMode.Text)
        vm.selectDifficulty(PathDifficulty.Medium)
        vm.selectInstrument(Instrument.Bass)
        vm.selectInstrument(Instrument.Drums)
        advanceUntilIdle()
        assertEquals(before, calls.size)
        assertEquals("text:Bass:Medium", calls.last())
    }

    @Test
    fun pathsNetworkFailureIsClassified() = runTest(main.dispatcher) {
        val vm = SongPathsViewModel(listOf(Instrument.Lead), PathDisplayMode.Text, { _, _ -> image() }, { _, _ -> throw FestivalApiException.InvalidResponse() })
        advanceUntilIdle()
        assertTrue((vm.state.value.load as PathLoad.Failed).issue is ServiceIssue.Other)
    }

    // endregion

    // region Summaries and extras

    @Test
    fun yourScoreSummaryCoversEveryState() {
        val detail = SongScoreDetail(95_198, accuracy = 987_000.0, isFullCombo = true, rank = 42, totalEntries = 1000)
        val live = SongScoreSource(true, detail = { _, chart -> if (chart == Instrument.Lead) detail else null })
        assertNull(SongDetailSummary.summary(SongScoreSource.NONE, "P", song, Instrument.Lead))
        assertEquals("Scores syncing", SongDetailSummary.summary(SongScoreSource.SYNCING, "P", song, Instrument.Lead)!!.text)
        val scored = SongDetailSummary.summary(live, "P", song, Instrument.Lead, Locale.US)!!
        assertEquals("Your score: 95,198 · 98.7% · FC · Top 5% · #42", scored.text)
        assertTrue(scored.scored)
        assertEquals(42, scored.rank)
        assertEquals("No Bass score for P", SongDetailSummary.summary(live, "P", song, Instrument.Bass)!!.text)
        assertEquals("Karaoke is not charted for this song", SongDetailSummary.summary(live, "P", song, Instrument.Karaoke)!!.text)
        assertEquals("Loading scores", SongDetailSummary.summary(SongScoreSource(true), "P", song, Instrument.Lead)!!.text)
        val bare = SongScoreSource(true, detail = { _, _ -> SongScoreDetail(10) })
        assertEquals("Your score: 10", SongDetailSummary.summary(bare, "P", song, Instrument.Lead, Locale.US)!!.text)
    }

    @Test
    fun detailExtrasUseSamePublicationShopAndScores() {
        val profile = SongsFixtures.profile(SongsFixtures.score("a", Instrument.Lead, 500, fc = false))
        val state = SelectedProfileState(player, SelectedProfileStatus.Available, profile, scoreIndex = profile.profile.scoreIndex())
        val shop = LoadState.Loaded(SongsFixtures.shop(SongsFixtures.offer("a", leaving = true)))
        val settings = AppSettings(selectedPlayer = player, visibleInstruments = setOf(Instrument.Lead, Instrument.Karaoke, Instrument.Bass))
        val extras = songDetailExtras(song, settings, shop, state, 7, 7)
        assertEquals(ShopHighlight.LeavingTomorrow, extras.shopHighlight)
        assertEquals(SongsFixtures.shopUrl("slug-a"), extras.shopUrl)
        assertFalse(extras.shopError)
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), extras.pathInstruments)
        assertTrue(extras.summaries.getValue(Instrument.Lead).scored)
        assertEquals(Fixtures.ACCOUNT_A, extras.selectedAccountId)

        val mismatch = songDetailExtras(song, settings, shop, state, 6, 7)
        assertNull(mismatch.shopUrl)
        assertEquals("Player scores paused until songs update", mismatch.summaries.getValue(Instrument.Lead).text)
        val hidden = songDetailExtras(song, settings.copy(hideShop = true), LoadState.Failed(ServiceIssue.NotFound), state, 7, 7)
        assertNull(hidden.shopUrl)
        assertFalse(hidden.shopError)
        val failed = songDetailExtras(song, AppSettings(), LoadState.Failed(ServiceIssue.NotFound), SelectedProfileState(), 7, 7)
        assertTrue(failed.shopError)
        assertTrue(failed.summaries.isEmpty())
        assertNull(failed.selectedAccountId)
    }

    // endregion

    // region Leeway previews

    @Test
    fun leewayPreviewsSendLeewayAndReReadWhenItChanges() = runTest(main.dispatcher) {
        val transport = FakeTransport.standard()
        val api = FestivalApi("https://fixture.test", transport)
        var leeway: Double? = null
        val vm = SongDetailViewModel("s-alpha", { api.catalog(it) }, { id, chart, page, top, l -> api.leaderboardPage(id, chart, page, top, l) }, ServiceRetryBackoff(), { leeway })
        advanceUntilIdle()
        assertEquals(7, vm.catalogPublication.value)
        val alpha = (vm.song.value as LoadState.Loaded).value
        vm.preview(alpha, Instrument.Lead)
        advanceUntilIdle()
        leeway = 1.25
        val filtered = vm.preview(alpha, Instrument.Lead)
        advanceUntilIdle()
        assertTrue(filtered.value is LoadState.Loaded)
        val urls = transport.sent("/api/leaderboard/s-alpha/Solo_Guitar").map { it.url }
        assertFalse(urls.first().contains("leeway"))
        assertTrue(urls.last().contains("leeway=1.3") || urls.last().contains("leeway=1.2"))
        assertEquals("-5.0", leewayParameter(-9.0))
        assertEquals("0.5", leewayParameter(0.5))
    }

    // endregion
}
