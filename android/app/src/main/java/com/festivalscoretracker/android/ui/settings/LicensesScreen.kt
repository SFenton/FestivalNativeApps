package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoadGate
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.common.oneLineUnlessLarge
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Screen

/**
 * Licenses (`/settings/licenses`): this app's own release runtime dependencies from the
 * generated `assets/licenses.json` (never the web's npm/NuGet list). Like the web page, one
 * card of package rows (name, coordinates, license badge, chevron) centred at the standard page
 * width; a row opens its full license text in a sheet (or the detail pane on expanded windows
 * and across a book-posture hinge). No bundled-assets section (operator batch 6.17). No network.
 *
 * @param loadManifest Manifest source (the bundled asset by default).
 */
@Composable
fun LicensesScreen(loadManifest: (suspend () -> LicenseManifest)? = null) {
    val context = LocalContext.current
    val manifest by produceState<LicenseManifest?>(null) {
        value = loadManifest?.invoke() ?: withContext(Dispatchers.IO) {
            LicenseManifest.parse(runCatching { context.assets.open(ASSET).bufferedReader().use { it.readText() } }.getOrNull())
        }
    }
    val split = rememberHingeSplit()
    // The app's shared list-detail rule (Songs): an expanded window (≥ 840 dp, in text-scaled
    // dp at large text) or a separating vertical hinge, so a flat unfolded book fold gets panes
    // instead of a modal sheet across the fold (issue #122).
    val wide = AdaptiveLayoutPolicy.showsTwoPanes(LocalConfiguration.current.screenWidthDp, split.value != null, LocalDensity.current.fontScale)
    Box(Modifier.fillMaxSize().then(split.modifier)) {
        LicensesContent(manifest, wide, split.value)
    }
}

/**
 * The Licenses page for a known layout: a list with a sheet, or list and detail panes.
 *
 * @param manifest Loaded manifest, or null while it is read (load gate).
 * @param wide Show list and detail side by side (expanded window or separating hinge).
 * @param hinge (start pane width, hinge width) in pixels across a separating vertical hinge, or null.
 */
@Composable
internal fun LicensesContent(manifest: LicenseManifest?, wide: Boolean, hinge: Pair<Float, Float>?) {
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()
    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    val density = LocalDensity.current
    // List-detail always populated (operator 2026-09-28): the package picked last, else the
    // first one; a sheet otherwise.
    FestivalScreen(title = "Licenses", isRoot = false, scrolled = scrolled) { padding ->
        // Shared load gate (batch 6.41): spinner until the manifest is read, then the rows stagger in.
        FestivalLoadGate(ready = manifest != null, modifier = Modifier.fillMaxSize(), label = "Loading licenses") {
        val current = manifest ?: return@FestivalLoadGate
        val open = current.packages.firstOrNull { it.id == openId }
        val shown = open ?: current.packages.firstOrNull()?.takeIf { wide }
        val detailPane = wide && (shown != null || hinge != null)
        Row(Modifier.fillMaxSize()) {
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = padding.calculateBottomPadding() + 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = when {
                    hinge != null -> Modifier.width(with(density) { hinge.first.toDp() })
                    detailPane -> Modifier.weight(0.45f)
                    else -> Modifier.weight(1f)
                }.fillMaxHeight().testTag("fst.licenses.list"),
            ) {
                item(key = "software-header") {
                    Header(
                        "Open Source Software",
                        if (current.packages.isEmpty()) {
                            "This build includes no third-party packages."
                        } else {
                            "This app includes ${current.packages.size} open source packages from its release build. Tap one to read its license."
                        },
                        Modifier.staggered(0),
                    )
                }
                itemsIndexed(current.packages, key = { _, item -> item.id }) { index, item ->
                    PackageRow(item, index, current.packages.size, selected = if (detailPane) item.id == shown?.id else null, Modifier.staggered(index + 1)) { openId = item.id }
                }
            }
            if (detailPane) {
                if (hinge != null) Spacer(Modifier.width(with(density) { hinge.second.toDp() }))
                Box(
                    Modifier
                        .weight(if (hinge != null) 1f else 0.55f)
                        .fillMaxHeight()
                        .padding(start = 16.dp, end = 16.dp, bottom = padding.calculateBottomPadding())
                        .testTag("fst.licenses.detail-pane"),
                ) {
                    if (shown == null) {
                        FestivalEmptyState("No packages", Modifier.fillMaxSize().testTag("fst.licenses.detail-empty"))
                    } else {
                        LicenseDetail(shown, current.text(shown), Modifier.fillMaxSize().verticalScroll(rememberScrollState()))
                    }
                }
            }
        }
        if (!wide && open != null) LicenseSheet(open, current.text(open)) { openId = null }
        }
    }
}

/** Generated manifest asset (`tools/android/licenses.py`). */
private const val ASSET = "licenses.json"

/** Content column width shared with Settings (web page column). */
internal val PAGE_CONTENT_MAX_WIDTH = 840.dp

// endregion

// region Rows

@Composable
private fun Header(title: String, hint: String, modifier: Modifier = Modifier) {
    Column(modifier.widthIn(max = PAGE_CONTENT_MAX_WIDTH).fillMaxWidth().padding(top = 8.dp, bottom = 12.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text(hint, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp))
    }
}

/**
 * One package row as a segment of a single glass card (web `FrostedCard` of rows): rounded
 * top on the first row, rounded bottom on the last, hairline separators between rows, and a
 * trailing chevron so every row reads as tappable.
 */
@Composable
private fun PackageRow(item: LicensedPackage, index: Int, count: Int, selected: Boolean?, modifier: Modifier, onOpen: () -> Unit) {
    val accessibility = LocalFestivalAccessibility.current
    val opaque = accessibility.increaseContrast || accessibility.reduceTransparency
    val top = if (index == 0) CARD_CORNER else 0.dp
    val bottom = if (index == count - 1) CARD_CORNER else 0.dp
    val shape = RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
    Surface(
        onClick = onOpen,
        shape = shape,
        color = when {
            selected == true -> BrandTokens.accentPurple.copy(alpha = 0.35f)
            opaque -> BrandTokens.cardBackground
            else -> BrandTokens.surfaceFrosted
        },
        modifier = modifier
            .widthIn(max = PAGE_CONTENT_MAX_WIDTH)
            .fillMaxWidth()
            .then(if (accessibility.increaseContrast) Modifier.border(1.dp, BrandTokens.textPrimary, shape) else Modifier)
            .testTag("fst.licenses.row.${item.id}")
            .semantics(mergeDescendants = true) {
                // The merged visible texts (name, coordinates, license) are the label, read once;
                // selection exists only beside the detail pane (issue #122: TalkBack read a custom
                // description and then the same texts, and "Not selected" on single-pane rows).
                role = Role.Button
                if (selected != null) this.selected = selected
            },
    ) {
        Column {
            if (index > 0) HorizontalDivider(color = BrandTokens.glassBorder)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 10.dp),
            ) {
                // Large text stacks the badge under the coordinates (rows stack their columns): beside
                // them at 200% it squeezed the name column and cut the badge to "Apache-…" (issue #122).
                val large = isLargeText()
                val license = item.licenses.joinToString(" / ").takeIf { it.isNotEmpty() }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(item.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis)
                    Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis)
                    if (large && license != null) LicenseBadge(license, large = true, Modifier.padding(top = 4.dp))
                }
                if (!large && license != null) LicenseBadge(license, large = false)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textPrimary)
            }
        }
    }
}

/**
 * SPDX badge (surface-muted pill).
 *
 * @param license SPDX IDs joined with " / ".
 * @param large Large text: stacked under the coordinates, wrapping rather than truncating.
 * @param modifier Modifier.
 */
@Composable
private fun LicenseBadge(license: String, large: Boolean, modifier: Modifier = Modifier) {
    Text(
        license,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = BrandTokens.textSecondary,
        maxLines = if (large) Int.MAX_VALUE else 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
            .then(if (large) Modifier else Modifier.widthIn(max = 140.dp))
            .background(BrandTokens.surfaceMuted, RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .testTag("fst.licenses.badge"),
    )
}

/** Compact-window license text: the shared modal sheet, titled with the package name and closed by its header Close. */
@Composable
private fun LicenseSheet(item: LicensedPackage, text: String, onDismiss: () -> Unit) {
    FestivalModalSheet(
        title = item.name,
        closeTag = "fst.licenses.close",
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("fst.licenses.detail"),
    ) {
        LicenseDetail(item, text, Modifier.fillMaxSize().padding(horizontal = 24.dp).verticalScroll(rememberScrollState()), showName = false)
    }
}

/**
 * License name, coordinates, project link and the full selectable text (sheet or detail pane).
 *
 * @param item Package.
 * @param text Full license text.
 * @param modifier Modifier (callers add scrolling).
 * @param showName Show the name heading (the sheet's header already shows it).
 */
@Composable
private fun LicenseDetail(item: LicensedPackage, text: String, modifier: Modifier, showName: Boolean = true) {
    val uri = LocalUriHandler.current
    Column(modifier) {
        if (showName) Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text("${item.subtitle} · ${item.licenses.joinToString(", ")}", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
        item.url?.let { url ->
            TextButton(onClick = { runCatching { uri.openUri(url) } }, modifier = Modifier.testTag("fst.licenses.project-link")) { Text("Project Website") }
        }
        HorizontalDivider(color = BrandTokens.glassBorder, modifier = Modifier.padding(vertical = 8.dp))
        SelectionContainer {
            Text(
                text,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = BrandTokens.textSecondary,
                modifier = Modifier.padding(bottom = 16.dp).testTag("fst.licenses.text"),
            )
        }
    }
}

// endregion

/** Corner radius of the package card. */
private val CARD_CORNER = 12.dp
