package com.festivalscoretracker.android.ui.suggestions

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.AccordionReveal
import com.festivalscoretracker.android.ui.common.AccordionRevealOf
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Filter sheet

/**
 * Live Suggestions filter (web `SuggestionsFilterModal`): Instruments, General and
 * Instrument-Specific switches with the web cascade rules. Every change applies and persists
 * at once (operator 2026-09-28: no Cancel/Apply); **Done**, back or a swipe closes the sheet.
 *
 * @param filter Applied filter.
 * @param instruments Settings-visible charts in display order.
 * @param onChange Apply and persist a change.
 * @param onDismiss Close the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SuggestionsFilterSheet(
    filter: SuggestionFilterSettings,
    instruments: List<Instrument>,
    onChange: (SuggestionFilterSettings) -> Unit,
    onDismiss: () -> Unit,
) {
    // Local copy so rapid toggles build on each other before the applied state round-trips.
    var draft by remember { mutableStateOf(filter) }
    LaunchedEffect(filter) { draft = filter }
    val update: (SuggestionFilterSettings) -> Unit = { next ->
        draft = next
        onChange(next)
    }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val pickedInstrument = instruments.firstOrNull { it.wireId == selected }

    // Pinned shared header: Close stays reachable however far the form scrolls (changes
    // apply live, so Close replaces the former Done; its test tag is kept).
    FestivalModalSheet(
        title = "Filter Suggestions",
        closeTag = "fst.suggestions.filter.done",
        titleTag = "fst.suggestions.filter.title",
        onDismissRequest = onDismiss,
    ) {
        HorizontalDivider(color = BrandTokens.glassBorder)
        LazyColumn(Modifier.fillMaxWidth().testTag("fst.suggestions.filter.form")) {
            item { SectionTitle("Instruments", "fst.suggestions.filter.instruments") }
            items(instruments, key = { "instrument.${it.wireId}" }) { instrument ->
                SwitchRow(
                    title = instrument.label,
                    checked = draft.isInstrumentEnabled(instrument),
                    tag = "fst.suggestions.filter.instrument.${instrument.wireId}",
                    instrument = instrument,
                ) { update(draft.withInstrument(instrument, it)) }
            }
            item { SectionTitle("General", "fst.suggestions.filter.general") }
            items(SuggestionCategoryType.entries, key = { "type.${it.key}" }) { type ->
                SwitchRow(
                    title = type.label,
                    supporting = type.filterDescription,
                    checked = draft.isGlobalEnabled(type),
                    tag = "fst.suggestions.filter.type.${type.key}",
                ) { update(draft.withGlobalType(type, it, instruments)) }
            }
            if (instruments.isNotEmpty()) {
                item { SectionTitle("Instrument-Specific", "fst.suggestions.filter.instrument-specific") }
                item {
                    InstrumentTypePicker(instruments, pickedInstrument) { instrument ->
                        selected = if (instrument == pickedInstrument) null else instrument.wireId
                    }
                }
                // One accordion (issue #561): the switches expand, then fade in; the last
                // instrument stays while they fade out and collapse. The hint closes as they open.
                item(key = "per-instrument") {
                    AccordionRevealOf(pickedInstrument, Modifier.testTag("fst.suggestions.filter.instrument-types")) { instrument ->
                        Column {
                            SuggestionCategoryType.entries.forEach { type ->
                                SwitchRow(
                                    title = type.label,
                                    checked = draft.isTypeEnabled(type, instrument),
                                    tag = "fst.suggestions.filter.type.${instrument.wireId}.${type.key}",
                                ) { update(draft.withPerInstrumentType(type, instrument, it, instruments)) }
                            }
                        }
                    }
                }
                item(key = "per-instrument-hint") {
                    AccordionReveal(pickedInstrument == null) {
                        Text(
                            "Choose an instrument to fine-tune its suggestion types.",
                            style = MaterialTheme.typography.bodySmall,
                            color = BrandTokens.textSecondary,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            item {
                OutlinedButton(
                    onClick = { update(SuggestionFilterSettings.DEFAULTS) },
                    enabled = draft.isActive,
                    modifier = Modifier.fillMaxWidth().padding(16.dp).heightIn(min = 48.dp).testTag("fst.suggestions.filter.reset"),
                ) { Text("Reset Filters") }
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, tag: String) {
    SectionHeader(title, Modifier.padding(horizontal = 16.dp).testTag(tag))
}

/**
 * The Instrument-Specific section's chip row: one filter chip per instrument, the picked one
 * filled purple. Shared by the sheet and its first-run demo (issue #380).
 *
 * @param instruments Instruments to offer.
 * @param picked Picked instrument, or null.
 * @param modifier Modifier.
 * @param onPick Tap on an instrument's chip.
 */
@Composable
internal fun InstrumentTypePicker(instruments: List<Instrument>, picked: Instrument?, modifier: Modifier = Modifier, onPick: (Instrument) -> Unit) {
    Row(
        modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp).testTag("fst.suggestions.filter.instrument-picker"),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        instruments.forEach { instrument ->
            FilterChip(
                selected = instrument == picked,
                onClick = { onPick(instrument) },
                label = { Text(instrument.label) },
                leadingIcon = { InstrumentIcon(instrument, size = 18.dp, decorative = true) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = BrandTokens.accentPurple),
                modifier = Modifier.testTag("fst.suggestions.filter.instrument-picker.${instrument.wireId}"),
            )
        }
    }
}

/** One full-row switch (the row is the toggle target, TalkBack role Switch). */
@Composable
internal fun SwitchRow(
    title: String,
    checked: Boolean,
    tag: String,
    supporting: String? = null,
    instrument: Instrument? = null,
    onChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = supporting?.let { { Text(it) } },
        leadingContent = instrument?.let { { InstrumentIcon(it, size = 28.dp, decorative = true) } },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
        colors = ListItemDefaults.colors(
            containerColor = Color.Transparent,
            headlineColor = BrandTokens.textPrimary,
            supportingColor = BrandTokens.textSecondary,
        ),
        modifier = Modifier.toggleable(value = checked, role = Role.Switch, onValueChange = onChange).testTag(tag),
    )
}

// endregion
