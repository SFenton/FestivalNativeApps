package com.festivalscoretracker.android.ui.songs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember

import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
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
import kotlin.math.roundToInt

// region Live sheet frame

/**
 * Bottom sheet whose changes apply immediately (operator rule: no Cancel/Apply and
 * no discard confirmation). Reset restores defaults (also live); Done closes.
 *
 * @param title Title Case header.
 * @param tag Test tag root.
 * @param onReset Restore defaults.
 * @param onDismiss Close.
 * @param content Form.
 */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
private fun LiveSheet(
    title: String,
    tag: String,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.testTag(tag),
    ) {
        Column(Modifier.semantics { testTagsAsResourceId = true }.padding(horizontal = 24.dp).padding(bottom = 16.dp)) {
            SectionHeader(title, Modifier.testTag("$tag.title"))
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).testTag("$tag.form")) { content() }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp)) {
                TextButton(onClick = onReset, modifier = Modifier.testTag("$tag.reset")) { Text("Reset") }
                Spacer(Modifier.weight(1f))
                Button(onClick = onDismiss, modifier = Modifier.testTag("$tag.done")) { Text("Done") }
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
    LiveSheet(title = "Sort Songs", tag = "fst.songs.sort", onReset = { change(draft.reset()) }, onDismiss = onDismiss) {
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
        SectionHeader("Direction")
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("fst.songs.sort.direction")) {
            listOf(true to "Ascending", false to "Descending").forEachIndexed { index, (value, label) ->
                SegmentedButton(
                    selected = draft.ascending == value,
                    onClick = { change(draft.copy(ascending = value)) },
                    shape = SegmentedButtonDefaults.itemShape(index, 2),
                    modifier = Modifier.testTag("fst.songs.sort.${label.lowercase()}"),
                ) { Text(label) }
            }
        }
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

@Composable
private fun RadioRow(label: String, selected: Boolean, tag: String, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
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
 * Filter Songs: instrument and difficulty, Item Shop toggles, and the selected
 * player's per-chart score/FC checks (plus Over CHOpt Threshold while Filter
 * Invalid Scores is on). Every change applies immediately.
 *
 * @param initial Draft seeded from saved values.
 * @param hasPlayer Show the player score section.
 * @param hideShop Shop toggles disabled (still clearable by Reset).
 * @param filterInvalidScores Offer Over CHOpt Threshold checks.
 * @param onApply Persist the filters.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterSheet(
    initial: SongFilterDraft,
    hasPlayer: Boolean,
    hideShop: Boolean,
    onApply: (SongFilterDraft) -> Unit,
    onDismiss: () -> Unit,
    filterInvalidScores: Boolean = false,
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
        SectionHeader("Instrument")
        Column(Modifier.selectableGroup().testTag("fst.songs.filter.instrument")) {
            RadioRow("All Instruments", draft.filter.instrument == null, "fst.songs.filter.instrument.all") { change(draft.withInstrument(null)) }
            visible.forEach { chart ->
                RadioRow(
                    chart.label, draft.filter.instrument == chart, "fst.songs.filter.instrument.${chart.wireId}",
                    leading = { InstrumentIcon(chart, size = 28.dp, decorative = true) },
                ) { change(draft.withInstrument(chart)) }
            }
        }
        SectionHeader("Difficulty")
        val min = draft.filter.minDifficulty
        val max = draft.filter.maxDifficulty
        Text(
            if (min == 1 && max == 7) "Any difficulty" else "Difficulty $min–$max of 7",
            color = BrandTokens.textSecondary,
            style = MaterialTheme.typography.bodyMedium,
        )
        RangeSlider(
            value = min.toFloat()..max.toFloat(),
            onValueChange = { range -> change(draft.withDifficulty(range.start.roundToInt(), range.endInclusive.roundToInt())) },
            valueRange = 1f..7f,
            steps = 5,
            modifier = Modifier.testTag("fst.songs.filter.difficulty").semantics { contentDescription = "Difficulty range" },
        )
        SectionHeader("Item Shop")
        if (hideShop) {
            Text("The Item Shop is hidden in Settings. Saved choices stay until you reset them.", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
        }
        SwitchRow("In Shop", draft.shopFilter.inShop, enabled = !hideShop, tag = "fst.songs.filter.in-shop") {
            change(draft.copy(shopFilter = draft.shopFilter.copy(inShop = it)))
        }
        SwitchRow("Leaving Tomorrow", draft.shopFilter.leavingTomorrow, enabled = !hideShop, tag = "fst.songs.filter.leaving") {
            change(draft.copy(shopFilter = draft.shopFilter.copy(leavingTomorrow = it)))
        }
        if (hasPlayer) {
            Column(Modifier.testTag("fst.songs.filter.score-sections")) {
                SectionHeader("Scores")
                kinds.forEach { kind ->
                    SwitchRow(kind.label, draft.allOn(kind), enabled = true, tag = "fst.songs.filter.score.global.${kind.name}") { change(draft.withAll(kind, it)) }
                }
                if (draft.hasHiddenChecks) {
                    Text(
                        "Some saved checks are for instruments hidden in Settings; they stay inactive and are removed when you change a filter.",
                        color = BrandTokens.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.testTag("fst.songs.score-filter-hidden"),
                    )
                }
                visible.forEach { chart ->
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)) {
                        InstrumentIcon(chart, size = 24.dp, decorative = true)
                        Text(chart.label, color = BrandTokens.textPrimary, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 8.dp))
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.testTag("fst.songs.filter.score.chart.${chart.wireId}")) {
                        kinds.forEach { kind ->
                            val on = draft.playerFilter.contains(kind, chart)
                            FilterChip(
                                selected = on,
                                onClick = { change(draft.withCheck(kind, chart, !on)) },
                                label = { Text(kind.label) },
                                modifier = Modifier
                                    .testTag("fst.songs.filter.score.instrument.${chart.wireId}.${kind.name}")
                                    .semantics { contentDescription = "${chart.label}: ${kind.label}" },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, enabled: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .testTag(tag),
    ) {
        Text(label, color = if (enabled) BrandTokens.textPrimary else BrandTokens.textDisabled, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

// endregion
