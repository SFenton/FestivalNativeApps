package com.festivalscoretracker.android.ui.rivals

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.PersonSearch
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.readingGroup
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalSettingsScope
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.ProfileSearchState
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalsHubContent
import com.festivalscoretracker.android.presentation.rivals.RivalsHubTab
import com.festivalscoretracker.android.presentation.rivals.RivalsHubViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.bands.windowWidthDp
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.ui.common.LoadSwapSpinner
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.isLargeText
import androidx.compose.material3.PrimaryScrollableTabRow
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Hub

/**
 * Rivals hub (`/rivals`, web `RivalsPage`): Song Rivals (Common, combo, per chart)
 * and Leaderboard Rivals tabs, Find Rival and Quick Links (web: one per card that has
 * rivals, for the current tab, once the tab has settled).
 *
 * @param viewModel Hub logic, or null with no selected player.
 * @param isRoot Whether shown as a tab root.
 * @param visibleCount Settings-visible charts (empty-state wording).
 * @param searchViewModel Find Rival search.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RivalsScreen(viewModel: RivalsHubViewModel?, isRoot: Boolean, visibleCount: Int, searchViewModel: ProfileSearchViewModel) {
    val shell = LocalShellActions.current
    var findOpen by rememberSaveable { mutableStateOf(false) }
    val gridState = rememberLazyStaggeredGridState()
    val tab = viewModel?.tab?.collectAsStateWithLifecycle()?.value ?: RivalsHubTab.Song
    val content = viewModel?.let {
        (if (tab == RivalsHubTab.Song) it.songContent else it.leaderboardContent).collectAsStateWithLifecycle().value
    }
    val cards = content?.takeIf { it.settled && it.fullPageIssue == null }?.sections.orEmpty()
    val sections = cards
        .filter { (it.state as? LoadState.Loaded)?.value?.isNotEmpty() == true }
        .map { RivalQuickLinks.hub(it.id, it.title, it.instrument) }
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", sections) { id -> cards.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    FestivalScreen(
        title = "Rivals",
        isRoot = isRoot,
        actions = {
            if (viewModel != null) {
                IconButton(onClick = { findOpen = true }, modifier = Modifier.testTag("fst.rivals.findRival")) {
                    Icon(Icons.Outlined.PersonSearch, contentDescription = RivalText.FIND_RIVAL)
                }
                QuickLinksAction(quickLinks, windowWidthDp().toInt())
            }
        },
    ) { padding ->
        if (viewModel == null || content == null) {
            Box(Modifier.padding(padding)) {
                RivalsMessage(RivalText.NO_PLAYER, null, "fst.rivals.chooseProfile", shell.openProfile, "Select Player")
            }
            return@FestivalScreen
        }
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            val tabs: @Composable () -> Unit = {
                RivalsHubTab.entries.forEach { entry ->
                    Tab(
                        selected = entry == tab,
                        onClick = { viewModel.select(entry) },
                        text = { Text(entry.title) },
                        modifier = Modifier.testTag("fst.rivals.tab.${entry.name.lowercase()}"),
                    )
                }
            }
            if (isLargeText()) {
                // Large text: "Leaderboard Rivals" no longer fits half the width (it broke
                // mid-word), so the tabs size to their labels and scroll (Material scrollable tabs).
                PrimaryScrollableTabRow(
                    selectedTabIndex = tab.ordinal,
                    containerColor = Color.Transparent,
                    contentColor = BrandTokens.textPrimary,
                    edgePadding = 16.dp,
                    modifier = Modifier.testTag("fst.rivals.tab"),
                    tabs = tabs,
                )
            } else {
                PrimaryTabRow(
                    selectedTabIndex = tab.ordinal,
                    containerColor = Color.Transparent,
                    contentColor = BrandTokens.textPrimary,
                    modifier = Modifier.testTag("fst.rivals.tab"),
                    tabs = tabs,
                )
            }
            HubBody(
                viewModel = viewModel,
                tab = tab,
                content = content,
                visibleCount = visibleCount,
                gridState = gridState,
                bottomPadding = padding.calculateBottomPadding(),
                navigate = shell.navigate,
            )
        }
    }
    if (findOpen && viewModel != null) {
        FindRivalSheet(
            searchViewModel = searchViewModel,
            selectedPlayer = shell.selectedPlayer,
            onSelect = { result ->
                findOpen = false
                shell.navigate(RivalRoutes.detail(result.accountId, result.displayName, RivalScope.FromSettings(RivalSettingsScope.All), allowLiveFallback = true))
            },
            onDismiss = { findOpen = false },
        )
    }
}

@Composable
private fun HubBody(
    viewModel: RivalsHubViewModel,
    tab: RivalsHubTab,
    content: RivalsHubContent,
    visibleCount: Int,
    gridState: androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState,
    bottomPadding: androidx.compose.ui.unit.Dp,
    navigate: (AppRoute) -> Unit,
) {
    // First loads and tab switches run the shared load swap (issue #71): the old tab fades out,
    // the spinner shows until the new tab settles, then its cards stagger in. A return visit
    // (already settled) shows at once.
    val swap = rememberLoadSwap(tab to content, content.settled || content.fullPageIssue != null, key = tab)
    val (shownTab, shown) = swap.shown
    val issue = shown.fullPageIssue
    val pageRevealed = swap.revealed
    if (swap.showsSpinner) {
        LoadSwapSpinner(swap, "Loading rivals", Modifier.fillMaxSize(), "fst.rivals.loading")
        return
    }
    Box(Modifier.fillMaxSize().then(swap.contentModifier)) { HubContent(viewModel, shownTab, shown, issue, pageRevealed, visibleCount, gridState, bottomPadding, navigate) }
}

@Composable
private fun HubContent(
    viewModel: RivalsHubViewModel,
    tab: RivalsHubTab,
    content: RivalsHubContent,
    issue: ServiceIssue?,
    pageRevealed: Boolean,
    visibleCount: Int,
    gridState: androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState,
    bottomPadding: androidx.compose.ui.unit.Dp,
    navigate: (AppRoute) -> Unit,
) {
    when {
        issue != null -> ServiceStatusView(issue, "Rivals unavailable", content.countdown, viewModel::retryFailed)
        content.empty -> if (tab == RivalsHubTab.Song) {
            RivalsMessage(RivalText.NO_RIVALS, RivalText.noRivalsSubtitle(visibleCount), "fst.rivals.empty")
        } else {
            RivalsMessage(RivalText.LEADERBOARD_EMPTY, null, "fst.rivals.empty")
        }
        else -> AdaptiveCardGrid(
            contentPadding = PaddingValues(top = 12.dp, bottom = bottomPadding + 24.dp),
            state = gridState,
            testTag = "fst.rivals.grid",
        ) {
            content.sections.forEach { section ->
                item(key = section.id) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.rivals.section.${section.id}").readingGroup()) {
                        val seeAll = { navigate(RivalRoutes.allRivals(section.seeAll)) }
                        val loaded = section.state as? LoadState.Loaded
                        val sectionRevealed = rememberRevealed(loaded != null)
                        RivalSectionHeader(
                            title = section.title,
                            instrument = section.instrument,
                            onSeeAll = if (loaded != null) seeAll else null,
                            seeAllTag = "fst.rivals.see-all.${section.id}",
                        )
                        when (val state = section.state) {
                            LoadState.Loading -> RivalCardLoading("Loading ${section.title}")
                            is LoadState.Failed -> RivalCardFailure(state.issue, "${section.title} unavailable", state.countdown) { viewModel.retry(section.id) }
                            is LoadState.Loaded -> RivalPreviewRows(
                                rows = state.value,
                                onRival = { entry -> navigate(RivalRoutes.detail(entry.rival.accountId, entry.rival.displayName, section.rowScope)) },
                                onViewAll = seeAll,
                                revealed = pageRevealed && sectionRevealed,
                            )
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Find Rival

/**
 * Find Rival (web `SearchModal` with player targets): the allowlisted account search;
 * the selected player is excluded. Picking a result opens Rival Detail with live fallback.
 *
 * @param searchViewModel Debounced search.
 * @param selectedPlayer Selected player, hidden from results.
 * @param onSelect Chosen account.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FindRivalSheet(
    searchViewModel: ProfileSearchViewModel,
    selectedPlayer: SelectedPlayer?,
    onSelect: (SelectedPlayer) -> Unit,
    onDismiss: () -> Unit,
) {
    FestivalModalSheet(
        title = RivalText.FIND_RIVAL,
        closeTag = "fst.rivals.find.close",
        onDismissRequest = onDismiss,
        skipPartiallyExpanded = false,
        modifier = Modifier.testTag("fst.rivals.find.sheet"),
    ) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp)) {
            val query by searchViewModel.query.collectAsStateWithLifecycle()
            val state by searchViewModel.state.collectAsStateWithLifecycle()
            TextField(
                value = query,
                onValueChange = searchViewModel::onQueryChange,
                singleLine = true,
                placeholder = { Text("Epic display name") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                shape = RoundedCornerShape(28.dp),
                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
                modifier = Modifier.fillMaxWidth().testTag("fst.rivals.find.search"),
            )
            Box(Modifier.fillMaxWidth().heightIn(min = 160.dp).padding(top = 12.dp)) {
                when (val current = state) {
                    // Find Rival searches players only; the band-mode state never applies.
                    ProfileSearchState.Hint, ProfileSearchState.BandsUnavailable -> Text(
                        "Enter at least 2 characters",
                        color = BrandTokens.textSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.align(Alignment.Center),
                    )
                    ProfileSearchState.Searching -> FestivalLoading("Searching", Modifier.align(Alignment.Center), size = 32.dp)
                    is ProfileSearchState.Failed -> ServiceStatusInline(current.issue, "Player search unavailable", null, searchViewModel::retry)
                    is ProfileSearchState.Results -> Column {
                        val results = current.results.filter { it.accountId != selectedPlayer?.accountId }
                        if (results.isEmpty()) Text("No players found", color = BrandTokens.textSecondary, modifier = Modifier.padding(8.dp))
                        results.forEach { result ->
                            Row(
                                Modifier
                                    .testTag("fst.rivals.find.result.${result.accountId}")
                                    .fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .clickable(role = Role.Button) { SelectedPlayer.validated(result.accountId, result.displayName)?.let(onSelect) }
                                    .padding(vertical = 14.dp, horizontal = 8.dp),
                            ) {
                                Text(result.displayName, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                    }
                }
            }
        }
    }
}

// endregion
