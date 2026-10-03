package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.privacy.PrivacyPolicy
import com.festivalscoretracker.android.core.privacy.PrivacyPolicySection
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalModalDialog
import com.festivalscoretracker.android.ui.common.FestivalModalSheet
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// region Modal

/**
 * Settings → Privacy Policy (issue #98): the shared policy text (`assets/privacy-policy.json`, a copy of
 * `contracts/privacy-policy.json`) in the app's standard modal, titled "Privacy Policy" with the header Close
 * button. A full-height [FestivalModalSheet] on compact windows (swipe down, back or a scrim tap also close
 * it), a [FestivalModalDialog] on wider windows (back or an outside tap also close it). Native text only (no
 * WebView, no network): headings for TalkBack, `sp` type that follows the system font size, and activatable
 * HTTPS links.
 *
 * @param compact Compact window width.
 * @param onDismiss Called once when the modal is closed in any way.
 * @param loadPolicy Policy source (the bundled asset by default).
 */
@Composable
fun PrivacyPolicySheet(compact: Boolean, onDismiss: () -> Unit, loadPolicy: (suspend () -> PrivacyPolicy)? = null) {
    val context = LocalContext.current
    val policy by produceState<PrivacyPolicy?>(null) {
        value = loadPolicy?.invoke() ?: withContext(Dispatchers.IO) {
            PrivacyPolicy.parse(runCatching { context.assets.open(PrivacyPolicy.ASSET).bufferedReader().use { it.readText() } }.getOrNull())
        }
    }
    val title = policy?.title ?: PrivacyPolicy.DEFAULT_TITLE
    if (compact) {
        FestivalModalSheet(
            title = title,
            closeTag = "fst.privacy-policy.close",
            titleTag = "fst.privacy-policy.title",
            onDismissRequest = onDismiss,
            modifier = Modifier.testTag("fst.privacy-policy.sheet"),
        ) {
            PolicyBody(policy, Modifier.fillMaxHeight())
        }
    } else {
        FestivalModalDialog(
            title = title,
            closeTag = "fst.privacy-policy.close",
            titleTag = "fst.privacy-policy.title",
            onDismissRequest = onDismiss,
            maxHeight = 640.dp,
            modifier = Modifier.testTag("fst.privacy-policy.sheet"),
        ) {
            PolicyBody(policy, Modifier)
        }
    }
}

// endregion

// region Body

@Composable
private fun ColumnScope.PolicyBody(policy: PrivacyPolicy?, modifier: Modifier) {
    if (policy == null) return
    if (policy.isEmpty) {
        FestivalEmptyState("The privacy policy could not be loaded.", modifier.fillMaxWidth().testTag("fst.privacy-policy.empty"))
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        modifier = modifier.weight(1f, fill = false).fillMaxWidth().testTag("fst.privacy-policy.content"),
    ) {
        if (policy.effectiveDateText.isNotBlank()) {
            item(key = "effective-date") {
                Text(
                    policy.effectiveDateText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.privacy-policy.effective-date"),
                )
            }
        }
        items(policy.sections, key = { it.id.ifBlank { it.title } }) { section -> PolicySection(section) }
    }
}

@Composable
private fun PolicySection(section: PrivacyPolicySection) = SelectionContainer {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.privacy-policy.section.${section.id}")) {
        Text(
            section.title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
        section.blocks.forEach { block ->
            if (block.isBullets) block.items.forEach { Bullet(it) } else PolicyText(block.text)
        }
    }
}

@Composable
private fun Bullet(text: String) {
    // Bullet glyph hidden from TalkBack; each item is read as one stop.
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text("•", color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.clearAndSetSemantics { })
        PolicyText(text)
    }
}

@Composable
private fun PolicyText(text: String) {
    val annotated = remember(text) { linkified(text) }
    Text(annotated, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
}

/** [text] with its HTTPS links ([PrivacyPolicy.linkRanges]) as underlined, activatable URL links. */
private fun linkified(text: String): AnnotatedString = buildAnnotatedString {
    var cursor = 0
    PrivacyPolicy.linkRanges(text).forEach { range ->
        append(text.substring(cursor, range.first))
        val url = text.substring(range)
        pushLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = BrandTokens.textPrimary, textDecoration = TextDecoration.Underline))))
        append(url)
        pop()
        cursor = range.last + 1
    }
    append(text.substring(cursor))
}

// endregion
