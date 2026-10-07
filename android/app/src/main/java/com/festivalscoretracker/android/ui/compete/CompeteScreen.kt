package com.festivalscoretracker.android.ui.compete

import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridScope
import androidx.compose.foundation.lazy.staggeredgrid.LazyStaggeredGridState
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import com.festivalscoretracker.android.ui.design.readingGroup
import com.festivalscoretracker.android.ui.leaderboards.rememberAccountColumns
import com.festivalscoretracker.android.ui.leaderboards.rememberRankingRowWidth
import com.festivalscoretracker.android.ui.leaderboards.RowSeparator
import com.festivalscoretracker.android.ui.leaderboards.LocalRankingColumns
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.core.compete.CompeteHeaderLayout
import com.festivalscoretracker.android.core.compete.CompeteScope
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingSpotlight
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.compete.CompeteBoard
import com.festivalscoretracker.android.presentation.compete.CompeteContent
import com.festivalscoretracker.android.presentation.compete.CompeteSection
import com.festivalscoretracker.android.presentation.compete.CompeteStaggerPlan
import com.festivalscoretracker.android.presentation.compete.CompeteViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadSwapSpinner
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.bands.windowWidthDp
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.leaderboards.AccountRankingRow
import com.festivalscoretracker.android.ui.rivals.AdaptiveCardGrid
import com.festivalscoretracker.android.ui.rivals.RivalCardFailure
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import com.festivalscoretracker.android.ui.theme.BrandTokens
import androidx.compose.foundation.layout.RowScope
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.SeeAllButton

// region Compete

/**
 * Compete hub (`/compete`, web `CompetePage`): a Leaderboards group (Top 10 Total
 * Score per supported scope with the player's own row) and a Rivals group (3 above /
 * 3 below per scope), with Quick Links for the two groups (shared `QuickLinksAction`).
 *
 * The page runs the shared load swap (load-transition R1, #354; web `usePageTransition` waits
 * for every leaderboard and rivals query): one centred spinner and no headers until every read
 * has finished (or every board failed), then the spinner fades and the headers and cards fade in
 * with one page-wide stagger ([CompeteStaggerPlan]). A return with loaded data shows at once,
 * and a retry runs the same swap, so no card ever shows a spinner under its header.
 *
 * @param viewModel Page logic.
 * @param isRoot Whether shown as the phone tab root.
 */
@Composable
fun CompeteScreen(viewModel: CompeteViewModel, isRoot: Boolean) {
    val latest by viewModel.content.collectAsStateWithLifecycle()
    val swap = rememberLoadSwap(latest, latest.ready)
    val content = swap.shown
    val gridState = rememberLazyStaggeredGridState()
    val rivalsIndex = 1 + content.sections.size
    // Web: the two groups once the page's content is in (no full-page failure).
    val sections = if (swap.showsContent && content.fullPageIssue == null) RivalQuickLinks.compete() else emptyList()
    // The page's fade window, here so Quick Links jumps rush it (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    val quickLinks = rememberQuickLinks(gridState, "Quick Links", sections, fadeInWindow = fadeIn) { id ->
        when (id) {
            RivalQuickLinks.COMPETE_LEADERBOARDS -> 0
            RivalQuickLinks.COMPETE_RIVALS -> rivalsIndex
            else -> null
        }
    }
    FestivalScreen(
        title = CompeteText.TITLE,
        isRoot = isRoot,
        fadeInWindow = fadeIn,
        actions = { QuickLinksAction(quickLinks, windowWidthDp().toInt()) },
    ) { padding ->
        if (swap.showsSpinner) {
            LoadSwapSpinner(swap, CompeteText.LOADING, Modifier.fillMaxSize().padding(padding), "fst.compete.loading")
            return@FestivalScreen
        }
        // Fading out for a retry: already stale, so TalkBack no longer reads it (load-transition R2).
        val fading = if (swap.phase == LoadSwapPhase.ContentOut) Modifier.clearAndSetSemantics { } else Modifier
        Box(Modifier.fillMaxSize().then(swap.contentModifier).then(fading)) {
            val issue = content.fullPageIssue
            if (issue != null) {
                ServiceStatusView(issue, "Compete unavailable", content.countdown, viewModel::retryFailed, contentPadding = padding)
            } else {
                CompeteGrid(content, padding, gridState, viewModel, swap.revealed)
            }
        }
    }
}

/**
 * The two groups' headers and cards.
 *
 * @param content Page state as shown.
 * @param padding Screen insets.
 * @param gridState Grid scroll state (kept across swaps for Quick Links).
 * @param viewModel Page logic.
 * @param revealed The page swap's reveal flag ([festivalFadeIn]).
 */
@Composable
private fun CompeteGrid(content: CompeteContent, padding: PaddingValues, gridState: LazyStaggeredGridState, viewModel: CompeteViewModel, revealed: Boolean) {
    val shell = LocalShellActions.current
    val selected = shell.selectedPlayer?.accountId
    val order = content.stagger
    AdaptiveCardGrid(
        contentPadding = PaddingValues(top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp),
        state = gridState,
        testTag = "fst.compete.grid",
    ) {
        groupHeader("leaderboards", CompeteText.LEADERBOARDS, revealed, order.leaderboardsHeader)
        content.sections.forEachIndexed { index, section ->
            item(key = "board:${section.scope.key}") {
                Box(Modifier.readingGroup()) { BoardCard(section, selected, viewModel, shell.navigate, revealed, order.boards[index]) }
            }
        }
        groupHeader("rivals", CompeteText.RIVALS, revealed, order.rivalsHeader)
        content.sections.forEachIndexed { index, section ->
            item(key = "rivals:${section.scope.key}") {
                Box(Modifier.readingGroup()) { RivalsCard(section, viewModel, shell.navigate, revealed, order.rivals[index]) }
            }
        }
    }
}

private fun LazyStaggeredGridScope.groupHeader(id: String, title: String, revealed: Boolean, stagger: Int) {
    item(key = "header:$id", span = StaggeredGridItemSpan.FullLine) {
        // A full-line item spans a separating hinge; the Box lets the heading (and its TalkBack
        // focus) hug the text in the first panel instead.
        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(stagger))) {
            Text(
                title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.padding(top = 8.dp).testTag("fst.compete.section.$id").semantics { heading() },
            )
        }
    }
}

@Composable
private fun ScopeHeader(scope: CompeteScope, onSeeAll: (() -> Unit)?, tag: String, modifier: Modifier = Modifier) {
    val icons: @Composable () -> Unit = {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            // Web `InstrumentHeader` SM: 36 dp icons above the card.
            scope.instruments.forEach { InstrumentIcon(it, size = 36.dp, decorative = true) }
        }
    }
    val titleAndLink: @Composable RowScope.() -> Unit = {
        Text(
            scope.label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        // The shared "View All ›" link (white, bold, chevron; read once as "View All: <scope>").
        if (onSeeAll != null) SeeAllButton(onClick = onSeeAll, section = scope.label, modifier = Modifier.testTag(tag))
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val stacked = CompeteHeaderLayout.stacks(maxWidth.value, scope.instruments.size, onSeeAll != null, isLargeText())
        if (stacked) {
            // Large text or a narrow lane: a four-instrument combo name needs the full width below its icons.
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.fillMaxWidth().testTag("fst.compete.scope-header.stacked")) {
                icons()
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = titleAndLink)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().testTag("fst.compete.scope-header.row")) {
                icons()
                titleAndLink()
            }
        }
    }
}

@Composable
private fun EmptyCard(title: String, subtitle: String, modifier: Modifier = Modifier) {
    GlassCard(modifier.fillMaxWidth()) {
        // One TalkBack stop for the title and its explanation.
        Column(Modifier.padding(16.dp).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        }
    }
}

/**
 * One scope's leaderboard card: its header, then rows, the player's row and View Full
 * Leaderboards (or empty copy, or an inline error), each fading in at its place in the page order.
 *
 * @param section Scope state.
 * @param selected Selected account, highlighted in the rows.
 * @param viewModel Page logic (retry).
 * @param navigate Navigation.
 * @param revealed The page swap's reveal flag ([festivalFadeIn]).
 * @param stagger Entrance index of the header; the body follows ([CompeteStaggerPlan]).
 */
@Composable
private fun BoardCard(section: CompeteSection, selected: String?, viewModel: CompeteViewModel, navigate: (AppRoute) -> Unit, revealed: Boolean, stagger: Int) {
    val scope = section.scope
    val board = (section.board as? LoadState.Loaded<CompeteBoard>)?.value
    // Only single charts have a native full board; combo boards stay previews.
    val fullBoard: (() -> Unit)? = (scope as? CompeteScope.Single)?.takeIf { board?.hasNavigation == true }?.let {
        { navigate(FullRankingsRoute(it.instrument.wireId, RankingMetric.TotalScore.wireId)) }
    }
    val body = stagger + 1
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.compete.leaderboard-card.${scope.key}")) {
        ScopeHeader(scope, fullBoard, "fst.compete.board.see-all.${scope.key}", Modifier.festivalFadeIn(revealed, fadeInStagger(stagger)))
        when (val state = section.board) {
            // The page swap shows content only once every read has settled (#354).
            LoadState.Loading -> Unit
            is LoadState.Failed -> Box(Modifier.festivalFadeIn(revealed, fadeInStagger(body))) {
                RivalCardFailure(state.issue, "${scope.label} unavailable", state.countdown) { viewModel.retryBoard(scope.key) }
            }
            is LoadState.Loaded -> {
                val value = state.value
                if (!value.hasNavigation) {
                    EmptyCard(CompeteText.NO_RANKINGS_TITLE, CompeteText.noRankings(scope.label), Modifier.festivalFadeIn(revealed, fadeInStagger(body)))
                } else {
                    GlassCard(Modifier.fillMaxWidth()) {
                        // Rows fill this column, so its inner width is the row width the songs column must fit in (issue #38).
                        var rowWidth by rememberRankingRowWidth()
                        val density = LocalDensity.current
                        val columns = rememberAccountColumns(value.entries + listOfNotNull(value.spotlight), RankingMetric.TotalScore, fitNamesTo = rowWidth)
                        CompositionLocalProvider(LocalRankingColumns provides columns) {
                        Column(Modifier.padding(8.dp).onSizeChanged { rowWidth = with(density) { it.width.toDp().value } }) {
                            value.entries.forEachIndexed { index, entry ->
                                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(body + index))) {
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
                                Column(Modifier.festivalFadeIn(revealed, fadeInStagger(body + value.entries.size))) {
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
                    }
                    if (fullBoard != null) {
                        val rows = value.entries.size + (if (value.spotlight != null) 1 else 0)
                        ViewFullLeaderboardButton(
                            onClick = fullBoard,
                            modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(body + rows)),
                            label = CompeteText.VIEW_FULL_LEADERBOARDS,
                            testTag = "fst.compete.view-full-leaderboards",
                            cardName = scope.label,
                        )
                    }
                }
            }
        }
    }
}

/**
 * One scope's rivals card: its header, then three above / three below and View All Rivals (or
 * empty copy, or an inline error), each fading in at its place in the page order.
 *
 * @param section Scope state.
 * @param viewModel Page logic (retry).
 * @param navigate Navigation.
 * @param revealed The page swap's reveal flag ([festivalFadeIn]).
 * @param stagger Entrance index of the header; the body follows ([CompeteStaggerPlan]).
 */
@Composable
private fun RivalsCard(section: CompeteSection, viewModel: CompeteViewModel, navigate: (AppRoute) -> Unit, revealed: Boolean, stagger: Int) {
    val scope = section.scope
    val rows = (section.rivals as? LoadState.Loaded)?.value
    val seeAll: (() -> Unit)? = rows?.takeIf { it.isNotEmpty() }?.let { { navigate(RivalRoutes.allRivals(scope.rivalScope)) } }
    val body = stagger + 1
    val bodyFade = Modifier.festivalFadeIn(revealed, fadeInStagger(body))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.compete.rivals-card.${scope.key}")) {
        ScopeHeader(scope, seeAll, "fst.compete.rivals.see-all.${scope.key}", Modifier.festivalFadeIn(revealed, fadeInStagger(stagger)))
        when (val state = section.rivals) {
            null -> EmptyCard(CompeteText.NO_RIVALS_TITLE, CompeteText.trackForRivals(scope.label), bodyFade)
            // The page swap shows content only once every read has settled (#354).
            LoadState.Loading -> Unit
            is LoadState.Failed -> Box(bodyFade) {
                RivalCardFailure(state.issue, "${scope.label} rivals unavailable", state.countdown) { viewModel.retryRivals(scope.key) }
            }
            is LoadState.Loaded -> if (state.value.isEmpty()) {
                EmptyCard(CompeteText.NO_RIVALS_TITLE, CompeteText.noRivals(scope.label), bodyFade)
            } else {
                RivalPreviewRows(
                    rows = state.value,
                    onRival = { entry -> navigate(RivalRoutes.detail(entry.rival.accountId, entry.rival.displayName, scope.rivalScope)) },
                    onViewAll = seeAll,
                    viewAllLabel = CompeteText.VIEW_ALL_RIVALS,
                    revealed = revealed,
                    cardName = scope.label,
                    firstStagger = body,
                )
            }
        }
    }
}

// endregion
