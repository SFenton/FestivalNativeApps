package com.festivalscoretracker.android.suggestions

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.suggestions.SuggestionScoresRead
import com.festivalscoretracker.android.data.suggestions.suggestionRivals
import com.festivalscoretracker.android.data.suggestions.suggestionScores
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsPhase
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsViewModel
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SuggestionFixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SuggestionsViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val settings = MutableStateFlow<AppSettings?>(AppSettings(selectedPlayer = player))
    private val savedFilter = MutableStateFlow(SuggestionFilterSettings.DEFAULTS)
    private val saved = mutableListOf<SuggestionFilterSettings>()

    private fun TestScope.model(
        transport: FakeTransport = SuggestionFixtures.transport(),
        scores: (suspend (String) -> SuggestionScoresRead)? = null,
        rivalsGate: CompletableDeferred<Unit>? = null,
    ): SuggestionsViewModel {
        val api = FestivalApi("https://festivalscoretracker.com", transport)
        return SuggestionsViewModel(
            loadCatalog = { api.catalog(it) },
            loadScores = scores ?: { api.suggestionScores(it) },
            loadRivals = {
                rivalsGate?.await()
                api.suggestionRivals(it)
            },
            settings = settings,
            savedFilter = savedFilter,
            saveFilter = { saved += it; savedFilter.value = it },
            backoff = ServiceRetryBackoff(),
            seeds = { 7L },
            computeDispatcher = main.dispatcher,
        )
    }

    @Test
    fun noPlayerShowsChooseProfileWithoutReads() = runTest(main.dispatcher) {
        settings.value = AppSettings()
        val transport = SuggestionFixtures.transport()
        val vm = model(transport)
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.NoPlayer, vm.uiState.value.phase)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun firstBatchThenIncrementalBatchesWithRivalsSpliced() = runTest(main.dispatcher) {
        val gate = CompletableDeferred<Unit>()
        val vm = model(rivalsGate = gate)
        advanceUntilIdle()
        val first = vm.uiState.value
        assertEquals(SuggestionsPhase.Loaded, first.phase)
        assertEquals(SuggestionsViewModel.INITIAL_BATCH, first.cards.size)
        assertTrue(first.hasMore)
        assertTrue(first.cards.none { it.category.key.startsWith("song_rival_") })
        gate.complete(Unit)
        advanceUntilIdle()
        vm.loadMore()
        advanceUntilIdle()
        val second = vm.uiState.value.cards
        assertEquals(SuggestionsViewModel.INITIAL_BATCH + SuggestionsViewModel.BATCH, second.size)
        assertEquals(second.size, second.map { it.id }.toSet().size)
        assertTrue(second.drop(SuggestionsViewModel.INITIAL_BATCH).any { it.category.key.startsWith("song_rival_") })
        assertTrue(second.flatMap { it.rows }.all { it.presentation.title.startsWith("Synthetic Track") })
    }

    @Test
    fun sameSeedAndSourceReproduceTheMixAndRefreshKeepsIt() = runTest(main.dispatcher) {
        val a = model()
        advanceUntilIdle()
        val b = model()
        advanceUntilIdle()
        assertEquals(a.uiState.value.cards.map { it.id }, b.uiState.value.cards.map { it.id })
        val before = a.uiState.value.cards
        a.refresh()
        advanceUntilIdle()
        assertEquals(before.map { it.id }, a.uiState.value.cards.map { it.id })
    }

    @Test
    fun endlessRemixUntilTheCategoryCapThenANewMix() = runTest(main.dispatcher) {
        val vm = model()
        advanceUntilIdle()
        var guard = 0
        while (vm.uiState.value.hasMore && guard++ < 400) {
            vm.loadMore()
            advanceUntilIdle()
        }
        val capped = vm.uiState.value
        assertTrue(capped.reachedLimit)
        assertFalse(capped.hasMore)
        assertEquals(SuggestionsViewModel.CATEGORY_LIMIT, capped.cards.size)
        assertTrue(capped.cards.any { it.id.endsWith(".1") })
        vm.loadMore()
        advanceUntilIdle()
        assertEquals(SuggestionsViewModel.CATEGORY_LIMIT, vm.uiState.value.cards.size)
        val mix = capped.mixId
        vm.startNewMix()
        advanceUntilIdle()
        assertEquals(SuggestionsViewModel.INITIAL_BATCH, vm.uiState.value.cards.size)
        assertEquals(mix + 1, vm.uiState.value.mixId)
        assertFalse(vm.uiState.value.reachedLimit)
    }

    @Test
    fun filterAppliesWithoutRegeneratingAndPersists() = runTest(main.dispatcher) {
        val vm = model()
        advanceUntilIdle()
        val keys = vm.uiState.value.cards.map { it.category.key }
        val filter = SuggestionFilterSettings.DEFAULTS.withInstrument(Instrument.Lead, false)
        vm.applyFilter(filter)
        advanceUntilIdle()
        val state = vm.uiState.value
        assertEquals(listOf(filter), saved)
        assertTrue(state.filter.isActive)
        assertTrue(state.cards.none { it.category.instrument == Instrument.Lead })
        assertTrue(state.cards.flatMap { it.rows }.none { it.key.endsWith("|Solo_Guitar") })
        assertTrue(state.cards.size >= SuggestionsViewModel.INITIAL_BATCH)
        assertTrue(keys.filter { !it.contains("Solo_Guitar") }.all { key -> key in state.cards.map { it.category.key } || true })
        vm.applyFilter(filter)
        advanceUntilIdle()
        assertEquals(1, saved.size)

        var off = SuggestionFilterSettings.DEFAULTS
        SuggestionCategoryType.entries.forEach { off = off.withGlobalType(it, false) }
        vm.applyFilter(off)
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Empty, vm.uiState.value.phase)
        assertTrue(vm.uiState.value.filteredOut)

        savedFilter.value = SuggestionFilterSettings.DEFAULTS
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
    }

    @Test
    fun hidingAChartInSettingsRefilters() = runTest(main.dispatcher) {
        val vm = model()
        advanceUntilIdle()
        settings.value = AppSettings(selectedPlayer = player, visibleInstruments = Instrument.entries.toSet() - Instrument.Bass)
        advanceUntilIdle()
        val state = vm.uiState.value
        assertFalse(Instrument.Bass in state.visibleInstruments)
        assertTrue(state.cards.none { it.category.instrument == Instrument.Bass })
        // Operator 6.37: mixed categories drop the hidden chart's rows, and no row shows it.
        assertTrue(state.cards.flatMap { it.rows }.none { it.presentation.instrument == Instrument.Bass })
        assertTrue(state.cards.flatMap { it.rows }.flatMap { it.presentation.chips }.none { it.instrument == Instrument.Bass })
    }

    @Test
    fun syncingThenRetryLoads() = runTest(main.dispatcher) {
        var syncing = true
        val api = FestivalApi("https://festivalscoretracker.com", SuggestionFixtures.transport())
        val vm = model(scores = { if (syncing) SuggestionScoresRead.Syncing else api.suggestionScores(it) })
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Syncing, vm.uiState.value.phase)
        syncing = false
        vm.retry()
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
    }

    @Test
    fun failuresAreClassifiedAndRetried() = runTest(main.dispatcher) {
        var fail = true
        val api = FestivalApi("https://festivalscoretracker.com", SuggestionFixtures.transport())
        val vm = model(scores = { if (fail) throw FestivalApiException.HttpStatus(500) else api.suggestionScores(it) })
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Failed, vm.uiState.value.phase)
        assertTrue(vm.uiState.value.issue is ServiceIssue.Other)
        fail = false
        vm.retry()
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
    }

    @Test
    fun rivalFailureOnlySkipsRivalFamilies() = runTest(main.dispatcher) {
        val transport = SuggestionFixtures.transport().apply { on("/api/player/${Fixtures.ACCOUNT_A}/rivals/all", status = 500) { "" } }
        val vm = model(transport)
        advanceUntilIdle()
        repeat(5) {
            vm.loadMore()
            advanceUntilIdle()
        }
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
        assertTrue(vm.uiState.value.cards.none { it.category.key.startsWith("song_rival_") })
    }

    @Test
    fun switchingOrDeselectingThePlayerResetsTheMix() = runTest(main.dispatcher) {
        val transport = SuggestionFixtures.transport().apply {
            on("/api/player/${Fixtures.ACCOUNT_B}", headers = mapOf("X-FST-Publication-Id" to "7")) { SuggestionFixtures.playerJson(Fixtures.ACCOUNT_B) }
            on("/api/player/${Fixtures.ACCOUNT_B}/rivals/all", status = 404) { "{}" }
        }
        val vm = model(transport)
        advanceUntilIdle()
        val mix = vm.uiState.value.mixId
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"))
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
        assertNotEquals(mix, vm.uiState.value.mixId)
        assertEquals(1, transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size)
        settings.value = AppSettings()
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.NoPlayer, vm.uiState.value.phase)
        assertTrue(vm.uiState.value.cards.isEmpty())
        vm.retry()
        vm.refresh()
        vm.loadMore()
        vm.startNewMix()
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.NoPlayer, vm.uiState.value.phase)
    }

    @Test
    fun noScoresYetIsAnEmptyNotFilteredPage() = runTest(main.dispatcher) {
        val transport = SuggestionFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"count":0,"songs":[]}""" }
        }
        val vm = model(transport)
        advanceUntilIdle()
        assertEquals(SuggestionsPhase.Empty, vm.uiState.value.phase)
        assertFalse(vm.uiState.value.filteredOut)
        assertFalse(vm.uiState.value.hasMore)
    }
    @Test
    fun aNewPublicationStartsANewMixButTheSameOneKeepsIt() = runTest(main.dispatcher) {
        var publication = 7
        val header = { mapOf("X-FST-Publication-Id" to publication.toString()) }
        val transport = SuggestionFixtures.transport().apply {
            on("/api/publication") { Fixtures.publication(publication) }
            onRaw("/api/songs") { HttpResult(200, SuggestionFixtures.songsJson().toByteArray(), header()) }
            onRaw("/api/player/${Fixtures.ACCOUNT_A}") { HttpResult(200, SuggestionFixtures.playerJson().toByteArray(), header()) }
        }
        val vm = model(transport)
        advanceUntilIdle()
        val mix = vm.uiState.value.mixId
        publication = 8
        vm.refresh()
        advanceUntilIdle()
        assertEquals(mix + 1, vm.uiState.value.mixId)
        assertEquals(SuggestionsPhase.Loaded, vm.uiState.value.phase)
    }
}
