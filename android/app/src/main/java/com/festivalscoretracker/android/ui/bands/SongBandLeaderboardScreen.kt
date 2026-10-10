package com.festivalscoretracker.android.ui.bands

import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.leaderboards.awaitSelectedRowEntrance
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.withFrameNanos
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.rankings.SelectedRowAction
import com.festivalscoretracker.android.core.rankings.SelectedRowLabels
import com.festivalscoretracker.android.core.rankings.SelectedRowSubject
import com.festivalscoretracker.android.core.rankings.label
import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.ui.leaderboards.AnchoredFooter
import com.festivalscoretracker.android.ui.leaderboards.AnchoredRowCard
import com.festivalscoretracker.android.ui.songdetail.RowSeparator
import com.festivalscoretracker.android.ui.leaderboards.SelectedRowAnchor
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.songdetail.selectedRowHighlight
import androidx.compose.foundation.clickable
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.RankingsBoardLayout
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.leaderboards.revealSelectedRow
import com.festivalscoretracker.android.ui.songdetail.SelectedScoreFooterRow
import com.festivalscoretracker.android.ui.songdetail.SongBoardSwitcher
import com.festivalscoretracker.android.ui.songdetail.SongHeader
import com.festivalscoretracker.android.ui.background.SongCoverBackdrop
import androidx.compose.runtime.derivedStateOf
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.starsDescription
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.leaderboards.TEXT_SLACK
import com.festivalscoretracker.android.ui.leaderboards.ANCHORED_ROW_CARD_PADDING
import com.festivalscoretracker.android.ui.leaderboards.LocalColumnProbe
import com.festivalscoretracker.android.ui.leaderboards.columnProbe
import com.festivalscoretracker.android.ui.songdetail.SCORE_ROW_PADDING
import com.festivalscoretracker.android.ui.songdetail.SELECTED_HIGHLIGHT_INSET
import com.festivalscoretracker.android.ui.songdetail.STACKED_RANK_GAP
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import androidx.compose.runtime.Immutable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.SongBandLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.fillEmptyRegion
import com.festivalscoretracker.android.ui.common.rememberEmptyRegion
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.design.AccuracyPill
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.rememberMeasuredPx

// region Screen

/**
 * `/songs/:songId/bands/:bandType`: the solo board's song header with the band size
 * (a drop-down) where the instrument goes, over the song's static cover, then 25-row
 * pages of band scores (pattern `song-leaderboard-header`, issue #317). Rows open Band Detail with
 * the type and team key.
 *
 * With a selected player, their best band is highlighted on its page and pinned above the
 * pager as one solo-style row (web `SongBandLeaderboardPage` footer, Apple
 * `SongBandLeaderboardScreen`), following the solo footer's rule (`leaderboard-row` R7,
 * issue #307): while the band's row is on another page the footer jumps there and reveals
 * it; once the row is on screen it opens the Band page.
 *
 * @param viewModel Board logic.
 * @param artworkUrl Artwork resolver.
 * @param background Shared backdrop (static song cover while visible).
 * @param onNavigate Push a route.
 * @param revealSelected Opened for the selected band's row (web `navToBand`): bring it into view once its page shows.
 * @param onRevealed Called once that reveal has run (or found no row), so the route stops asking for it.
 */
@Composable
fun SongBandLeaderboardScreen(
    viewModel: SongBandLeaderboardViewModel,
    artworkUrl: (String?) -> String?,
    background: BackgroundController,
    onNavigate: (AppRoute) -> Unit,
    revealSelected: Boolean = false,
    onRevealed: () -> Unit = {},
) {
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val type by viewModel.bandType.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val song = (songState as? LoadState.Loaded)?.value
    SongCoverBackdrop(background, song?.albumArt)
    // A page or band-size change fades the rows out, shows the spinner and staggers the new
    // rows in (web PaginatedLeaderboard, issue #71). The pinned band depends on the band size,
    // never the page (web `footerAnimKey`, issue #190).
    val swap = rememberLoadSwap(board, board !is LoadState.Loading, key = type to page, pinnedKey = type)
    val listState = rememberLazyListState()
    // The last page of this band size: paging keeps the footer and pager in place while the
    // next page loads, while a size change drops them until its first page arrives.
    val shown = ((swap.shown as? LoadState.Loaded)?.value)?.takeIf { it.bandType == type.wireId }
    val footerEntry = shown?.selectedPlayerEntry
    // The requested page's rows are on screen: not the previous page still showing over a fresh load.
    val pageShown = swap.phase == LoadSwapPhase.ContentIn && board is LoadState.Loaded && swap.shown === board && shown != null
    val selectedIndex = if (pageShown && footerEntry != null) shown.entries.indexOfFirst { it.sameBand(footerEntry) } else -1
    // `leaderboard-row` R7: off-page the footer jumps; on screen it opens the Band page. While a page loads, the rank decides.
    val footerAction = footerEntry?.let {
        val visible = if (pageShown) selectedIndex >= 0 else it.rank > 0 && LeaderboardPaging.pageForRank(it.rank, BandPaging.PAGE_SIZE) == page
        SelectedRowAction.footer(it.rank, visible, page, BandPaging.PAGE_SIZE)
    }
    var revealPending by rememberSaveable { mutableStateOf(revealSelected) }
    val anchor = remember { SelectedRowAnchor() }
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    // The page's fade window, here so the reveal can rush the rows its scroll reaches (load-transition R5).
    val fadeIn = rememberPageFadeInWindow()
    val footerRows = remember(footerEntry) { listOfNotNull(footerEntry?.footerLeaderboardEntry) }
    // One plan for the board (`leaderboard-row` R1, R5): the rank column fits the page and the
    // pinned band (an off-page #9,968 too), and the member cards start their rank and names
    // where the pinned solo-style footer row does.
    val rankWidth = rememberBandRankWidth((swap.shown as? LoadState.Loaded)?.value?.entries.orEmpty() + listOfNotNull(footerEntry))
    val columns = rememberScoreColumns(footerRows, minRankWidth = rankWidth)
    val rowColumns = bandBoardColumns(columns.plan, rankWidth, hasFooter = footerEntry != null)
    var twoPane by remember { mutableStateOf(false) }

    LaunchedEffect(type, page) { listState.scrollToItem(0) }
    // Opened (or jumped) to the band's page: centre its highlighted row once it shows.
    LaunchedEffect(revealPending, pageShown, shown) {
        if (!revealPending || !pageShown) return@LaunchedEffect
        // Like the web's navToBand: scroll once the row's own entrance has finished (issue #323).
        if (selectedIndex >= 0 && awaitSelectedRowEntrance(fadeIn, fadeInStagger(selectedIndex), reduceMotion)) {
            withFrameNanos { }
            val bounds = anchor.bounds()
            // Single pane: the header and size switcher are the list's first item.
            if (bounds != null) listState.revealSelectedRow(BAND_ROWS_KEY, if (twoPane) 0 else 1, bounds.first, bounds.second, animate = !reduceMotion)
        }
        revealPending = false
        onRevealed()
    }

    // Like the solo board (pattern `song-leaderboard-header` R3, issue #317): the song header and band size
    // scroll with the rows and the top bar takes the song title, over the band size (no icon, issue #580),
    // once they have scrolled away. Across a hinge the header stays in the leading pane, so the bar stays empty.
    val headerGone by remember(listState) { derivedStateOf { !twoPane && listState.firstVisibleItemIndex > 0 } }
    FestivalScreen(
        title = if (headerGone) song?.title.orEmpty() else "",
        isRoot = false,
        scrolled = headerGone,
        marqueeTitle = true,
        subtitle = type.label,
        modifier = Modifier.testTag("fst.song-band-leaderboard.screen"),
        fadeInWindow = fadeIn,
    ) { padding ->
        var contentLeft by rememberMeasuredPx(0f)
        BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { contentLeft = it.positionInWindow().x }) {
            val split = BandLayout.listSplit(rememberBandHinge(contentLeft, maxWidth))
            SideEffect { twoPane = split.twoPane && split.leadingWidth != null }
            SongBandLeaderboardLayout(
                split = split,
                padding = padding,
                listState = listState,
                controls = {
                    // The solo board's header, with the band size where the instrument goes (web `SongInfoHeader`;
                    // its `onTitleClick` opens Song Detail, issue #315).
                    song?.let {
                        SongHeader(
                            it,
                            artworkUrl(it.albumArt),
                            artSize = 64.dp,
                            onTitleClick = { onNavigate(SongDetailRoute(it.songId)) },
                            tag = "fst.song-band-leaderboard.song",
                        )
                    }
                    SongBoardSwitcher(
                        current = type,
                        options = BandType.entries,
                        label = BandType::label,
                        id = BandType::wireId,
                        clickLabel = "Switch band size",
                        tag = "fst.song-band-leaderboard.band-type",
                        onSelect = viewModel::selectBandType,
                    )
                },
                // The pinned band fades in with the first rows (issue #295) and stays visible and usable
                // while another page loads (issue #190); a band-size change hides it beside the spinner (load-transition R2).
                footer = {
                    footerEntry?.let { entry ->
                        AnchoredRowCard(with(swap) { Modifier.pinnedStaggered(0) }.then(swap.pinnedContentModifier)) {
                            LeaderboardSectionMember(columns, "footer") {
                                SelectedScoreFooterRow(
                                    entry = entry.footerLeaderboardEntry,
                                    columns = columns.plan,
                                    actionLabel = footerAction?.label(SelectedRowSubject.Band) ?: SelectedRowLabels.OPEN_BAND,
                                    tag = "fst.song-band-leaderboard.spotlight-footer",
                                ) {
                                    when (val action = footerAction) {
                                        is SelectedRowAction.Jump -> {
                                            revealPending = true
                                            viewModel.goTo(action.page)
                                        }
                                        else -> onNavigate(entry.bandRoute())
                                    }
                                }
                            }
                        }
                    }
                },
                // Hidden until the band size's page count loads and for a single page (load-transition R4, #575).
                pager = { RankingsPager(page, shown?.pageCount(BandPaging.PAGE_SIZE), "fst.song-band-leaderboard", viewModel::goTo) },
            ) {
                val state = swap.shown
                if (swap.showsSpinner || state is LoadState.Loading) {
                    loadSwapSpinnerItem(swap, "Loading band scores", "fst.song-band-leaderboard.loading")
                } else when (state) {
                    LoadState.Loading -> Unit
                    is LoadState.Failed -> item(key = "error") {
                        ServiceStatusView(
                            state.issue,
                            "Band scores unavailable",
                            state.countdown,
                            viewModel::retry,
                            Modifier.height(360.dp).then(swap.contentModifier).testTag("fst.song-band-leaderboard.error"),
                        )
                    }
                    is LoadState.Loaded -> {
                        val response = state.value
                        if (response.entries.isEmpty()) {
                            item(key = "empty") {
                                // Centred between the song header and the anchored footer (`empty-error-states` R2, #377).
                                Box(Modifier.fillMaxWidth().fillEmptyRegion(rememberEmptyRegion(listState, "empty")).then(swap.contentModifier)) {
                                    BandEmptyState(
                                        "No Band Scores Found",
                                        "No ${type.label} scores have been recorded for this song yet.",
                                        "fst.song-band-leaderboard.empty",
                                        Modifier.fillMaxSize(),
                                    )
                                }
                            }
                        }
                        val selected = response.selectedPlayerEntry
                        // One card for the page's bands with hairlines between them, like the solo
                        // board (owner #543, `leaderboard-row` R10); padded like the pinned row's card
                        // so the ranks line up (R1). The reveal anchor sits outside the fade-in.
                        if (response.entries.isNotEmpty()) item(key = BAND_ROWS_KEY) {
                            GlassCard(anchor.item.fillMaxWidth().then(swap.contentModifier).testTag("fst.song-band-leaderboard.rows")) {
                                Column(Modifier.padding(horizontal = ANCHORED_ROW_CARD_PADDING, vertical = 6.dp)) {
                                    response.entries.forEachIndexed { index, entry ->
                                        val isSelected = selected?.sameBand(entry) == true
                                        Column((if (isSelected) anchor.row else Modifier).festivalFadeIn(swap.revealed, fadeInStagger(index))) {
                                            if (index > 0) RowSeparator()
                                            // The selected player's band keeps the purple treatment in place and opens the Band page.
                                            BandScoreRow(entry, song, selected = isSelected, columns = rowColumns) { onNavigate(entry.bandRoute()) }
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
}

/**
 * Band Detail for a song-board row.
 *
 * @return The band's route (band ID, or its team key when the ID is missing).
 */
private fun SongBandLeaderboardEntry.bandRoute(): BandRoute = BandRoute(bandId.ifEmpty { teamKey }, membersLabel, bandType, teamKey)

/**
 * The page's single column on the shared [RankingsBoardLayout] (the rows card scrolls under the pinned
 * band footer and pager, fading above them), or — across a separating vertical hinge
 * (half-open book or passport fold) — the song header, size switcher, footer and pager on
 * the leading side and the score rows on the trailing side, so no card or segment straddles
 * the fold. Reading order stays header → sizes → rows → footer → pager in both layouts.
 *
 * @param split [BandLayout.listSplit] for the content box.
 * @param padding Shell padding.
 * @param listState Row list state (the screen scrolls it on page changes and reveals).
 * @param controls Song header and band-size switcher.
 * @param footer The selected band's pinned row (may emit nothing).
 * @param pager Pager (may emit nothing for a single page).
 * @param rows Board state items (spinner, failure, empty, rows).
 */
@Composable
internal fun SongBandLeaderboardLayout(
    split: BandLayout.Panes,
    padding: PaddingValues,
    listState: LazyListState = rememberLazyListState(),
    controls: @Composable () -> Unit,
    footer: @Composable ColumnScope.() -> Unit = {},
    pager: @Composable () -> Unit = {},
    rows: LazyListScope.() -> Unit,
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
                    .testTag("fst.song-band-leaderboard.controls-pane")
                    .padding(start = 16.dp, end = 16.dp, top = top, bottom = bottom),
            ) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) { controls() }
                AnchoredFooter("fst.song-band-leaderboard", footer, pager)
            }
            Spacer(Modifier.width(split.gap.dp))
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = top + 8.dp, bottom = bottom),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f).fillMaxHeight().testTag("fst.song-band-leaderboard.list"),
                content = rows,
            )
        }
    } else {
        BandReadableWidth {
            RankingsBoardLayout(
                hinge = null,
                measure = Modifier,
                padding = padding,
                listState = listState,
                idPrefix = "fst.song-band-leaderboard",
                controls = { controls() },
                footer = footer,
                pager = pager,
                // The rows card fades out above the pinned band and pager, like the solo board (issue #93).
                fadeAboveFooter = true,
                itemGap = 8.dp,
                rows = rows,
            )
        }
    }
}

// endregion

// region Row

/**
 * One band score: rank, members with instruments and per-member scores, team
 * score, FC badge, accuracy and stars. The whole row opens Band Detail. A grouped row
 * with no card of its own: the song band board and Song Detail's band previews put a
 * section's rows into one [GlassCard] with separators, like the solo rows (owner #543,
 * `leaderboard-row` R10). The selected player's band takes the solo rows' purple
 * treatment ([selectedRowHighlight]).
 *
 * @param entry Wire row.
 * @param song Song, for keyboard-variant icons.
 * @param selected The selected player's band (purple highlight and border).
 * @param columns The section's shared rank column, inset and gap ([BandRowColumns]), so
 *   members line up across every row, including an appended or pinned selected band
 *   (`leaderboard-row` R1).
 * @param tag Test tag.
 * @param actionLabel TalkBack click label naming the destination (Song Detail's appended selected band jumps instead, issue #307).
 * @param onClick Open action.
 */
@Composable
internal fun BandScoreRow(
    entry: SongBandLeaderboardEntry,
    song: Song?,
    selected: Boolean = false,
    columns: BandRowColumns = BandRowColumns(),
    tag: String = "fst.song-band-leaderboard.row.${entry.key}",
    actionLabel: String = SelectedRowLabels.OPEN_BAND,
    onClick: () -> Unit,
) {
    val keyboard = song?.sig == "Keyboard"
    val announcement = bandScoreAnnouncement(entry, selected)
    val probe = LocalColumnProbe.current
    Box(
        Modifier
            .fillMaxWidth()
            .selectedRowHighlight(selected)
            .clickable(role = Role.Button, onClickLabel = actionLabel, onClick = onClick)
            .testTag(tag)
            .semantics(mergeDescendants = true) { contentDescription = announcement },
    ) {
        // Narrow rows (phones, one side of a hinge) move the team score under the members
        // (web `scoreFooter`), so member names keep their width.
        // The row's description is the whole announcement; the texts inside add nothing for TalkBack.
        BoxWithConstraints(
            Modifier
                .padding(horizontal = SCORE_ROW_PADDING, vertical = BAND_ROW_PADDING)
                .clearAndSetSemantics { },
        ) {
            // The whole card's width: these insets plus the card's own padding on each side.
            val cardWidth = maxWidth + (SCORE_ROW_PADDING + SELECTED_HIGHLIGHT_INSET + columns.cardPadding) * 2
            val stacked = maxWidth < BAND_ROW_STACK_WIDTH
            // Without a pinned row to follow, the gap is the one a footer row of this card's width would use.
            val gap = columns.gap ?: LeaderboardColumnLayout.gapFor((cardWidth - ANCHORED_ROW_CARD_PADDING * 2).value).dp
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(gap)) {
                    Text(
                        BandFormatting.rank(entry.rank),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.widthIn(min = columns.rankWidth).columnProbe(probe, "band.rank.${entry.rank}"),
                    )
                    Column(Modifier.weight(1f).columnProbe(probe, "band.name.${entry.rank}"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        BandMember.distinct(entry.members).forEach { BandMemberScoreLine(it, keyboard) }
                    }
                    if (!stacked) {
                        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            BandTeamScore(entry)
                            BandScoreBadges(entry)
                        }
                    }
                    RowChevron()
                }
                if (stacked) BandScoreFooter(entry, Modifier.padding(start = columns.rankWidth + gap, end = 34.dp))
            }
        }
    }
}

/**
 * One member: instrument icons, name and member score. Large text wraps names
 * ([FestivalMarqueeText]), so the score flows under the name instead of squeezing it mid-word.
 *
 * @param member Member.
 * @param keyboard Keyboard-variant icons.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BandMemberScoreLine(member: BandMember, keyboard: Boolean) {
    val icons: @Composable () -> Unit = {
        member.chartedInstruments.forEach { InstrumentIcon(it, keyboard = keyboard, size = 18.dp, decorative = true) }
    }
    val score: @Composable () -> Unit = {
        member.score?.let { Text(BandFormatting.count(it), style = MaterialTheme.typography.bodySmall, color = BrandTokens.textPrimary) }
    }
    if (isLargeText()) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), itemVerticalAlignment = Alignment.CenterVertically) {
            icons()
            FestivalMarqueeText(member.resolvedName, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
            score()
        }
    } else {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            icons()
            FestivalMarqueeText(
                member.resolvedName,
                style = MaterialTheme.typography.bodyMedium,
                color = BrandTokens.textPrimary,
                modifier = Modifier.weight(1f, fill = false),
            )
            score()
        }
    }
}

/**
 * Narrow-card footer: team score leading, accuracy and stars trailing; the badges wrap
 * under the score when large text leaves no room beside it, so no star is clipped.
 *
 * @param entry Wire row.
 * @param modifier Modifier (insets under the members).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BandScoreFooter(entry: SongBandLeaderboardEntry, modifier: Modifier = Modifier) {
    FlowRow(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        BandTeamScore(entry)
        BandScoreBadges(entry)
    }
}

@Composable
private fun BandTeamScore(entry: SongBandLeaderboardEntry) {
    Text(BandFormatting.count(entry.score), fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
}

@Composable
private fun BandScoreBadges(entry: SongBandLeaderboardEntry) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        // Web `AccuracyDisplay`: a full combo is the gold-outlined accuracy, not an "FC" chip (7.11);
        // a band's 0 accuracy is "not recorded", so an FC without it reads "FC", never "0%".
        AccuracyPill(entry.accuracy?.takeIf { it > 0 }, entry.isFullCombo == true, id = entry.key)
        entry.stars?.takeIf { it > 0 }?.let { StarRating(it, size = 14.dp) }
    }
}

/**
 * TalkBack description of a band score row: everything the card shows, in visual order —
 * rank, each member with instruments and member score, band score, full combo, accuracy and
 * stars (gold stars read as "5 gold stars", like the star row, never "6 stars"). The selected
 * player's band starts with "Your band" (iOS `SongBandPreviewText`, Windows), since its purple
 * highlight is otherwise visual only (issue #172).
 *
 * @param entry Wire row.
 * @param selected The selected player's band.
 * @return Announcement.
 */
internal fun bandScoreAnnouncement(entry: SongBandLeaderboardEntry, selected: Boolean = false): String = buildList {
    if (selected) add(YOUR_BAND)
    add("Rank ${entry.rank}")
    BandMember.distinct(entry.members).forEach { member ->
        add(memberAnnouncement(member) + (member.score?.let { ", " + BandFormatting.count(it) } ?: ""))
    }
    add("band score ${BandFormatting.count(entry.score)}")
    if (entry.isFullCombo == true) add("full combo")
    entry.accuracy?.takeIf { it > 0 }?.let { add(ScoreFormatting.accuracy(it) + "% accuracy") }
    entry.stars?.takeIf { it > 0 }?.let { add(starsDescription(it)) }
}.joinToString(", ")

/** Spoken prefix of the selected player's band row. */
internal const val YOUR_BAND = "Your band"

/** Lazy key of the song band board's rows card (the reveal finds the selected band inside it). */
private const val BAND_ROWS_KEY = "rows"

/** Row content width below which the team score moves under the members. */
private val BAND_ROW_STACK_WIDTH = 400.dp

/** Smallest band rank column (fits "#10" at default text). */
internal val BAND_RANK_MIN_WIDTH = 44.dp

/** Gap between the rank column and the members on Song Detail's band rows. */
private val BAND_RANK_GAP = 10.dp

/** Band row vertical padding. */
private val BAND_ROW_PADDING = 12.dp

/**
 * One band section's shared row geometry (`leaderboard-row` R1).
 *
 * @property rankWidth Rank column width ([rememberBandRankWidth]).
 * @property cardPadding Horizontal padding of the section's card around its rows: 0 on Song
 *   Detail (rank 12 dp from the card edge, like its solo rows), [ANCHORED_ROW_CARD_PADDING]
 *   on the full board (rank 20 dp from the card edge, like the pinned footer row).
 * @property gap Space between the rank and the members; null takes the gap a pinned score
 *   row of the card's width would use ([LeaderboardColumnLayout.gapFor]).
 */
@Immutable
internal data class BandRowColumns(
    val rankWidth: Dp = BAND_RANK_MIN_WIDTH,
    val cardPadding: Dp = 0.dp,
    val gap: Dp? = BAND_RANK_GAP,
)

/**
 * The full song band board's row geometry: band rows put their rank and members exactly
 * where the pinned selected band's solo-style footer row ([SelectedScoreFooterRow] in an
 * [AnchoredRowCard]) puts its rank and name, so the pinned band shares the board's columns
 * (`leaderboard-row` R1, R5) whether it is on this page or not. The rows card is padded like
 * the [AnchoredRowCard] and each row is inset like the footer's [selectedRowHighlight], so
 * both ranks start [ANCHORED_ROW_CARD_PADDING] + [SELECTED_HIGHLIGHT_INSET] +
 * [SCORE_ROW_PADDING] from their card's edge. The rows use the same geometry while no band
 * is pinned, so switching band sizes never moves the columns.
 *
 * @param plan The footer's plan, fitted with the board's rank width.
 * @param rankWidth Board rank width ([rememberBandRankWidth] over the page and the pinned band).
 * @param hasFooter Whether a band is pinned (its plan's gap is known).
 * @return Band row geometry.
 */
@Composable
internal fun bandBoardColumns(plan: LeaderboardColumnPlan, rankWidth: Dp, hasFooter: Boolean): BandRowColumns = BandRowColumns(
    rankWidth = maxOf(rankWidth, plan.rankWidth.dp),
    cardPadding = ANCHORED_ROW_CARD_PADDING,
    gap = when {
        isLargeText() -> STACKED_RANK_GAP
        hasFooter -> plan.gap.dp
        else -> null
    },
)

/**
 * One rank column for a band section, measured from its widest rank label in the bold band
 * rank style and in the pinned score row's rank style (web `computeRankWidth`;
 * `leaderboard-row` R1), so a pinned "#9,968" doesn't push its members right of the top ten's.
 *
 * @param entries Every row drawn in the section, including an appended or pinned selected band.
 * @return Rank column width, at least [BAND_RANK_MIN_WIDTH].
 */
@Composable
internal fun rememberBandRankWidth(entries: List<SongBandLeaderboardEntry>): Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold)
    val pinnedStyle = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold)
    val ranks = entries.map { it.rank }.distinct()
    return remember(ranks, density, style, pinnedStyle) {
        val px = ranks.maxOfOrNull { rank ->
            maxOf(
                measurer.measure(BandFormatting.rank(rank), style, maxLines = 1).size.width,
                measurer.measure(RankingFormatting.rankLabel(rank), pinnedStyle, maxLines = 1).size.width,
            )
        } ?: 0
        maxOf(BAND_RANK_MIN_WIDTH, with(density) { px.toDp() } + TEXT_SLACK)
    }
}

// endregion
