package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsTab
import com.festivalscoretracker.android.core.rankings.RankHistoryChart
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.data.rankings.bandRankings
import com.festivalscoretracker.android.data.rankings.playerInstrumentRanking
import com.festivalscoretracker.android.data.rankings.rankHistory
import com.festivalscoretracker.android.data.rankings.rankings
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.leaderboards.BandRankingsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.FullRankingsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.LeaderboardsViewModel
import com.festivalscoretracker.android.presentation.leaderboards.RankingsReads
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map

// region Graph

/**
 * The service reads the Leaderboards screens use.
 *
 * @param container Process dependencies.
 * @return Reads bound to the shared API client.
 */
fun rankingsReads(container: AppContainer): RankingsReads {
    val api = container.api
    return RankingsReads(
        rankings = { instrument, metric, page, size -> api.rankings(instrument, metric, page, size) },
        bandRankings = { bandType, metric, page, size -> api.bandRankings(bandType, metric, page, size) },
        playerRanking = { instrument, accountId -> api.playerInstrumentRanking(instrument, accountId) },
        rankHistory = { instrument, accountId -> api.rankHistory(instrument, accountId, RankHistoryChart.DAYS) },
    )
}

/**
 * Register the Leaderboards destinations: the tab root, the pushed overview, Full
 * Rankings and Band Rankings.
 *
 * @param container Process dependencies.
 * @param shellViewModel Shell state (settings, selected player).
 * @param preferences Persisted Rank By.
 */
fun NavGraphBuilder.leaderboardsGraph(container: AppContainer, shellViewModel: ShellViewModel, preferences: LeaderboardPreferences) {
    composable<LeaderboardsTab> { Overview(container, shellViewModel, preferences, isRoot = true) }
    composable<LeaderboardsRoute> { Overview(container, shellViewModel, preferences, isRoot = false) }
    composable<FullRankingsRoute> { entry ->
        // The entry's saved route arguments are rewritten as the user pages or switches,
        // so a recreated entry (process death) restores the same board and page.
        val route = entry.savedStateHandle.toRoute<FullRankingsRoute>()
        val viewModel: FullRankingsViewModel = viewModel {
            FullRankingsViewModel(
                initialInstrument = Instrument.fromWireId(route.instrument) ?: Instrument.Lead,
                initialMetric = RankingMetric.fromWireId(route.rankBy) ?: RankingMetric.DEFAULT,
                reads = rankingsReads(container),
                settings = shellViewModel.settings,
                backoff = container.backoff,
                initialPage = route.page,
            )
        }
        val instrument by viewModel.instrument.collectAsStateWithLifecycle()
        val metric by viewModel.metric.collectAsStateWithLifecycle()
        val page by viewModel.page.collectAsStateWithLifecycle()
        SyncRouteArguments(entry.savedStateHandle, "instrument" to instrument.wireId, "rankBy" to metric.wireId, "page" to page)
        FullRankingsScreen(viewModel)
    }
    composable<BandRankingsRoute> { entry ->
        val route = entry.savedStateHandle.toRoute<BandRankingsRoute>()
        val viewModel: BandRankingsViewModel = viewModel {
            BandRankingsViewModel(
                BandType.fromWireId(route.bandType) ?: BandType.Duets,
                preferences.rankBy,
                shellViewModel.settings.filterNotNull().map { it.experimentalRanks },
                rankingsReads(container),
                container.backoff,
                route.page,
            )
        }
        val bandType by viewModel.bandType.collectAsStateWithLifecycle()
        val page by viewModel.page.collectAsStateWithLifecycle()
        SyncRouteArguments(entry.savedStateHandle, "bandType" to bandType.wireId, "page" to page)
        val settings by shellViewModel.settings.collectAsStateWithLifecycle()
        BandRankingsScreen(viewModel, settings?.selectedPlayer?.accountId)
    }
}

/**
 * Mirror a board's current state into its back-stack entry's route arguments (the
 * spec's native correction: paging updates the route rather than only local state).
 *
 * @param handle The entry's saved state (holds the typed route's arguments).
 * @param values Argument name to current value (names match the route's properties).
 */
@Composable
fun SyncRouteArguments(handle: SavedStateHandle, vararg values: Pair<String, Any>) {
    SideEffect { values.forEach { (key, value) -> if (handle.get<Any>(key) != value) handle[key] = value } }
}

@Composable
private fun Overview(container: AppContainer, shellViewModel: ShellViewModel, preferences: LeaderboardPreferences, isRoot: Boolean) {
    val viewModel: LeaderboardsViewModel = viewModel {
        LeaderboardsViewModel(rankingsReads(container), shellViewModel.settings, preferences.rankBy, preferences::setRankBy, container.backoff)
    }
    LeaderboardsScreen(viewModel, isRoot)
}

// endregion
