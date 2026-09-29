package com.festivalscoretracker.android.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.licenses.BundledAssets
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// region Screen

/**
 * Licenses (`/settings/licenses`): this app's own release runtime dependencies
 * from the generated `assets/licenses.json` (never the web's npm/NuGet list),
 * plus bundled first-party assets. A row opens its full license text in a
 * sheet; dismissing returns focus to the row. No network.
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
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()
    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    val split = rememberHingeSplit()
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxSize().then(split.modifier)) {
        val hinge = split.value
        // List-detail on a book-posture hinge, or on a wide page once a package is open (the
        // list stays full width until then); a sheet otherwise. Back closes the open pane.
        val wide = hinge != null || maxWidth >= LICENSE_DETAIL_PANE_MIN_WIDTH
        val detailPane = hinge != null || (wide && openId != null)
        BackHandler(enabled = wide && openId != null) { openId = null }
        FestivalScreen(title = "Licenses", isRoot = false, scrolled = scrolled) { padding ->
            val current = manifest
            if (current == null) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { FestivalLoading("Loading licenses") }
                return@FestivalScreen
            }
            val open = current.packages.firstOrNull { it.id == openId }
            Row(Modifier.fillMaxSize()) {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
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
                        )
                    }
                    items(current.packages, key = { it.id }) { item -> PackageRow(item, selected = detailPane && item.id == openId) { openId = item.id } }
                    item(key = "assets-header") { Header("Bundled Assets", "Artwork and icons shipped inside the app.") }
                    items(BundledAssets.all, key = { it.id }) { asset ->
                        GlassCard(Modifier.fillMaxWidth().widthIn(max = 840.dp).testTag("fst.licenses.asset.${asset.id}")) {
                            Column(Modifier.padding(16.dp).semantics(mergeDescendants = true) {}) {
                                Text(asset.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                                Text(asset.detail, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
                            }
                        }
                    }
                }
                if (detailPane) {
                    if (hinge != null) Spacer(Modifier.width(with(density) { hinge.second.toDp() }))
                    Box(
                        Modifier
                            .weight(if (hinge != null) 1f else 0.55f)
                            .fillMaxHeight()
                            .padding(top = padding.calculateTopPadding(), start = 16.dp, end = 16.dp, bottom = padding.calculateBottomPadding())
                            .testTag("fst.licenses.detail-pane"),
                    ) {
                        if (open == null) {
                            Text("Select a package to read its license.", color = BrandTokens.textSecondary, modifier = Modifier.align(Alignment.Center).testTag("fst.licenses.detail-placeholder"))
                        } else {
                            LicenseDetail(open, current.text(open), Modifier.fillMaxSize().verticalScroll(rememberScrollState()))
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

// endregion

// region Rows

@Composable
private fun Header(title: String, hint: String) {
    Column(Modifier.padding(top = 8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text(hint, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun PackageRow(item: LicensedPackage, selected: Boolean, onOpen: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().widthIn(max = 840.dp).then(if (selected) Modifier.border(2.dp, BrandTokens.accentPurple, RoundedCornerShape(12.dp)) else Modifier)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .clickable(onClick = onOpen)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .testTag("fst.licenses.row.${item.id}")
                .semantics(mergeDescendants = true) {
                    role = Role.Button
                    this.selected = selected
                    contentDescription = "${item.name}, ${item.version}, ${item.licenses.joinToString(" and ")}"
                },
        ) {
            Column(Modifier.weight(1f)) {
                Text(item.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
            item.licenses.forEach { license ->
                Text(
                    license,
                    style = MaterialTheme.typography.labelSmall,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.padding(start = 8.dp).background(BrandTokens.accentPurple.copy(alpha = 0.5f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LicenseSheet(item: LicensedPackage, text: String, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.popupTestTags().testTag("fst.licenses.detail").semantics { paneTitle = item.name },
    ) {
        LicenseDetail(item, text, Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()))
    }
}

/**
 * License name, coordinates, project link and the full selectable text (sheet or detail pane).
 *
 * @param item Package.
 * @param text Full license text.
 * @param modifier Modifier (callers add scrolling).
 */
@Composable
private fun LicenseDetail(item: LicensedPackage, text: String, modifier: Modifier) {
    val uri = LocalUriHandler.current
    Column(modifier) {
        Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text("${item.subtitle} \u00B7 ${item.licenses.joinToString(", ")}", style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
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
                modifier = Modifier.testTag("fst.licenses.text"),
            )
        }
    }
}

// endregion

/** Page width from which Licenses shows list and detail side by side. */
private val LICENSE_DETAIL_PANE_MIN_WIDTH = 960.dp
