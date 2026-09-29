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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.Immutable
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingEntry
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.asRankingMetric
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat

// region Rows

/** Accent fill for the selected player's row (web `playerEntryRow`, `Colors.purpleHighlight`). */
private val SelectedFill = BrandTokens.accentPurple.copy(alpha = 0.18f)

/** Rating text (web `Colors.accentBlueBright` #4C7DFF). */
private val RatingBlue = Color(0xFF4C7DFF)

/**
 * Fixed column widths shared by every row of one board or card, so the selected
 * player's row (inline or pinned below) lines up with the rest (web `RankingEntry`
 * `rankWidth` / reserved score width; operator batch 7, 7.9).
 *
 * @property rank Rank column.
 * @property songs "X / Y" column.
 * @property rating Rating column.
 */
@Immutable
data class RankingColumns(val rank: Dp, val songs: Dp, val rating: Dp)

/** Column widths for the rows below, or null for intrinsic widths. */
val LocalRankingColumns = compositionLocalOf<RankingColumns?> { null }

/**
 * Measure the widest rank, songs and rating text (bold, as the selected row draws them).
 *
 * @param ranks Rank labels.
 * @param songs Songs labels.
 * @param ratings Rating labels.
 * @return Column widths.
 */
@Composable
fun rememberRankingColumns(ranks: List<String>, songs: List<String>, ratings: List<String>): RankingColumns {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    return remember(ranks, songs, ratings, density, typography) {
        fun widest(texts: List<String>, style: TextStyle, minimum: Dp): Dp = with(density) {
            val px = texts.maxOfOrNull { measurer.measure(it, style.copy(fontWeight = FontWeight.Bold), maxLines = 1).size.width } ?: 0
            maxOf(px.toDp() + 2.dp, minimum)
        }
        RankingColumns(
            rank = widest(ranks, typography.bodyMedium, 44.dp),
            songs = widest(songs, typography.bodyMedium, 0.dp),
            rating = widest(ratings, typography.bodyLarge, 0.dp),
        )
    }
}

/**
 * [rememberRankingColumns] for account rows.
 *
 * @param entries Rows sharing the columns (page rows plus the selected player's pinned row).
 * @param metric Rank By metric.
 * @return Column widths.
 */
@Composable
fun rememberAccountColumns(entries: List<AccountRankingEntry>, metric: RankingMetric): RankingColumns = rememberRankingColumns(
    entries.map { RankingFormatting.rankLabel(it.rank(metric)) },
    entries.map { it.songsLabel(metric) },
    entries.map { RankingFormatting.rating(it.ratingValue(metric), metric) },
)

/**
 * [rememberRankingColumns] for band rows.
 *
 * @param entries Rows sharing the columns.
 * @param metric Band metric.
 * @return Column widths.
 */
@Composable
fun rememberBandColumns(entries: List<BandRankingEntry>, metric: BandRankingMetric): RankingColumns = rememberRankingColumns(
    entries.map { RankingFormatting.rankLabel(it.rank(metric)) },
    entries.map { it.songsLabel(metric) },
    entries.map { RankingFormatting.rating(it.ratingValue(metric), metric.asRankingMetric) },
)

/**
 * The one-line rank · name · "X / Y" · rating layout shared by account and band rows
 * (web `RankingEntry`: accent-blue rating, songs as a bare fraction).
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
    modifier: Modifier = Modifier,
) {
    val description = RankingFormatting.rowDescription(rank, name, rating, songs, isSelected)
    val shape = RoundedCornerShape(10.dp)
    var rowModifier = modifier
        .fillMaxWidth()
        .heightIn(min = 48.dp)
        .clip(shape)
    if (isSelected) rowModifier = rowModifier.background(SelectedFill).border(BorderStroke(1.dp, BrandTokens.accentPurple), shape)
    if (route != null) rowModifier = rowModifier.clickable(role = Role.Button, onClickLabel = "Open") { onOpen(route) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = rowModifier
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .testTag(tag)
            .clearAndSetSemantics {
                contentDescription = description
                if (route == null) stateDescription = "Profile unavailable"
            },
    ) {
        // Web `RankingEntry` `isPlayer`: every text in the selected player's row is bold.
        val weight = if (isSelected) FontWeight.Bold else null
        val columns = LocalRankingColumns.current
        Text(
            RankingFormatting.rankLabel(rank),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = weight,
            color = BrandTokens.textPrimary,
            maxLines = 1,
            modifier = columns?.let { Modifier.width(it.rank) } ?: Modifier.widthIn(min = 44.dp),
        )
        Text(name, style = MaterialTheme.typography.bodyLarge, fontWeight = weight, color = BrandTokens.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(
            songs,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = weight,
            color = BrandTokens.textSecondary,
            maxLines = 1,
            textAlign = TextAlign.End,
            modifier = columns?.let { Modifier.width(it.songs) } ?: Modifier,
        )
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
 * One account rankings row; opens the player (Statistics for the selected player).
 * Anonymous rows show "Unknown User" and are not interactive.
 *
 * @param entry Row.
 * @param metric Selected metric.
 * @param isSelected Selected player's own row.
 * @param route Destination or null.
 * @param onOpen Navigation callback.
 * @param tag Test tag; defaults to `fst.rankings.row.<key>`.
 * @param reveal Scroll the selected row into view when it appears (paginated boards).
 */
@Composable
fun AccountRankingRow(
    entry: AccountRankingEntry,
    metric: RankingMetric,
    isSelected: Boolean,
    route: AppRoute?,
    onOpen: (AppRoute) -> Unit,
    tag: String = "fst.rankings.row.${entry.key}",
    reveal: Boolean = false,
) {
    val requester = remember { BringIntoViewRequester() }
    if (reveal && isSelected) {
        LaunchedEffect(entry.key) { requester.bringIntoView() }
    }
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
        modifier = Modifier.bringIntoViewRequester(requester),
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
 * Static skeleton rows (no shimmer, so no per-frame work while loading).
 *
 * @param count Rows.
 */
@Composable
fun RankingsSkeletonRows(count: Int) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 8.dp)
            .testTag("fst.rankings.skeleton")
            .clearAndSetSemantics { contentDescription = "Loading rankings" },
    ) {
        repeat(count) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SkeletonBar(32)
                SkeletonBar(128)
                Spacer(Modifier.weight(1f))
                SkeletonBar(56)
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
            .heightIn(min = 48.dp)
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
 * chrome. The page text is a polite live region ("Page 2 of 34,760"); First/Last
 * collapse on very narrow windows. Every target is at least 48 dp.
 *
 * @param page Current one-based page.
 * @param totalPages Page count.
 * @param idPrefix Test-tag prefix (`fst.full-rankings`, …).
 * @param onChange Page change.
 * @param modifier Modifier.
 */
@Composable
fun RankingsPager(page: Int, totalPages: Int, idPrefix: String, onChange: (Int) -> Unit, modifier: Modifier = Modifier) {
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
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = PagerSurface,
            border = BorderStroke(1.dp, BrandTokens.glassBorder),
            shadowElevation = 4.dp,
        ) {
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

/** Opaque frosted fill for the floating pager, legible over rows scrolling beneath it. */
private val PagerSurface: Color get() = BrandTokens.cardBackground.copy(alpha = 0.96f)

/**
 * One frosted circular pager button (web `PaginatorButton`): 48 dp, dimmed when disabled.
 * Shared by the boards' pager and the Rank History charts' pagers (operator 7.4).
 *
 * @param icon Glyph.
 * @param label Accessible name.
 * @param tag Test tag.
 * @param enabled Whether it can be pressed.
 * @param onClick Action.
 */
@Composable
internal fun FrostedPagerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, enabled: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        color = PagerSurface,
        border = BorderStroke(1.dp, BrandTokens.glassBorder),
        shadowElevation = 4.dp,
        modifier = Modifier.size(48.dp).testTag(tag).semantics { contentDescription = label },
    ) {
        Box(contentAlignment = Alignment.Center) {
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
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                color = BrandTokens.textPrimary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            options.forEachIndexed { index, option ->
                val isSelected = option == selected
                DropdownMenuItem(
                    text = { Text(optionLabel(option), color = BrandTokens.textPrimary) },
                    leadingIcon = leading?.let { { it(option) } },
                    trailingIcon = if (isSelected) ({ Icon(Icons.Filled.Check, contentDescription = null, tint = BrandTokens.textPrimary) }) else null,
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                    modifier = Modifier
                        .testTag(itemTag(index, option))
                        .semantics { stateDescription = if (isSelected) "Selected" else "Not selected" },
                )
            }
        }
    }
}

/**
 * Top-bar Rank By action: a sort icon that opens the metric menu.
 *
 * @param selected Current metric.
 * @param onSelect Selection callback.
 * @param options Metrics offered.
 */
@Composable
fun RankByAction(selected: RankingMetric, onSelect: (RankingMetric) -> Unit, options: List<RankingMetric> = RankingMetric.entries) {
    TopBarChoiceAction(
        label = "Rank By",
        options = options,
        selected = selected,
        optionLabel = RankingMetric::label,
        onSelect = onSelect,
        tag = "fst.rankings.rank-by-menu",
        itemTag = { _, metric -> "fst.rankings.rank-by.${metric.wireId}" },
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
