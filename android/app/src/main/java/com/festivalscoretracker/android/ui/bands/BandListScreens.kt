package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.PlayerBandsViewModel
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.LoadSwapSpinner
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.common.rememberSingleColumn

// region Shared grid

/**
 * The band route a player-band row opens, carrying the type and team key (the only safe lookup).
 *
 * @param entry Wire row.
 * @return Band Detail route.
 */
internal fun bandRouteFor(entry: PlayerBandEntry): AppRoute = BandRoute(entry.key, entry.membersLabel, entry.bandType, entry.teamKey)

/**
 * Adaptive card grid with full-width header rows; with a vertical fold or hinge the
 * two columns meet exactly at it ([BandLayout.grid]). Across a **separating** hinge
 * (half-open book or passport fold) the [controls] move to a leading pane that ends at
 * the hinge and the cards fill a single column on the trailing side, so no segment,
 * header or pager straddles the crease ([BandLayout.listSplit]). Under TalkBack or at
 * large text the page is one centred column ([rememberSingleColumn]).
 *
 * @param padding Shell padding.
 * @param tag Test tag.
 * @param controls Header and selectors, above the cards or in the leading pane.
 * @param content Grid content (state rows, cards, pager).
 */
@Composable
private fun BandGrid(padding: PaddingValues, tag: String, controls: @Composable () -> Unit, content: LazyGridScope.() -> Unit) {
    var contentLeft by remember { mutableFloatStateOf(0f) }
    // One column under TalkBack or at large text, like every other content grid (rememberSingleColumn).
    val singleColumn = rememberSingleColumn()
    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { contentLeft = it.positionInWindow().x }) {
        val hinge = rememberBandHinge(contentLeft, maxWidth).takeUnless { singleColumn }
        val grid = if (singleColumn) BandLayout.Grid(1, BandLayout.EDGE, BandLayout.EDGE, BandLayout.GUTTER) else BandLayout.grid(maxWidth.value, hinge)
        val layout: @Composable () -> Unit = { PlayerBandsLayout(BandLayout.listSplit(hinge), grid, padding, tag, controls, content) }
        if (singleColumn) BandReadableWidth { layout() } else layout()
    }
}

/**
 * [BandGrid]'s layout for a given split and grid (separated for layout tests).
 *
 * @param split [BandLayout.listSplit] for the content box.
 * @param grid [BandLayout.grid] for the content box (single-pane only).
 * @param padding Shell padding.
 * @param tag Test tag of the card grid.
 * @param controls Header and selectors.
 * @param content Grid content.
 */
@Composable
internal fun PlayerBandsLayout(
    split: BandLayout.Panes,
    grid: BandLayout.Grid,
    padding: PaddingValues,
    tag: String,
    controls: @Composable () -> Unit,
    content: LazyGridScope.() -> Unit,
) {
    val top = padding.calculateTopPadding()
    val bottom = padding.calculateBottomPadding() + 24.dp
    val leading = split.leadingWidth
    if (split.twoPane && leading != null) {
        Row(Modifier.fillMaxSize()) {
            Column(
                Modifier
                    .width(leading.dp)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .padding(start = BandLayout.EDGE.dp, end = BandLayout.EDGE.dp, top = top, bottom = bottom)
                    .testTag("$tag.controls-pane"),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) { controls() }
            Spacer(Modifier.width(split.gap.dp))
            LazyVerticalGrid(
                columns = GridCells.Fixed(1),
                contentPadding = PaddingValues(start = BandLayout.EDGE.dp, end = BandLayout.EDGE.dp, top = top + 8.dp, bottom = bottom),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f).fillMaxHeight().testTag(tag),
                content = content,
            )
        }
    } else {
        LazyVerticalGrid(
            columns = GridCells.Fixed(grid.columns),
            contentPadding = PaddingValues(start = grid.start.dp, end = grid.end.dp, top = top, bottom = bottom),
            horizontalArrangement = Arrangement.spacedBy(grid.gutter.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize().testTag(tag),
        ) {
            fullRow("controls") { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { controls() } }
            content()
        }
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

// region Band not found

/** Web `band.notFound`. */
internal const val BAND_NOT_FOUND_TITLE = "Band not found"

/** Web `band.missingId`. */
internal const val BAND_MISSING_ID_MESSAGE = "This band link is missing an ID and cannot be resolved."

/**
 * `/bands` with no band id (web `BandPage` without an id or lookup context): the web's
 * "Band not found" empty state, built with the shared [FestivalEmptyState]. There is no band
 * search (the service's band search can write on a GET, service-safety.md); bands open from a
 * player's band list, Band Rankings, a song's band leaderboard or global search.
 *
 * The state centres in the viewport and scrolls when large text outgrows it (landscape at
 * font scale 2). Across a separating vertical hinge (half-open book posture) it sits in the
 * leading pane ([BandLayout.listSplit]); above a separating horizontal hinge (tabletop) it
 * centres in the top half, so no text lies on the crease.
 */
@Composable
fun BandNotFoundScreen() {
    FestivalScreen(title = "Band", isRoot = false, modifier = Modifier.testTag("fst.bands.screen")) { padding ->
        var contentOrigin by remember { mutableStateOf(Offset.Zero) }
        BoxWithConstraints(Modifier.fillMaxSize().padding(padding).onGloballyPositioned { contentOrigin = it.positionInWindow() }) {
            val split = BandLayout.listSplit(rememberBandHinge(contentOrigin.x, maxWidth))
            val viewport = rememberBandTabletopHinge(contentOrigin.y, maxHeight)?.left?.dp ?: maxHeight
            Column(
                Modifier
                    .width(split.leadingWidth?.dp ?: maxWidth)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .testTag("fst.bands.not-found.pane"),
            ) {
                Box(Modifier.fillMaxWidth().heightIn(min = viewport).testTag("fst.bands.not-found"), contentAlignment = Alignment.Center) {
                    FestivalEmptyState(BAND_NOT_FOUND_TITLE, Modifier.fillMaxWidth(), subtitle = BAND_MISSING_ID_MESSAGE)
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
        // A group or page change fades the cards out, shows the spinner and staggers the new
        // page in (web stagger, issue #71); a return visit with the page ready shows it at once.
        val swap = rememberLoadSwap(state, state !is LoadState.Loading, key = group to page)
        val loaded = (swap.shown as? LoadState.Loaded)?.value
        BandGrid(
            padding,
            "fst.player-bands.list",
            controls = {
                val subtitle = loaded?.let { "${group.label} · ${BandFormatting.count(it.totalCount.toLong())} ${if (it.totalCount == 1) "band" else "bands"}" }
                BandPageHeader(null, subtitle, "fst.player-bands")
                BandSegmentedControl(
                    options = PlayerBandGroup.entries,
                    selected = group,
                    label = { if (it == PlayerBandGroup.All) "All" else it.label },
                    tag = { "fst.player-bands.group.${it.wireId}" },
                    onSelect = viewModel::selectGroup,
                    modifier = Modifier.testTag("fst.player-bands.group-picker"),
                )
            },
        ) {
            val current = swap.shown
            if (swap.showsSpinner || current is LoadState.Loading) {
                fullRow("loading") { LoadSwapSpinner(swap, "Loading bands", Modifier.fillMaxWidth().heightIn(min = 240.dp), "fst.player-bands.loading") }
            } else when (current) {
                LoadState.Loading -> Unit
                is LoadState.Failed -> fullRow("error") {
                    ServiceStatusView(current.issue, "Bands unavailable", current.countdown, viewModel::retry, Modifier.height(360.dp).then(swap.contentModifier).testTag("fst.player-bands.error"))
                }
                is LoadState.Loaded -> {
                    val list = current.value
                    if (list.entries.isEmpty()) {
                        fullRow("empty") {
                            val noun = if (group == PlayerBandGroup.All) "bands" else group.label.lowercase()
                            Box(swap.contentModifier) { BandEmptyState("No bands found", "No $noun have been recorded for this player yet.", "fst.player-bands.empty") }
                        }
                    }
                    itemsIndexed(list.entries, key = { _, entry -> entry.key }) { index, entry ->
                        PlayerBandCard(entry, { onNavigate(bandRouteFor(entry)) }, with(swap) { Modifier.staggered(index) })
                    }
                }
            }
            // The pager stays outside the swapped result, visible and usable while a page loads, so
            // a newer page supersedes the pending one (load-transition R4; web keeps the previous
            // page's count as placeholder data). Hidden for the first load and on failure, as on web.
            loaded?.let { list -> fullRow("pager") { BandPager(page, list.pageCount(viewModel.pageSize), "fst.player-bands", viewModel::goTo) } }
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
