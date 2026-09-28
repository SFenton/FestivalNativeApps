package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.licenses.BundledAssets
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.design.GlassCard
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
    FestivalScreen(title = "Licenses", isRoot = false) { padding ->
        val current = manifest
        if (current == null) {
            androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@FestivalScreen
        }
        LazyColumn(
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.licenses.list"),
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
            items(current.packages, key = { it.id }) { item -> PackageRow(item) { openId = item.id } }
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
        current.packages.firstOrNull { it.id == openId }?.let { item -> LicenseSheet(item, current.text(item)) { openId = null } }
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
private fun PackageRow(item: LicensedPackage, onOpen: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().widthIn(max = 840.dp)) {
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
    val uri = LocalUriHandler.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.testTag("fst.licenses.detail").semantics { paneTitle = item.name },
    ) {
        Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp)) {
            Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
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
                    modifier = Modifier.verticalScroll(rememberScrollState()).testTag("fst.licenses.text"),
                )
            }
        }
    }
}

// endregion
