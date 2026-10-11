package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardDoubleArrowLeft
import androidx.compose.material.icons.filled.KeyboardDoubleArrowRight
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.Immutable
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardRowKind
import com.festivalscoretracker.android.core.rankings.LeaderboardSection
import com.festivalscoretracker.android.core.rankings.BandRankingEntry
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.RankingNavigation
import com.festivalscoretracker.android.core.rankings.RankingPaging
import com.festivalscoretracker.android.core.rankings.asRankingMetric
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat
import androidx.compose.foundation.layout.RowScope
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.common.rememberMeasuredPx

// region Rows

/** Rating text (web `Colors.accentBlueBright` #4C7DFF). */
private val RatingBlue = Color(0xFF4C7DFF)

/**
 * A leaderboard row's player or band name (issue #292): one line in the row's flexible name
 * column that scrolls like the web `MarqueeText` when it doesn't fit and stays still when it
 * does, so a long name never spills over the rank, songs, value or chevron columns. Under
 * Remove animations or in-app Reduce Motion it tail-truncates instead ([FestivalMarqueeText]).
 * Rows switch to their stacked, wrapping layout at large font scales before reaching this.
 * The full name stays in the text (and in the rows' spoken descriptions) for TalkBack.
 *
 * @param name Display name, roster or "Unknown User".
 * @param modifier Modifier; give it the row's flexible width (`Modifier.weight(1f)`).
 * @param style Text style.
 * @param fontWeight Optional weight (bold for the selected player's row).
 */
@Composable
internal fun LeaderboardNameText(
    name: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    fontWeight: FontWeight? = null,
) = FestivalMarqueeText(name, modifier, style = style, color = BrandTokens.textPrimary, fontWeight = fontWeight)

/**
 * Minimum height of every leaderboard row, its loading skeleton and pinned rows (web
 * `Layout.entryRowHeight`, issue #90). A minimum, so large text still grows rows.
 */
internal val LEADERBOARD_ROW_MIN_HEIGHT = 48.dp

/** Vertical gap between the rows of a Leaderboards overview card (skeleton and loaded). */
internal val LEADERBOARD_ROW_GAP = 2.dp

/**
 * Vertical inset of a one-line ranking row: the percentile metrics' two-line rating
 * (bodyLarge value over a labelSmall Bayesian value, 40 dp) still fits the 48 dp row (issue #188).
 * 3 dp, not 4: 4 dp rounds up to 11 px per side at 2.625× density, making the row 1 px taller.
 */
private val RANKING_ROW_VERTICAL_PADDING = 3.dp

/** Vertical inset of a stacked (large-text or narrow) ranking row and its skeleton. */
private val STACKED_RANKING_ROW_VERTICAL_PADDING = 6.dp

/** Gap between the lines of a stacked ranking row and its skeleton. */
private val STACKED_RANKING_LINE_GAP = 2.dp

/**
 * Name lines a large-text (stacked) player ranking row and its skeleton reserve (issue #188):
 * an Epic display name (at most 16 characters) wraps to at most two lines at font scale 2.0,
 * so one-line and wrapped names give rows of one height and the loading skeleton predicts it.
 * A minimum, never a cap: a longer name still wraps rather than being cut off.
 */
internal const val STACKED_RANKING_NAME_LINES = 2

/**
 * Name lines a large-text band ranking row and its skeleton reserve: one per member (a
 * roster's typical wrapped length), never fewer than a player row's [STACKED_RANKING_NAME_LINES].
 * A roster with a member name wider than the column still wraps past it rather than clipping.
 *
 * @param memberCount Players in the band.
 * @return Minimum name lines.
 */
internal fun stackedBandNameLines(memberCount: Int): Int = maxOf(STACKED_RANKING_NAME_LINES, memberCount)

/**
 * Fixed column widths shared by every row of one board or card, so the selected
 * player's row (inline or pinned below) lines up with the rest (web `RankingEntry`
 * `rankWidth` / reserved score width; operator batch 7, 7.9).
 *
 * @property rank Rank column.
 * @property songs "X / Y" column (0 when hidden).
 * @property rating Rating column.
 * @property showSongs Whether one-line rows draw the songs column; it yields to names on
 *   narrow Compete cards (issue #38) and narrow Leaderboards cards (issue #114) and stays in the row's spoken description.
 * @property stacked Whether rows use the stacked layout (as at large text) because the row is
 *   too narrow for the name beside the other columns (Full Rankings beside a hinge, issue #115;
 *   Band Rankings, issue #116).
 */
@Immutable
data class RankingColumns(val rank: Dp, val songs: Dp, val rating: Dp, val showSongs: Boolean = true, val stacked: Boolean = false)

/** Column widths for the rows below, or null for intrinsic widths. */
val LocalRankingColumns = compositionLocalOf<RankingColumns?> { null }

/**
 * The measured inner width (dp) of a rankings card's rows, written from `onSizeChanged` and
 * passed to [rememberAccountColumns] / [rememberBandColumns]. It is NaN only before the
 * card's first layout, and it is saved with the destination, so returning to a page on the
 * back stack (Compete from View Full Leaderboard, issues #82, #185) draws the same column
 * plan on its first frame instead of a NaN plan that drops or restacks columns for a frame.
 *
 * @return Width state shared by the rows' column plan.
 */
@Composable
fun rememberRankingRowWidth(): MutableFloatState = rememberMeasuredPx(Float.NaN)

/**
 * Measure the widest rank, songs and rating text (bold, as the selected row draws them)
 * and size the columns with the shared [LeaderboardColumnLayout] (issue #37).
 *
 * @param ranks Rank labels.
 * @param songs Songs labels.
 * @param ratings Rating labels.
 * @param names Row names; when non-empty the songs column shows only if every name fits
 *   beside it in [rowWidth] (issue #38). Empty keeps the songs column unless names would
 *   collapse below their minimum in [rowWidth] (issue #114).
 * @param rowWidth Row width in dp (NaN before the first layout or when unknown).
 * @param stackNarrowNames Stack the rows when the one-line columns would leave names less
 *   than their minimum in [rowWidth] (issue #116).
 * @param keepNameMinimum Keep a minimum name width in [rowWidth]: the songs column yields,
 *   then rows stack (issue #115).
 * @return Column widths.
 */
@Composable
fun rememberRankingColumns(
    ranks: List<String>,
    songs: List<String>,
    ratings: List<String>,
    names: List<String> = emptyList(),
    rowWidth: Float = Float.NaN,
    stackNarrowNames: Boolean = false,
    keepNameMinimum: Boolean = false,
): RankingColumns {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    val section = remember(ranks, songs, ratings, names, stackNarrowNames, density, typography, keepNameMinimum) {
        fun widest(texts: List<String>, style: TextStyle): Float = with(density) {
            val px = texts.maxOfOrNull { measurer.measure(it, style.copy(fontWeight = FontWeight.Bold), maxLines = 1).size.width } ?: return@with 0f
            (px.toDp() + TEXT_SLACK).value
        }
        LeaderboardSection(
            LeaderboardRowKind.Ranking,
            rankWidth = widest(ranks, typography.bodyMedium),
            metaWidth = widest(songs, typography.bodyMedium),
            valueWidth = widest(ratings, typography.bodyLarge),
            nameWidth = widest(names, typography.bodyLarge),
            stackNarrowNames = stackNarrowNames,
            keepsNameMinimum = keepNameMinimum,
        )
    }
    // The shared section fitter (issues #37, #38, #115): without names or a name minimum, rankings keep every column at any width.
    return remember(section, rowWidth) {
        val plan = LeaderboardColumnLayout.fit(section, rowWidth, density.fontScale)
        RankingColumns(rank = plan.rankWidth.dp, songs = plan.metaWidth.dp, rating = plan.valueWidth.dp, showSongs = plan.showMeta, stacked = plan.stacked)
    }
}

/**
 * [rememberRankingColumns] for account rows.
 *
 * @param entries Rows sharing the columns (page rows plus the selected player's pinned row).
 * @param metric Rank By metric.
 * @param fitNamesTo Row width in dp (NaN before the first layout) to hide the songs column
 *   in when it would truncate a name (Compete, issue #38); null keeps it at any width.
 * @param keepNameMinimumIn Row width in dp (NaN before the first layout) in which names keep
 *   their minimum width: the songs column yields, then rows stack (Full Rankings, issue #115).
 *   Ignored when [fitNamesTo] is set.
 * @param rowWidth Row width in dp (NaN when unknown) to hide the songs column in when names
 *   would collapse below their minimum (Leaderboards cards, issue #114); ignored with [fitNamesTo]
 *   or [keepNameMinimumIn].
 * @return Column widths.
 */
@Composable
fun rememberAccountColumns(
    entries: List<AccountRankingEntry>,
    metric: RankingMetric,
    fitNamesTo: Float? = null,
    keepNameMinimumIn: Float? = null,
    rowWidth: Float = Float.NaN,
): RankingColumns = rememberRankingColumns(
    entries.map { RankingFormatting.rankLabel(it.rank(metric)) },
    entries.map { it.songsLabel(metric) },
    entries.map { RankingFormatting.rating(it.ratingValue(metric), metric) },
    names = if (fitNamesTo != null) entries.map { it.name } else emptyList(),
    rowWidth = fitNamesTo ?: keepNameMinimumIn ?: rowWidth,
    keepNameMinimum = fitNamesTo == null && keepNameMinimumIn != null,
)

/**
 * [rememberRankingColumns] for band rows.
 *
 * @param entries Rows sharing the columns.
 * @param metric Band metric.
 * @param stackBelow Row width in dp (NaN before the first layout) under which rows stack
 *   rather than squeeze rosters below their minimum (Band Rankings, issue #116); null keeps
 *   one-line rows at any width.
 * @param rowWidth Row width in dp (NaN when unknown) to hide the songs column in when names
 *   would collapse below their minimum (Leaderboards cards, issue #114); ignored with [stackBelow].
 * @return Column widths.
 */
@Composable
fun rememberBandColumns(entries: List<BandRankingEntry>, metric: BandRankingMetric, stackBelow: Float? = null, rowWidth: Float = Float.NaN): RankingColumns = rememberRankingColumns(
    entries.map { RankingFormatting.rankLabel(it.rank(metric)) },
    entries.map { it.songsLabel(metric) },
    entries.map { RankingFormatting.rating(it.ratingValue(metric), metric.asRankingMetric) },
    rowWidth = stackBelow ?: rowWidth,
    stackNarrowNames = stackBelow != null,
)

/**
 * The one-line rank · name · "X / Y" · rating layout shared by account and band rows
 * (web `RankingEntry`: accent-blue rating, songs as a bare fraction). A long name scrolls
 * inside its column ([LeaderboardNameText], issue #292) rather than truncating.
 *
 * @param rank One-based rank.
 * @param name Display name or roster.
 * @param songs "X / Y" songs text.
 * @param rating Primary rating text.
 * @param bayesian Bayesian value text for percentile metrics.
 * @param isSelected Selected-player accent treatment.
 * @param route Destination; null makes the row non-interactive.
 * @param onOpen Navigation callback.
 * @param tag Test tag.
 * @param clickLabel TalkBack action label ("Double-tap to …") for a navigable row.
 * @param unavailable TalkBack state for a row without a destination.
 * @param nameLines Name lines a large-text row reserves (the skeleton reserves the same).
 * @param modifier Modifier.
 */
@Composable
private fun RankingRowLayout(
    rank: Int,
    name: String,
    songs: String,
    rating: String,
    bayesian: String?,
    isSelected: Boolean,
    route: AppRoute?,
    onOpen: (AppRoute) -> Unit,
    tag: String,
    clickLabel: String,
    unavailable: String,
    nameLines: Int = STACKED_RANKING_NAME_LINES,
    modifier: Modifier = Modifier,
) {
    val description = RankingFormatting.rowDescription(rank, name, rating, songs, isSelected)
    val shape = RoundedCornerShape(10.dp)
    var rowModifier = modifier
        .fillMaxWidth()
        .heightIn(min = LEADERBOARD_ROW_MIN_HEIGHT)
        .clip(shape)
    // Same selected-player treatment as the song boards (web `playerEntryRow`, 7.7).
    if (isSelected) rowModifier = rowModifier.background(BrandTokens.purpleHighlight).border(BorderStroke(1.dp, BrandTokens.purpleHighlightBorder), shape)
    if (route != null) rowModifier = rowModifier.clickable(role = Role.Button, onClickLabel = clickLabel) { onOpen(route) }
    val columns = LocalRankingColumns.current
    val largeText = isLargeText()
    val stacked = largeText || columns?.stacked == true
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = rowModifier
            .padding(horizontal = 8.dp, vertical = if (stacked) STACKED_RANKING_ROW_VERTICAL_PADDING else RANKING_ROW_VERTICAL_PADDING)
            .testTag(tag)
            .clearAndSetSemantics {
                contentDescription = description
                if (route == null) stateDescription = unavailable
            },
    ) {
        // Web `RankingEntry` `isPlayer`: every text in the selected player's row is bold.
        val weight = if (isSelected) FontWeight.Bold else null
        if (stacked) {
            // Narrow rows at normal text (#115, #116) have no skeleton and keep names at their own length.
            StackedRankingRow(rank, name, songs, rating, bayesian, weight, route != null, columns?.rank, if (largeText) nameLines else 1)
            return@Row
        }
        Text(
            RankingFormatting.rankLabel(rank),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = weight,
            color = BrandTokens.textPrimary,
            maxLines = 1,
            modifier = columns?.let { Modifier.width(it.rank) } ?: Modifier.widthIn(min = 44.dp),
        )
        LeaderboardNameText(name, Modifier.weight(1f), fontWeight = weight)
        // Hidden for the whole section when a name wouldn't fit beside it or would collapse (issues #38, #114); still spoken in `description`.
        if (columns?.showSongs != false) {
            Text(
                songs,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = weight,
                color = BrandTokens.textSecondary,
                maxLines = 1,
                textAlign = TextAlign.End,
                modifier = columns?.let { Modifier.width(it.songs) } ?: Modifier,
            )
        }
        Column(horizontalAlignment = Alignment.End, modifier = columns?.let { Modifier.widthIn(min = it.rating) } ?: Modifier) {
            Text(rating, style = MaterialTheme.typography.bodyLarge, fontWeight = weight ?: FontWeight.SemiBold, color = RatingBlue, maxLines = 1)
            if (bayesian != null) {
                Text(bayesian, style = MaterialTheme.typography.labelSmall, fontWeight = weight, color = BrandTokens.textSecondary, maxLines = 1)
            }
        }
        // In-card chevron on navigable rows (7.3); anonymous rows keep the slot so columns align.
        if (route != null) RowChevron() else Spacer(Modifier.width(20.dp))
    }
}

/**
 * [RankingRowLayout]'s content at large font scales: rank and the (wrapping) name on the
 * first line, the songs count and rating on the next, so no column is squeezed or overlaps.
 * The rank keeps the section's shared width, so names line up down the section (issue #149).
 * The name reserves [nameLines] lines, as [RankingsSkeletonRows] does, so a wrapped name
 * doesn't make its row taller than the others or than the skeleton (issue #188).
 */
@Composable
private fun RowScope.StackedRankingRow(rank: Int, name: String, songs: String, rating: String, bayesian: String?, weight: FontWeight?, navigable: Boolean, rankWidth: Dp?, nameLines: Int) {
    Text(
        RankingFormatting.rankLabel(rank),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = weight,
        color = BrandTokens.textPrimary,
        modifier = rankWidth?.let { Modifier.widthIn(min = it) } ?: Modifier,
    )
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(STACKED_RANKING_LINE_GAP)) {
        Text(name, style = MaterialTheme.typography.bodyLarge, fontWeight = weight, color = BrandTokens.textPrimary, minLines = nameLines)
        Text(rating, style = MaterialTheme.typography.bodyLarge, fontWeight = weight ?: FontWeight.SemiBold, color = RatingBlue)
        if (bayesian != null) Text(bayesian, style = MaterialTheme.typography.labelSmall, fontWeight = weight, color = BrandTokens.textSecondary)
        Text(songs, style = MaterialTheme.typography.bodyMedium, fontWeight = weight, color = BrandTokens.textSecondary)
    }
    if (navigable) RowChevron() else Spacer(Modifier.width(20.dp))
}

/**
 * One account rankings row; opens the player (Statistics for the selected player).
 * Anonymous rows show "Unknown User" and are not interactive.
 *
 * @param entry Row.
 * @param metric Selected metric.
 * @param isSelected Selected player's own row.
 * @param route Destination or null.
 * @param onOpen Navigation callback.
 * @param tag Test tag; defaults to `fst.rankings.row.<key>`.
 * @param clickLabel TalkBack action label overriding the route's (a pinned footer that may
 *   jump to its page instead, `leaderboard-row` R7).
 */
@Composable
fun AccountRankingRow(
    entry: AccountRankingEntry,
    metric: RankingMetric,
    isSelected: Boolean,
    route: AppRoute?,
    onOpen: (AppRoute) -> Unit,
    tag: String = "fst.rankings.row.${entry.key}",
    clickLabel: String? = null,
) {
    RankingRowLayout(
        rank = entry.rank(metric),
        name = entry.name,
        songs = entry.songsLabel(metric),
        rating = RankingFormatting.rating(entry.ratingValue(metric), metric),
        bayesian = entry.bayesianValue(metric)?.let(RankingFormatting::bayesian),
        isSelected = isSelected,
        route = route,
        onOpen = onOpen,
        tag = tag,
        clickLabel = clickLabel ?: route?.let(RankingNavigation::actionLabel).orEmpty(),
        unavailable = "Profile unavailable",
    )
}

/**
 * One band rankings row; opens Band Detail with its `bandType`/`teamKey`.
 *
 * @param entry Row.
 * @param metric Band metric.
 * @param isSelected Whether the selected player is a member (web `BandRankingCard` highlight).
 * @param route Destination or null.
 * @param onOpen Navigation callback.
 */
@Composable
fun BandRankingRow(entry: BandRankingEntry, metric: BandRankingMetric, isSelected: Boolean, route: AppRoute?, onOpen: (AppRoute) -> Unit) {
    RankingRowLayout(
        rank = entry.rank(metric),
        name = entry.membersLabel,
        songs = entry.songsLabel(metric),
        rating = RankingFormatting.rating(entry.ratingValue(metric), metric.asRankingMetric),
        bayesian = entry.bayesianValue(metric)?.let(RankingFormatting::bayesian),
        isSelected = isSelected,
        route = route,
        onOpen = onOpen,
        tag = "fst.band-rankings.row.${entry.key}",
        clickLabel = "Open band",
        unavailable = "Band unavailable",
        nameLines = stackedBandNameLines(entry.teamMembers.size),
    )
}

// endregion

// region Separators

/**
 * A hairline between rows grouped in one card (operator batch 6, 6.5: cards with several
 * entries separate them), inset to the rows' text.
 *
 * @param modifier Modifier.
 */
@Composable
fun RowSeparator(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier.padding(horizontal = 8.dp), thickness = 1.dp, color = BrandTokens.glassBorder)
}

// endregion

// region Placeholders

/**
 * Static skeleton rows (no shimmer, so no per-frame work while loading). Each row has the
 * loaded rows' height, inset and gap, so rows don't jump when data arrives (issue #90). At
 * large text the rows take the stacked rows' shape, one bar per text line in the same
 * styles, so they grow with the loaded rows (issue #188); the name reserves the loaded rows'
 * [nameLines], so wrapped names don't make the card jump either.
 *
 * @param count Rows.
 * @param bayesian Whether the loaded rows draw a Bayesian value line (percentile metrics),
 *   which adds a line to stacked rows.
 * @param nameLines Name lines the loaded large-text rows reserve: [STACKED_RANKING_NAME_LINES]
 *   for players, [stackedBandNameLines] for bands.
 */
@Composable
fun RankingsSkeletonRows(count: Int, bayesian: Boolean = false, nameLines: Int = STACKED_RANKING_NAME_LINES) {
    val stacked = isLargeText()
    val typography = MaterialTheme.typography
    Column(
        verticalArrangement = Arrangement.spacedBy(LEADERBOARD_ROW_GAP),
        modifier = Modifier
            .fillMaxWidth()
            .testTag("fst.rankings.skeleton")
            .clearAndSetSemantics { contentDescription = "Loading rankings" },
    ) {
        repeat(count) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = LEADERBOARD_ROW_MIN_HEIGHT)
                    .padding(horizontal = 8.dp, vertical = if (stacked) STACKED_RANKING_ROW_VERTICAL_PADDING else 0.dp),
            ) {
                if (stacked) {
                    SkeletonLine(typography.labelLarge, 32)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(STACKED_RANKING_LINE_GAP)) {
                        SkeletonLine(typography.bodyLarge, 128, lines = nameLines)
                        SkeletonLine(typography.bodyLarge, 72)
                        if (bayesian) SkeletonLine(typography.labelSmall, 48)
                        SkeletonLine(typography.bodyMedium, 72)
                    }
                    Spacer(Modifier.width(20.dp))
                } else {
                    SkeletonBar(32)
                    SkeletonBar(128)
                    Spacer(Modifier.weight(1f))
                    SkeletonBar(56)
                }
            }
        }
    }
}

@Composable
private fun SkeletonBar(widthDp: Int) {
    Box(
        Modifier
            .width(widthDp.dp)
            .height(14.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(BrandTokens.surfaceMuted),
    )
}

/**
 * A skeleton bar per text line in [style]: blank text of that style and line count sizes it,
 * so it scales with the font exactly as the loaded row's text does.
 *
 * @param style Loaded text style.
 * @param widthDp Bar width.
 * @param lines Text lines to cover, one bar each.
 */
@Composable
private fun SkeletonLine(style: TextStyle, widthDp: Int, lines: Int = 1) {
    Box(
        Modifier
            .width(widthDp.dp)
            .drawBehind {
                val line = size.height / lines
                val bar = line * 0.6f
                repeat(lines) { index ->
                    drawRoundRect(BrandTokens.surfaceMuted, topLeft = Offset(0f, line * index + (line - bar) / 2), size = Size(size.width, bar), cornerRadius = CornerRadius(bar / 2))
                }
            },
    ) {
        Text(" ", style = style, minLines = lines, maxLines = lines)
    }
}

/**
 * Small "Loading your rank" row.
 *
 * @param tag Test tag.
 */
@Composable
fun SpotlightLoadingRow(tag: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = LEADERBOARD_ROW_MIN_HEIGHT)
            .padding(horizontal = 8.dp)
            .testTag(tag)
            .clearAndSetSemantics { contentDescription = "Loading your rank" },
    ) {
        FestivalLoading(label = null, size = 24.dp)
    }
}

/**
 * "Not yet ranked" text.
 *
 * @param message Text.
 * @param tag Test tag.
 */
@Composable
fun SpotlightUnrankedRow(message: String, tag: String) {
    Text(
        message,
        style = MaterialTheme.typography.bodySmall,
        color = BrandTokens.textSecondary,
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp).testTag(tag),
    )
}

// endregion

// region Pager

/**
 * « ‹ page / total › » (First, Previous, Next, Last), shared by every paginated board,
 * drawn like the web's floating paginator: each button its own frosted circle and
 * the page label its own frosted pill, in a row the board anchors above the bottom
 * chrome. Both are [GlassCard]s, the rows' own surface (issue #319). The page text is a polite live region ("Page 2 of 34,760"); First/Last
 * collapse on very narrow windows. Every target is at least 48 dp.
 *
 * It draws nothing until the board's page count is known and nothing for a single page
 * (web `hasPagination = !!data && totalPages > 1`; load-transition R4, issue #575), so no
 * board ever shows or announces a placeholder "1 / 1" while its first page loads.
 *
 * @param page Current one-based page.
 * @param totalPages The last loaded board's page count, or null before any board has loaded.
 * @param idPrefix Test-tag prefix (`fst.full-rankings`, …).
 * @param onChange Page change.
 * @param modifier Modifier.
 */
@Composable
fun RankingsPager(page: Int, totalPages: Int?, idPrefix: String, onChange: (Int) -> Unit, modifier: Modifier = Modifier) {
    if (totalPages == null || !RankingPaging.showsPager(totalPages)) return
    val grouping = remember { NumberFormat.getIntegerInstance() }
    // Five 48 dp buttons and the label need ~370 dp: First/Last drop below 400 dp windows.
    val showEnds = LocalConfiguration.current.screenWidthDp >= 400
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier.testTag("$idPrefix.pager"),
    ) {
        if (showEnds) {
            FrostedPagerButton(Icons.Filled.KeyboardDoubleArrowLeft, "First page", "$idPrefix.page-first", page > 1) { onChange(1) }
        }
        FrostedPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous page", "$idPrefix.page-previous", page > 1) { onChange(page - 1) }
        GlassCard(shape = PagerBadgeShape) {
            Text(
                "${grouping.format(page)} / ${grouping.format(totalPages)}",
                style = MaterialTheme.typography.labelLarge,
                color = BrandTokens.textPrimary,
                maxLines = 1,
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .padding(horizontal = 14.dp, vertical = 14.dp)
                    .testTag("$idPrefix.page-info")
                    .semantics {
                        contentDescription = "Page ${grouping.format(page)} of ${grouping.format(totalPages)}"
                        liveRegion = LiveRegionMode.Polite
                    },
            )
        }
        FrostedPagerButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next page", "$idPrefix.page-next", page < totalPages) { onChange(page + 1) }
        if (showEnds) {
            FrostedPagerButton(Icons.Filled.KeyboardDoubleArrowRight, "Last page", "$idPrefix.page-last", page < totalPages) { onChange(totalPages) }
        }
    }
}

/** The page badge's pill shape (the buttons are circles). */
private val PagerBadgeShape = RoundedCornerShape(24.dp)

/**
 * One frosted circular pager button (web `PaginatorButton`, which spreads the rows'
 * `frostedCard`): a 48 dp [GlassCard] circle, so it has the row cards' fill, border and
 * Increase Contrast / Reduce Transparency fallback (issue #319); the glyph dims when
 * disabled. Shared by the boards' pager and the Rank History charts' pagers (operator 7.4).
 *
 * @param icon Glyph.
 * @param label Accessible name.
 * @param tag Test tag.
 * @param enabled Whether it can be pressed.
 * @param onClick Action.
 */
@Composable
internal fun FrostedPagerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, enabled: Boolean, onClick: () -> Unit) {
    GlassCard(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        modifier = Modifier.size(48.dp).testTag(tag).semantics { contentDescription = label; role = Role.Button },
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = if (enabled) BrandTokens.textPrimary else BrandTokens.textDisabled)
        }
    }
}

// endregion

// region Pickers

/**
 * A top-app-bar action that opens a single-choice Material menu (check on the
 * selected item, a Title Case header). Rankings put their view options here, next
 * to search, like Songs' sort/filter actions (Material 3 top app bar actions).
 *
 * @param T Option type.
 * @param label Menu header and accessible name ("Rank By", "Instrument", …).
 * @param options Options in display order.
 * @param selected Current option.
 * @param optionLabel Visible option text.
 * @param onSelect Selection callback.
 * @param tag Test tag of the action.
 * @param itemTag Test tag of each item.
 * @param icon Action glyph.
 * @param leading Optional leading content for items.
 */
@Composable
fun <T> TopBarChoiceAction(
    label: String,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    onSelect: (T) -> Unit,
    tag: String,
    itemTag: (Int, T) -> String = { index, _ -> "$tag.$index" },
    icon: @Composable () -> Unit,
    leading: (@Composable (T) -> Unit)? = null,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(
            onClick = { expanded = true },
            modifier = Modifier
                .testTag(tag)
                .semantics { contentDescription = "$label, ${optionLabel(selected)}" },
        ) { icon() }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = BrandTokens.cardBackground) {
            ChoiceMenuItems(label, options, selected, optionLabel, itemTag, leading) {
                expanded = false
                onSelect(it)
            }
        }
    }
}

/**
 * The single-choice menu's content: a Title Case header, then one item per option with a check on
 * the selected one. Shared by [TopBarChoiceAction] and the First Run Rank By demo.
 *
 * @param T Option type.
 * @param label Header, or null for none (the First Run demo's 220 dp frame).
 * @param options Options in display order.
 * @param selected Current option.
 * @param optionLabel Visible option text.
 * @param itemTag Test tag of each item.
 * @param leading Optional leading content for items.
 * @param onSelect Selection callback.
 */
@Composable
internal fun <T> ChoiceMenuItems(
    label: String?,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    itemTag: (Int, T) -> String,
    leading: (@Composable (T) -> Unit)? = null,
    onSelect: (T) -> Unit,
) {
    if (label != null) {
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }
    options.forEachIndexed { index, option ->
        val isSelected = option == selected
        DropdownMenuItem(
            text = { Text(optionLabel(option), color = BrandTokens.textPrimary) },
            leadingIcon = leading?.let { { it(option) } },
            trailingIcon = if (isSelected) ({ Icon(Icons.Filled.Check, contentDescription = null, tint = BrandTokens.textPrimary) }) else null,
            onClick = { onSelect(option) },
            modifier = Modifier
                .testTag(itemTag(index, option))
                .semantics { stateDescription = if (isSelected) "Selected" else "Not selected" },
        )
    }
}

/**
 * Top-bar Rank By action: a sort icon that opens the metric menu. The one Settings →
 * Experimental Ranks gate for account and band boards: nothing renders while the setting
 * is off (web `{experimentalRanksEnabled && <RankBy…>}`), and the menu offers only
 * [RankingMetric.enabled] (experimental-ranks R1). Leaderboard Rivals reuses it.
 *
 * @param selected Current metric.
 * @param experimentalRanks `AppSettings.experimentalRanks`.
 * @param tagPrefix Test-tag prefix: `<prefix>.rank-by-menu` and `<prefix>.rank-by.<wire id>`.
 * @param onSelect Selection callback.
 */
@Composable
fun RankByAction(selected: RankingMetric, experimentalRanks: Boolean, onSelect: (RankingMetric) -> Unit, tagPrefix: String = "fst.rankings") {
    if (!experimentalRanks) return
    TopBarChoiceAction(
        label = "Rank By",
        options = RankingMetric.enabled(experimentalRanks),
        selected = selected,
        optionLabel = RankingMetric::label,
        onSelect = onSelect,
        tag = "$tagPrefix.rank-by-menu",
        itemTag = { _, metric -> "$tagPrefix.rank-by.${metric.wireId}" },
        icon = { Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null) },
    )
}

/**
 * Band boards' Rank By action: [RankByAction]'s gate with the band metric list
 * ([BandRankingMetric.enabled], web `BAND_RANKING_METRICS`).
 *
 * @param selected Current band metric.
 * @param experimentalRanks `AppSettings.experimentalRanks`.
 * @param onSelect Selection callback.
 */
@Composable
fun BandRankByAction(selected: BandRankingMetric, experimentalRanks: Boolean, onSelect: (BandRankingMetric) -> Unit) {
    if (!experimentalRanks) return
    TopBarChoiceAction(
        label = "Rank By",
        options = BandRankingMetric.enabled(experimentalRanks),
        selected = selected,
        optionLabel = BandRankingMetric::label,
        onSelect = onSelect,
        tag = "fst.band-rankings.rank-by-menu",
        icon = { Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = null) },
    )
}

/**
 * Top-bar instrument action: the current chart's icon, opening the chart menu.
 *
 * @param selected Current chart.
 * @param options Charts offered.
 * @param onSelect Selection callback.
 * @param tag Test tag (items `<tag>.<index>`).
 */
@Composable
fun InstrumentAction(selected: Instrument, options: List<Instrument>, onSelect: (Instrument) -> Unit, tag: String) {
    TopBarChoiceAction(
        label = "Instrument",
        options = options,
        selected = selected,
        optionLabel = Instrument::label,
        onSelect = onSelect,
        tag = tag,
        // Same 24 dp as the Rank By glyph beside it (operator 2026-09-28).
        icon = { InstrumentIcon(selected, size = 24.dp, decorative = true) },
        leading = { PickerInstrumentIcon(it) },
    )
}

/**
 * Instrument icon for picker buttons and menu items.
 *
 * @param instrument Chart.
 */
@Composable
fun PickerInstrumentIcon(instrument: Instrument) {
    InstrumentIcon(instrument, size = 22.dp, decorative = true)
}

/** Band-size glyph for band cards and pickers. */
@Composable
fun BandGlyph() {
    Icon(Icons.Outlined.Groups, contentDescription = null, tint = BrandTokens.textPrimary, modifier = Modifier.size(22.dp))
}

// endregion
