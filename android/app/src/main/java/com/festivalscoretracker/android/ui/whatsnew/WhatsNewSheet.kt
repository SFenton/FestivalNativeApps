package com.festivalscoretracker.android.ui.whatsnew

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogEntry
import com.festivalscoretracker.android.core.whatsnew.WhatsNewBlock
import com.festivalscoretracker.android.core.whatsnew.WhatsNewGate
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.festivalscoretracker.android.ui.common.FestivalModalDialog
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Host

/**
 * Shell-level "What's New" host: once the launch page's first-run carousel (if any) has
 * closed and no other sheet owns the screen, presents the changelog owed at launch; also
 * shows the Settings replay. Every close records the dismissal.
 *
 * @param controller Process-wide state.
 * @param blocked Another modal owns the screen (profile or notifications sheet, a carousel).
 * @param compact Compact window width (bottom sheet) vs wider (dialog).
 * @param entries Changelog entries (the bundled `WhatsNew.json`; tests pass their own).
 */
@Composable
fun WhatsNewHost(
    controller: WhatsNewController,
    blocked: Boolean,
    compact: Boolean,
    entries: List<ChangelogEntry> = Changelog.entries,
) {
    val shown by controller.shown.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LaunchedEffect(blocked) {
        if (blocked) return@LaunchedEffect
        // Web order: the launch page's carousel claims the one-modal slot first.
        delay(WhatsNewGate.SETTLE_MS)
        controller.presentIfOwed()
    }
    val blocks = remember(entries, controller.channel) { Changelog.displayBlocks(entries, controller.channel) }
    if (shown != null) {
        WhatsNewSheet(
            title = WhatsNewGate.title(controller.version),
            blocks = blocks,
            compact = compact,
            onDismiss = { scope.launch { controller.dismiss() } },
        )
    }
}

// endregion

// region Sheet

/**
 * The native "What's New" changelog (web `ChangelogModal`, Apple `WhatsNewSheet`, Windows
 * What's New dialog): a titled, scrolling list of version blocks, each with its notes under
 * page-category subheadings (web changelog order, "Other" last), the shared header Close button
 * and a centred Dismiss button in an opaque bottom bar the list scrolls above.
 *
 * Material presentation through the shared modal component: a full-height
 * [FestivalModalSheet] on compact windows (swipe down, back or a scrim tap also close it), a
 * [FestivalModalDialog] on wider windows (outside tap or back also close it).
 *
 * @param title "What's New · <version>".
 * @param blocks Displayable blocks ([Changelog.displayBlocks]).
 * @param compact Compact window width.
 * @param onDismiss Called once when closed in any way.
 */
@Composable
fun WhatsNewSheet(title: String, blocks: List<WhatsNewBlock>, compact: Boolean, onDismiss: () -> Unit) {
    if (compact) {
        FestivalModalSheet(
            title = title,
            closeTag = "fst.whats-new.close",
            titleTag = "fst.whats-new.title",
            onDismissRequest = onDismiss,
            modifier = Modifier.testTag("fst.whats-new.sheet"),
        ) {
            WhatsNewContent(blocks, onDismiss, fillHeight = true)
        }
    } else {
        FestivalModalDialog(
            title = title,
            closeTag = "fst.whats-new.close",
            titleTag = "fst.whats-new.title",
            onDismissRequest = onDismiss,
            maxHeight = 640.dp,
            modifier = Modifier.testTag("fst.whats-new.sheet"),
        ) {
            WhatsNewContent(blocks, onDismiss, fillHeight = false)
        }
    }
}

/**
 * The scrolling notes above the Dismiss bar.
 *
 * @param blocks Displayable blocks.
 * @param onClose Dismiss action.
 * @param fillHeight Full-height sheet: the list takes the free height so the bar stays at the
 *   bottom edge (issue #142); the dialog hugs its content instead.
 */
@Composable
private fun ColumnScope.WhatsNewContent(blocks: List<WhatsNewBlock>, onClose: () -> Unit, fillHeight: Boolean) {
    Column(Modifier.weight(1f, fill = fillHeight).fillMaxWidth()) {
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.weight(1f, fill = fillHeight).fillMaxWidth().testTag("fst.whats-new.list"),
        ) {
            itemsIndexed(blocks, key = { index, block -> "$index-${block.title}" }) { index, block ->
                Column(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.testTag("fst.whats-new.section.$index")) {
                    Text(
                        block.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.semantics { heading() },
                    )
                    block.groups.forEachIndexed { groupIndex, group ->
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.whats-new.group.$index.$groupIndex")) {
                            if (block.headed) {
                                Text(
                                    group.displayTitle,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = BrandTokens.textSecondary,
                                    modifier = Modifier.semantics { heading() },
                                )
                            }
                            group.items.forEach { Bullet(it) }
                        }
                    }
                }
            }
        }
        DismissBar(onClose)
    }
}

@Composable
private fun Bullet(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text("•", style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary, modifier = Modifier.clearAndSetSemantics { })
        Text(text, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
    }
}

/** Opaque bottom bar with a hairline; Dismiss is centred horizontally (operator batch 6.14). */
@Composable
private fun ColumnScope.DismissBar(onDismiss: () -> Unit) {
    HorizontalDivider(color = BrandTokens.glassBorder)
    Button(
        onClick = onDismiss,
        colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentBlueFill, contentColor = BrandTokens.textPrimary),
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
        // Title and explanation are one stop, read before the button.
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("What's New", color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
            Text("Recent changes to Festival Score Tracker.", color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
        }
        Button(
            onClick = onShow,
            colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentBlueFill, contentColor = BrandTokens.textPrimary),
            modifier = Modifier.padding(start = 12.dp).testTag("fst.settings.whats-new").semantics { contentDescription = "Show What's New" },
            // The description replaces the visible "Show" (read once).
        ) { Text("Show", Modifier.clearAndSetSemantics {}) }
    }
}

// endregion
