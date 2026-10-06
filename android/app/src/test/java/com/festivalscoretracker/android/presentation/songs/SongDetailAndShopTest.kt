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
import com.festivalscoretracker.android.core.shop.ShopOfferFilter
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
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

    @Test
    fun shopFilterSelectsDisjointGroupsAndResetRestoresEveryOffer() = runTest(main.dispatcher) {
        val shop = MutableStateFlow<LoadState<ShopPayload>>(LoadState.Loading)
        val settings = MutableStateFlow<AppSettings?>(AppSettings())
        val vm = ShopViewModel(shop, { payload }, settings, ServiceRetryBackoff())
        shop.value = LoadState.Loaded(
            SongsFixtures.shop(
                SongsFixtures.offer("a", isNew = true),
                SongsFixtures.offer("b"),
                SongsFixtures.offer("c", leaving = true),
                SongsFixtures.offer("d"),
            ),
        )
        advanceUntilIdle()
        fun ids() = vm.uiState.value.offers.map { it.offer.songId }
        assertEquals(listOf("a", "b", "c", "d"), ids())
        assertFalse(vm.uiState.value.filter.isActive)

        vm.setFilter(ShopOfferFilter(new = true))
        advanceUntilIdle()
        assertEquals(listOf("a"), ids())
        assertTrue(vm.uiState.value.filter.isActive)
        vm.setFilter(ShopOfferFilter(available = true))
        advanceUntilIdle()
        assertEquals(listOf("b", "d"), ids())
        vm.setFilter(ShopOfferFilter(leavingTomorrow = true))
        advanceUntilIdle()
        assertEquals(listOf("c"), ids())
        vm.setFilter(ShopOfferFilter(new = true, leavingTomorrow = true))
        advanceUntilIdle()
        assertEquals(listOf("a", "c"), ids())
        assertEquals(4, vm.uiState.value.totalOffers)

        // Filters use the wire flags, so they keep working while Shop highlighting is off.
        settings.value = AppSettings(disableShopHighlighting = true)
        advanceUntilIdle()
        assertEquals(listOf("a", "c"), ids())

        vm.resetFilter()
        advanceUntilIdle()
        assertEquals(listOf("a", "b", "c", "d"), ids())
        assertFalse(vm.uiState.value.filter.isActive)
    }

    @Test
    fun shopFilterThatHidesEveryOfferIsNotTheEmptyShop() = runTest(main.dispatcher) {
        val shop = MutableStateFlow<LoadState<ShopPayload>>(LoadState.Loaded(SongsFixtures.shop(SongsFixtures.offer("b"))))
        val vm = ShopViewModel(shop, { payload }, MutableStateFlow<AppSettings?>(AppSettings()), ServiceRetryBackoff())
        advanceUntilIdle()
        vm.setFilter(ShopOfferFilter(new = true))
        advanceUntilIdle()
        assertTrue(vm.uiState.value.offers.isEmpty())
        assertTrue(vm.uiState.value.filteredEmpty)

        shop.value = LoadState.Loaded(SongsFixtures.shop())
        advanceUntilIdle()
        assertFalse(vm.uiState.value.filteredEmpty)
        assertEquals(0, vm.uiState.value.totalOffers)
        // The filter survives a feed change (the sheet reopens with it).
        assertEquals(ShopOfferFilter(new = true), vm.uiState.value.filter)
    }

    @Test
    fun shopOfferFilterMatchesAnySelectedGroup() {
        val fresh = SongsFixtures.offer("n", isNew = true)
        val plain = SongsFixtures.offer("p")
        val leaving = SongsFixtures.offer("l", leaving = true)
        val both = SongsFixtures.offer("b", isNew = true, leaving = true)
        val all = listOf(fresh, plain, leaving, both)
        assertEquals(all, ShopOfferFilter().apply(all))
        assertEquals(listOf(fresh, both), ShopOfferFilter(new = true).apply(all))
        assertEquals(listOf(plain), ShopOfferFilter(available = true).apply(all))
        assertEquals(listOf(leaving, both), ShopOfferFilter(leavingTomorrow = true).apply(all))
        assertEquals(all, ShopOfferFilter(new = true, available = true, leavingTomorrow = true).apply(all))
        assertFalse(ShopOfferFilter(available = true).matches(both))
    }

    @Test
    fun shopOfferFilterDescribesItsStateForTalkBack() {
        assertEquals("No filters", ShopOfferFilter().stateDescription)
        assertEquals("Filters on: Leaving Tomorrow", ShopOfferFilter(leavingTomorrow = true).stateDescription)
        assertEquals("Filters on: New, Available", ShopOfferFilter(new = true, available = true).stateDescription)
        assertEquals("Filters on: New, Available, Leaving Tomorrow", ShopOfferFilter(true, true, true).stateDescription)
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

    /** Issue #164: the view model outlives the sheet, so each new opening restarts at Settings' default. */
    @Test
    fun pathsNewOpeningResetsToTheSavedDefault() = runTest(main.dispatcher) {
        val calls = mutableListOf<String>()
        val vm = SongPathsViewModel(
            listOf(Instrument.Lead, Instrument.Bass),
            PathDisplayMode.Image,
            { chart, difficulty -> calls += "image:${chart.name}:${difficulty.name}"; image() },
            { chart, difficulty -> calls += "text:${chart.name}:${difficulty.name}"; text() },
        )
        vm.reduceMotion = true
        vm.beginOpening(1, PathDisplayMode.Image)
        advanceUntilIdle()
        assertEquals(listOf("image:Lead:Expert"), calls)

        vm.selectInstrument(Instrument.Bass)
        vm.selectDifficulty(PathDifficulty.Hard)
        advanceUntilIdle()
        // Recomposition or rotation repeats the same opening: the selection stays.
        vm.beginOpening(1, PathDisplayMode.Text)
        advanceUntilIdle()
        assertEquals(Instrument.Bass, vm.state.value.instrument)
        assertEquals(PathDisplayMode.Image, vm.state.value.display)
        assertEquals("image:Bass:Hard", calls.last())

        // Reopened after Settings changed to Text: first chart, Expert, text table.
        vm.beginOpening(2, PathDisplayMode.Text)
        assertEquals(PathLoad.Loading, vm.state.value.load)
        advanceUntilIdle()
        assertEquals(PathSelection(Instrument.Lead, PathDifficulty.Expert, PathDisplayMode.Text), vm.state.value.selection)
        assertEquals(3, (vm.state.value.load as PathLoad.Text).data.rows.size)
        assertEquals("text:Lead:Expert", calls.last())
    }

    @Test
    fun pathsNetworkFailureIsClassified() = runTest(main.dispatcher) {
        val vm = SongPathsViewModel(listOf(Instrument.Lead), PathDisplayMode.Text, { _, _ -> image() }, { _, _ -> throw FestivalApiException.InvalidResponse() })
        advanceUntilIdle()
        assertTrue((vm.state.value.load as PathLoad.Failed).issue is ServiceIssue.Other)
    }

    @Test
    fun pathsSwapFadesOutHoldsSpinnerThenFadesIn() = runTest(main.dispatcher) {
        val vm = SongPathsViewModel(listOf(Instrument.Lead), PathDisplayMode.Image, { _, _ -> image() }, { _, _ -> text() })
        advanceUntilIdle()
        val lead = Instrument.Lead.label
        assertEquals(PathSwapPhase.Content, vm.state.value.phase)
        assertEquals("$lead Expert path image loaded", vm.state.value.status)

        val start = currentTime
        vm.selectDifficulty(PathDifficulty.Hard)
        runCurrent()
        // The old chart stays mounted while it fades out; the controls already show Hard.
        assertEquals(PathSwapPhase.ContentOut, vm.state.value.phase)
        assertTrue(vm.state.value.load is PathLoad.Image)
        assertEquals(PathDifficulty.Expert, vm.state.value.shown.difficulty)
        assertEquals(PathDifficulty.Hard, vm.state.value.difficulty)
        assertEquals("Loading $lead Hard path", vm.state.value.status)
        advanceTimeBy(PathSwapTiming.FADE_MILLIS - 1); runCurrent()
        assertEquals(PathSwapPhase.ContentOut, vm.state.value.phase)
        advanceTimeBy(1); runCurrent()
        assertEquals(PathSwapPhase.Spinner, vm.state.value.phase)
        assertEquals(PathLoad.Loading, vm.state.value.load)
        assertTrue(vm.state.value.spinnerVisible)
        // The read already finished; the spinner still holds for the web minimum.
        advanceTimeBy(PathSwapTiming.MIN_IMAGE_SPINNER_MILLIS - 1); runCurrent()
        assertEquals(PathSwapPhase.Spinner, vm.state.value.phase)
        advanceTimeBy(1); runCurrent()
        assertEquals(PathSwapPhase.SpinnerOut, vm.state.value.phase)
        assertEquals(PathLoad.Loading, vm.state.value.load)
        advanceTimeBy(PathSwapTiming.FADE_MILLIS); runCurrent()
        assertEquals(PathSwapPhase.Content, vm.state.value.phase)
        assertTrue(vm.state.value.load is PathLoad.Image)
        assertEquals(PathDifficulty.Hard, vm.state.value.shown.difficulty)
        assertEquals("$lead Hard path image loaded", vm.state.value.status)
        assertEquals(PathSwapTiming.FADE_MILLIS * 2 + PathSwapTiming.MIN_IMAGE_SPINNER_MILLIS, currentTime - start)

        // Image → Text holds the spinner for the text minimum.
        val textStart = currentTime
        vm.selectDisplay(PathDisplayMode.Text)
        advanceUntilIdle()
        assertTrue(vm.state.value.load is PathLoad.Text)
        assertEquals("$lead Hard path loaded, 3 activations", vm.state.value.status)
        assertEquals(PathSwapTiming.FADE_MILLIS * 2 + PathSwapTiming.MIN_TEXT_SPINNER_MILLIS, currentTime - textStart)
    }

    @Test
    fun pathsRapidSwitchesNeverShowStaleContent() = runTest(main.dispatcher) {
        val slow = CompletableDeferred<Unit>()
        val vm = SongPathsViewModel(
            listOf(Instrument.Lead, Instrument.Bass),
            PathDisplayMode.Image,
            { chart, _ -> if (chart == Instrument.Bass) slow.await(); image() },
            { _, _ -> text() },
        )
        advanceUntilIdle()
        val seen = mutableListOf<SongPathsState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.state.collect { seen += it } }

        vm.selectDifficulty(PathDifficulty.Hard)
        advanceTimeBy(150); runCurrent()
        vm.selectInstrument(Instrument.Bass)
        advanceTimeBy(PathSwapTiming.FADE_MILLIS + 50); runCurrent()
        assertEquals(PathSwapPhase.Spinner, vm.state.value.phase)
        // A switch while the spinner is up keeps the spinner (no extra fade-out).
        vm.selectDisplay(PathDisplayMode.Text)
        runCurrent()
        assertEquals(PathSwapPhase.Spinner, vm.state.value.phase)
        slow.complete(Unit)
        advanceUntilIdle()

        val final = vm.state.value
        assertEquals(PathSwapPhase.Content, final.phase)
        assertTrue(final.load is PathLoad.Text)
        assertEquals(PathSelection(Instrument.Bass, PathDifficulty.Hard, PathDisplayMode.Text), final.shown)
        // Only the opening chart and the latest selection were ever presented.
        val presented = seen.filter { it.load !is PathLoad.Loading }.map { it.shown }.distinct()
        assertEquals(listOf(PathSelection(Instrument.Lead, PathDifficulty.Expert, PathDisplayMode.Image), final.shown), presented)
    }

    @Test
    fun pathsReduceMotionSwapsInstantly() = runTest(main.dispatcher) {
        val vm = SongPathsViewModel(
            listOf(Instrument.Lead),
            PathDisplayMode.Image,
            { _, difficulty -> if (difficulty == PathDifficulty.Easy) throw FestivalApiException.HttpStatus(404) else image() },
            { _, _ -> text() },
        )
        vm.reduceMotion = true
        advanceUntilIdle()
        val start = currentTime
        vm.selectDifficulty(PathDifficulty.Hard)
        runCurrent()
        assertEquals(PathSwapPhase.Content, vm.state.value.phase)
        assertEquals(PathDifficulty.Hard, vm.state.value.shown.difficulty)
        assertEquals(start, currentTime)
        vm.selectDifficulty(PathDifficulty.Easy)
        runCurrent()
        assertEquals(PathLoad.NotGenerated, vm.state.value.load)
        assertEquals(start, currentTime)
    }

    @Test
    fun pathsPrepareImageDuringSpinnerAndDescribeEveryOutcome() = runTest(main.dispatcher) {
        var decoded = 0
        val vm = SongPathsViewModel(
            listOf(Instrument.Lead),
            PathDisplayMode.Image,
            { _, difficulty ->
                if (difficulty == PathDifficulty.Easy) throw FestivalApiException.HttpStatus(404)
                if (difficulty == PathDifficulty.Medium) throw FestivalApiException.HttpStatus(500)
                image()
            },
            { _, _ -> text() },
            decodeImage = { decoded++; null },
        )
        advanceUntilIdle()
        val load = vm.state.value.load as PathLoad.Image
        assertTrue(load.prepared)
        assertNull(load.decoded)
        assertEquals(1, decoded)

        vm.selectDifficulty(PathDifficulty.Easy)
        advanceUntilIdle()
        val easy = PathSelection(Instrument.Lead, PathDifficulty.Easy, PathDisplayMode.Image)
        assertEquals(SongPathsState.notGeneratedText(easy), vm.state.value.status)
        assertEquals("No Easy path has been generated for ${Instrument.Lead.label} yet.", vm.state.value.status)
        vm.selectDifficulty(PathDifficulty.Medium)
        advanceUntilIdle()
        assertEquals("Path unavailable", vm.state.value.status)
        assertEquals(1, decoded)
    }

    // endregion

    // region Summaries and extras

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
        assertEquals(500, extras.spotlight[Instrument.Lead]?.score ?: 500)
        assertNull(extras.historyLeeway)
        assertEquals(Fixtures.ACCOUNT_A, extras.selectedAccountId)

        val mismatch = songDetailExtras(song, settings, shop, state, 6, 7)
        assertNull(mismatch.shopUrl)
        assertTrue(mismatch.spotlight.isEmpty())
        val hidden = songDetailExtras(song, settings.copy(hideShop = true), LoadState.Failed(ServiceIssue.NotFound), state, 7, 7)
        assertNull(hidden.shopUrl)
        assertFalse(hidden.shopError)
        val failed = songDetailExtras(song, AppSettings(), LoadState.Failed(ServiceIssue.NotFound), SelectedProfileState(), 7, 7)
        assertTrue(failed.shopError)
        assertTrue(failed.spotlight.isEmpty())
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
