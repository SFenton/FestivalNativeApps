package com.festivalscoretracker.android.ui.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.semantics.selected
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsDetail
import com.festivalscoretracker.android.core.settings.SettingsDetailText
import com.festivalscoretracker.android.core.settings.SettingsPanes
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.shell.icon
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
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.presentation.feedback.FeedbackViewModel
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.AdaptiveLayoutPolicy
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
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewSettingsRow
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog

// region Sections

/**
 * Settings sections in web order (quick-link IDs double as list keys and test
 * tags), plus the native Accessibility section after Show Instrument Metadata.
 * The web's Diagnostics section (Tap Diagnostics / Tap Telemetry) is not ported (#374).
 *
 * @return Quick Links sections.
 */
internal fun settingsSections(): List<QuickLinkSection> = buildList {
    add(QuickLinkSection("app-settings", "App Settings", "settings"))
    add(QuickLinkSection("item-shop", "Item Shop", "shop"))
    add(QuickLinkSection("show-instruments", "Show Instruments", "music"))
    add(QuickLinkSection("show-metadata", "Show Instrument Metadata", "list"))
    add(QuickLinkSection("accessibility", "Accessibility", "accessibility"))
    add(QuickLinkSection("version", "Festival Score Tracker Version", "info"))
    add(QuickLinkSection("service-info", "Service Info", "service"))
    add(QuickLinkSection("first-run", "First Run Guides", "sparkles"))
    add(QuickLinkSection("licenses", "Licenses", "document"))
    add(QuickLinkSection("privacy-policy", "Privacy Policy", "privacy"))
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
 * @param debug Whether this is a debug build (Version → Build).
 * @param onShowWhatsNew Settings → Version "What's New" Show (replays the changelog sheet).
 * @param feedback Report an Issue / Request a Feature form (App Settings rows; hidden when null or
 *   until `GET /api/features` reports `feedback: true`).
 */
@Composable
fun SettingsScreen(
    settings: AppSettings,
    viewModel: SettingsViewModel,
    serviceOrigin: String,
    onReplayFirstRun: (FirstRunPageKey) -> Unit,
    debug: Boolean = BuildConfig.DEBUG,
    onShowWhatsNew: () -> Unit = {},
    feedback: FeedbackViewModel? = null,
) {
    val shell = LocalShellActions.current
    val listState = rememberLazyListState()
    val sections = remember { settingsSections() }
    val quickLinks = rememberQuickLinks(listState, "Quick Links", sections) { id -> sections.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    val density = LocalDensity.current
    val windowWidthDp = with(density) { currentWindowSize().width.toDp().value.toInt() }
    var confirmReset by rememberSaveable { mutableStateOf(false) }
    var showPrivacy by rememberSaveable { mutableStateOf(false) }
    val serviceVersion by viewModel.serviceVersion.collectAsStateWithLifecycle()
    // The rows show only once the service reports `feedback: true`; each Settings visit retries a failed read.
    val feedbackAvailable = feedback?.let { it.available.collectAsStateWithLifecycle().value } == true
    LaunchedEffect(feedback) { feedback?.loadAvailability() }

    val scrolled by remember(listState) { derivedStateOf { listState.canScrollBackward } }
    val split = rememberHingeSplit()
    // Wide windows: list/detail (owner, #371) by the app's list-detail rule (Songs, Licenses).
    val twoPane = AdaptiveLayoutPolicy.showsTwoPanes(windowWidthDp, split.value != null, density.fontScale)
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val shown = SettingsPanes.shown(selectedId, settings)
    // A detail whose row disappeared (its switch turned off) returns the pane to the placeholder for good.
    LaunchedEffect(shown, selectedId) { if (shown == null && selectedId != null) selectedId = null }
    val panes = if (twoPane) SettingsPaneSelection(shown) { selectedId = it.id } else null
    // Unfolding with the policy modal open moves the policy into the pane rather than dropping it.
    LaunchedEffect(twoPane, showPrivacy) {
        if (twoPane && showPrivacy) {
            selectedId = SettingsDetail.PrivacyPolicy.id
            showPrivacy = false
        }
    }
    val onFeedback = feedback?.takeIf { feedbackAvailable }?.let { it::open }
    BoxWithConstraints(Modifier.fillMaxSize().then(split.modifier)) {
        val hinge = split.value
        val listWidth = when {
            hinge != null -> with(density) { hinge.first.toDp() }
            panes != null -> AdaptiveLayoutPolicy.listPaneWidth(maxWidth.value.toInt(), null).dp
            else -> null
        }
        FestivalScreen(title = "Settings", isRoot = true, scrolled = scrolled, actions = { QuickLinksAction(quickLinks, windowWidthDp) }) { padding ->
            Row(Modifier.fillMaxSize()) {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    // Centred page column on wide windows, like the web and Licenses.
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = (if (listWidth != null) Modifier.width(listWidth) else Modifier.weight(1f)).fillMaxHeight().testTag("fst.settings.list"),
                ) {
                    sections.forEach { section ->
                        item(key = section.id) {
                            // Cap before filling: fillMaxWidth() first would pin the incoming width and defeat the cap.
                            Column(Modifier.widthIn(max = 840.dp).fillMaxWidth().testTag("fst.settings.section.${section.id}")) {
                                val detail = SettingsDetail.forSection(section.id)
                                if (panes != null && detail != null) {
                                    NavigationRow(detail.title, detail.hint.orEmpty(), detail.rowTag, selected = detail == panes.shown) { panes.select(detail) }
                                } else {
                                    when (section.id) {
                                        "app-settings" -> AppSettingsSection(settings, viewModel, onFeedback, panes)
                                        "item-shop" -> ItemShopSection(settings, viewModel)
                                        "show-instruments" -> InstrumentsSection(settings, viewModel)
                                        "show-metadata" -> MetadataSection(settings, viewModel)
                                        "accessibility" -> AccessibilitySection(settings, viewModel)
                                        "version" -> VersionSection(serviceOrigin, debug, serviceVersion, viewModel::loadServiceVersion) { WhatsNewSettingsRow(onShowWhatsNew) }
                                        "service-info" -> ServiceInfoSection(viewModel.serviceInfo)
                                        "first-run" -> FirstRunSection(onReplayFirstRun)
                                        "licenses" -> SettingsDetail.Licenses.let { NavigationRow(it.title, it.hint.orEmpty(), it.rowTag) { shell.navigate(LicensesRoute) } }
                                        "privacy-policy" -> SettingsDetail.PrivacyPolicy.let { NavigationRow(it.title, it.hint.orEmpty(), it.rowTag) { showPrivacy = true } }
                                        "reset" -> ResetSection { confirmReset = true }
                                    }
                                }
                            }
                        }
                    }
                }
                // Book posture: the list stays on the leading side of the hinge (hinge-safe).
                if (hinge != null) Spacer(Modifier.width(with(density) { hinge.second.toDp() }))
                if (panes != null) {
                    // No drawn divider: the panes' margins (or the hinge) separate them (split-panes R1).
                    Box(Modifier.weight(1f).fillMaxHeight().testTag("fst.settings.detail-pane")) {
                        if (shown == null) {
                            SettingsDetailPlaceholder(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding()))
                        } else {
                            key(shown) {
                                SettingsDetailContent(
                                    shown, padding, settings, viewModel, serviceOrigin, debug, serviceVersion,
                                    onReplayFirstRun, onShowWhatsNew,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    feedback?.let { FeedbackDialogHost(it) }
    // A modal only in one column; list/detail shows the policy in the trailing pane.
    if (showPrivacy && panes == null) PrivacyPolicySheet(compact = !AdaptiveLayoutPolicy.isRegularWidth(windowWidthDp), onDismiss = { showPrivacy = false })
    if (confirmReset) {
        FestivalAlertDialog(
            title = "Reset Settings",
            text = "Are you sure you want to restore all settings to their default values?",
            tag = "fst.settings.reset.dialog",
            confirmLabel = "Reset",
            confirmTag = "fst.settings.reset.confirm",
            onConfirm = {
                confirmReset = false
                viewModel.resetAppSettings()
            },
            dismissLabel = "Cancel",
            dismissTag = "fst.settings.reset.cancel",
            onDismissRequest = { confirmReset = false },
            destructive = true,
        )
    }
}

// endregion

// region Section content

@Composable
private fun AppSettingsSection(settings: AppSettings, vm: SettingsViewModel, onFeedback: ((FeedbackKind) -> Unit)?, panes: SettingsPaneSelection? = null) {
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
            if (panes != null) {
                SettingsDetail.SongRowOrder.let { DetailRow(it, songRowOrderSummary(settings), panes) }
            } else {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    SubTitle(SettingsDetail.SongRowOrder.title)
                    SettingsDetail.SongRowOrder.hint?.let { Hint(it) }
                    SongRowOrderControl(settings, vm)
                }
            }
        }
        Divider()
        if (panes != null) {
            DetailRow(SettingsDetail.PathDefaultView, settings.pathDefaultView.label, panes)
        } else {
            Column(Modifier.padding(16.dp)) {
                SubTitle(SettingsDetail.PathDefaultView.title)
                SettingsDetail.PathDefaultView.hint?.let { Hint(it) }
                PathDefaultViewControl(settings, vm)
            }
        }
        Divider()
        if (panes != null) {
            DetailRow(SettingsDetail.PathColumnOrder, settings.pathColumnOrder.joinToString(", ") { it.label }, panes)
        } else {
            Column(Modifier.padding(16.dp)) {
                SubTitle(SettingsDetail.PathColumnOrder.title)
                SettingsDetail.PathColumnOrder.hint?.let { Hint(it) }
                PathColumnOrderControl(settings, vm)
            }
        }
        Divider()
        ToggleRow(
            "Filter Invalid Scores",
            "When enabled, the app will attempt to filter out invalid leaderboard values based on the maximum score derived from the CHOpt path.",
            settings.filterInvalidScores, vm::setFilterInvalidScores, "fst.settings.filter-invalid-scores",
        )
        AnimatedVisibility(settings.filterInvalidScores) {
            if (panes != null) DetailRow(SettingsDetail.Leeway, ScoreLeeway.format(settings.leeway), panes) else LeewayControl(settings.leeway, vm::setLeeway)
        }
        Divider()
        ToggleRow(
            "Enable Experimental Leaderboard Ranks",
            "Enable this to see more ranking mechanisms in the Leaderboards page.",
            settings.experimentalRanks, vm::setExperimentalRanks, "fst.settings.experimental-ranks",
        )
        if (onFeedback != null) {
            FeedbackKind.entries.forEach { kind ->
                Divider()
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    NavigationRow(kind.formTitle, kind.rowDescription, "fst.settings.feedback.${kind.wire}") { onFeedback(kind) }
                }
            }
        }
    }
}

/** Song Row Visual Order: the visible metadata fields as a drag/keyboard reorder list. */
@Composable
private fun SongRowOrderControl(settings: AppSettings, vm: SettingsViewModel) {
    val visible = settings.songRowVisualOrder.filter { it in settings.visibleMetadata }
    ReorderList(visible.map { it.label }, "fst.settings.song-row-order") { index, offset ->
        val moved = com.festivalscoretracker.android.core.settings.SettingsOrder.move(visible, index, offset)
        vm.setVisualOrder(moved + settings.songRowVisualOrder.filter { it !in settings.visibleMetadata })
    }
    if (visible.isEmpty()) Hint("Turn on at least one field in Show Instrument Metadata to order it.")
}

/** The visible Song Row Visual Order fields, comma-separated (the list row's value). */
private fun songRowOrderSummary(settings: AppSettings): String =
    settings.songRowVisualOrder.filter { it in settings.visibleMetadata }.joinToString(", ") { it.label }

/** CHOpt Path Default View: Image / Text radio group. */
@Composable
private fun PathDefaultViewControl(settings: AppSettings, vm: SettingsViewModel) {
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

/** CHOpt Text Path Column Order: the path table's columns as a reorder list. */
@Composable
private fun PathColumnOrderControl(settings: AppSettings, vm: SettingsViewModel) {
    ReorderList(settings.pathColumnOrder.map { it.label }, "fst.settings.path-column-order", vm::movePathColumn)
}

/**
 * Maximum Score Leeway slider with its live description. In the list it sits indented under
 * Filter Invalid Scores with its own title; in the detail pane the pane header is the title.
 *
 * @param inPane Shown in the Settings detail pane (no own title, no indent).
 */
@Composable
private fun LeewayControl(leeway: Double, onChange: (Double) -> Unit, inPane: Boolean = false) {
    var dragging by remember { mutableStateOf(false) }
    var draft by remember { mutableFloatStateOf(leeway.toFloat()) }
    val shown = if (dragging) ScoreLeeway.clamp(draft.toDouble()) else leeway
    Column(if (inPane) Modifier.padding(16.dp) else Modifier.padding(start = 32.dp, end = 16.dp, bottom = 12.dp)) {
        if (!inPane) SubTitle(SettingsDetail.Leeway.title)
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
private fun ItemShopSection(settings: AppSettings, vm: SettingsViewModel) {
    Header(SettingsDetail.ItemShop)
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
    Header(SettingsDetail.ShowInstruments)
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
    Header(SettingsDetail.ShowMetadata)
    GlassCard(Modifier.fillMaxWidth()) {
        MetadataField.toggleOrder.forEachIndexed { index, field ->
            if (index > 0) Divider()
            ToggleRow(field.label, null, field in settings.visibleMetadata, { vm.setMetadataVisible(field, it) }, "fst.settings.metadata.${field.tag}")
        }
    }
}

@Composable
private fun AccessibilitySection(settings: AppSettings, vm: SettingsViewModel) {
    Header(SettingsDetail.Accessibility)
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
    Header(SettingsDetail.Version)
    GlassCard(Modifier.fillMaxWidth()) {
        AppVersionRow()
        Divider()
        SettingsValueRow("Build", if (debug) "Debug" else "Release", "fst.settings.build")
        Divider()
        SettingsValueRow(
            "Service Version",
            when (serviceVersion) {
                ServiceVersionState.Loading -> "Loading"
                is ServiceVersionState.Loaded -> serviceVersion.version
                ServiceVersionState.Unavailable -> "Unavailable"
            },
            "fst.settings.service-version",
        )
        Divider()
        SettingsValueRow("Service", serviceOrigin, "fst.settings.service-origin")
        Divider()
        whatsNew()
    }
}

@Composable
private fun FirstRunSection(onShow: (FirstRunPageKey) -> Unit) {
    Header(SettingsDetail.FirstRun)
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
private fun Header(title: String, hint: String?) {
    Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
    if (hint != null) {
        Text(hint, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
    } else {
        Spacer(Modifier.height(8.dp))
    }
}

/** A section or detail header from its [SettingsDetail] strings (one source for list and pane). */
@Composable
private fun Header(detail: SettingsDetail) = Header(detail.title, detail.hint)

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

/**
 * Settings → App Version: `versionName (versionCode)`, plus ` · <sha7>` on builds stamped with
 * a commit ([AppBuildInfo], issues #43/#151).
 *
 * @param versionText Text to show; defaults to this build's [BuildConfig] identity.
 */
@Composable
internal fun AppVersionRow(
    versionText: String = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA),
) {
    SettingsValueRow("App Version", versionText, "fst.settings.app-version")
}

/**
 * Web Settings navigation row (Licenses): a section header (title + description) on the page
 * itself, not in a card, with a trailing chevron; the whole row is one link (batch 6.17).
 *
 * In list/detail Settings (issue #371) every multi-option section is this row; [selected] then
 * marks the row whose options the detail pane shows (the Songs/Licenses selected-row tint) and
 * insets the text so the tint has room around it. Null outside list/detail.
 */
@Composable
private fun NavigationRow(title: String, description: String, tag: String, selected: Boolean? = null, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(12.dp))
            .then(if (selected == true) Modifier.background(SELECTED_ROW_COLOR) else Modifier)
            .clickable(role = Role.Button, onClickLabel = "Open $title", onClick = onClick)
            .padding(vertical = if (selected != null) 8.dp else 4.dp, horizontal = if (selected != null) 12.dp else 0.dp)
            .testTag(tag)
            .semantics(mergeDescendants = true) { if (selected != null) this.selected = selected },
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
            Text(description, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp))
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textPrimary)
    }
}

/**
 * List/detail Settings (issue #371): a multi-option setting inside the App Settings card as a
 * chevron row (title, current value, chevron) that opens its options in the detail pane.
 *
 * @param detail Setting the row opens.
 * @param value Current value, read as the row's supporting text.
 * @param panes Pane selection.
 */
@Composable
private fun DetailRow(detail: SettingsDetail, value: String, panes: SettingsPaneSelection) {
    val selected = panes.shown == detail
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(if (selected) Modifier.background(SELECTED_ROW_COLOR) else Modifier)
            .clickable(role = Role.Button, onClickLabel = "Open ${detail.title}") { panes.select(detail) }
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag(detail.rowTag)
            .semantics(mergeDescendants = true) { this.selected = selected },
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(detail.title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
            if (value.isNotEmpty()) Text(value, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textPrimary)
    }
}

/** Selected list row tint, the Songs and Licenses list/detail selection (web `--accent-purple` wash). */
private val SELECTED_ROW_COLOR = BrandTokens.accentPurple.copy(alpha = 0.35f)

// endregion

// region Detail pane

/**
 * List/detail Settings state handed to the list (issue #371).
 *
 * @property shown Detail open in the pane, or null for the placeholder.
 * @property select Opens a detail in the pane.
 */
private class SettingsPaneSelection(val shown: SettingsDetail?, val select: (SettingsDetail) -> Unit)

/**
 * The detail pane with nothing selected (owner, issue #371): the Settings icon, "Settings" and
 * "Select a setting to see more options here", vertically centred, in the app's shared empty
 * state ([FestivalEmptyState]; icon treatment as Notifications').
 */
@Composable
private fun SettingsDetailPlaceholder(modifier: Modifier) {
    FestivalEmptyState(
        SettingsDetailText.PLACEHOLDER_TITLE,
        modifier.testTag("fst.settings.detail-placeholder"),
        subtitle = SettingsDetailText.PLACEHOLDER_SUBTITLE,
        icon = { Icon(FestivalSection.Settings.icon(), contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(48.dp)) },
    )
}

/**
 * One setting's options in the detail pane: its header and the same card the phone list shows
 * (whole sections), or the extracted control (App Settings sub-settings). Licenses and Privacy
 * Policy are their own scrolling lists in the pane.
 */
@Composable
private fun SettingsDetailContent(
    detail: SettingsDetail,
    padding: PaddingValues,
    settings: AppSettings,
    vm: SettingsViewModel,
    serviceOrigin: String,
    debug: Boolean,
    serviceVersion: ServiceVersionState,
    onReplayFirstRun: (FirstRunPageKey) -> Unit,
    onShowWhatsNew: () -> Unit,
) {
    when (detail) {
        SettingsDetail.Licenses -> return LicensesPane(padding, header = { Header(detail) })
        SettingsDetail.PrivacyPolicy -> return PrivacyPolicyPane(padding, header = { Header(detail) })
        else -> Unit
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 24.dp)
            .testTag("fst.settings.detail.${detail.id}"),
    ) {
        Column(Modifier.widthIn(max = 840.dp).fillMaxWidth()) {
            when (detail) {
                SettingsDetail.ItemShop -> ItemShopSection(settings, vm)
                SettingsDetail.ShowInstruments -> InstrumentsSection(settings, vm)
                SettingsDetail.ShowMetadata -> MetadataSection(settings, vm)
                SettingsDetail.Accessibility -> AccessibilitySection(settings, vm)
                SettingsDetail.Version -> VersionSection(serviceOrigin, debug, serviceVersion, vm::loadServiceVersion) { WhatsNewSettingsRow(onShowWhatsNew) }
                SettingsDetail.ServiceInfo -> ServiceInfoSection(vm.serviceInfo)
                SettingsDetail.FirstRun -> FirstRunSection(onReplayFirstRun)
                SettingsDetail.PathDefaultView -> PaneCard(detail) { Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { PathDefaultViewControl(settings, vm) } }
                SettingsDetail.PathColumnOrder -> PaneCard(detail) { Column(Modifier.padding(16.dp)) { PathColumnOrderControl(settings, vm) } }
                SettingsDetail.SongRowOrder -> PaneCard(detail) { Column(Modifier.padding(16.dp)) { SongRowOrderControl(settings, vm) } }
                SettingsDetail.Leeway -> PaneCard(detail) { LeewayControl(settings.leeway, vm::setLeeway, inPane = true) }
                SettingsDetail.Licenses, SettingsDetail.PrivacyPolicy -> Unit
            }
        }
    }
}

/** An App Settings sub-setting in the pane: its header over one glass card, like a section. */
@Composable
private fun PaneCard(detail: SettingsDetail, content: @Composable () -> Unit) {
    Header(detail)
    GlassCard(Modifier.fillMaxWidth()) { content() }
}

// endregion
