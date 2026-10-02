package com.festivalscoretracker.android.ui.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.core.settings.AppBuildInfo
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.ScoreLeeway
import com.festivalscoretracker.android.presentation.settings.ServiceVersionState
import com.festivalscoretracker.android.presentation.settings.SettingsViewModel
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewSettingsRow

// region Sections

/**
 * Settings sections in web order (quick-link IDs double as list keys and test
 * tags), plus the native Accessibility section after Show Instrument Metadata.
 *
 * @param debug Whether the debug-only Diagnostics section exists.
 * @return Quick Links sections.
 */
internal fun settingsSections(debug: Boolean): List<QuickLinkSection> = buildList {
    add(QuickLinkSection("app-settings", "App Settings", "settings"))
    if (debug) add(QuickLinkSection("diagnostics", "Diagnostics", "info"))
    add(QuickLinkSection("item-shop", "Item Shop", "shop"))
    add(QuickLinkSection("show-instruments", "Show Instruments", "music"))
    add(QuickLinkSection("show-metadata", "Show Instrument Metadata", "list"))
    add(QuickLinkSection("accessibility", "Accessibility", "accessibility"))
    add(QuickLinkSection("version", "Festival Score Tracker Version", "info"))
    add(QuickLinkSection("service-info", "Service Info", "service"))
    add(QuickLinkSection("first-run", "First Run Guides", "sparkles"))
    add(QuickLinkSection("licenses", "Licenses", "document"))
    add(QuickLinkSection("reset", "Reset Settings", "trash"))
}

// endregion

// region Screen

/**
 * Settings: every web section that has a native meaning, persisted through
 * [SettingsViewModel] (DataStore). Service Progress, profile-name refresh (a
 * POST), ZIP export and the mouse/header-button settings have no Android
 * equivalent or allowlisted read (see `.agents/pages/settings/android.md`).
 *
 * @param settings Effective settings.
 * @param viewModel Settings actions.
 * @param serviceOrigin Active service origin (shown in Version).
 * @param onReplayFirstRun Settings "Show" for one page's first-run guide.
 * @param debug Whether this is a debug build (Diagnostics section).
 * @param onShowWhatsNew Settings → Version "What's New" Show (replays the changelog sheet).
 */
@Composable
fun SettingsScreen(
    settings: AppSettings,
    viewModel: SettingsViewModel,
    serviceOrigin: String,
    onReplayFirstRun: (FirstRunPageKey) -> Unit,
    debug: Boolean = BuildConfig.DEBUG,
    onShowWhatsNew: () -> Unit = {},
) {
    val shell = LocalShellActions.current
    val listState = rememberLazyListState()
    val sections = remember(debug) { settingsSections(debug) }
    val quickLinks = rememberQuickLinks(listState, "Quick Links", sections) { id -> sections.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    val density = LocalDensity.current
    val windowWidthDp = with(density) { currentWindowSize().width.toDp().value.toInt() }
    var confirmReset by rememberSaveable { mutableStateOf(false) }
    val serviceVersion by viewModel.serviceVersion.collectAsStateWithLifecycle()

    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    val split = rememberHingeSplit()
    BoxWithConstraints(Modifier.fillMaxSize().then(split.modifier)) {
        val hinge = split.value
        FestivalScreen(title = "Settings", isRoot = true, scrolled = scrolled, actions = { QuickLinksAction(quickLinks, windowWidthDp) }) { padding ->
            Row(Modifier.fillMaxSize()) {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    // Centred page column on wide windows, like the web and Licenses.
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = (if (hinge != null) Modifier.width(with(density) { hinge.first.toDp() }) else Modifier.weight(1f)).fillMaxHeight().testTag("fst.settings.list"),
                ) {
                    sections.forEach { section ->
                        item(key = section.id) {
                            Column(Modifier.fillMaxWidth().widthIn(max = 840.dp).testTag("fst.settings.section.${section.id}")) {
                                when (section.id) {
                                    "app-settings" -> AppSettingsSection(settings, viewModel)
                                    "diagnostics" -> DiagnosticsSection(settings, viewModel)
                                    "item-shop" -> ItemShopSection(settings, viewModel)
                                    "show-instruments" -> InstrumentsSection(settings, viewModel)
                                    "show-metadata" -> MetadataSection(settings, viewModel)
                                    "accessibility" -> AccessibilitySection(settings, viewModel)
                                    "version" -> VersionSection(serviceOrigin, debug, serviceVersion, viewModel::loadServiceVersion) { WhatsNewSettingsRow(onShowWhatsNew) }
                                    "service-info" -> ServiceInfoSection(viewModel.serviceInfo)
                                    "first-run" -> FirstRunSection(onReplayFirstRun)
                                    "licenses" -> NavigationRow("Licenses", "Open source package license details.", "fst.settings.licenses") {
                                        shell.navigate(LicensesRoute)
                                    }
                                    "reset" -> ResetSection { confirmReset = true }
                                }
                            }
                        }
                    }
                }
                // Book posture: the list stays on the leading side of the hinge (hinge-safe).
                if (hinge != null) Spacer(Modifier.width(with(density) { hinge.second.toDp() }))
            }
        }
    }
    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Reset Settings") },
            text = { Text("Are you sure you want to restore all settings to their default values?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmReset = false
                        viewModel.resetAppSettings()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.testTag("fst.settings.reset.confirm"),
                ) { Text("Reset") }
            },
            dismissButton = { TextButton(onClick = { confirmReset = false }, modifier = Modifier.testTag("fst.settings.reset.cancel")) { Text("Cancel") } },
            containerColor = BrandTokens.cardBackground,
            modifier = Modifier.popupTestTags().testTag("fst.settings.reset.dialog"),
        )
    }
}

// endregion

// region Section content

@Composable
private fun AppSettingsSection(settings: AppSettings, vm: SettingsViewModel) {
    Header("App Settings", "General Festival Score Tracker app settings.")
    GlassCard(Modifier.fillMaxWidth()) {
        ToggleRow(
            "Show Instrument Icons",
            "Display instrument icons on each song row showing which parts have leaderboard scores or FCs.",
            settings.showInstrumentIcons, vm::setShowInstrumentIcons, "fst.settings.show-instrument-icons",
        )
        Divider()
        ToggleRow(
            "Enable Independent Song Row Visual Order",
            "When enabled, the metadata display order on song rows is controlled separately from sort priority. When disabled, metadata follows sort priority order.",
            settings.enableVisualOrder, vm::setEnableVisualOrder, "fst.settings.enable-visual-order",
        )
        AnimatedVisibility(settings.enableVisualOrder) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                SubTitle("Song Row Visual Order")
                Hint("When filtering to a single instrument in the song list, extra metadata is displayed. Choose the order it appears in on the bottom row.")
                val visible = settings.songRowVisualOrder.filter { it in settings.visibleMetadata }
                ReorderList(visible.map { it.label }, "fst.settings.song-row-order") { index, offset ->
                    val moved = com.festivalscoretracker.android.core.settings.SettingsOrder.move(visible, index, offset)
                    vm.setVisualOrder(moved + settings.songRowVisualOrder.filter { it !in settings.visibleMetadata })
                }
                if (visible.isEmpty()) Hint("Turn on at least one field in Show Instrument Metadata to order it.")
            }
        }
        Divider()
        Column(Modifier.padding(16.dp)) {
            SubTitle("CHOpt Path Default View")
            Hint("Choose whether CHOpt paths open as an image or text table by default.")
            Column(Modifier.selectableGroup()) {
                PathDisplayMode.entries.forEach { mode ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .selectable(selected = settings.pathDefaultView == mode, role = Role.RadioButton) { vm.setPathDefaultView(mode) }
                            .testTag("fst.settings.path-default-view.${mode.token}"),
                    ) {
                        RadioButton(selected = settings.pathDefaultView == mode, onClick = null)
                        Text(mode.label, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 12.dp))
                    }
                }
            }
        }
        Divider()
        Column(Modifier.padding(16.dp)) {
            SubTitle("CHOpt Text Path Column Order")
            Hint("Choose the order columns appear in the CHOpt text path view. You can also drag column headers directly in the path modal.")
            ReorderList(settings.pathColumnOrder.map { it.label }, "fst.settings.path-column-order", vm::movePathColumn)
        }
        Divider()
        ToggleRow(
            "Filter Invalid Scores",
            "When enabled, the app will attempt to filter out invalid leaderboard values based on the maximum score derived from the CHOpt path.",
            settings.filterInvalidScores, vm::setFilterInvalidScores, "fst.settings.filter-invalid-scores",
        )
        AnimatedVisibility(settings.filterInvalidScores) { LeewayControl(settings.leeway, vm::setLeeway) }
        Divider()
        ToggleRow(
            "Enable Experimental Leaderboard Ranks",
            "Enable this to see more ranking mechanisms in the Leaderboards page.",
            settings.experimentalRanks, {}, "fst.settings.experimental-ranks",
            enabled = false, disabledReason = "Not available on Android yet.",
        )
    }
}

@Composable
private fun LeewayControl(leeway: Double, onChange: (Double) -> Unit) {
    var dragging by remember { mutableStateOf(false) }
    var draft by remember { mutableFloatStateOf(leeway.toFloat()) }
    val shown = if (dragging) ScoreLeeway.clamp(draft.toDouble()) else leeway
    Column(Modifier.padding(start = 32.dp, end = 16.dp, bottom = 12.dp)) {
        SubTitle("Maximum Score Leeway")
        Hint(ScoreLeeway.description(shown))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Slider(
                value = shown.toFloat(),
                onValueChange = {
                    dragging = true
                    draft = it
                },
                onValueChangeFinished = {
                    dragging = false
                    onChange(ScoreLeeway.clamp(draft.toDouble()))
                },
                valueRange = ScoreLeeway.MINIMUM.toFloat()..ScoreLeeway.MAXIMUM.toFloat(),
                steps = ScoreLeeway.SLIDER_STEPS,
                colors = SliderDefaults.colors(thumbColor = BrandTokens.textPrimary, activeTrackColor = BrandTokens.accentBlue, inactiveTrackColor = BrandTokens.surfaceMuted),
                modifier = Modifier
                    .weight(1f)
                    .testTag("fst.settings.leeway")
                    .semantics {
                        contentDescription = "Maximum Score Leeway"
                        stateDescription = ScoreLeeway.format(shown)
                    },
            )
            Text(ScoreLeeway.format(shown), color = BrandTokens.textSecondary, modifier = Modifier.padding(start = 12.dp).widthIn(min = 56.dp).clearAndSetSemantics { })
        }
    }
}

@Composable
private fun DiagnosticsSection(settings: AppSettings, vm: SettingsViewModel) {
    Header("Diagnostics", "Debug-only tools for investigating mobile tap and navigation issues.")
    GlassCard(Modifier.fillMaxWidth()) {
        ToggleRow(
            "Tap Diagnostics",
            "Capture recent taps, hit targets, routes, and shell state in a local diagnostic buffer on this device.",
            settings.tapDiagnostics, vm::setTapDiagnostics, "fst.settings.tap-diagnostics",
        )
        Divider()
        ToggleRow(
            "Upload Tap Telemetry",
            if (settings.tapDiagnostics) {
                "Send sanitized tap diagnostic batches to the development service logs while diagnostics are enabled."
            } else {
                "Enable Tap Diagnostics first, then upload sanitized batches to the development service logs."
            },
            settings.tapTelemetry && settings.tapDiagnostics, vm::setTapTelemetry, "fst.settings.tap-telemetry",
            enabled = settings.tapDiagnostics,
        )
    }
}

@Composable
private fun ItemShopSection(settings: AppSettings, vm: SettingsViewModel) {
    Header("Item Shop", "Control how Item Shop availability is displayed.")
    GlassCard(Modifier.fillMaxWidth()) {
        ToggleRow(
            "Disable Item Shop Highlighting",
            "Turn off green, gold, and red pulsing Item Shop highlights.",
            settings.disableShopHighlighting, vm::setDisableShopHighlighting, "fst.settings.disable-shop-highlighting",
            enabled = !settings.hideShop, disabledReason = "Unavailable while the Item Shop is hidden.",
        )
        Divider()
        ToggleRow(
            "Hide Item Shop",
            "Hide all Item Shop UI elements including navigation, buttons, and sort options.",
            settings.hideShop, vm::setHideShop, "fst.settings.hide-shop",
        )
    }
}

@Composable
private fun InstrumentsSection(settings: AppSettings, vm: SettingsViewModel) {
    Header("Show Instruments", "Choose which instruments to display throughout the app.")
    GlassCard(Modifier.fillMaxWidth()) {
        Instrument.entries.forEachIndexed { index, instrument ->
            if (index > 0) Divider()
            val last = settings.isLastVisible(instrument)
            ToggleRow(
                instrument.label, null, instrument in settings.visibleInstruments,
                { vm.setInstrumentVisible(instrument, it) }, "fst.settings.instrument.${instrument.wireId}",
                enabled = !last, disabledReason = "At least one instrument must stay visible.",
            ) { InstrumentIcon(instrument, size = 28.dp, decorative = true) }
        }
    }
}

@Composable
private fun MetadataSection(settings: AppSettings, vm: SettingsViewModel) {
    Header(
        "Show Instrument Metadata",
        "When filtering songs down to one instrument in the song list, extra metadata for that song can appear. Choose what you'd like to see in the song row here.",
    )
    GlassCard(Modifier.fillMaxWidth()) {
        MetadataField.toggleOrder.forEachIndexed { index, field ->
            if (index > 0) Divider()
            ToggleRow(field.label, null, field in settings.visibleMetadata, { vm.setMetadataVisible(field, it) }, "fst.settings.metadata.${field.tag}")
        }
    }
}

@Composable
private fun AccessibilitySection(settings: AppSettings, vm: SettingsViewModel) {
    Header("Accessibility", "These add to your Android accessibility settings and can only make the app calmer or clearer.")
    GlassCard(Modifier.fillMaxWidth()) {
        ToggleRow("Reduce Motion", "Hold the background still and skip decorative animation, even when system animations are on.", settings.reduceMotion, vm::setReduceMotion, "fst.settings.motion")
        Divider()
        ToggleRow("Disable Animated Artwork", "Keep the album-art background on a single still cover.", settings.disableAnimatedArtwork, vm::setDisableAnimatedArtwork, "fst.settings.still-artwork")
        Divider()
        ToggleRow("Increase Contrast", "Use opaque cards with stronger borders and brighter secondary text.", settings.increaseContrast, vm::setIncreaseContrast, "fst.settings.contrast")
        Divider()
        ToggleRow("Reduce Transparency", "Use opaque cards over the artwork background.", settings.reduceTransparency, vm::setReduceTransparency, "fst.settings.transparency")
    }
}

@Composable
private fun VersionSection(
    serviceOrigin: String,
    debug: Boolean,
    serviceVersion: ServiceVersionState,
    loadServiceVersion: () -> Unit,
    whatsNew: @Composable () -> Unit = {},
) {
    LaunchedEffect(Unit) { loadServiceVersion() }
    Header("Festival Score Tracker Version", "Festival Score Tracker information to help with debugging.")
    GlassCard(Modifier.fillMaxWidth()) {
        ValueRow(
            "App Version",
            AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA),
            "fst.settings.app-version",
        )
        Divider()
        ValueRow("Build", if (debug) "Debug" else "Release", "fst.settings.build")
        Divider()
        ValueRow(
            "Service Version",
            when (serviceVersion) {
                ServiceVersionState.Loading -> "Loading"
                is ServiceVersionState.Loaded -> serviceVersion.version
                ServiceVersionState.Unavailable -> "Unavailable"
            },
            "fst.settings.service-version",
        )
        Divider()
        ValueRow("Service", serviceOrigin, "fst.settings.service-origin")
        Divider()
        whatsNew()
    }
}

@Composable
private fun FirstRunSection(onShow: (FirstRunPageKey) -> Unit) {
    Header("First Run Guides", "Re-visit the first run experience for each page.")
    GlassCard(Modifier.fillMaxWidth()) {
        FirstRunPageKey.entries.forEachIndexed { index, page ->
            if (index > 0) Divider()
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp),
            ) {
                Text(page.label, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
                Button(
                    onClick = { onShow(page) },
                    colors = festivalFilledButtonColors(),
                    modifier = Modifier.testTag("fst.settings.first-run.${page.key}").semantics { contentDescription = "Show ${page.label} guide" },
                    // The description replaces the visible "Show" (read once).
                ) { Text("Show", Modifier.clearAndSetSemantics {}) }
            }
        }
    }
}

@Composable
private fun ResetSection(onReset: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Reset Settings", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
            Hint("Restore all settings to their default values.")
            Button(
                onClick = onReset,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = BrandTokens.textPrimary),
                modifier = Modifier.fillMaxWidth().testTag("fst.settings.reset"),
            ) { Text("Reset All Settings") }
        }
    }
}

// endregion

// region Rows

@Composable
private fun Header(title: String, hint: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
    Text(hint, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
}

@Composable
private fun SubTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
}

@Composable
private fun Divider() = HorizontalDivider(color = BrandTokens.glassBorder)

/**
 * A switch row: the whole row toggles, announces name + on/off + description,
 * and a disabled row explains why.
 */
@Composable
private fun ToggleRow(
    title: String,
    description: String?,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    tag: String,
    enabled: Boolean = true,
    disabledReason: String? = null,
    leading: (@Composable () -> Unit)? = null,
) {
    val reason = disabledReason.takeIf { !enabled }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag(tag),
    ) {
        leading?.invoke()
        // 4 dp between the title and each supporting line (cross-platform settings row standard).
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = if (enabled) BrandTokens.textPrimary else BrandTokens.textMuted, style = MaterialTheme.typography.bodyLarge)
            listOfNotNull(description, reason).forEach {
                Text(it, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
            }
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

@Composable
private fun ValueRow(title: String, value: String, tag: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 8.dp).testTag(tag).semantics(mergeDescendants = true) {},
    ) {
        Text(title, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
        Text(value, color = BrandTokens.textSecondary, modifier = Modifier.padding(start = 12.dp))
    }
}

/**
 * Web Settings navigation row (Licenses): a section header (title + description) on the page
 * itself, not in a card, with a trailing chevron; the whole row is one link (batch 6.17).
 */
@Composable
private fun NavigationRow(title: String, description: String, tag: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClickLabel = "Open $title", onClick = onClick)
            .padding(vertical = 4.dp)
            .testTag(tag)
            .semantics(mergeDescendants = true) {},
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
            Text(description, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp))
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textPrimary)
    }
}

// endregion
