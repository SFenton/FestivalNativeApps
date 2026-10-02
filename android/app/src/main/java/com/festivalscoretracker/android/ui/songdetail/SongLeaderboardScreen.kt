package com.festivalscoretracker.android.ui.songdetail

import com.festivalscoretracker.android.ui.design.popupTestTags
import androidx.compose.ui.semantics.selected
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.Icon
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.Icons
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.songs.leaderboardPage
import com.festivalscoretracker.android.presentation.songs.effective
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.derivedStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rankings.SongScoreSpotlight
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongLeaderboardViewModel
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.leaderboards.AnchoredRowCard
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardScaffold
import com.festivalscoretracker.android.ui.leaderboards.SyncRouteArguments
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.leaderboards.RankingsSkeletonRows
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.flow.StateFlow

// region Song leaderboard

/**
 * Route wiring for `/songs/:songId/:instrument`: reads pages with `leeway=` while
 * Filter Invalid Scores is on, re-reading when it changes (web `LeaderboardPage`).
 *
 * @param container Process dependencies.
 * @param settings Current settings.
 * @param route Route.
 * @param routeState The back-stack entry's saved route arguments; the current page is
 *   written back so the route follows paging (spec native correction).
 */
@Composable
fun SongLeaderboardRouteScreen(container: AppContainer, settings: AppSettings, route: SongLeaderboardRoute, routeState: SavedStateHandle? = null) {
    val api = container.api
    val instrument = Instrument.fromWireId(route.instrument) ?: Instrument.Lead
    val leeway = settings.leeway.takeIf { settings.filterInvalidScores }
    val boardViewModel: SongLeaderboardViewModel = viewModel(key = "board:${route.songId}:${instrument.wireId}:$leeway") {
        SongLeaderboardViewModel(
            route.songId, instrument, route.page, { api.catalog(it) },
            { id, chart, page, top -> api.leaderboardPage(id, chart, page, top, leeway) },
            container.backoff,
        )
    }
    if (routeState != null) {
        val page by boardViewModel.page.collectAsStateWithLifecycle()
        SyncRouteArguments(routeState, "page" to page)
    }
    SongLeaderboardScreen(boardViewModel, settings.selectedPlayer?.accountId, container.selectedProfile.state, leeway, settings.visibleInstruments, api::artworkUrl)
}

/**
 * Full 25-row song leaderboard (`/songs/:songId/:instrument`) with the shared
 * rankings pager. Rows open the player's profile (Statistics for the selected
 * player, web `LeaderboardPage.tsx`); rows without a usable account ID are shown
 * but not interactive. The selected player's row is highlighted in place, or pinned
 * above the pager from their score index (same publication only).
 *
 * @param viewModel Leaderboard logic.
 * @param selectedAccountId Selected player, or null.
 * @param selectedProfile Selected player's process-only scores, or null.
 * @param visibleInstruments Settings-visible charts (the header's instrument switcher).
 * @param leeway Filter Invalid Scores leeway (the page is read with it; the spotlight shows the next valid score), or null.
 * @param artworkUrl Artwork resolver for the song header.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SongLeaderboardScreen(
    viewModel: SongLeaderboardViewModel,
    selectedAccountId: String? = null,
    selectedProfile: StateFlow<SelectedProfileState>? = null,
    leeway: Double? = null,
    visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    artworkUrl: (String?) -> String? = { null },
) {
    val song by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val navigate = LocalShellActions.current.navigate
    val listState = rememberLazyListState()
    val title = (song as? LoadState.Loaded)?.value?.title ?: "Leaderboard"
    val payload = (board as? LoadState.Loaded)?.value
    val loaded = payload?.leaderboard
    val profile = selectedProfile?.collectAsStateWithLifecycle()?.value
    val revealed = rememberRevealed(loaded != null)
    val footer = payload?.let {
        SongScoreSpotlight.footer(
            player = profile?.player?.takeIf { player -> RankingSpotlight.isSelected(selectedAccountId, player.accountId) },
            score = profile?.scoreIndex?.get(it.leaderboard.songId)?.get(viewModel.instrument)?.let { raw ->
                if (leeway == null) raw else raw.effective((song as? LoadState.Loaded)?.value, viewModel.instrument, leeway)
            },
            scorePublicationId = profile?.observedPublicationId,
            boardPublicationId = it.publicationId,
            visible = it.leaderboard.entries,
        )
    }

    // The rows and the pinned footer share one column plan, fitted to the narrower of the two (issue #37, 7.9).
    val columns = rememberScoreColumns(loaded?.entries.orEmpty() + listOfNotNull(footer))

    LaunchedEffect(page) { listState.scrollToItem(0) }

    // The song header (art, title, artist, instrument) scrolls with the rows; the top bar
    // takes the title once it has scrolled away (operator 7.8, like Song Detail).
    val headerGone by remember(listState) { derivedStateOf { listState.firstVisibleItemIndex > 0 } }
    FestivalScreen(
        title = if (headerGone) title else "",
        isRoot = false,
        scrolled = headerGone,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
    ) { padding ->
        val failed = board as? LoadState.Failed
        if (failed != null) {
            ServiceStatusView(failed.issue, "Leaderboard unavailable", failed.countdown, viewModel::retry, contentPadding = padding)
            return@FestivalScreen
        }
        RankingsBoardScaffold(
            padding = padding,
            listState = listState,
            idPrefix = "fst.song-leaderboard",
            loadingOverlay = false,
            controls = {
                val loadedSong = (song as? LoadState.Loaded)?.value
                loadedSong?.let { SongHeader(it, artworkUrl(it.albumArt), artSize = 64.dp) }
                val charts = loadedSong?.let { current -> Instrument.entries.filter { it in visibleInstruments && current.supports(it) } }.orEmpty()
                InstrumentSwitcher(viewModel.instrument, charts) { chart ->
                    loadedSong?.let { navigate(SongLeaderboardRoute(it.songId, chart.wireId)) }
                }
            },
            footer = { footer?.let { AnchoredRowCard { LeaderboardSectionMember(columns, "footer") { SelectedScoreFooter(it, navigate, columns.plan) } } } },
            pager = { RankingsPager(page, loaded?.pageCount() ?: page, "fst.song-leaderboard", viewModel::goTo) },
        ) {
            item(key = "rows") {
                GlassCard(Modifier.fillMaxWidth()) {
                    // Same 8 dp horizontal inset as AnchoredRowCard, so the pinned row's columns line up (issue #37).
                    LeaderboardSectionMember(columns, "rows", Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
                        when {
                            loaded == null -> RankingsSkeletonRows(10)
                            loaded.entries.isEmpty() -> Text("No scores yet", color = BrandTokens.textPrimary, modifier = Modifier.padding(16.dp))
                            else -> {
                                loaded.entries.forEachIndexed { index, entry ->
                                    Column(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                                        if (index > 0) RowSeparator()
                                        SongLeaderboardRow(
                                            entry = entry,
                                            isSelected = RankingSpotlight.isSelected(selectedAccountId, entry.accountId),
                                            route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selectedAccountId),
                                            onOpen = navigate,
                                            columns = columns.plan,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * The selected player's pinned score row (web `LeaderboardPage` footer: just the row,
 * which opens Statistics; no page-jump button, so its columns align with the board, 7.9).
 *
 * @param entry Footer row built from the score index.
 * @param navigate Push a route.
 * @param columns The board's shared column plan.
 */
@Composable
private fun SelectedScoreFooter(entry: LeaderboardEntry, navigate: (AppRoute) -> Unit, columns: LeaderboardColumnPlan) {
    Box(Modifier.fillMaxWidth().testTag("fst.song-leaderboard.spotlight-footer")) {
        SongLeaderboardRow(entry, isSelected = true, route = StatisticsRoute, onOpen = navigate, columns = columns)
    }
}

/**
 * One score row, interactive when it has a usable account.
 *
 * @param entry Score row.
 * @param isSelected Selected player's row (accent treatment).
 * @param route Destination or null.
 * @param onOpen Navigation callback.
 * @param columns The board's shared column plan (season and stars by row width, issue #37).
 */
@Composable
private fun SongLeaderboardRow(
    entry: LeaderboardEntry,
    isSelected: Boolean,
    route: AppRoute?,
    onOpen: (AppRoute) -> Unit,
    columns: LeaderboardColumnPlan,
) {
    var modifier = Modifier.fillMaxWidth().selectedRowHighlight(isSelected)
    modifier = if (route != null) {
        modifier.clickable(role = Role.Button, onClickLabel = "Open profile") { onOpen(route) }
    } else {
        modifier.semantics(mergeDescendants = true) { stateDescription = "Profile unavailable" }
    }
    Box(modifier.testTag("fst.song-leaderboard.row.${entry.accountId.ifEmpty { "rank-${entry.rank}" }}")) {
        ScoreRow(entry, isSelected = isSelected, navigable = route != null, columns = columns)
    }
}


/**
 * The header's instrument (web instrument switcher): icon and name; with more
 * than one visible chart it opens a menu that switches the board.
 */
@Composable
private fun InstrumentSwitcher(current: Instrument, charts: List<Instrument>, onSelect: (Instrument) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val switchable = charts.size > 1
    Box {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .padding(vertical = 8.dp)
                .clip(RoundedCornerShape(12.dp))
                .clickable(enabled = switchable, onClickLabel = "Switch instrument") { open = true }
                .padding(end = 8.dp)
                .testTag("fst.song-leaderboard.instrument"),
        ) {
            InstrumentIcon(current, size = 32.dp, decorative = true)
            Text(
                current.label,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.padding(start = 10.dp),
            )
            if (switchable) Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = BrandTokens.textPrimary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.popupTestTags().testTag("fst.song-leaderboard.instrument-menu")) {
            charts.forEach { chart ->
                DropdownMenuItem(
                    text = { Text(chart.label, fontWeight = if (chart == current) FontWeight.Bold else null) },
                    leadingIcon = { InstrumentIcon(chart, size = 24.dp, decorative = true) },
                    onClick = {
                        open = false
                        if (chart != current) onSelect(chart)
                    },
                    modifier = Modifier.testTag("fst.song-leaderboard.instrument.${chart.wireId}").semantics { selected = chart == current },
                )
            }
        }
    }
}

// endregion
