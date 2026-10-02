package com.festivalscoretracker.android.presentation.compete

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.compete.CompeteScope
import com.festivalscoretracker.android.core.compete.CompeteScopes
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.PlayerRankingResult
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.rivalEntries
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.compete.comboRankings
import com.festivalscoretracker.android.data.compete.playerComboRanking
import com.festivalscoretracker.android.data.rankings.playerInstrumentRanking
import com.festivalscoretracker.android.data.rankings.rankings
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import com.festivalscoretracker.android.presentation.rivals.map
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// region Reads

/**
 * The rankings reads Compete needs, per scope.
 *
 * @property board Top-[CompeteViewModel.BOARD_SIZE] Total Score rows.
 * @property playerRow The account's own row, or null when unranked.
 */
class CompeteReads(
    val board: suspend (CompeteScope) -> List<AccountRankingEntry>,
    val playerRow: suspend (CompeteScope, String) -> AccountRankingEntry?,
) {
    companion object {
        /**
         * Reads over the shared client (instrument boards from the Leaderboards feature,
         * combo boards from `data/compete`).
         *
         * @param api Keyless client.
         * @return Reads.
         */
        fun from(api: FestivalApi) = CompeteReads(
            board = { scope ->
                when (scope) {
                    is CompeteScope.Single -> api.rankings(scope.instrument, RankingMetric.TotalScore, 1, CompeteViewModel.BOARD_SIZE).rankings.entries
                    is CompeteScope.Combo -> api.comboRankings(scope.comboId, RankingMetric.TotalScore, 1, CompeteViewModel.BOARD_SIZE).entries.map { it.asAccountEntry() }
                }
            },
            playerRow = { scope, accountId ->
                when (scope) {
                    is CompeteScope.Single -> (api.playerInstrumentRanking(scope.instrument, accountId) as? PlayerRankingResult.Ranked)?.ranking?.entry
                    is CompeteScope.Combo -> api.playerComboRanking(accountId, scope.comboId, RankingMetric.TotalScore)?.asAccountEntry()
                }
            },
        )
    }
}

// endregion

// region State

/**
 * One scope's leaderboard preview.
 *
 * @property entries Top rows.
 * @property spotlight The player's row when ranked outside the top rows (web `playerEntry && !playerInTop`).
 */
data class CompeteBoard(val entries: List<AccountRankingEntry>, val spotlight: AccountRankingEntry?) {
    /** Whether the card links to the full board (web `hasLeaderboardNavigation`). */
    val hasNavigation: Boolean get() = entries.isNotEmpty() || spotlight != null
}

/**
 * One scope's two cards.
 *
 * @property scope Scope.
 * @property board Leaderboard preview state.
 * @property rivals Three above / three below, or null with no selected player.
 */
data class CompeteSection(
    val scope: CompeteScope,
    val board: LoadState<CompeteBoard>,
    val rivals: LoadState<List<RivalEntry>>?,
)

/**
 * The page.
 *
 * @property sections Scope cards in web order.
 * @property fullPageIssue Set when every leaderboard read failed (web `allLeaderboardsErrored`).
 * @property countdown Automatic retry countdown for [fullPageIssue].
 */
data class CompeteContent(val sections: List<CompeteSection>, val fullPageIssue: ServiceIssue?, val countdown: Int?)

// endregion

// region View model

/**
 * Compete hub logic (web `CompetePage`): for each supported ranking scope, a Top 10
 * Total Score preview with the player's own row, and the scope's 3-above/3-below
 * rivals. Every read uses the shared retry semantics independently.
 *
 * The model lives on the back stack (keyed by account and visible charts), so returning
 * from View Full Leaderboard or a rival shows the loaded cards in place without a reload;
 * a newer observed publication refreshes every read in place (iOS `ReappearanceLoadGate`,
 * issue #82), and a different account or chart set creates a new model.
 *
 * @param accountId Selected player, or null (leaderboards only).
 * @param visible Settings-visible charts.
 * @param reads Rankings reads.
 * @param rivals Rivals reads.
 * @param backoff Shared retry backoff.
 * @param publications Observed publication stream (`FestivalApi.publicationChanges`).
 */
class CompeteViewModel(
    private val accountId: String?,
    visible: Set<Instrument>,
    private val reads: CompeteReads,
    private val rivals: RivalsRepository,
    backoff: ServiceRetryBackoff,
    publications: Flow<Int?> = emptyFlow(),
) : ViewModel() {
    /** Scopes in web order. */
    val scopes: List<CompeteScope> = CompeteScopes.resolve(visible)

    private val boardLoaders = scopes.map { scope ->
        RetryingLoader(viewModelScope, "compete:board:${scope.key}", backoff) { loadBoard(scope) }
    }
    private val rivalLoaders = scopes.map { scope ->
        accountId?.let { id ->
            RetryingLoader(viewModelScope, "compete:rivals:$id:${scope.key}", backoff) { refresh -> rivals.list(id, scope.key, refresh) }
        }
    }

    /** Page state. */
    val content: StateFlow<CompeteContent> = run {
        val flows = boardLoaders.map { it.state } + rivalLoaders.mapNotNull { it?.state }
        val initial = assemble(flows.map { it.value })
        if (flows.isEmpty()) MutableStateFlow(initial) else combine(flows) { assemble(it.toList()) }.stateIn(viewModelScope, SharingStarted.Eagerly, initial)
    }

    init {
        boardLoaders.forEach { it.ensureStarted() }
        rivalLoaders.forEach { it?.ensureStarted() }
        viewModelScope.launch {
            // The publication current at creation is what the first loads read; only a newer one refreshes.
            publications.filterNotNull().distinctUntilChanged().drop(1).collect { refreshAll() }
        }
    }

    /** Reload every read for a newer publication, keeping loaded cards visible (failed ones retry). */
    private fun refreshAll() {
        boardLoaders.forEach { it.refresh() }
        rivalLoaders.forEach { it?.refresh() }
    }

    /** Retry every failed read. */
    fun retryFailed() {
        (boardLoaders + rivalLoaders.filterNotNull()).filter { it.state.value is LoadState.Failed }.forEach { it.retry() }
    }

    /**
     * Retry one scope's leaderboard read.
     *
     * @param key Scope key.
     */
    fun retryBoard(key: String) {
        boardLoaders.getOrNull(scopes.indexOfFirst { it.key == key })?.retry()
    }

    /**
     * Retry one scope's rivals read.
     *
     * @param key Scope key.
     */
    fun retryRivals(key: String) {
        rivalLoaders.getOrNull(scopes.indexOfFirst { it.key == key })?.retry()
    }

    private suspend fun loadBoard(scope: CompeteScope): CompeteBoard = coroutineScope {
        val own = accountId?.let { id ->
            async {
                try {
                    reads.playerRow(scope, id)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    // The spotlight is optional; the board itself still renders.
                    null
                }
            }
        }
        val entries = reads.board(scope)
        val player = own?.await()
        val inTop = player != null && entries.any { it.accountId.equals(player.accountId, ignoreCase = true) }
        CompeteBoard(entries, player.takeUnless { inTop })
    }

    @Suppress("UNCHECKED_CAST")
    private fun assemble(states: List<LoadState<*>>): CompeteContent {
        val boards = states.take(scopes.size) as List<LoadState<CompeteBoard>>
        val rivalStates = states.drop(scopes.size) as List<LoadState<com.festivalscoretracker.android.core.rivals.RivalsListResponse>>
        var rivalIndex = 0
        val sections = scopes.mapIndexed { index, scope ->
            val rivalsState = if (rivalLoaders[index] != null) rivalStates[rivalIndex++].map { rivalEntries(it.above, it.below, PREVIEW_COUNT) } else null
            CompeteSection(scope, boards[index], rivalsState)
        }
        val failures = boards.filterIsInstance<LoadState.Failed>()
        val allFailed = boards.isNotEmpty() && failures.size == boards.size
        return CompeteContent(sections, if (allFailed) failures.first().issue else null, if (allFailed) failures.first().countdown else null)
    }

    companion object {
        /** Leaderboard rows per card (web `getRankings(…, 1, 10)`). */
        const val BOARD_SIZE = 10

        /** Rivals kept from each side. */
        const val PREVIEW_COUNT = 3
    }
}

// endregion
