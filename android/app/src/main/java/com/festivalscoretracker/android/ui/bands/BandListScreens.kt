package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.PlayerBandsViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Shared grid

/**
 * The band route a player-band row opens, carrying the type and team key (the only safe lookup).
 *
 * @param entry Wire row.
 * @return Band Detail route.
 */
internal fun bandRouteFor(entry: PlayerBandEntry): AppRoute = BandRoute(entry.key, entry.membersLabel, entry.bandType, entry.teamKey)

/**
 * Adaptive card grid with full-width header rows; column count keeps an even split around a hinge.
 *
 * @param padding Shell padding.
 * @param tag Test tag.
 * @param content Grid content.
 */
@Composable
private fun BandGrid(padding: PaddingValues, tag: String, content: LazyGridScope.() -> Unit) {
    val hingeSplit = currentWindowAdaptiveInfo().windowPosture.hingeList.any { it.isSeparating && it.isVertical }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = bandGridColumns(maxWidth - 32.dp, hingeSplit)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = padding.calculateTopPadding(),
                bottom = padding.calculateBottomPadding() + 24.dp,
            ),
            horizontalArrangement = Arrangement.spacedBy(if (hingeSplit) 32.dp else 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize().testTag(tag),
            content = content,
        )
    }
}

/**
 * A full-width grid row.
 *
 * @param key Stable key.
 * @param content Row content.
 */
private fun LazyGridScope.fullRow(key: String, content: @Composable () -> Unit) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }) { content() }
}

// endregion

// region Bands landing

/**
 * `/bands`: no band-name search (the service's band search can write on a GET,
 * service-safety.md). Shows the selected player's bands preview with View All,
 * Band Rankings per size, and a footnote explaining the missing search.
 *
 * @param player Selected player, if any.
 * @param preview Six-row preview for [player] (keyed by account so it resets on change).
 * @param onNavigate Push a route.
 */
@Composable
fun BandsLandingScreen(player: SelectedPlayer?, preview: PlayerBandsViewModel?, onNavigate: (AppRoute) -> Unit) {
    val shell = LocalShellActions.current
    FestivalScreen(title = "Bands", isRoot = false, modifier = Modifier.testTag("fst.bands.screen")) { padding ->
        BandGrid(padding, "fst.bands.list") {
            fullRow("header") {
                BandPageHeader(null, "Band lineups, rankings and band scores", "fst.bands")
            }
            if (player != null && preview != null) {
                yourBands(player, preview, onNavigate)
            } else {
                fullRow("no-player") {
                    GlassCard(Modifier.fillMaxWidth().testTag("fst.bands.select-player")) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text("Your Bands", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                            Text(
                                "Select a player profile to see the bands they have played in.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = BrandTokens.textSecondary,
                            )
                            FilledTonalButton(onClick = shell.openProfile, modifier = Modifier.heightIn(min = 48.dp)) { Text("Select Player") }
                        }
                    }
                }
            }
            fullRow("rankings-header") { SectionHeader("Band Rankings") }
            items(BandType.entries, key = { "rankings-${it.wireId}" }) { type ->
                GlassCard(
                    Modifier
                        .fillMaxWidth()
                        .testTag("fst.bands.rankings.${type.wireId}")
                        .semantics(mergeDescendants = true) { contentDescription = "${type.label} rankings, ${rankingsDescription(type)}" },
                    onClick = { onNavigate(BandRankingsRoute(type.wireId)) },
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Outlined.Groups, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.size(28.dp))
                        Column(Modifier.weight(1f)) {
                            Text("${type.label} Rankings", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                            Text(rankingsDescription(type), style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
                        }
                    }
                }
            }
            fullRow("footnote") {
                Row(
                    Modifier.fillMaxWidth().padding(top = 8.dp).testTag("fst.bands.footnote"),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Outlined.Info, contentDescription = null, tint = BrandTokens.textMuted, modifier = Modifier.size(18.dp))
                    Text(SEARCH_FOOTNOTE, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textMuted)
                }
            }
        }
    }
}

/** Why the landing has no band search. */
internal const val SEARCH_FOOTNOTE =
    "Band search isn't available in the app: looking a band up by name can change data on the service. " +
        "Open bands from a player's band list, Band Rankings or a song's band leaderboard instead."

/**
 * One-line description of a band-size ranking.
 *
 * @param type Band size.
 * @return Description.
 */
internal fun rankingsDescription(type: BandType): String = "${type.memberCount}-player bands ranked across every song"

private fun LazyGridScope.yourBands(player: SelectedPlayer, preview: PlayerBandsViewModel, onNavigate: (AppRoute) -> Unit) {
    fullRow("your-header") {
        SectionHeader("${player.displayName}'s Bands", Modifier.testTag("fst.bands.your-bands-section"))
    }
    fullRow("your-state") { YourBandsState(player, preview, onNavigate) }
}

@Composable
private fun YourBandsState(player: SelectedPlayer, preview: PlayerBandsViewModel, onNavigate: (AppRoute) -> Unit) {
    val state by preview.bands.collectAsStateWithLifecycle()
    when (val current = state) {
        LoadState.Loading -> Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.Center) {
            CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading bands" })
        }
        is LoadState.Failed -> ServiceStatusInline(current.issue, "Bands unavailable", current.countdown, preview::retry)
        is LoadState.Loaded -> {
            val list = current.value
            if (list.entries.isEmpty()) {
                BandEmptyState("No bands found", "No bands have been recorded for this player yet.", "fst.bands.your-bands-empty")
            } else {
                // A nested lazy grid is not allowed; the preview is at most six cards, laid out in a flow.
                BoxWithConstraints(Modifier.fillMaxWidth().testTag("fst.bands.your-bands-list")) {
                    val columns = bandGridColumns(maxWidth, false)
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        list.entries.chunked(columns).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                row.forEach { entry -> PlayerBandCard(entry, { onNavigate(bandRouteFor(entry)) }, Modifier.weight(1f)) }
                                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                            }
                        }
                        BandTextLink("View All ${BandFormatting.count(list.totalCount.toLong())} Bands", "fst.bands.your-bands") {
                            onNavigate(PlayerBandsRoute(player.accountId, player.displayName))
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Player bands

/**
 * `/bands/player/:accountId`: group segmented control (All Bands · Duos · Trios ·
 * Quads, in place of the web filter sheet), adaptive card grid and pager.
 *
 * @param viewModel List logic.
 * @param title `<Name>'s Bands` or `Player Bands`.
 * @param onNavigate Push a route.
 */
@Composable
fun PlayerBandsScreen(viewModel: PlayerBandsViewModel, title: String, onNavigate: (AppRoute) -> Unit) {
    val state by viewModel.bands.collectAsStateWithLifecycle()
    val group by viewModel.group.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    FestivalScreen(title = title, isRoot = false, modifier = Modifier.testTag("fst.player-bands.screen")) { padding ->
        if (!viewModel.isValidAccount) {
            BandEmptyState("Player not found", "This link doesn't name a valid player.", "fst.player-bands.invalid")
            return@FestivalScreen
        }
        val loaded = (state as? LoadState.Loaded)?.value
        BandGrid(padding, "fst.player-bands.list") {
            fullRow("header") {
                val subtitle = loaded?.let { "${group.label} · ${BandFormatting.count(it.totalCount.toLong())} ${if (it.totalCount == 1) "band" else "bands"}" }
                BandPageHeader(null, subtitle, "fst.player-bands")
            }
            fullRow("groups") {
                BandSegmentedControl(
                    options = PlayerBandGroup.entries,
                    selected = group,
                    label = { if (it == PlayerBandGroup.All) "All" else it.label },
                    tag = { "fst.player-bands.group.${it.wireId}" },
                    onSelect = viewModel::selectGroup,
                    modifier = Modifier.testTag("fst.player-bands.group-picker"),
                )
            }
            when (val current = state) {
                LoadState.Loading -> fullRow("loading") { LoadingView("Loading bands", Modifier.heightIn(min = 240.dp)) }
                is LoadState.Failed -> fullRow("error") {
                    ServiceStatusView(current.issue, "Bands unavailable", current.countdown, viewModel::retry, Modifier.height(360.dp).testTag("fst.player-bands.error"))
                }
                is LoadState.Loaded -> {
                    val list = current.value
                    if (list.entries.isEmpty()) {
                        fullRow("empty") {
                            val noun = if (group == PlayerBandGroup.All) "bands" else group.label.lowercase()
                            BandEmptyState("No bands found", "No $noun have been recorded for this player yet.", "fst.player-bands.empty")
                        }
                    }
                    items(list.entries, key = { it.key }) { entry -> PlayerBandCard(entry, { onNavigate(bandRouteFor(entry)) }) }
                    fullRow("pager") { BandPager(page, list.pageCount(viewModel.pageSize), "fst.player-bands", viewModel::goTo) }
                }
            }
        }
    }
}

/**
 * Title for Player Bands: the route/selected name, else the account's own member row, else `Player Bands`.
 *
 * @param routeName Name carried by the route.
 * @param selected Selected player.
 * @param accountId Listed account.
 * @param entries Loaded rows.
 * @return Title.
 */
internal fun playerBandsTitle(routeName: String?, selected: SelectedPlayer?, accountId: String, entries: List<PlayerBandEntry>): String {
    val name = routeName?.trim()?.takeIf { it.isNotEmpty() }
        ?: selected?.takeIf { it.accountId == accountId }?.displayName
        ?: entries.asSequence().flatMap { it.members }.firstOrNull { it.accountId == accountId && !it.displayName.isNullOrBlank() }?.resolvedName
    return if (name != null) "$name's Bands" else "Player Bands"
}

// endregion
