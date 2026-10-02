package com.festivalscoretracker.android.ui.songdetail

import android.graphics.BitmapFactory
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Image
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import com.festivalscoretracker.android.ui.design.InstrumentSelector
import kotlin.math.roundToInt
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.paths.PathActivationRow
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.data.paths.SongPathDataPayload
import com.festivalscoretracker.android.data.paths.SongPathImagePayload
import com.festivalscoretracker.android.presentation.songs.PathLoad
import com.festivalscoretracker.android.presentation.songs.PathSwapPhase
import com.festivalscoretracker.android.presentation.songs.PathSwapTiming
import com.festivalscoretracker.android.presentation.songs.SongPathsState
import com.festivalscoretracker.android.presentation.songs.SongPathsViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog
import com.festivalscoretracker.android.ui.common.FestivalModalSheet

// region Sheet

/**
 * CHOpt Paths sheet (web `PathsModal`, operator 6.27): a "Paths" header, the PNG
 * (zoom 100–300%) or the activation table filling the sheet, and the web's bottom
 * control row — instrument, difficulty and view buttons, each expanding its panel
 * above the row (the shared Instrument Selector, a 2×2 difficulty grid, Image/Text).
 * Karaoke's missing paths are announced once in a native alert (OK / Don't Show
 * Again), not a banner. The sheet is modal and focus returns on close.
 *
 * @param viewModel Paths logic (one per opening).
 * @param songTitle Song title (sheet description for TalkBack).
 * @param columns Saved text-table column order.
 * @param showKaraokeWarning Karaoke is visible and the warning wasn't dismissed permanently.
 * @param onDontShowAgain Persist the permanent dismissal.
 * @param onDismiss Close.
 * @param keyboard Keys artwork for Lead/Pro Lead.
 */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun SongPathsSheet(
    viewModel: SongPathsViewModel,
    songTitle: String,
    columns: List<PathColumnKey>,
    showKaraokeWarning: Boolean,
    onDontShowAgain: () -> Unit,
    onDismiss: () -> Unit,
    keyboard: Boolean = false,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var warning by rememberSaveable { mutableStateOf(showKaraokeWarning) }
    var panel by rememberSaveable { mutableStateOf<PathPanel?>(null) }
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    SideEffect { viewModel.reduceMotion = reduceMotion }
    val fade: AnimationSpec<Float> = if (reduceMotion) snap() else tween(PathSwapTiming.FADE_MILLIS.toInt(), easing = LinearEasing)
    val contentAlpha by animateFloatAsState(if (state.phase == PathSwapPhase.Content) 1f else 0f, fade, label = "paths-content")
    val spinnerAlpha by animateFloatAsState(if (state.phase == PathSwapPhase.Spinner) 1f else 0f, fade, label = "paths-spinner")
    FestivalModalSheet(
        title = "Paths",
        closeTag = "fst.paths.close",
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("fst.song-detail.paths").semantics { contentDescription = "Paths for $songTitle" },
    ) {
        BoxWithConstraints(Modifier.fillMaxHeight()) {
            val wide = maxWidth >= PATH_TABLE_WIDE
            Column(Modifier.fillMaxHeight().padding(horizontal = 16.dp).padding(bottom = 12.dp)) {
                if (wide && state.load is PathLoad.Text) Box(Modifier.graphicsLayer { alpha = contentAlpha }) { PathTableHeader(columns) }
                // Polite live region: "Loading <chart> path", then what loaded (web swap has no announcement).
                Box(Modifier.size(1.dp).testTag("fst.paths.status").semantics { contentDescription = state.status; liveRegion = LiveRegionMode.Polite })
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    Box(Modifier.fillMaxSize().graphicsLayer { alpha = contentAlpha }) {
                        val shown = state.shown
                        when (val load = state.load) {
                            PathLoad.Loading -> Unit
                            PathLoad.NotGenerated -> Text(
                                SongPathsState.notGeneratedText(shown),
                                color = BrandTokens.textPrimary,
                                modifier = Modifier.align(Alignment.Center).padding(24.dp).testTag("fst.paths.not-generated"),
                            )
                            is PathLoad.Failed -> ServiceStatusInline(load.issue, "Path unavailable", null, viewModel::retry, Modifier.testTag("fst.paths.error"))
                            is PathLoad.Image -> PathImage(load, "${shown.instrument.label} ${shown.difficulty.label} CHOpt path")
                            is PathLoad.Text -> Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { PathTable(load.data, columns, wide) }
                        }
                    }
                    if (state.spinnerVisible) {
                        Box(Modifier.fillMaxSize().graphicsLayer { alpha = spinnerAlpha }, contentAlignment = Alignment.Center) {
                            FestivalLoading(null, Modifier.testTag("fst.paths.loading"), size = 32.dp)
                        }
                    }
                }
                PathControls(state.instrument, state.difficulty, state.display, viewModel, panel, keyboard) { panel = it }
            }
        }
    }
    if (warning) {
        FestivalAlertDialog(
            title = "Some Instruments Unavailable",
            text = "Karaoke is not available for path visualization yet.",
            tag = "fst.paths.karaoke-warning",
            textTag = "fst.paths.karaoke-warning.message",
            confirmLabel = "OK",
            confirmTag = "fst.paths.warning.ok",
            onConfirm = { warning = false },
            dismissLabel = "Don't Show Again",
            dismissTag = "fst.paths.warning.never",
            onDismissRequest = { warning = false },
            onDismissButton = { warning = false; onDontShowAgain() },
        )
    }
}

/** Which bottom-row panel is open. */
private enum class PathPanel { Instrument, Difficulty, Display }

/** Pane widths from which the table uses the web's desktop grid with a column header. */
private val PATH_TABLE_WIDE = 600.dp

/**
 * Web mobile controls: a row of three frosted buttons (instrument icon, difficulty,
 * view icon) with chevrons; tapping one opens its panel above the row, tapping it
 * (or the current choice) again closes it.
 */
@Composable
private fun PathControls(
    instrument: Instrument,
    difficulty: PathDifficulty,
    display: PathDisplayMode,
    viewModel: SongPathsViewModel,
    panel: PathPanel?,
    keyboard: Boolean,
    onPanel: (PathPanel?) -> Unit,
) {
    fun toggle(target: PathPanel) = onPanel(if (panel == target) null else target)
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).testTag("fst.paths.selectors")) {
        AnimatedVisibility(visible = panel == PathPanel.Instrument, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            InstrumentSelector(
                instruments = viewModel.instruments,
                selected = instrument,
                onSelect = { chosen -> if (chosen == null || chosen == instrument) onPanel(null) else viewModel.selectInstrument(chosen) },
                required = true,
                keyboard = keyboard,
                tag = "fst.paths.instrument",
                modifier = Modifier.padding(bottom = 12.dp),
            )
        }
        AnimatedVisibility(visible = panel == PathPanel.Difficulty, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            OptionGrid(PathDifficulty.entries, difficulty, { it.label }, "fst.paths.difficulty") { choice ->
                if (choice == difficulty) onPanel(null) else viewModel.selectDifficulty(choice)
            }
        }
        AnimatedVisibility(visible = panel == PathPanel.Display, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            OptionGrid(PathDisplayMode.entries, display, { it.label }, "fst.paths.display") { choice ->
                if (choice == display) onPanel(null) else viewModel.selectDisplay(choice)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            ControlButton(panel == PathPanel.Instrument, "Instrument: ${instrument.label}", "fst.paths.instrument.open", Modifier, onClick = { toggle(PathPanel.Instrument) }) { InstrumentIcon(instrument, keyboard = keyboard, size = 28.dp, decorative = true) }
            ControlButton(panel == PathPanel.Difficulty, "Difficulty: ${difficulty.label}", "fst.paths.difficulty.open", Modifier.weight(1f), onClick = { toggle(PathPanel.Difficulty) }) { Text(difficulty.label, color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)) }
            ControlButton(panel == PathPanel.Display, "View: ${display.label}", "fst.paths.display.open", Modifier, onClick = { toggle(PathPanel.Display) }) { Icon(if (display == PathDisplayMode.Image) Icons.Outlined.Image else Icons.AutoMirrored.Outlined.Article, contentDescription = null, tint = BrandTokens.textPrimary) }
        }
    }
}

/** One frosted control with a chevron that points down while its panel is open. */
@Composable
private fun ControlButton(open: Boolean, label: String, tag: String, modifier: Modifier, onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    val rotation by animateFloatAsState(if (open) 0f else 180f, label = "pathsChevron")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(BrandTokens.surfaceFrosted)
            .border(1.dp, BrandTokens.glassBorder, RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp)
            .semantics(mergeDescendants = true) { contentDescription = label; stateDescription = if (open) "Expanded" else "Collapsed" }
            .testTag(tag),
    ) {
        content()
        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = BrandTokens.textMuted, modifier = Modifier.size(18.dp).graphicsLayer { rotationZ = rotation })
    }
}

/** Web option grid (2 columns): the choice is purple-highlighted. Tagged `$tag.<label lowercase>`. */
@Composable
private fun <T> OptionGrid(options: List<T>, selected: T, text: (T) -> String, tag: String, onSelect: (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 12.dp).selectableGroup()) {
        options.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { option ->
                    val chosen = option == selected
                    val shape = RoundedCornerShape(12.dp)
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .clip(shape)
                            .background(if (chosen) PurpleHighlight else BrandTokens.surfaceFrosted)
                            .border(1.dp, if (chosen) PurpleHighlightBorder else BrandTokens.glassBorder, shape)
                            .selectable(selected = chosen, role = Role.RadioButton) { onSelect(option) }
                            .testTag("$tag.${text(option).lowercase()}"),
                    ) {
                        Text(text(option), color = if (chosen) BrandTokens.textPrimary else BrandTokens.textSecondary, fontWeight = FontWeight.SemiBold)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// endregion

// region Image

/**
 * Decode the validated PNG off the main thread, downsampled to a bounded size.
 *
 * @param bytes PNG bytes.
 * @param width Pixel width.
 * @param height Pixel height.
 * @return Image, or null when decoding fails.
 */
internal fun decodePathImage(bytes: ByteArray, width: Int, height: Int): ImageBitmap? {
    var sample = 1
    while (width / sample > MAX_DECODED_WIDTH || (width / sample).toLong() * (height / sample) > MAX_DECODED_PIXELS) sample *= 2
    val options = BitmapFactory.Options().apply { inSampleSize = sample }
    return runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.asImageBitmap() }.getOrNull()
}

private const val MAX_DECODED_WIDTH = 2_048
private const val MAX_DECODED_PIXELS = 16_000_000L

@Composable
private fun PathImage(load: PathLoad.Image, description: String) {
    val image = load.image
    // null = decoding, empty = undecodable, else the image (decoded during the swap spinner when prepared).
    val bitmap by produceState(if (load.prepared) listOfNotNull(load.decoded) else null, load) {
        if (!load.prepared) value = withContext(Dispatchers.Default) { listOfNotNull(decodePathImage(image.bytes, image.width, image.height)) }
    }
    var zoom by remember(image) { mutableFloatStateOf(1f) }
    Box(Modifier.fillMaxSize().testTag("fst.paths.image")) {
        val decoded = bitmap?.firstOrNull()
        if (bitmap == null) {
            FestivalLoading(null, Modifier.align(Alignment.Center), size = 28.dp)
        } else if (decoded == null) {
            Text("This path image couldn't be displayed.", color = BrandTokens.textPrimary, modifier = Modifier.align(Alignment.Center).padding(24.dp).testTag("fst.paths.image-error"))
        } else {
            BoxWithConstraints(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                val width = maxWidth * zoom
                Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
                    Image(
                        bitmap = decoded,
                        contentDescription = description,
                        contentScale = ContentScale.FillWidth,
                        modifier = Modifier
                            .width(width)
                            .aspectRatio(image.width.toFloat() / image.height)
                            .background(Color.White),
                    )
                }
            }
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).background(BrandTokens.cardBackground.copy(alpha = 0.85f), RoundedCornerShape(20.dp)),
        ) {
            IconButton(onClick = { zoom = max(1f, zoom - 0.5f) }, enabled = zoom > 1f, modifier = Modifier.testTag("fst.paths.zoom-out")) {
                Icon(Icons.Filled.ZoomOut, contentDescription = "Zoom out")
            }
            Text("${(zoom * 100).toInt()}%", color = BrandTokens.textPrimary, modifier = Modifier.testTag("fst.paths.zoom"))
            IconButton(onClick = { zoom = minOf(3f, zoom + 0.5f) }, enabled = zoom < 3f, modifier = Modifier.testTag("fst.paths.zoom-in")) {
                Icon(Icons.Filled.ZoomIn, contentDescription = "Zoom in")
            }
        }
    }
}

// endregion

// region Table

/**
 * The web `PathDataTable` (operator 6.27): no path summary or max-score line; one
 * frosted card per activation. Phones use the web's mobile card (Activation fret
 * pills, then Beat / Time / Score, then the Overdrive bar); wide panes use the
 * desktop grid in the saved column order under [PathTableHeader].
 */
@Composable
private fun PathTable(payload: SongPathDataPayload, columns: List<PathColumnKey>, wide: Boolean) {
    Column(Modifier.fillMaxWidth().testTag("fst.paths.table"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (payload.rows.isEmpty()) {
            Text("Paths not available", color = BrandTokens.textMuted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(24.dp))
            return@Column
        }
        payload.rows.forEach { row -> if (wide) PathGridRow(row, columns) else PathCardRow(row) }
    }
}

/** Web column labels (`paths.col*`). */
private val PathColumnKey.header: String
    get() = when (this) {
        PathColumnKey.Note -> "Activation"
        PathColumnKey.Beat -> "Beat"
        PathColumnKey.Time -> "Time"
        PathColumnKey.Od -> "Overdrive %"
        PathColumnKey.Score -> "Score"
    }

private fun weight(column: PathColumnKey): Float = when (column) {
    PathColumnKey.Note -> 1.9f
    PathColumnKey.Beat -> 0.8f
    PathColumnKey.Time -> 1.1f
    PathColumnKey.Od -> 1.6f
    PathColumnKey.Score -> 1f
}

/** Desktop column header (muted uppercase labels). */
@Composable
private fun PathTableHeader(columns: List<PathColumnKey>) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).semantics { heading() }.testTag("fst.paths.table.header")) {
        columns.forEach { column ->
            Text(column.header.uppercase(), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textMuted, textAlign = TextAlign.Center, modifier = Modifier.weight(weight(column)))
        }
    }
}

private fun spoken(row: PathActivationRow): String =
    "Activation ${row.number}: frets ${row.fretsText}, beat ${row.beatText()}, time ${row.timeText}, overdrive ${row.odText}, score ${row.scoreText()}" +
        (row.instruction?.let { ". $it" } ?: "")

@Composable
private fun PathCardRow(row: PathActivationRow) {
    PathRowCard(row) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Column {
                MobileLabel("Activation")
                Frets(row.frets, Arrangement.Start)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f)) { MobileLabel("Beat"); Cell(row.beatText()) }
                Column(Modifier.weight(1f)) { MobileLabel("Time"); Cell(row.timeText) }
                Column(Modifier.weight(1f)) { MobileLabel("Score"); ScoreCell(row) }
            }
            Column {
                MobileLabel("Overdrive %")
                OdCell(row.odPercent)
            }
        }
    }
}

@Composable
private fun PathGridRow(row: PathActivationRow, columns: List<PathColumnKey>) {
    PathRowCard(row) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            columns.forEach { column ->
                Box(Modifier.weight(weight(column)).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
                    when (column) {
                        PathColumnKey.Note -> Frets(row.frets, Arrangement.Center)
                        PathColumnKey.Beat -> Cell(row.beatText())
                        PathColumnKey.Time -> Cell(row.timeText)
                        PathColumnKey.Od -> OdCell(row.odPercent)
                        PathColumnKey.Score -> ScoreCell(row)
                    }
                }
            }
        }
    }
}

/** One frosted activation card (one TalkBack stop). */
@Composable
private fun PathRowCard(row: PathActivationRow, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(BrandTokens.surfaceFrosted)
            .border(1.dp, BrandTokens.glassBorder, shape)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("fst.paths.row.${row.number}")
            .clearAndSetSemantics { contentDescription = spoken(row) },
    ) {
        // The web table shows no path instruction text; TalkBack still reads it.
        content()
    }
}

@Composable
private fun MobileLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = BrandTokens.textMuted,
        modifier = Modifier.padding(bottom = 6.dp),
    )
}

@Composable
private fun Cell(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = 1)
}

@Composable
private fun ScoreCell(row: PathActivationRow) {
    if (row.scoreBeforeActivation == null) Text("—", color = BrandTokens.textMuted) else Cell(row.scoreText())
}

/** The five fret pills (web `FretPill`: 22 dp, active in the fret colour, inactive muted with a border). */
@Composable
private fun Frets(frets: List<String>, arrangement: Arrangement.Horizontal) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp, if (arrangement == Arrangement.Center) Alignment.CenterHorizontally else Alignment.Start), modifier = Modifier.fillMaxWidth()) {
        FRETS.forEach { (name, color) ->
            val active = name in frets
            Box(
                Modifier
                    .size(22.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(if (active) color else BrandTokens.surfaceMuted)
                    .then(if (active) Modifier else Modifier.border(2.dp, BORDER_SUBTLE, RoundedCornerShape(4.dp)))
                    .testTag("fst.paths.fret.$name.${if (active) "on" else "off"}"),
            )
        }
    }
}

/** Web `OdBar`: amber fill on a subtle 8 dp track, then the rounded percent. */
@Composable
private fun OdCell(percent: Double?) {
    if (percent == null) {
        Text("—", color = BrandTokens.textMuted)
        return
    }
    val clamped = percent.coerceIn(0.0, 100.0).roundToInt()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .weight(1f)
                .height(8.dp)
                .clip(CircleShape)
                .background(BrandTokens.surfaceSubtle)
                .drawBehind { drawRoundRect(OD_AMBER, size = size.copy(width = size.width * clamped / 100f), cornerRadius = CornerRadius(size.height / 2)) },
        )
        Text("$clamped%", fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 40.dp))
    }
}

/** Web `FRET_COLORS` in fret order. */
private val FRETS = listOf(
    "green" to Color(0xFF2ECC71),
    "red" to Color(0xFFE74C3C),
    "yellow" to Color(0xFFF1C40F),
    "blue" to Color(0xFF3498DB),
    "orange" to Color(0xFFE67E22),
)

/** Web `statusAmber`. */
private val OD_AMBER = Color(0xFFF5A623)

/** Web `borderSubtle`. */
private val BORDER_SUBTLE = Color(0xFF1E2A3A)

// endregion
