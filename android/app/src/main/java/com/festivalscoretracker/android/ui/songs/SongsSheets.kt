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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState

import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.songs.SongFilterDraft
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlin.math.roundToInt

// region Draft sheet frame

/**
 * Bottom sheet whose content is a draft: swiping away or Cancel with changes asks
 * to discard; Reset/Cancel/Apply sit at the bottom (web modal semantics).
 *
 * @param title Title Case header.
 * @param tag Test tag root.
 * @param changed Whether the draft differs from the applied value.
 * @param canApply Whether Apply is enabled.
 * @param onReset Reset the draft.
 * @param onApply Apply and close.
 * @param onDismiss Close without applying.
 * @param content Form.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DraftSheet(
    title: String,
    tag: String,
    changed: Boolean,
    canApply: Boolean,
    onReset: () -> Unit,
    onApply: () -> Unit,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    var confirmDiscard by remember { mutableStateOf(false) }
    val isChanged by rememberUpdatedState(changed)
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { value ->
            if (value == SheetValue.Hidden && isChanged) {
                confirmDiscard = true
                false
            } else {
                true
            }
        },
    )
    ModalBottomSheet(
        onDismissRequest = { if (changed) confirmDiscard = true else onDismiss() },
        sheetState = sheetState,
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.testTag(tag),
    ) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 16.dp)) {
            SectionHeader(title, Modifier.testTag("$tag.title"))
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).testTag("$tag.form")) { content() }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 12.dp)) {
                TextButton(onClick = onReset, modifier = Modifier.testTag("$tag.reset")) { Text("Reset") }
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = { if (changed) confirmDiscard = true else onDismiss() }, modifier = Modifier.testTag("$tag.cancel")) { Text("Cancel") }
                Button(onClick = onApply, enabled = canApply, modifier = Modifier.testTag("$tag.apply")) { Text("Apply") }
            }
        }
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard Changes?") },
            text = { Text("Your changes haven't been applied.") },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onDismiss() }, modifier = Modifier.testTag("$tag.discard")) { Text("Discard") }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep Editing") } },
        )
    }
}

// endregion

// region Sort

/**
 * Sort Songs: mode and direction are a draft until Apply.
 *
 * @param mode Saved mode.
 * @param ascending Saved direction.
 * @param hideShop Hide Item Shop (removes the Shop choice).
 * @param onApply Persist a sort.
 * @param onDismiss Close.
 */
@Composable
fun SortSheet(mode: SongSortMode, ascending: Boolean, hideShop: Boolean, onApply: (SongSortMode, Boolean) -> Unit, onDismiss: () -> Unit) {
    var draft by remember { mutableStateOf(SongSortDraft(mode, ascending)) }
    DraftSheet(
        title = "Sort Songs",
        tag = "fst.songs.sort",
        changed = draft.changed,
        canApply = draft.changed,
        onReset = { draft = draft.reset() },
        onApply = { onApply(draft.mode, draft.ascending); onDismiss() },
        onDismiss = onDismiss,
    ) {
        Column(Modifier.selectableGroup().testTag("fst.songs.sort.mode")) {
            SongSortDraft.modes(hideShop).forEach { option ->
                RadioRow(option.label, option == draft.mode, "fst.songs.sort.${option.name.lowercase()}") { draft = draft.copy(mode = option) }
            }
        }
        SectionHeader("Direction")
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("fst.songs.sort.direction")) {
            listOf(true to "Ascending", false to "Descending").forEachIndexed { index, (value, label) ->
                SegmentedButton(
                    selected = draft.ascending == value,
                    onClick = { draft = draft.copy(ascending = value) },
                    shape = SegmentedButtonDefaults.itemShape(index, 2),
                    modifier = Modifier.testTag("fst.songs.sort.${label.lowercase()}"),
                ) { Text(label) }
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
 * player's per-chart score/FC checks — all a draft until Apply.
 *
 * @param initial Draft seeded from saved values.
 * @param hasPlayer Show the player score section.
 * @param hideShop Shop toggles disabled (still clearable by Reset).
 * @param onApply Persist the draft.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterSheet(initial: SongFilterDraft, hasPlayer: Boolean, hideShop: Boolean, onApply: (SongFilterDraft) -> Unit, onDismiss: () -> Unit) {
    var draft by remember { mutableStateOf(initial) }
    val visible = Instrument.entries.filter { it in draft.visible }
    DraftSheet(
        title = "Filter Songs",
        tag = "fst.songs.filter",
        changed = draft.changed,
        canApply = draft.canApply,
        onReset = { draft = draft.reset() },
        onApply = { onApply(draft); onDismiss() },
        onDismiss = onDismiss,
    ) {
        SectionHeader("Instrument")
        Column(Modifier.selectableGroup().testTag("fst.songs.filter.instrument")) {
            RadioRow("All Instruments", draft.filter.instrument == null, "fst.songs.filter.instrument.all") { draft = draft.withInstrument(null) }
            visible.forEach { chart ->
                RadioRow(
                    chart.label, draft.filter.instrument == chart, "fst.songs.filter.instrument.${chart.wireId}",
                    leading = { InstrumentIcon(chart, size = 28.dp, decorative = true) },
                ) { draft = draft.withInstrument(chart) }
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
            onValueChange = { range -> draft = draft.withDifficulty(range.start.roundToInt(), range.endInclusive.roundToInt()) },
            valueRange = 1f..7f,
            steps = 5,
            modifier = Modifier.testTag("fst.songs.filter.difficulty").semantics { contentDescription = "Difficulty range" },
        )
        SectionHeader("Item Shop")
        if (hideShop) {
            Text("The Item Shop is hidden in Settings. Saved choices stay until you reset them.", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
        }
        SwitchRow("In Shop", draft.shopFilter.inShop, enabled = !hideShop, tag = "fst.songs.filter.in-shop") {
            draft = draft.copy(shopFilter = draft.shopFilter.copy(inShop = it))
        }
        SwitchRow("Leaving Tomorrow", draft.shopFilter.leavingTomorrow, enabled = !hideShop, tag = "fst.songs.filter.leaving") {
            draft = draft.copy(shopFilter = draft.shopFilter.copy(leavingTomorrow = it))
        }
        if (hasPlayer) {
            Column(Modifier.testTag("fst.songs.filter.score-sections")) {
                SectionHeader("Scores")
                SongScoreFilterKind.entries.forEach { kind ->
                    SwitchRow(kind.label, draft.allOn(kind), enabled = true, tag = "fst.songs.filter.score.global.${kind.name}") { draft = draft.withAll(kind, it) }
                }
                if (draft.hasHiddenChecks) {
                    Text(
                        "Some saved checks are for instruments hidden in Settings; they stay inactive and are removed when you apply.",
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
                        SongScoreFilterKind.entries.forEach { kind ->
                            val on = draft.playerFilter.contains(kind, chart)
                            FilterChip(
                                selected = on,
                                onClick = { draft = draft.withCheck(kind, chart, !on) },
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
