package com.festivalscoretracker.android.ui.whatsnew

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogEntry
import com.festivalscoretracker.android.core.whatsnew.WhatsNewGate
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.ui.common.festivalSheetTop
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// region Host

/**
 * Shell-level "What's New" host: once the launch page's first-run carousel (if any) has
 * closed and no other sheet owns the screen, presents the changelog owed at launch; also
 * shows the Settings replay. Every close records the dismissal.
 *
 * @param controller Process-wide state.
 * @param blocked Another modal owns the screen (profile or notifications sheet, a carousel).
 * @param compact Compact window width (bottom sheet) vs wider (dialog).
 */
@Composable
fun WhatsNewHost(controller: WhatsNewController, blocked: Boolean, compact: Boolean) {
    val shown by controller.shown.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LaunchedEffect(blocked) {
        if (blocked) return@LaunchedEffect
        // Web order: the launch page's carousel claims the one-modal slot first.
        delay(WhatsNewGate.SETTLE_MS)
        controller.presentIfOwed()
    }
    if (shown != null) {
        WhatsNewSheet(
            title = WhatsNewGate.title(controller.version),
            entries = Changelog.displayEntries(),
            compact = compact,
            onDismiss = { scope.launch { controller.dismiss() } },
        )
    }
}

// endregion

// region Sheet

/**
 * The native "What's New" changelog (web `ChangelogModal`, Apple `WhatsNewSheet`, Windows
 * What's New dialog): a titled, scrolling list of Title Case sections with bullets, a Close
 * icon and a centred Dismiss button in an opaque bottom bar the list scrolls above.
 *
 * Material presentation: a full-height modal bottom sheet on compact windows (swipe down,
 * back or a scrim tap closes it), a dialog on wider windows (outside tap or back closes it).
 *
 * @param title "What's New · <version>".
 * @param entries Displayable entries ([Changelog.displayEntries]).
 * @param compact Compact window width.
 * @param onDismiss Called once when closed in any way.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhatsNewSheet(title: String, entries: List<ChangelogEntry>, compact: Boolean, onDismiss: () -> Unit) {
    if (compact) {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = BrandTokens.cardBackground,
            modifier = Modifier.festivalSheetTop().popupTestTags().testTag("fst.whats-new.sheet").semantics { paneTitle = title },
        ) {
            WhatsNewContent(title, entries, onDismiss, Modifier.fillMaxHeight())
        }
    } else {
        Dialog(onDismissRequest = onDismiss) {
            Surface(
                shape = RoundedCornerShape(28.dp),
                color = BrandTokens.cardBackground,
                modifier = Modifier
                    .widthIn(max = 560.dp)
                    .heightIn(max = 640.dp)
                    .popupTestTags()
                    .testTag("fst.whats-new.sheet")
                    .semantics { paneTitle = title },
            ) {
                WhatsNewContent(title, entries, onDismiss, Modifier.padding(top = 12.dp))
            }
        }
    }
}

@Composable
private fun WhatsNewContent(title: String, entries: List<ChangelogEntry>, onClose: () -> Unit, modifier: Modifier) {
    Column(modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 24.dp, end = 8.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.weight(1f).semantics { heading() }.testTag("fst.whats-new.title"),
            )
            IconButton(onClick = onClose, modifier = Modifier.testTag("fst.whats-new.close")) {
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = BrandTokens.textPrimary)
            }
        }
        val sections = entries.flatMap { it.sections }
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.weight(1f, fill = false).fillMaxWidth().testTag("fst.whats-new.list"),
        ) {
            itemsIndexed(sections, key = { index, section -> "$index-${section.title}" }) { index, section ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.testTag("fst.whats-new.section.$index")) {
                    Text(
                        section.displayTitle,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.semantics { heading() },
                    )
                    section.items.forEach { Bullet(it) }
                }
            }
        }
        DismissBar(onClose)
    }
}

@Composable
private fun Bullet(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text("•", color = BrandTokens.textPrimary, modifier = Modifier.clearAndSetSemantics { })
        Text(text, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
    }
}

/** Opaque bottom bar with a hairline; Dismiss is centred horizontally (operator batch 6.14). */
@Composable
private fun ColumnScope.DismissBar(onDismiss: () -> Unit) {
    HorizontalDivider(color = BrandTokens.glassBorder)
    Button(
        onClick = onDismiss,
        colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentBlue, contentColor = BrandTokens.textPrimary),
        modifier = Modifier
            .align(Alignment.CenterHorizontally)
            .padding(vertical = 12.dp)
            .widthIn(min = 200.dp)
            .testTag("fst.whats-new.dismiss"),
    ) { Text("Dismiss", fontWeight = FontWeight.SemiBold) }
}

// endregion

// region Settings row

/**
 * Settings → Version "What's New" row with a blue Show button that replays the sheet
 * (Apple `fst.settings.whats-new`, Windows Settings → Version).
 *
 * @param onShow Replay the sheet.
 */
@Composable
fun WhatsNewSettingsRow(onShow: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("What's New", color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
            Text("Recent changes to Festival Score Tracker.", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
        }
        Button(
            onClick = onShow,
            colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentBlue, contentColor = BrandTokens.textPrimary),
            modifier = Modifier.padding(start = 12.dp).testTag("fst.settings.whats-new").semantics { contentDescription = "Show What's New" },
        ) { Text("Show") }
    }
}

// endregion
