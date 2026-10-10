package com.festivalscoretracker.android.ui.songdetail

import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import com.festivalscoretracker.android.ui.leaderboards.awaitSelectedRowEntrance
import com.festivalscoretracker.android.ui.design.popupTestTags
import androidx.compose.ui.semantics.selected
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.Icon
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
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
import androidx.compose.runtime.saveable.rememberSaveable
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import androidx.compose.runtime.withFrameNanos
import com.festivalscoretracker.android.core.rankings.SelectedRowAction
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.rankings.SelectedRowSubject
import com.festivalscoretracker.android.core.rankings.label
import com.festivalscoretracker.android.ui.leaderboards.SelectedRowAnchor
import com.festivalscoretracker.android.ui.leaderboards.revealSelectedRow
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
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
import androidx.compose.ui.unit.Dp
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.ui.background.SongCoverBackdrop
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
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.leaderboards.AnchoredRowCard
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardScaffold
import com.festivalscoretracker.android.ui.leaderboards.SyncRouteArguments
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
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
    SongLeaderboardScreen(
        boardViewModel, settings.selectedPlayer?.accountId, container.selectedProfile.state, leeway, settings.visibleInstruments, api::artworkUrl,
        background = container.background,
        revealSelected = route.navToPlayer,
        // Revealed once: Back or a recreated entry keeps the scroll position instead (web clears `navToPlayer`).
        onRevealed = { routeState?.set("navToPlayer", false) },
    )
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
 * @param background Shared backdrop: shows the song's static cover while the board is visible (pattern `song-leaderboard-header` R4, issue #317), or null.
 * @param revealSelected Opened for the selected player's row (web `navToPlayer`): bring it into view once its page shows.
 * @param onRevealed Called once that reveal has run (or found no row), so the route stops asking for it.
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
    background: BackgroundController? = null,
    revealSelected: Boolean = false,
    onRevealed: () -> Unit = {},
) {
    val song by viewModel.song.collectAsStateWithLifecycle()
    SongCoverBackdrop(background, (song as? LoadState.Loaded)?.value?.albumArt)
    val board by viewModel.board.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val navigate = LocalShellActions.current.navigate
    val listState = rememberLazyListState()
    val title = (song as? LoadState.Loaded)?.value?.title ?: "Leaderboard"
    // Page reloads fade the rows out, show the spinner and stagger the new page in, like the
    // web's PaginatedLeaderboard (issue #71). The pinned score depends on the chart and the
    // invalid-score leeway, never the page (web `footerAnimKey`, issue #190).
    val swap = rememberLoadSwap(board, board !is LoadState.Loading, key = page, pinnedKey = viewModel.instrument to leeway)
    val payload = (swap.shown as? LoadState.Loaded)?.value
    val loaded = payload?.leaderboard
    val profile = selectedProfile?.collectAsStateWithLifecycle()?.value
    val footer = payload?.let {
        SongScoreSpotlight.footer(
            player = profile?.player?.takeIf { player -> RankingSpotlight.isSelected(selectedAccountId, player.accountId) },
            score = profile?.scoreIndex?.get(it.leaderboard.songId)?.get(viewModel.instrument)?.let { raw ->
                if (leeway == null) raw else raw.effective((song as? LoadState.Loaded)?.value, viewModel.instrument, leeway)
            },
            scorePublicationId = profile?.observedPublicationId,
            boardPublicationId = it.publicationId,
        )
    }
    // The requested page's rows are on screen (not the previous page still showing over a fresh load, fading out or the spinner).
    val pageShown = swap.phase == LoadSwapPhase.ContentIn && board is LoadState.Loaded && swap.shown === board && loaded != null
    val selectedOnPage = pageShown && loaded.entries.any { RankingSpotlight.isSelected(selectedAccountId, it.accountId) }
    // `leaderboard-row` R7 (issue #307): the footer jumps to the player's page while their row is
    // elsewhere and opens Statistics once it is on screen. While a page loads, the rank decides.
    val footerAction = footer?.let {
        val visible = if (pageShown) selectedOnPage else it.rank > 0 && LeaderboardPaging.pageForRank(it.rank) == page
        SelectedRowAction.footer(it.rank, visible, page)
    }
    var revealPending by rememberSaveable { mutableStateOf(revealSelected) }
    val anchor = remember { SelectedRowAnchor() }
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    // The page's fade window, here so the reveal can rush the rows its scroll reaches (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()

    // The rows and the pinned footer share one column plan, fitted to the narrower of the two (issue #37, 7.9).
    val columns = rememberScoreColumns(loaded?.entries.orEmpty() + listOfNotNull(footer))

    LaunchedEffect(page) { listState.scrollToItem(0) }
    // Opened (or jumped) to the selected row's page: centre the highlighted row once it shows.
    LaunchedEffect(revealPending, pageShown, loaded) {
        if (!revealPending || !pageShown) return@LaunchedEffect
        if (selectedOnPage) {
            // Like the web's navToPlayer: scroll once the row's own entrance has finished (issue #323).
            val index = loaded.entries.indexOfFirst { RankingSpotlight.isSelected(selectedAccountId, it.accountId) }
            if (awaitSelectedRowEntrance(fadeIn, fadeInStagger(index), reduceMotion)) {
                withFrameNanos { }
                val bounds = anchor.bounds()
                if (bounds != null) listState.revealSelectedRow("rows", null, bounds.first, bounds.second, animate = !reduceMotion)
            }
        }
        revealPending = false
        onRevealed()
    }

    // The song header (art, title, artist, instrument) scrolls with the rows; the top bar
    // takes the title once it has scrolled away (operator 7.8, like Song Detail).
    val headerGone by remember(listState) { derivedStateOf { listState.firstVisibleItemIndex > 0 } }
    FestivalScreen(
        title = if (headerGone) title else "",
        isRoot = false,
        scrolled = headerGone,
        marqueeTitle = true,
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        fadeInWindow = fadeIn,
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
            controls = {
                val loadedSong = (song as? LoadState.Loaded)?.value
                loadedSong?.let { SongHeader(it, artworkUrl(it.albumArt), artSize = 64.dp) }
                val charts = loadedSong?.let { current -> Instrument.entries.filter { it in visibleInstruments && current.supports(it) } }.orEmpty()
                InstrumentSwitcher(viewModel.instrument, charts) { chart ->
                    loadedSong?.let { navigate(SongLeaderboardRoute(it.songId, chart.wireId)) }
                }
            },
            // The pinned score fades in with the first rows on the first load (issue #295) and
            // stays visible and usable in place with the pager while another page loads, like the
            // web footer (issues #93, #190). A leeway change hides it, unread and untouchable,
            // beside the spinner (issue #149) and re-reveals it with the new rows.
            footer = {
                footer?.let { entry ->
                    AnchoredRowCard(with(swap) { Modifier.pinnedStaggered(0) }.then(swap.pinnedContentModifier)) {
                        LeaderboardSectionMember(columns, "footer") {
                            SelectedScoreFooterRow(
                                entry = entry,
                                columns = columns.plan,
                                actionLabel = footerAction?.label(SelectedRowSubject.Player) ?: SelectedRowLabels.OPEN_STATISTICS,
                                tag = "fst.song-leaderboard.spotlight-footer",
                            ) {
                                when (val action = footerAction) {
                                    is SelectedRowAction.Jump -> {
                                        revealPending = true
                                        viewModel.goTo(action.page)
                                    }
                                    else -> navigate(StatisticsRoute)
                                }
                            }
                        }
                    }
                }
            },
            // No pager until this board's page count has loaded (a switched instrument is a new route), and none for one page (#575).
            pager = { RankingsPager(page, loaded?.pageCount(), "fst.song-leaderboard", viewModel::goTo) },
            // Rows fade out above the pinned score and pager, as on the web (issue #93).
            fadeAboveFooter = true,
        ) {
            if (swap.showsSpinner || loaded == null) {
                loadSwapSpinnerItem(swap, "Loading leaderboard", "fst.song-leaderboard.loading")
            } else item(key = "rows") {
                GlassCard(anchor.item.fillMaxWidth().then(swap.contentModifier)) {
                    // Same 8 dp horizontal inset as AnchoredRowCard, so the pinned row's columns line up (issue #37).
                    LeaderboardSectionMember(columns, "rows", Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
                        when {
                            loaded.entries.isEmpty() -> Text("No scores yet", color = BrandTokens.textPrimary, modifier = Modifier.padding(16.dp))
                            else -> {
                                loaded.entries.forEachIndexed { index, entry ->
                                    val selected = RankingSpotlight.isSelected(selectedAccountId, entry.accountId)
                                    // The reveal anchor sits outside the fade-in so it measures the settled row.
                                    Column((if (selected) anchor.row else Modifier).festivalFadeIn(swap.revealed, fadeInStagger(index))) {
                                        if (index > 0) RowSeparator()
                                        SongLeaderboardRow(
                                            entry = entry,
                                            isSelected = selected,
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
 * The selected profile's pinned footer row on a song board (web `LeaderboardPage` and
 * `SongBandLeaderboardPage` fixed footers; Apple `SelectedScoreFooterRow`): the shared
 * [ScoreRow] in the selected treatment, in the board's columns. Solo and band boards use
 * this one row, and its click follows [SelectedRowAction.footer] (`leaderboard-row` R7,
 * issue #307): jump to the row's page while it is elsewhere, otherwise open the profile.
 *
 * @param entry Footer row (the band's members as its name on a band board).
 * @param columns The board's shared column plan.
 * @param actionLabel TalkBack click label naming the destination ([SelectedRowLabels]).
 * @param tag Test tag.
 * @param onClick Jump or open.
 */
@Composable
internal fun SelectedScoreFooterRow(entry: LeaderboardEntry, columns: LeaderboardColumnPlan, actionLabel: String, tag: String, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .selectedRowHighlight(true)
            .clickable(role = Role.Button, onClickLabel = actionLabel, onClick = onClick)
            .testTag(tag),
    ) {
        ScoreRow(entry, isSelected = true, navigable = true, columns = columns)
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
 * @param modifier Modifier (the reveal anchor on the selected row).
 */
@Composable
private fun SongLeaderboardRow(
    entry: LeaderboardEntry,
    isSelected: Boolean,
    route: AppRoute?,
    onOpen: (AppRoute) -> Unit,
    columns: LeaderboardColumnPlan,
    modifier: Modifier = Modifier,
) {
    var rowModifier = modifier.fillMaxWidth().selectedRowHighlight(isSelected)
    rowModifier = if (route != null) {
        // "Open your statistics" for the selected player's row, "Open profile" otherwise.
        rowModifier.clickable(role = Role.Button, onClickLabel = RankingNavigation.actionLabel(route)) { onOpen(route) }
    } else {
        rowModifier.semantics(mergeDescendants = true) { stateDescription = "Profile unavailable" }
    }
    Box(rowModifier.testTag("fst.song-leaderboard.row.${entry.accountId.ifEmpty { "rank-${entry.rank}" }}")) {
        ScoreRow(entry, isSelected = isSelected, navigable = route != null, columns = columns)
    }
}


/**
 * The header's instrument (web instrument switcher): icon and name, on the shared
 * [SongBoardSwitcher].
 *
 * @param current Board's chart.
 * @param charts Settings-visible charts the song supports, in display order.
 * @param onSelect Opens the board for another chart.
 */
@Composable
internal fun InstrumentSwitcher(current: Instrument, charts: List<Instrument>, onSelect: (Instrument) -> Unit) {
    SongBoardSwitcher(
        current = current,
        options = charts,
        label = Instrument::label,
        id = Instrument::wireId,
        clickLabel = "Switch instrument",
        tag = "fst.song-leaderboard.instrument",
        icon = { chart, size -> InstrumentIcon(chart, size = size, decorative = true) },
        onSelect = onSelect,
    )
}

/**
 * The board line under a song leaderboard's [SongHeader] (pattern `song-leaderboard-header` R1): the
 * board's instrument on the solo board, its band size on the band board (issue #317).
 * With more than one option it is a 48 dp drop-down (TalkBack "drop down list") whose
 * menu switches the board and checks the current option; with a single option it is
 * plain text, not a disabled control (issue #104).
 *
 * @param current Board's option.
 * @param options Options in display order.
 * @param label Visible name.
 * @param id Stable wire ID for item test tags (`<tag>.<id>`).
 * @param clickLabel TalkBack click label of the anchor.
 * @param tag Anchor test tag; the menu is `<tag>-menu`.
 * @param icon Optional leading glyph (32 dp in the header, 24 dp in the menu), or null for text only.
 * @param onSelect Opens the board for another option.
 */
@Composable
internal fun <T> SongBoardSwitcher(
    current: T,
    options: List<T>,
    label: (T) -> String,
    id: (T) -> String,
    clickLabel: String,
    tag: String,
    icon: (@Composable (T, Dp) -> Unit)? = null,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val switchable = options.size > 1
    Box {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(12.dp))
                .then(
                    if (switchable) Modifier.clickable(role = Role.DropdownList, onClickLabel = clickLabel) { open = true }
                    else Modifier,
                )
                .padding(end = 8.dp)
                .testTag(tag),
        ) {
            icon?.invoke(current, 32.dp)
            Text(
                label(current),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = if (icon != null) Modifier.padding(start = 10.dp) else Modifier,
            )
            if (switchable) Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = BrandTokens.textPrimary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.popupTestTags().testTag("$tag-menu")) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option), fontWeight = if (option == current) FontWeight.Bold else null) },
                    leadingIcon = icon?.let { draw -> { draw(option, 24.dp) } },
                    // Same single-choice cue as the rankings' top-bar pickers.
                    trailingIcon = if (option == current) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                    onClick = {
                        open = false
                        if (option != current) onSelect(option)
                    },
                    modifier = Modifier.testTag("$tag.${id(option)}").semantics { selected = option == current },
                )
            }
        }
    }
}

// endregion
