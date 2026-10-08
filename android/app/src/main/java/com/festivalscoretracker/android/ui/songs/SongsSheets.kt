package com.festivalscoretracker.android.ui.songs

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import com.festivalscoretracker.android.core.songs.SongBucketKind
import com.festivalscoretracker.android.core.songs.SongCatalogBuckets
import com.festivalscoretracker.android.core.songs.SongGeneralBucketKind
import com.festivalscoretracker.android.core.songs.SongIntensityBucket
import com.festivalscoretracker.android.core.songs.SongPercentileBucket
import com.festivalscoretracker.android.core.songs.SongSeasonBucket
import com.festivalscoretracker.android.core.songs.SongStarsBucket
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.InstrumentSelector
import com.festivalscoretracker.android.ui.design.StarRating
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.songs.SongFilterDraft
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.presentation.SongsUiState
import com.festivalscoretracker.android.ui.settings.ReorderList
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.FestivalModalSheet
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.ui.platform.LocalDensity
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy


// region Live sheet frame

/**
 * Bottom sheet whose changes apply immediately (operator rule: no Cancel/Apply and
 * no discard confirmation). Reset restores defaults (also live); the shared header Close (tag `$tag.done`) dismisses.
 * Reset sits below the form, or in the header on compact-height windows.
 *
 * @param title Title Case header.
 * @param tag Test tag root.
 * @param onReset Restore defaults.
 * @param onDismiss Close.
 * @param titleTag Header title test tag (Sort passes `.heading`: its `.title` is the Title choice).
 * @param content Form.
 */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
internal fun LiveSheet(
    title: String,
    tag: String,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
    titleTag: String = "$tag.title",
    content: @Composable () -> Unit,
) {
    // Compact-height windows (landscape phones, folded landscape) move Reset into the header:
    // a pinned footer there left the form a sliver at large text (issue #126).
    val heightDp = with(LocalDensity.current) { currentWindowSize().height.toDp().value.toInt() }
    val resetInHeader = AdaptiveLayoutPolicy.isCompactHeight(heightDp)
    val reset = @Composable {
        // Destructive action in red (operator 7.10).
        TextButton(
            onClick = onReset,
            colors = ButtonDefaults.textButtonColors(contentColor = RESET_RED),
            modifier = Modifier.testTag("$tag.reset"),
        ) { Text("Reset", fontWeight = FontWeight.SemiBold) }
    }
    // The shared header's Close replaces the former Done (changes are already applied); it
    // keeps the `.done` test tag, like Apple's `FestivalSheetCloseItem`.
    FestivalModalSheet(
        title = title,
        closeTag = "$tag.done",
        titleTag = titleTag,
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag(tag),
        headerActions = { if (resetInHeader) reset() },
    ) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp)) {
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).testTag("$tag.form")) { content() }
            if (!resetInHeader) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp)) { reset() }
            }
        }
    }
}

// endregion

// region Sort

/**
 * Sort Songs (web `SortModal`): general modes (Has FC and Last Played with a
 * player), single-chart modes and the metadata sort priority while filtered to
 * one chart, and the direction. Every change applies immediately.
 *
 * @param state Songs state (saved sort, player, Shop, chart filter, visible metadata).
 * @param onApply Persist the sort.
 * @param onDismiss Close.
 */
@Composable
fun SortSheet(state: SongsUiState, onApply: (SongSortDraft) -> Unit, onDismiss: () -> Unit) {
    var sort by remember { mutableStateOf(SongSortDraft(state.sort, state.ascending, state.prefs.metadataOrder)) }
    val draft = sort
    fun change(next: SongSortDraft) {
        sort = next
        onApply(next)
    }
    val chartModes = SongSortDraft.chartModes(state.hasPlayer, state.sortChart, state.visibleMetadata)
    val priority = if (state.hasPlayer && state.sortChart != null) SongSortDraft.visiblePriority(draft.metadataOrder, state.visibleMetadata) else emptyList()
    LiveSheet(title = "Sort Songs", tag = "fst.songs.sort", onReset = { change(draft.reset()) }, onDismiss = onDismiss, titleTag = "fst.songs.sort.heading") {
        Column(Modifier.selectableGroup().testTag("fst.songs.sort.mode")) {
            SongSortDraft.modes(state.hideShop, state.hasPlayer).forEach { option ->
                RadioRow(option.label, option == draft.mode, "fst.songs.sort.${option.name.lowercase()}") { change(draft.copy(mode = option)) }
            }
        }
        if (chartModes.isNotEmpty()) {
            SectionHeader("${state.sortChart!!.label} Sort Mode")
            Text("Filtering to a single instrument enables more sort options.", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
            Column(Modifier.selectableGroup().testTag("fst.songs.sort.chart-mode")) {
                chartModes.forEach { option ->
                    RadioRow(option.label, option == draft.mode, "fst.songs.sort.${option.name.lowercase()}") { change(draft.copy(mode = option)) }
                }
            }
        }
        SortDirectionSection(draft.ascending, "fst.songs.sort") { change(draft.copy(ascending = it)) }
        if (priority.isNotEmpty()) {
            SectionHeader("Metadata Sort Priority")
            Text(
                "Song rows show metadata in this order (after the sort's own field) while Independent Song Row Visual Order is off in Settings.",
                color = BrandTokens.textSecondary,
                style = MaterialTheme.typography.bodySmall,
            )
            ReorderList(priority.map { it.label }, "fst.songs.sort.priority") { index, offset ->
                change(draft.move(state.visibleMetadata, index, offset))
            }
        }
    }
}

/**
 * The Sort sheets' "Sort Direction" section (Songs and Item Shop, issue #379): a heading and a
 * radio group of [DirectionRow]s tagged `$tag.direction`, `$tag.ascending` and `$tag.descending`.
 *
 * @param ascending Current direction.
 * @param tag Sheet test-tag root.
 * @param onChange Choose a direction (true = ascending).
 */
@Composable
internal fun SortDirectionSection(ascending: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    SectionHeader("Sort Direction")
    Column(Modifier.selectableGroup().testTag("$tag.direction")) {
        DirectionRow("Ascending", "A–Z, low–high", Icons.Filled.ArrowUpward, ascending, "$tag.ascending") { onChange(true) }
        DirectionRow("Descending", "Z–A, high–low", Icons.Filled.ArrowDownward, !ascending, "$tag.descending") { onChange(false) }
    }
}

/**
 * One direction choice (operator 7.21): the web's ↑/↓ circle (purple when chosen) with
 * the direction as the title and its meaning as the subtitle.
 */
@Composable
internal fun DirectionRow(title: String, subtitle: String, icon: ImageVector, selected: Boolean, tag: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .testTag(tag),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(40.dp).clip(CircleShape).background(if (selected) BrandTokens.accentPurple else BrandTokens.surfaceMuted),
        ) { Icon(icon, contentDescription = null, tint = if (selected) BrandTokens.textPrimary else BrandTokens.textMuted, modifier = Modifier.size(20.dp)) }
        Column(Modifier.weight(1f)) {
            Text(title, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
        }
    }
}

/** Web danger red for Reset text (readable on the dark sheet). */
private val RESET_RED = Color(0xFFFF6B6B)

@Composable
internal fun RadioRow(label: String, selected: Boolean, tag: String, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .testTag(tag),
    ) {
        RadioButton(selected = selected, onClick = null)
        Spacer(Modifier.width(12.dp))
        if (leading != null) {
            leading()
            Spacer(Modifier.width(8.dp))
        }
        Text(label, color = BrandTokens.textPrimary)
    }
}

// endregion

// region Filter

/**
 * Filter Songs, structured like the web `FilterModal`: General (Year, Duration, Item Shop
 * while shown, Double Bass) always; with a selected player also Global Score & FC
 * Toggles, Individual Score & FC Toggles per instrument and Selected Instrument
 * Filters — the shared Instrument Selector (deferred selection) revealing Season,
 * Percentile, Stars and Song Intensity bucket toggles with Select All / Clear All.
 * Every section is a collapsible group (web `Accordion`); toggles are switches with the
 * web's descriptions. Every change applies immediately.
 *
 * @param initial Draft seeded from saved values.
 * @param hasPlayer Show the player score and Selected Instrument sections.
 * @param hideShop Item Shop availability removed (a saved choice stays until Reset).
 * @param onApply Persist the filters.
 * @param onDismiss Close.
 * @param filterInvalidScores Offer Over CHOpt Threshold checks.
 * @param availableSeasons Seasons in the selected player's scores (Season buckets).
 * @param keyboard Keys artwork for Lead/Pro Lead in the selector.
 * @param decades Catalogue release decades (Year toggles).
 * @param durations Catalogue duration buckets (Duration toggles).
 */
@Composable
fun FilterSheet(
    initial: SongFilterDraft,
    hasPlayer: Boolean,
    hideShop: Boolean,
    onApply: (SongFilterDraft) -> Unit,
    onDismiss: () -> Unit,
    filterInvalidScores: Boolean = false,
    availableSeasons: List<Int> = emptyList(),
    keyboard: Boolean = false,
    decades: List<Int> = emptyList(),
    durations: List<Int> = emptyList(),
) {
    var filters by remember { mutableStateOf(initial) }
    val draft = filters
    fun change(next: SongFilterDraft) {
        filters = next
        if (next.isValid) onApply(next)
    }
    val kinds = SongScoreFilterKind.offered(filterInvalidScores)
    val visible = Instrument.entries.filter { it in draft.visible }
    LiveSheet(title = "Filter Songs", tag = "fst.songs.filter", onReset = { change(draft.reset()) }, onDismiss = onDismiss) {
        GeneralFilters(draft, decades, durations, hideShop, ::change)
        if (hasPlayer) {
            Column(Modifier.testTag("fst.songs.filter.score-sections")) {
                Accordion(
                    title = "Global Score & FC Toggles",
                    hint = "Toggles that impact visible instruments. Turning these on or off will enable or disable them across the instruments shown in app settings.",
                    tag = "fst.songs.filter.global",
                    initiallyOpen = kinds.any(draft::allOn),
                ) {
                    kinds.forEach { kind ->
                        ToggleRow(kind.label, kind.globalDescription, draft.allOn(kind), enabled = true, tag = "fst.songs.filter.score.global.${kind.name}") { change(draft.withAll(kind, it)) }
                    }
                }
                SectionHeader("Individual Score & FC Toggles")
                Hint("Toggles that impact individual instruments. These filters are computed per-instrument and then combined with other instruments.")
                if (draft.hasHiddenChecks) {
                    Hint(
                        "Some saved checks are for instruments hidden in Settings; they stay inactive and are removed when you change a filter.",
                        Modifier.testTag("fst.songs.score-filter-hidden"),
                    )
                }
                visible.forEach { chart ->
                    Accordion(
                        title = chart.label,
                        tag = "fst.songs.filter.score.chart.${chart.wireId}",
                        icon = { InstrumentIcon(chart, keyboard = keyboard, size = 28.dp, decorative = true) },
                        initiallyOpen = kinds.any { draft.playerFilter.contains(it, chart) },
                    ) {
                        kinds.forEach { kind ->
                            ToggleRow(
                                kind.chartLabel(chart),
                                kind.chartDescription(chart),
                                draft.playerFilter.contains(kind, chart),
                                enabled = true,
                                tag = "fst.songs.filter.score.instrument.${chart.wireId}.${kind.name}",
                            ) { change(draft.withCheck(kind, chart, it)) }
                        }
                    }
                }
            }
            SectionHeader("Selected Instrument Filters")
            Hint("Select an instrument to only show its metadata on each song row. When none is selected, all instruments are shown.")
            InstrumentSelector(
                instruments = visible,
                selected = draft.filter.instrument,
                onSelect = { change(draft.withInstrument(it)) },
                deferSelection = true,
                keyboard = keyboard,
                tag = "fst.songs.filter.instrument",
                modifier = Modifier.padding(vertical = 8.dp),
            ) {
                Column {
                    SongBucketKind.entries.forEach { kind ->
                        val keys = when (kind) {
                            SongBucketKind.Season -> SongSeasonBucket.keys(availableSeasons)
                            SongBucketKind.Percentile -> SongPercentileBucket.KEYS
                            SongBucketKind.Stars -> SongStarsBucket.KEYS
                            SongBucketKind.Intensity -> SongIntensityBucket.KEYS
                        }
                        val hidden = draft.excluded(kind)
                        Accordion(kind.title, kind.hint, "fst.songs.filter.${kind.name.lowercase()}", initiallyOpen = hidden.isNotEmpty()) {
                            BulkActions(
                                tag = "fst.songs.filter.${kind.name.lowercase()}",
                                onSelectAll = { change(draft.withAllBuckets(kind, keys, shown = true)) },
                                onClearAll = { change(draft.withAllBuckets(kind, keys, shown = false)) },
                            )
                            keys.forEach { key ->
                                BucketRow(kind, key, key !in hidden, "fst.songs.filter.${kind.name.lowercase()}.$key") { change(draft.withBucket(kind, key, it)) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Web `FilterModal` General section: Year and Duration bucket toggles (Select All /
 * Clear All), Item Shop availability (only while the Shop is shown) and Double Bass.
 *
 * @param draft Current draft.
 * @param decades Year keys.
 * @param durations Duration keys.
 * @param hideShop Item Shop hidden in Settings.
 * @param change Apply a new draft.
 */
@Composable
private fun GeneralFilters(draft: SongFilterDraft, decades: List<Int>, durations: List<Int>, hideShop: Boolean, change: (SongFilterDraft) -> Unit) {
    val general = draft.general
    Column(Modifier.testTag("fst.songs.filter.general")) {
        SectionHeader("General")
        Hint("General filters that apply to all songs.")
        GeneralBuckets(draft, SongGeneralBucketKind.Year, decades, "Year", "Filter songs by their release decade.", "fst.songs.filter.year", change)
        GeneralBuckets(draft, SongGeneralBucketKind.Duration, durations, "Duration", "Filter songs by their duration.", "fst.songs.filter.duration", change)
        if (!hideShop) {
            Accordion(
                title = "Item Shop",
                hint = "Filter songs by whether they are available in the Item Shop.",
                tag = "fst.songs.filter.shop",
                initiallyOpen = general.shopActive,
            ) {
                ToggleRow("Available in Item Shop", null, general.shopAvailable, enabled = true, tag = "fst.songs.filter.shop-available") {
                    change(draft.copy(general = general.copy(shopAvailable = it)))
                }
                ToggleRow("Not Available in Item Shop", null, general.shopUnavailable, enabled = true, tag = "fst.songs.filter.shop-unavailable") {
                    change(draft.copy(general = general.copy(shopUnavailable = it)))
                }
            }
        }
        Accordion(
            title = "Double Bass",
            hint = "Filter songs that have or don't have double bass charts for Pro Drums.",
            tag = "fst.songs.filter.double-bass",
            initiallyOpen = !general.doubleBassSupported || !general.doubleBassUnsupported,
        ) {
            ToggleRow("Double Bass Support", null, general.doubleBassSupported, enabled = true, tag = "fst.songs.filter.double-bass.supported") {
                change(draft.copy(general = general.copy(doubleBassSupported = it)))
            }
            ToggleRow("No Double Bass Support", null, general.doubleBassUnsupported, enabled = true, tag = "fst.songs.filter.double-bass.unsupported") {
                change(draft.copy(general = general.copy(doubleBassUnsupported = it)))
            }
        }
    }
}

/** One Year/Duration group (web `CatalogBucketToggles`); omitted until the catalogue lists keys. */
@Composable
private fun GeneralBuckets(
    draft: SongFilterDraft,
    kind: SongGeneralBucketKind,
    keys: List<Int>,
    title: String,
    hint: String,
    tag: String,
    change: (SongFilterDraft) -> Unit,
) {
    if (keys.isEmpty()) return
    val hidden = draft.general.excluded(kind)
    Accordion(title, hint, tag, initiallyOpen = hidden.isNotEmpty()) {
        BulkActions(
            tag = tag,
            onSelectAll = { change(draft.withAllGeneralBuckets(kind, keys, shown = true)) },
            onClearAll = { change(draft.withAllGeneralBuckets(kind, keys, shown = false)) },
        )
        keys.forEach { key ->
            val label = if (kind == SongGeneralBucketKind.Year) SongCatalogBuckets.decadeLabel(key) else SongCatalogBuckets.durationLabel(key)
            ToggleRow(label, null, key !in hidden, enabled = true, tag = "$tag.$key") { change(draft.withGeneralBucket(kind, key, it)) }
        }
    }
}

/** Web global-toggle descriptions. */
internal val SongScoreFilterKind.globalDescription: String
    get() = when (this) {
        SongScoreFilterKind.MissingScores -> "Songs missing scores on any visible instrument."
        SongScoreFilterKind.HasScores -> "Songs with scores on any visible instrument."
        SongScoreFilterKind.MissingFCs -> "Songs missing FCs on any visible instrument."
        SongScoreFilterKind.HasFCs -> "Songs with FCs on any visible instrument."
        SongScoreFilterKind.OverThreshold -> "Songs with scores above the configured CHOpt max score threshold in app settings."
    }

/** Web per-instrument toggle labels ("Missing Lead Scores"). */
internal fun SongScoreFilterKind.chartLabel(chart: Instrument): String = when (this) {
    SongScoreFilterKind.MissingScores -> "Missing ${chart.label} Scores"
    SongScoreFilterKind.HasScores -> "Has ${chart.label} Scores"
    SongScoreFilterKind.MissingFCs -> "Missing ${chart.label} FCs"
    SongScoreFilterKind.HasFCs -> "Has ${chart.label} FCs"
    SongScoreFilterKind.OverThreshold -> "${chart.label} Over CHOpt Threshold"
}

/** Web per-instrument toggle descriptions. */
internal fun SongScoreFilterKind.chartDescription(chart: Instrument): String = when (this) {
    SongScoreFilterKind.MissingScores -> "Songs missing scores on ${chart.label}."
    SongScoreFilterKind.HasScores -> "Songs with scores on ${chart.label}."
    SongScoreFilterKind.MissingFCs -> "Songs missing FCs on ${chart.label}."
    SongScoreFilterKind.HasFCs -> "Songs with FCs on ${chart.label}."
    SongScoreFilterKind.OverThreshold -> "Songs with ${chart.label} scores above the configured CHOpt max score threshold in app settings."
}

/**
 * A collapsible group (web `Accordion`): a heading row with optional icon and a
 * rotating chevron; the hint and content expand below it.
 */
@Composable
private fun Accordion(
    title: String,
    hint: String? = null,
    tag: String,
    initiallyOpen: Boolean = false,
    icon: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    var open by rememberSaveable(tag) { mutableStateOf(initiallyOpen) }
    val rotation by animateFloatAsState(if (open) 180f else 0f, label = "accordionChevron")
    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(BrandTokens.surfaceFrosted)
                .toggleable(value = open, role = Role.Button, onValueChange = { open = it })
                .padding(horizontal = 12.dp)
                .semantics { heading(); stateDescription = if (open) "Expanded" else "Collapsed" }
                .testTag(tag),
        ) {
            if (icon != null) {
                icon()
                Spacer(Modifier.width(10.dp))
            }
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = BrandTokens.textSecondary, modifier = Modifier.graphicsLayer { rotationZ = rotation })
        }
        AnimatedVisibility(visible = open, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            Column(Modifier.padding(horizontal = 4.dp).testTag("$tag.content")) {
                hint?.let { Hint(it) }
                content()
            }
        }
    }
}

/** Secondary hint text under a filter section (also used by the Item Shop filter sheet). */
@Composable
internal fun Hint(text: String, modifier: Modifier = Modifier) {
    Text(text, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall, modifier = modifier.padding(vertical = 4.dp))
}

/** Web `BulkActions` as trailing text actions on the section's header line (operator 7.17). */
@Composable
private fun BulkActions(tag: String, onSelectAll: () -> Unit, onClearAll: () -> Unit) {
    Row(horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        TextButton(onClick = onSelectAll, modifier = Modifier.testTag("$tag.select-all")) { Text("Select All") }
        TextButton(onClick = onClearAll, modifier = Modifier.testTag("$tag.clear-all")) { Text("Clear All") }
    }
}

/**
 * One bucket toggle: "Season 9" / "Top 5%" / star images / the intensity meter, or
 * "No Score"; the switch shows whether songs in the bucket are shown.
 */
@Composable
private fun BucketRow(kind: SongBucketKind, key: Int, shown: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    val spoken = bucketLabel(kind, key)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(value = shown, role = Role.Switch, onValueChange = onChange)
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .testTag(tag),
    ) {
        // The row speaks the bucket; the meter's or stars' own label would repeat it.
        Box(Modifier.weight(1f).clearAndSetSemantics { }) {
            when {
                key == 0 -> Text("No Score", color = BrandTokens.textPrimary)
                kind == SongBucketKind.Stars -> StarRating(key, size = 16.dp)
                kind == SongBucketKind.Intensity -> DifficultyMeter((key - 1).toDouble())
                else -> Text(spoken, color = BrandTokens.textPrimary)
            }
        }
        Switch(checked = shown, onCheckedChange = null)
    }
}

/**
 * Spoken/visible bucket label.
 *
 * @param kind Section.
 * @param key Key.
 * @return Label.
 */
internal fun bucketLabel(kind: SongBucketKind, key: Int): String = when {
    key == 0 -> "No Score"
    kind == SongBucketKind.Season -> "Season $key"
    kind == SongBucketKind.Percentile -> "Top $key%"
    kind == SongBucketKind.Stars -> when {
        key >= 6 -> "Gold stars"
        key == 1 -> "1 star"
        else -> "$key stars"
    }
    else -> "Intensity $key of 7"
}

/** Web `ToggleRow`: label, description and a switch; the whole row toggles. */
@Composable
internal fun ToggleRow(label: String, description: String?, checked: Boolean, enabled: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 4.dp)
            .testTag(tag),
    ) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(label, color = if (enabled) BrandTokens.textPrimary else BrandTokens.textDisabled, fontWeight = FontWeight.SemiBold)
            description?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = if (enabled) BrandTokens.textSecondary else BrandTokens.textDisabled) }
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

// endregion
