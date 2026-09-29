package com.festivalscoretracker.android.ui.compete

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridScope
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.festivalscoretracker.android.ui.leaderboards.rememberAccountColumns
import com.festivalscoretracker.android.ui.leaderboards.RowSeparator
import com.festivalscoretracker.android.ui.leaderboards.LocalRankingColumns
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.core.compete.CompeteScope
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.compete.CompeteBoard
import com.festivalscoretracker.android.presentation.compete.CompeteSection
import com.festivalscoretracker.android.presentation.compete.CompeteViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.bands.windowWidthDp
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.leaderboards.AccountRankingRow
import com.festivalscoretracker.android.ui.leaderboards.RankingsSkeletonRows
import com.festivalscoretracker.android.ui.rivals.AdaptiveCardGrid
import com.festivalscoretracker.android.ui.rivals.RivalCardFailure
import com.festivalscoretracker.android.ui.rivals.RivalCardLoading
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Compete

/**
 * Compete hub (`/compete`, web `CompetePage`): a Leaderboards group (Top 10 Total
 * Score per supported scope with the player's own row) and a Rivals group (3 above /
 * 3 below per scope), with Quick Links for the two groups (shared `QuickLinksAction`).
 *
 * @param viewModel Page logic.
 * @param isRoot Whether shown as the phone tab root.
 */
@Composable
fun CompeteScreen(viewModel: CompeteViewModel, isRoot: Boolean) {
    val shell = LocalShellActions.current
    val content by viewModel.content.collectAsStateWithLifecycle()
    val gridState = rememberLazyStaggeredGridState()
    val rivalsIndex = 1 + content.sections.size
    // Web: the two groups once the page has content (no full-page failure).
    val sections = if (content.fullPageIssue == null) RivalQuickLinks.compete() else emptyList()
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", sections) { id ->
        when (id) {
            RivalQuickLinks.COMPETE_LEADERBOARDS -> 0
            RivalQuickLinks.COMPETE_RIVALS -> rivalsIndex
            else -> null
        }
    }
    FestivalScreen(
        title = CompeteText.TITLE,
        isRoot = isRoot,
        actions = { QuickLinksAction(quickLinks, windowWidthDp().toInt()) },
    ) { padding ->
        val issue = content.fullPageIssue
        if (issue != null) {
            ServiceStatusView(issue, "Compete unavailable", content.countdown, viewModel::retryFailed, contentPadding = padding)
            return@FestivalScreen
        }
        val selected = shell.selectedPlayer?.accountId
        AdaptiveCardGrid(
            contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
            state = gridState,
            testTag = "fst.compete.grid",
        ) {
            groupHeader("leaderboards", CompeteText.LEADERBOARDS)
            content.sections.forEach { section ->
                item(key = "board:${section.scope.key}") {
                    BoardCard(section, selected, viewModel, shell.navigate)
                }
            }
            groupHeader("rivals", CompeteText.RIVALS)
            content.sections.forEach { section ->
                item(key = "rivals:${section.scope.key}") {
                    RivalsCard(section, viewModel, shell.navigate)
                }
            }
        }
    }
}

private fun LazyStaggeredGridScope.groupHeader(id: String, title: String) {
    item(key = "header:$id", span = StaggeredGridItemSpan.FullLine) {
        Text(
            title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(top = 8.dp).testTag("fst.compete.section.$id").semantics { heading() },
        )
    }
}

@Composable
private fun ScopeHeader(scope: CompeteScope, onSeeAll: (() -> Unit)?, tag: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            // Web `InstrumentHeader` SM: 36 dp icons above the card.
            scope.instruments.forEach { InstrumentIcon(it, size = 36.dp, decorative = true) }
        }
        Text(
            scope.label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        if (onSeeAll != null) {
            TextButton(
                onClick = onSeeAll,
                modifier = Modifier.heightIn(min = 48.dp).testTag(tag).semantics { contentDescription = "${RivalText.SEE_ALL}: ${scope.label}" },
            ) { Text(RivalText.SEE_ALL) }
        }
    }
}

@Composable
private fun EmptyCard(title: String, subtitle: String) {
    GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        }
    }
}

@Composable
private fun BoardCard(section: CompeteSection, selected: String?, viewModel: CompeteViewModel, navigate: (AppRoute) -> Unit) {
    val scope = section.scope
    val board = (section.board as? LoadState.Loaded<CompeteBoard>)?.value
    // Only single charts have a native full board; combo boards stay previews.
    val fullBoard: (() -> Unit)? = (scope as? CompeteScope.Single)?.takeIf { board?.hasNavigation == true }?.let {
        { navigate(FullRankingsRoute(it.instrument.wireId, RankingMetric.TotalScore.wireId)) }
    }
    // The card item stays composed through loading, so a fresh board fades in (web stagger).
    val revealed = rememberRevealed(section.board is LoadState.Loaded)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.compete.leaderboard-card.${scope.key}")) {
        ScopeHeader(scope, fullBoard, "fst.compete.board.see-all.${scope.key}")
        when (val state = section.board) {
            LoadState.Loading -> GlassCard(Modifier.fillMaxWidth()) { RankingsSkeletonRows(5) }
            is LoadState.Failed -> RivalCardFailure(state.issue, "${scope.label} unavailable", state.countdown) { viewModel.retryBoard(scope.key) }
            is LoadState.Loaded -> {
                val value = state.value
                if (!value.hasNavigation) {
                    EmptyCard(CompeteText.NO_RANKINGS_TITLE, CompeteText.noRankings(scope.label))
                } else {
                    GlassCard(Modifier.fillMaxWidth()) {
                        CompositionLocalProvider(LocalRankingColumns provides rememberAccountColumns(value.entries + listOfNotNull(value.spotlight), RankingMetric.TotalScore)) {
                        Column(Modifier.padding(8.dp)) {
                            value.entries.forEachIndexed { index, entry ->
                                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1))) {
                                    if (index > 0) RowSeparator(Modifier.align(Alignment.TopCenter))
                                    AccountRankingRow(
                                        entry = entry,
                                        metric = RankingMetric.TotalScore,
                                        isSelected = RankingSpotlight.isSelected(selected, entry.accountId),
                                        route = RankingNavigation.playerRoute(entry.accountId, entry.displayName, selected),
                                        onOpen = navigate,
                                        tag = "fst.compete.rank.${scope.key}.${entry.key}",
                                    )
                                }
                            }
                            value.spotlight?.let { own ->
                                HorizontalDivider(color = BrandTokens.glassBorder, modifier = Modifier.padding(vertical = 4.dp))
                                AccountRankingRow(
                                    entry = own,
                                    metric = RankingMetric.TotalScore,
                                    isSelected = true,
                                    route = RankingNavigation.playerRoute(own.accountId, own.displayName, selected),
                                    onOpen = navigate,
                                    tag = "fst.compete.spotlight.${scope.key}",
                                )
                            }
                        }
                        }
                    }
                    if (fullBoard != null) {
                        ViewFullLeaderboardButton(
                            onClick = fullBoard,
                            modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(value.entries.size + 1)),
                            label = CompeteText.VIEW_FULL_LEADERBOARDS,
                            testTag = "fst.compete.view-full-leaderboards",
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RivalsCard(section: CompeteSection, viewModel: CompeteViewModel, navigate: (AppRoute) -> Unit) {
    val scope = section.scope
    val rows = (section.rivals as? LoadState.Loaded)?.value
    val seeAll: (() -> Unit)? = rows?.takeIf { it.isNotEmpty() }?.let { { navigate(RivalRoutes.allRivals(scope.rivalScope)) } }
    val revealed = rememberRevealed(section.rivals is LoadState.Loaded)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.compete.rivals-card.${scope.key}")) {
        ScopeHeader(scope, seeAll, "fst.compete.rivals.see-all.${scope.key}")
        when (val state = section.rivals) {
            null -> EmptyCard(CompeteText.NO_RIVALS_TITLE, CompeteText.trackForRivals(scope.label))
            LoadState.Loading -> RivalCardLoading("Loading ${scope.label} rivals")
            is LoadState.Failed -> RivalCardFailure(state.issue, "${scope.label} rivals unavailable", state.countdown) { viewModel.retryRivals(scope.key) }
            is LoadState.Loaded -> if (state.value.isEmpty()) {
                EmptyCard(CompeteText.NO_RIVALS_TITLE, CompeteText.noRivals(scope.label))
            } else {
                RivalPreviewRows(
                    rows = state.value,
                    onRival = { entry -> navigate(RivalRoutes.detail(entry.rival.accountId, entry.rival.displayName, scope.rivalScope)) },
                    onViewAll = seeAll,
                    viewAllLabel = CompeteText.VIEW_ALL_RIVALS,
                    revealed = revealed,
                )
            }
        }
    }
}

// endregion
