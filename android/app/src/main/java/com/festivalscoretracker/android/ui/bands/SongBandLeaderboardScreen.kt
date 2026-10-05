package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnPlan
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.SongBandSpotlight
import com.festivalscoretracker.android.ui.leaderboards.AnchoredBoardList
import com.festivalscoretracker.android.ui.leaderboards.AnchoredRowCard
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.songdetail.selectedRowHighlight
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.starsDescription
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick as onClickAction
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.bands.SongBandLeaderboardViewModel
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.loadSwapSpinnerItem
import com.festivalscoretracker.android.ui.common.rememberLoadSwap
import com.festivalscoretracker.android.ui.design.AccuracyPill
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Screen

/**
 * `/songs/:songId/bands/:bandType`: song header, in-place band-size switcher,
 * 25-row pages of band scores. Rows open Band Detail with the type and team key.
 *
 * @param viewModel Board logic.
 * @param artworkUrl Artwork resolver.
 * @param background Shared backdrop (static song cover while visible).
 * @param onNavigate Push a route.
 */
@Composable
fun SongBandLeaderboardScreen(
    viewModel: SongBandLeaderboardViewModel,
    artworkUrl: (String?) -> String?,
    background: BackgroundController,
    onNavigate: (AppRoute) -> Unit,
) {
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val board by viewModel.board.collectAsStateWithLifecycle()
    val type by viewModel.bandType.collectAsStateWithLifecycle()
    val page by viewModel.page.collectAsStateWithLifecycle()
    val song = (songState as? LoadState.Loaded)?.value
    DisposableEffect(song?.albumArt) {
        val token = background.pushFocus(song?.albumArt)
        onDispose { background.popFocus(token) }
    }
    // A page or band-size change fades the rows out, shows the spinner and staggers the new
    // rows in (web PaginatedLeaderboard, issue #71).
    val swap = rememberLoadSwap(board, board !is LoadState.Loading, key = type to page)
    val accountId by viewModel.accountId.collectAsStateWithLifecycle()
    val shown = (swap.shown as? LoadState.Loaded)?.value
    // The selected player's band: highlighted in place on its page, pinned above the pager on
    // every other page (web SongBandLeaderboardPage footer; the solo board's rule, issue #306).
    val selectedBand = shown?.let { SongBandSpotlight.selected(it, accountId) }
    val footer = shown?.let { SongBandSpotlight.footer(it, accountId) }
    val footerColumns = rememberScoreColumns(listOfNotNull(footer))
    // The pager keeps its place while the next page loads (issue #93).
    val loadedPages = (board as? LoadState.Loaded)?.value?.pageCount(BandPaging.PAGE_SIZE)
    val lastPages = remember(type) { mutableIntStateOf(1) }
    if (loadedPages != null) SideEffect { lastPages.intValue = loadedPages }
    val pageCount = loadedPages ?: lastPages.intValue
    val listState = rememberLazyListState()
    LaunchedEffect(type, page) { listState.scrollToItem(0) }
    FestivalScreen(title = "${type.label} Leaderboard", isRoot = false, modifier = Modifier.testTag("fst.song-band-leaderboard.screen")) { padding ->
        var contentLeft by remember { mutableFloatStateOf(0f) }
        BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { contentLeft = it.positionInWindow().x }) {
            SongBandLeaderboardLayout(
                split = BandLayout.listSplit(rememberBandHinge(contentLeft, maxWidth)),
                padding = padding,
                listState = listState,
                controls = {
                    SongHeader(song, swap.shown, type, artworkUrl, onNavigate)
                    BandSegmentedControl(
                        options = BandType.entries,
                        selected = type,
                        label = { it.label },
                        tag = { "fst.song-band-leaderboard.band-type.${it.wireId}" },
                        onSelect = viewModel::selectBandType,
                        modifier = Modifier.padding(vertical = 4.dp).testTag("fst.song-band-leaderboard.band-type-menu"),
                    )
                },
                // The pinned band fades out with the page and staggers back in with its first row (issue #295).
                footer = {
                    val band = selectedBand
                    if (footer != null && band != null) {
                        AnchoredRowCard(with(swap) { Modifier.staggered(0) }) {
                            LeaderboardSectionMember(footerColumns, "footer") {
                                SelectedBandFooter(footer, SongBandSpotlight.route(band), onNavigate, footerColumns.plan)
                            }
                        }
                    }
                },
                pager = {
                    if (pageCount > 1 && board !is LoadState.Failed) RankingsPager(page, pageCount, "fst.song-band-leaderboard", viewModel::goTo)
                },
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
                                Box(swap.contentModifier) { BandEmptyState(
                                    "No Band Scores Found",
                                    "No ${type.label} scores have been recorded for this song yet.",
                                    "fst.song-band-leaderboard.empty",
                                ) }
                            }
                        }
                        itemsIndexed(response.entries, key = { _, entry -> entry.key }) { index, entry ->
                            Box(with(swap) { Modifier.staggered(index) }) {
                                BandScoreRow(entry, song, selected = SongBandSpotlight.isSelected(entry, selectedBand)) {
                                    onNavigate(SongBandSpotlight.route(entry))
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
 * The selected player's band pinned above the pager: the solo board's footer row (rank,
 * joined member names scrolling inside their column, score, accuracy, stars), which opens the
 * band (web `getBandProfileRoute`).
 *
 * @param entry Footer row from [SongBandSpotlight.footer].
 * @param route The band's page.
 * @param onNavigate Push a route.
 * @param columns The footer's column plan.
 */
@Composable
private fun SelectedBandFooter(entry: LeaderboardEntry, route: AppRoute, onNavigate: (AppRoute) -> Unit, columns: LeaderboardColumnPlan) {
    Box(
        Modifier
            .fillMaxWidth()
            .selectedRowHighlight(true)
            .clickable(role = Role.Button, onClickLabel = RankingNavigation.actionLabel(route)) { onNavigate(route) }
            .testTag("fst.song-band-leaderboard.spotlight-footer"),
    ) {
        ScoreRow(entry, isSelected = true, navigable = true, columns = columns)
    }
}

/**
 * The page's single column, or — across a separating vertical hinge (half-open book or
 * passport fold) — the song header and size switcher on the leading side and the score rows
 * and pager on the trailing side, so no card or segment straddles the fold. Reading order
 * stays header → sizes → rows → pinned band → pager in both layouts. The selected player's
 * band and the pager are anchored to the bottom of the rows' column, like the other paginated
 * boards ([AnchoredBoardList], issue #306).
 *
 * @param split [BandLayout.listSplit] for the content box.
 * @param padding Shell padding.
 * @param listState Rows' list state.
 * @param controls Song header and band-size switcher.
 * @param footer Pinned selected-band row (may emit nothing).
 * @param pager Pager (may emit nothing).
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
    val bottom = padding.calculateBottomPadding()
    val leading = split.leadingWidth
    if (split.twoPane && leading != null) {
        Row(Modifier.fillMaxSize()) {
            Column(
                Modifier
                    .width(leading.dp)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, end = 16.dp, top = top, bottom = bottom + 24.dp)
                    .testTag("fst.song-band-leaderboard.controls-pane"),
            ) { controls() }
            Spacer(Modifier.width(split.gap.dp))
            AnchoredBoardList(
                listState = listState,
                idPrefix = "fst.song-band-leaderboard",
                contentTop = top + 8.dp,
                bottomInset = bottom,
                footer = footer,
                pager = pager,
                fadeAboveFooter = true,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                rowGap = 8.dp,
                rows = rows,
            )
        }
    } else {
        BandReadableWidth {
            AnchoredBoardList(
                listState = listState,
                idPrefix = "fst.song-band-leaderboard",
                contentTop = top,
                bottomInset = bottom,
                footer = footer,
                pager = pager,
                fadeAboveFooter = true,
                rowGap = 8.dp,
            ) {
                item(key = "controls") { Column { controls() } }
                rows()
            }
        }
    }
}

@Composable
private fun SongHeader(
    song: Song?,
    board: LoadState<SongBandLeaderboardResponse>,
    type: BandType,
    artworkUrl: (String?) -> String?,
    onNavigate: (AppRoute) -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AsyncImage(
            model = artworkUrl(song?.albumArt),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(72.dp).clip(RoundedCornerShape(10.dp)).background(BrandTokens.surfaceMuted),
        )
        Column(Modifier.weight(1f)) {
            if (song != null) {
                BandTextLink(song.title, "fst.song-band-leaderboard.song") { onNavigate(SongDetailRoute(song.songId)) }
                val details = listOfNotNull(song.artist.ifEmpty { null }, song.year?.toString()).joinToString(" · ")
                if (details.isNotEmpty()) Text(details, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
            val total = (board as? LoadState.Loaded)?.value?.population
            if (total != null) {
                Text(
                    "${type.label} · ${BandFormatting.count(total.toLong())} ${if (total == 1) "entry" else "entries"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.song-band-leaderboard.subtitle"),
                )
            }
        }
    }
}

// endregion

// region Row

/**
 * One band score: rank, members with instruments and per-member scores, team
 * score, FC badge, accuracy and stars. The whole card opens Band Detail. Shared with
 * Song Detail's band previews, where the selected player's band gets the web
 * `selectedCard` purple treatment.
 *
 * @param entry Wire row.
 * @param song Song, for keyboard-variant icons.
 * @param selected The selected player's band (purple highlight and border).
 * @param tag Test tag.
 * @param onClick Open action.
 */
@Composable
internal fun BandScoreRow(
    entry: SongBandLeaderboardEntry,
    song: Song?,
    selected: Boolean = false,
    tag: String = "fst.song-band-leaderboard.row.${entry.key}",
    onClick: () -> Unit,
) {
    val keyboard = song?.sig == "Keyboard"
    val announcement = bandScoreAnnouncement(entry)
    GlassCard(
        Modifier
            .fillMaxWidth()
            .testTag(tag)
            .semantics(mergeDescendants = true) {
                contentDescription = announcement
                role = Role.Button
                onClickAction(label = "Open band") { onClick(); true }
            },
        onClick = onClick,
        accent = if (selected) BrandTokens.purpleHighlightBorder else null,
    ) {
        // Narrow cards (phones, one side of a hinge) move the team score under the members
        // (web `scoreFooter`), so member names keep their width.
        // The card's description is the whole announcement; the texts inside add nothing for TalkBack.
        BoxWithConstraints(Modifier.background(if (selected) BrandTokens.purpleHighlight else Color.Transparent).padding(12.dp).clearAndSetSemantics { }) {
            val stacked = maxWidth < BAND_ROW_STACK_WIDTH
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        BandFormatting.rank(entry.rank),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.widthIn(min = 44.dp),
                    )
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
                if (stacked) BandScoreFooter(entry, Modifier.padding(start = 54.dp, end = 34.dp))
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
 * stars (gold stars read as "5 gold stars", like the star row, never "6 stars").
 *
 * @param entry Wire row.
 * @return Announcement.
 */
internal fun bandScoreAnnouncement(entry: SongBandLeaderboardEntry): String = buildList {
    add("Rank ${entry.rank}")
    BandMember.distinct(entry.members).forEach { member ->
        add(memberAnnouncement(member) + (member.score?.let { ", " + BandFormatting.count(it) } ?: ""))
    }
    add("band score ${BandFormatting.count(entry.score)}")
    if (entry.isFullCombo == true) add("full combo")
    entry.accuracy?.takeIf { it > 0 }?.let { add(ScoreFormatting.accuracy(it) + "% accuracy") }
    entry.stars?.takeIf { it > 0 }?.let { add(starsDescription(it)) }
}.joinToString(", ")

/** Card width below which the team score moves under the members. */
private val BAND_ROW_STACK_WIDTH = 400.dp

// endregion
