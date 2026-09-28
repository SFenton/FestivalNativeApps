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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FirstPage
import androidx.compose.material.icons.filled.LastPage
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.BandRankingEntry
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.rankings.RankingFormatting
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rankings.asRankingMetric
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat

// region Rows

/** Accent fill for the selected player's row (web `playerEntryRow`, `Colors.purpleHighlight`). */
private val SelectedFill = BrandTokens.accentPurple.copy(alpha = 0.18f)

/**
 * The rank / name + songs / rating layout shared by account and band rows.
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
        Text(
            RankingFormatting.rankLabel(rank),
            style = MaterialTheme.typography.bodyMedium,
            color = BrandTokens.textSecondary,
            maxLines = 1,
            modifier = Modifier.widthIn(min = 44.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("$songs songs", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = 1)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(rating, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = 1)
            if (bayesian != null) {
                Text(bayesian, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textSecondary, maxLines = 1)
            }
        }
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
        CircularProgressIndicator(Modifier.size(18.dp), color = BrandTokens.textPrimary, strokeWidth = 2.dp)
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
 * First / Previous / "page / total" / Next / Last, shared by every paginated board.
 * The page text is a polite live region ("Page 2 of 34,760"); First/Last collapse on
 * very narrow windows. Every target is at least 48 dp.
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
    val showEnds = LocalConfiguration.current.screenWidthDp >= 360
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier.fillMaxWidth().testTag("$idPrefix.pager"),
    ) {
        if (showEnds) {
            IconButton(onClick = { onChange(1) }, enabled = page > 1, modifier = Modifier.testTag("$idPrefix.page-first")) {
                Icon(Icons.Filled.FirstPage, contentDescription = "First page")
            }
        }
        IconButton(onClick = { onChange(page - 1) }, enabled = page > 1, modifier = Modifier.testTag("$idPrefix.page-previous")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous page")
        }
        Text(
            "${grouping.format(page)} / ${grouping.format(totalPages)}",
            style = MaterialTheme.typography.labelLarge,
            color = BrandTokens.textPrimary,
            modifier = Modifier
                .padding(horizontal = 8.dp)
                .testTag("$idPrefix.page-info")
                .semantics {
                    contentDescription = "Page ${grouping.format(page)} of ${grouping.format(totalPages)}"
                    liveRegion = LiveRegionMode.Polite
                },
        )
        IconButton(onClick = { onChange(page + 1) }, enabled = page < totalPages, modifier = Modifier.testTag("$idPrefix.page-next")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next page")
        }
        if (showEnds) {
            IconButton(onClick = { onChange(totalPages) }, enabled = page < totalPages, modifier = Modifier.testTag("$idPrefix.page-last")) {
                Icon(Icons.Filled.LastPage, contentDescription = "Last page")
            }
        }
    }
}

// endregion

// region Pickers

/**
 * A single-choice dropdown picker: an outlined button showing the current value that
 * opens a Material menu with a check on the selected item.
 *
 * @param T Option type.
 * @param label Accessible name of the picker ("Rank by", "Instrument", …).
 * @param options Options in display order.
 * @param selected Current option.
 * @param optionLabel Visible option text.
 * @param onSelect Selection callback.
 * @param tag Test tag of the button; items get `<tag>.<index>`.
 * @param leading Optional leading content for the button and items.
 * @param modifier Modifier.
 */
@Composable
fun <T> ChoicePicker(
    label: String,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    onSelect: (T) -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
    leading: (@Composable (T) -> Unit)? = null,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedButton(
            onClick = { expanded = true },
            border = BorderStroke(1.dp, BrandTokens.glassBorder.copy(alpha = 0.4f)),
            modifier = Modifier
                .heightIn(min = 48.dp)
                .testTag(tag)
                .semantics { contentDescription = "$label, ${optionLabel(selected)}" },
        ) {
            leading?.invoke(selected)
            Text(
                optionLabel(selected),
                color = BrandTokens.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = if (leading != null) 8.dp else 0.dp),
            )
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = BrandTokens.textPrimary)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = BrandTokens.cardBackground) {
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
                        .testTag("$tag.$index")
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
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(
            onClick = { expanded = true },
            modifier = Modifier.testTag("fst.rankings.rank-by-menu"),
        ) {
            Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Rank by, ${selected.label}")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = BrandTokens.cardBackground) {
            Text(
                "Rank By",
                style = MaterialTheme.typography.labelLarge,
                color = BrandTokens.textSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            options.forEach { metric ->
                val isSelected = metric == selected
                DropdownMenuItem(
                    text = { Text(metric.label, color = BrandTokens.textPrimary) },
                    trailingIcon = if (isSelected) ({ Icon(Icons.Filled.Check, contentDescription = null, tint = BrandTokens.textPrimary) }) else null,
                    onClick = {
                        expanded = false
                        onSelect(metric)
                    },
                    modifier = Modifier
                        .testTag("fst.rankings.rank-by.${metric.wireId}")
                        .semantics { stateDescription = if (isSelected) "Selected" else "Not selected" },
                )
            }
        }
    }
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
    Icon(Icons.Outlined.Groups, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.size(22.dp))
}

// endregion
