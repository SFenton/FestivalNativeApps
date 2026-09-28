package com.festivalscoretracker.android.presentation.suggestions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.suggestions.RivalDataIndex
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import com.festivalscoretracker.android.core.suggestions.SuggestionCategory
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryFilter
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.core.suggestions.SuggestionGenerator
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.core.suggestions.SuggestionScoreIndex
import com.festivalscoretracker.android.core.suggestions.SuggestionSeason
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.suggestions.SuggestionScoresRead
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// region State

/** What the Suggestions page shows. */
enum class SuggestionsPhase {
    /** No player selected: Choose Profile prompt. */
    NoPlayer,

    /** Catalogue or scores in flight. */
    Loading,

    /** Scores are syncing (HTTP 202). */
    Syncing,

    /** Catalogue or score read failed. */
    Failed,

    /** Nothing to show (none generated, or all filtered out). */
    Empty,

    /** Category cards shown. */
    Loaded,
}

/**
 * One tappable row.
 *
 * @property key Stable identity within its card (`songId` or `songId|Solo_X`).
 * @property presentation Display values.
 * @property songId Song Detail destination.
 * @property albumArt Artwork reference.
 * @property usesKeyboardIcon Keys icon variant for Lead/Pro Lead.
 */
data class SuggestionRow(
    val key: String,
    val presentation: SuggestionRowPresentation,
    val songId: String,
    val albumArt: String?,
    val usesKeyboardIcon: Boolean,
)

/**
 * One category card.
 *
 * @property id Stable list key and test-tag suffix (`<key>` or `<key>.<mix>` after a remix).
 * @property category Generated (and possibly trimmed) category.
 * @property rows Rows.
 */
data class SuggestionCard(val id: String, val category: SuggestionCategory, val rows: List<SuggestionRow>)

/**
 * Everything the Suggestions screen renders.
 *
 * @property phase Page phase.
 * @property issue Failure classification (phase [SuggestionsPhase.Failed]).
 * @property countdown Seconds until an automatic retry (scrape freeze).
 * @property cards Visible cards.
 * @property hasMore Whether scrolling can generate more.
 * @property reachedLimit 1,000-category cap reached (Start a new mix).
 * @property filter Applied filter.
 * @property visibleInstruments Settings-visible charts in display order.
 * @property filteredOut Whether the filter (not a lack of scores) caused an empty page.
 * @property mixId Increments with every new mix so the list can reset its scroll.
 */
data class SuggestionsUiState(
    val phase: SuggestionsPhase = SuggestionsPhase.Loading,
    val issue: ServiceIssue? = null,
    val countdown: Int? = null,
    val cards: List<SuggestionCard> = emptyList(),
    val hasMore: Boolean = false,
    val reachedLimit: Boolean = false,
    val filter: SuggestionFilterSettings = SuggestionFilterSettings.DEFAULTS,
    val visibleInstruments: List<Instrument> = Instrument.entries,
    val filteredOut: Boolean = false,
    val mixId: Int = 0,
)

/**
 * The inputs one mix is built from.
 *
 * @property accountId Selected player.
 * @property catalog Catalogue and its publication.
 * @property scores Score read (available or syncing).
 */
data class SuggestionSource(val accountId: String, val catalog: CatalogPayload, val scores: SuggestionScoresRead)

// endregion

// region View model

/**
 * Suggestions page: one [SuggestionGenerator] per (player, catalogue publication,
 * score publication) source, web batching (10 first, 6 per scroll trigger,
 * endless `resetForEndless` remix up to 1,000 categories), `/rivals/all` spliced in
 * when it answers (best-effort), and a persisted filter re-applied without
 * regenerating (Windows `SuggestionsViewModel`, web `useSuggestions`).
 *
 * Generation runs on [computeDispatcher] under a mutex (the generator is not
 * thread-safe); the UI only ever sees immutable [SuggestionsUiState] snapshots.
 *
 * @param loadCatalog Catalogue read.
 * @param loadScores Selected player's score read.
 * @param loadRivals `/rivals/all` read.
 * @param settings Effective settings stream.
 * @param savedFilter Persisted filter stream.
 * @param saveFilter Persist a filter.
 * @param backoff Shared retry backoff.
 * @param seeds Seed per mix (debug `FST_DEBUG_SUGGESTIONS_SEED` and tests pin it).
 * @param computeDispatcher Dispatcher for generation.
 */
class SuggestionsViewModel(
    private val loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    private val loadScores: suspend (accountId: String) -> SuggestionScoresRead,
    private val loadRivals: suspend (accountId: String) -> RivalsAllResponse,
    settings: Flow<AppSettings?>,
    savedFilter: Flow<SuggestionFilterSettings>,
    private val saveFilter: suspend (SuggestionFilterSettings) -> Unit,
    backoff: ServiceRetryBackoff,
    private val seeds: () -> Long = RANDOM_SEEDS,
    private val computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SuggestionsUiState())
    private val mutex = Mutex()
    private var accountId: String? = null
    private var settingsSeen = false
    private val loader = RetryingLoader(viewModelScope, "suggestions", backoff) { refresh -> readSource(refresh) }

    // Guarded by [mutex].
    private var generator: SuggestionGenerator? = null
    private var source: SuggestionSource? = null
    private var scores: SuggestionScoreIndex = emptyMap()
    private val generated = mutableListOf<Pair<SuggestionCategory, Int>>()
    private var mix = 0
    private var rivalsJob: Job? = null
    private var generationJob: Job? = null

    /** Screen state. */
    val uiState: StateFlow<SuggestionsUiState> = mutableState.asStateFlow()

    init {
        viewModelScope.launch {
            settings.filterNotNull()
                .map { it.selectedPlayer?.accountId to Instrument.entries.filter(it.visibleInstruments::contains) }
                .distinctUntilChanged()
                .collect { (account, visible) -> onSettings(account, visible) }
        }
        viewModelScope.launch {
            savedFilter.distinctUntilChanged().collect { filter ->
                if (filter != mutableState.value.filter) {
                    mutableState.update { it.copy(filter = filter) }
                    refilter()
                }
            }
        }
        viewModelScope.launch { loader.state.collect(::onLoad) }
    }

    // region Loading

    private suspend fun readSource(refresh: Boolean): SuggestionSource {
        val account = accountId ?: throw CancellationException("No player")
        val catalog = loadCatalog(refresh)
        return SuggestionSource(account, catalog, loadScores(account))
    }

    private fun onSettings(account: String?, visible: List<Instrument>) {
        val accountChanged = !settingsSeen || !account.equals(accountId, ignoreCase = true)
        settingsSeen = true
        mutableState.update { it.copy(visibleInstruments = visible) }
        if (!accountChanged) {
            refilter()
            return
        }
        accountId = account
        viewModelScope.launch { mutex.withLock { resetLocked() } }
        if (account == null) {
            mutableState.update { SuggestionsUiState(SuggestionsPhase.NoPlayer, filter = it.filter, visibleInstruments = visible, mixId = it.mixId) }
        } else {
            mutableState.update { SuggestionsUiState(SuggestionsPhase.Loading, filter = it.filter, visibleInstruments = visible, mixId = it.mixId) }
            loader.retry()
        }
    }

    private suspend fun onLoad(state: LoadState<SuggestionSource>) {
        if (accountId == null) return
        when (state) {
            LoadState.Loading -> if (mutableState.value.cards.isEmpty()) {
                mutableState.update { it.copy(phase = SuggestionsPhase.Loading, issue = null, countdown = null) }
            }
            is LoadState.Failed -> {
                mutex.withLock { resetLocked() }
                mutableState.update { it.copy(phase = SuggestionsPhase.Failed, issue = state.issue, countdown = state.countdown, cards = emptyList()) }
            }
            is LoadState.Loaded -> {
                val loaded = state.value
                if (!loaded.accountId.equals(accountId, ignoreCase = true)) return
                when (val read = loaded.scores) {
                    SuggestionScoresRead.Syncing -> {
                        mutex.withLock { resetLocked() }
                        mutableState.update { it.copy(phase = SuggestionsPhase.Syncing, issue = null, countdown = null, cards = emptyList()) }
                    }
                    is SuggestionScoresRead.Available -> {
                        val same = mutex.withLock { source?.let { sameSource(it, loaded) } == true }
                        if (same) refilter() else startMix(loaded, read.index)
                    }
                }
            }
        }
    }

    private fun sameSource(old: SuggestionSource, new: SuggestionSource): Boolean {
        val oldScores = old.scores as? SuggestionScoresRead.Available ?: return false
        val newScores = new.scores as? SuggestionScoresRead.Available ?: return false
        return old.accountId.equals(new.accountId, ignoreCase = true) &&
            old.catalog.publicationId == new.catalog.publicationId &&
            oldScores.observedPublicationId == newScores.observedPublicationId
    }

    /** Retry after a failure or while syncing. */
    fun retry() {
        if (accountId != null) loader.retry()
    }

    /** Re-read the catalogue and scores (pull to refresh); keeps the mix when nothing changed. */
    fun refresh() {
        if (accountId != null) loader.refresh()
    }

    // endregion

    // region Generation

    private fun resetLocked() {
        rivalsJob?.cancel()
        generationJob?.cancel()
        generator = null
        source = null
        scores = emptyMap()
        generated.clear()
        mix = 0
    }

    private suspend fun startMix(loaded: SuggestionSource, index: SuggestionScoreIndex) {
        val built = mutex.withLock {
            resetLocked()
            source = loaded
            scores = index
            val season = SuggestionSeason.effective(loaded.catalog.catalog.currentSeason, index)
            SuggestionGenerator(SuggestionGenerator.Options(seed = seeds(), currentSeason = season)).also {
                it.setSource(loaded.catalog.catalog.songs, index)
                generator = it
            }
        }
        mutableState.update {
            it.copy(cards = emptyList(), hasMore = true, reachedLimit = false, issue = null, countdown = null, mixId = it.mixId + 1)
        }
        generate(INITIAL_BATCH, replace = true)
        rivalsJob = viewModelScope.launch { loadRivalsFor(loaded.accountId, built) }
    }

    /** Best-effort `/rivals/all`; spliced into the running generator when it answers. */
    private suspend fun loadRivalsFor(account: String, target: SuggestionGenerator) {
        val response = try {
            loadRivals(account)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            return // Rival families are optional; every other family still shows.
        }
        val index = withContext(computeDispatcher) { RivalDataIndex.build(response) }
        val resume = mutex.withLock {
            if (generator !== target) return
            target.setRivalData(index)
            val state = mutableState.value
            !state.hasMore && !state.reachedLimit
        }
        if (resume) {
            mutableState.update { it.copy(hasMore = true) }
            loadMore()
        }
    }

    /** Generate the next batch (the list's third-from-last card became visible). */
    fun loadMore() {
        val state = mutableState.value
        if (!state.hasMore || generationJob?.isActive == true) return
        generationJob = viewModelScope.launch { generate(BATCH, replace = false) }
    }

    /** Start a fresh mix from the same source (after the cap, or on request). */
    fun startNewMix() {
        viewModelScope.launch {
            val current = mutex.withLock { source } ?: return@launch
            val available = current.scores as? SuggestionScoresRead.Available ?: return@launch
            startMix(current, available.index)
        }
    }

    /**
     * Pull categories until [count] new cards are visible (the filter may hide some)
     * or nothing is left even after a remix.
     */
    private suspend fun generate(count: Int, replace: Boolean) {
        withContext(computeDispatcher) {
            mutex.withLock {
                val target = generator ?: return@withLock
                val state = mutableState.value
                val filter = state.filter
                val visible = state.visibleInstruments
                val cards = if (replace) mutableListOf() else state.cards.toMutableList()
                var hasMore = true
                var reachedLimit = false
                if (!filter.allTypesOff) {
                    var added = 0
                    var remixed = false
                    var round = 0
                    while (added < count && round < MAX_ROUNDS) {
                        round++
                        val remaining = CATEGORY_LIMIT - generated.size
                        if (remaining <= 0) {
                            reachedLimit = true
                            hasMore = false
                            break
                        }
                        val next = target.getNext(minOf(count - added, remaining))
                        if (next.isEmpty()) {
                            if (remixed || generated.isEmpty()) {
                                hasMore = false
                                break
                            }
                            target.resetForEndless()
                            mix++
                            remixed = true
                            continue
                        }
                        remixed = false
                        for (category in next) {
                            generated += category to mix
                            card(category, mix, filter, visible)?.let {
                                cards += it
                                added++
                            }
                        }
                    }
                }
                // Published under the lock so a queued batch always extends this one.
                mutableState.update {
                    it.copy(
                        cards = cards,
                        hasMore = hasMore,
                        reachedLimit = reachedLimit,
                        phase = if (cards.isEmpty()) SuggestionsPhase.Empty else SuggestionsPhase.Loaded,
                        filteredOut = cards.isEmpty() && (filter.allTypesOff || filter.isActive && generated.isNotEmpty()),
                    )
                }
            }
        }
    }

    /** Filter and present one category, or null when hidden. Caller holds [mutex]. */
    private fun card(category: SuggestionCategory, mixNumber: Int, filter: SuggestionFilterSettings, visible: List<Instrument>): SuggestionCard? {
        val shown = SuggestionCategoryFilter.visible(category, filter.effectiveInstruments(visible.toSet()), filter) ?: return null
        val rows = shown.songs.map { item ->
            SuggestionRow(
                key = item.id,
                presentation = SuggestionRowPresentation.create(shown, item, scores, visible),
                songId = item.song.songId,
                albumArt = item.song.albumArt,
                usesKeyboardIcon = item.song.usesKeyboardIcon,
            )
        }
        val id = if (mixNumber == 0) category.key else "${category.key}.$mixNumber"
        return SuggestionCard(id, shown, rows)
    }

    /** Re-derive cards from the generated list (filter or visibility change); never regenerates. */
    private fun refilter() {
        viewModelScope.launch {
            val short = withContext(computeDispatcher) {
                mutex.withLock {
                    if (generator == null) return@withLock false
                    val state = mutableState.value
                    val cards = generated.mapNotNull { (category, mixNumber) -> card(category, mixNumber, state.filter, state.visibleInstruments) }
                    mutableState.update {
                        it.copy(
                            cards = cards,
                            phase = if (cards.isEmpty()) SuggestionsPhase.Empty else SuggestionsPhase.Loaded,
                            filteredOut = cards.isEmpty() && state.filter.isActive,
                        )
                    }
                    cards.size < INITIAL_BATCH && state.hasMore
                }
            }
            if (short) generate(INITIAL_BATCH - mutableState.value.cards.size, replace = false)
        }
    }

    // endregion

    // region Filter

    /**
     * Apply and persist a filter; cards re-derive without regenerating.
     *
     * @param next New filter.
     */
    fun applyFilter(next: SuggestionFilterSettings) {
        if (next == mutableState.value.filter) return
        mutableState.update { it.copy(filter = next) }
        refilter()
        viewModelScope.launch { saveFilter(next) }
    }

    // endregion

    companion object {
        /** Categories generated on first appearance (web `INITIAL_BATCH`). */
        const val INITIAL_BATCH = 10

        /** Categories generated per scroll trigger (web `BATCH_SIZE`). */
        const val BATCH = 6

        /** Most categories kept in one mix (web `SUGGESTIONS_CATEGORY_LIMIT`). */
        const val CATEGORY_LIMIT = 1_000

        /** A fresh random 32-bit seed per mix (the default). */
        val RANDOM_SEEDS: () -> Long = { Random.nextLong(0, 1L shl 32) }

        /** Loop guard for one batch (the filter can hide many categories in a row). */
        private const val MAX_ROUNDS = 50
    }
}

// endregion
