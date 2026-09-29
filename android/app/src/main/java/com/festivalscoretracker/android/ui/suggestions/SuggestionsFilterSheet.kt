package com.festivalscoretracker.android.ui.suggestions

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.common.festivalSheetTop
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

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
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val pickedInstrument = instruments.firstOrNull { it.wireId == selected }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.festivalSheetTop().semantics { testTagsAsResourceId = true },
    ) {
        // Pinned header: Done stays reachable however far the form scrolls.
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Filter Suggestions",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.weight(1f).semantics { heading() }.testTag("fst.suggestions.filter.title"),
            )
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.suggestions.filter.done")) { Text("Done") }
        }
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
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp).testTag("fst.suggestions.filter.instrument-picker"),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        instruments.forEach { instrument ->
                            val isSelected = instrument == pickedInstrument
                            FilterChip(
                                selected = isSelected,
                                onClick = { selected = if (isSelected) null else instrument.wireId },
                                label = { Text(instrument.label) },
                                leadingIcon = { InstrumentIcon(instrument, size = 18.dp, decorative = true) },
                                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = BrandTokens.accentPurple),
                                modifier = Modifier.testTag("fst.suggestions.filter.instrument-picker.${instrument.wireId}"),
                            )
                        }
                    }
                }
                if (pickedInstrument != null) {
                    items(SuggestionCategoryType.entries, key = { "per.${pickedInstrument.wireId}.${it.key}" }) { type ->
                        SwitchRow(
                            title = type.label,
                            checked = draft.isTypeEnabled(type, pickedInstrument),
                            tag = "fst.suggestions.filter.type.${pickedInstrument.wireId}.${type.key}",
                        ) { update(draft.withPerInstrumentType(type, pickedInstrument, it, instruments)) }
                    }
                } else {
                    item {
                        Text(
                            "Choose an instrument to fine-tune its suggestion types.",
                            style = MaterialTheme.typography.bodySmall,
                            color = BrandTokens.textSecondary,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
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

/** One full-row switch (the row is the toggle target, TalkBack role Switch). */
@Composable
private fun SwitchRow(
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
