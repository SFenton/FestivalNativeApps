package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.style.TextOverflow
import com.festivalscoretracker.android.ui.design.popupTestTags
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
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
import com.festivalscoretracker.android.presentation.songs.SongPathsViewModel
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max

// region Sheet

/**
 * CHOpt Paths sheet (web Paths modal): a one-line header, the PNG (zoom 100–300%)
 * or activation table filling the sheet, and one compact bottom row of M3 exposed
 * dropdown menus for chart, difficulty and view. The sheet is modal, so the page
 * behind cannot be used and focus returns on close.
 *
 * @param viewModel Paths logic (one per opening).
 * @param songTitle Song title for the header.
 * @param columns Saved text-table column order.
 * @param showKaraokeWarning Karaoke is visible and the warning wasn't dismissed permanently.
 * @param onDontShowAgain Persist the permanent dismissal.
 * @param onDismiss Close.
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
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var warning by remember { mutableStateOf(showKaraokeWarning) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.testTag("fst.song-detail.paths"),
    ) {
        Column(Modifier.fillMaxHeight().semantics { testTagsAsResourceId = true }.padding(horizontal = 16.dp).padding(bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Paths · $songTitle",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = BrandTokens.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("fst.paths.close")) { Icon(Icons.Filled.Close, contentDescription = "Close Paths") }
            }
            if (warning) {
                GlassCard(Modifier.fillMaxWidth().padding(bottom = 8.dp).testTag("fst.paths.karaoke-warning")) {
                    Column(Modifier.padding(12.dp)) {
                        Text("Karaoke doesn't have CHOpt paths, so it isn't listed here.", color = BrandTokens.textPrimary)
                        Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                            TextButton(onClick = { warning = false; onDontShowAgain() }, modifier = Modifier.testTag("fst.paths.warning.never")) { Text("Don't Show Again") }
                            TextButton(onClick = { warning = false }, modifier = Modifier.testTag("fst.paths.warning.ok")) { Text("OK") }
                        }
                    }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (val load = state.load) {
                    PathLoad.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(32.dp).testTag("fst.paths.loading"))
                    }
                    PathLoad.NotGenerated -> Text(
                        "No ${state.difficulty.label} path has been generated for ${state.instrument.label} yet.",
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.align(Alignment.Center).padding(24.dp).testTag("fst.paths.not-generated"),
                    )
                    is PathLoad.Failed -> ServiceStatusInline(load.issue, "Path unavailable", null, viewModel::retry, Modifier.testTag("fst.paths.error"))
                    is PathLoad.Image -> PathImage(load.image, "${state.instrument.label} ${state.difficulty.label} CHOpt path")
                    is PathLoad.Text -> Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { PathTable(load.data, columns) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp).testTag("fst.paths.selectors")) {
                Selector(
                    label = "Instrument",
                    options = viewModel.instruments,
                    selected = state.instrument,
                    text = { it.label },
                    tag = "fst.paths.instrument",
                    optionTag = { it.wireId },
                    icon = { InstrumentIcon(it, size = 20.dp, decorative = true) },
                    modifier = Modifier.weight(1.4f),
                    onSelect = viewModel::selectInstrument,
                )
                Selector("Difficulty", PathDifficulty.entries, state.difficulty, { it.label }, "fst.paths.difficulty", { it.label.lowercase() }, null, Modifier.weight(1f), viewModel::selectDifficulty)
                Selector("View", PathDisplayMode.entries, state.display, { it.label }, "fst.paths.display", { it.label.lowercase() }, null, Modifier.weight(1f), viewModel::selectDisplay)
            }
        }
    }
}

/**
 * One compact M3 exposed dropdown (read-only field + menu). The anchor is tagged
 * [tag]; each option is `$tag.<optionTag>`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> Selector(
    label: String,
    options: List<T>,
    selected: T,
    text: (T) -> String,
    tag: String,
    optionTag: (T) -> String,
    icon: (@Composable (T) -> Unit)?,
    modifier: Modifier,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }, modifier = modifier) {
        OutlinedTextField(
            value = text(selected),
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text(label, maxLines = 1) },
            leadingIcon = icon?.let { draw -> { draw(selected) } },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            textStyle = MaterialTheme.typography.bodyMedium,
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = BrandTokens.textPrimary,
                unfocusedTextColor = BrandTokens.textPrimary,
                focusedLabelColor = BrandTokens.textPrimary,
                unfocusedLabelColor = BrandTokens.textPrimary,
            ),
            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth().testTag(tag),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, modifier = Modifier.popupTestTags()) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(text(option), fontWeight = if (option == selected) FontWeight.Bold else null) },
                    leadingIcon = icon?.let { draw -> { draw(option) } },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                    modifier = Modifier.testTag("$tag.${optionTag(option)}").semantics { this.selected = option == selected },
                )
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
private fun PathImage(image: SongPathImagePayload, description: String) {
    // null = decoding, empty = undecodable, else the image.
    val bitmap by produceState<List<ImageBitmap>?>(null, image) {
        value = withContext(Dispatchers.Default) { listOfNotNull(decodePathImage(image.bytes, image.width, image.height)) }
    }
    var zoom by remember(image) { mutableFloatStateOf(1f) }
    Box(Modifier.fillMaxSize().testTag("fst.paths.image")) {
        val decoded = bitmap?.firstOrNull()
        if (bitmap == null) {
            CircularProgressIndicator(Modifier.size(28.dp).align(Alignment.Center))
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

@Composable
private fun PathTable(payload: SongPathDataPayload, columns: List<PathColumnKey>) {
    val path = payload.path
    Column(Modifier.testTag("fst.paths.table"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(path.pathSummary.ifBlank { "No path summary provided" }, color = BrandTokens.textPrimary, fontFamily = FontFamily.Monospace)
        Text("Max score: ${ScoreFormatting.score(path.totalScore.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())}", color = BrandTokens.gold, fontWeight = FontWeight.SemiBold)
        if (payload.rows.isEmpty()) {
            Text("This path has no activations.", color = BrandTokens.textSecondary)
            return@Column
        }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp).semantics { heading() }) {
            columns.forEach { column ->
                Text(column.label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textSecondary, modifier = Modifier.weight(weight(column)))
            }
        }
        HorizontalDivider(color = BrandTokens.glassBorder)
        payload.rows.forEach { row -> PathRow(row, columns) }
    }
}

private fun weight(column: PathColumnKey): Float = when (column) {
    PathColumnKey.Note -> 1.2f
    PathColumnKey.Beat -> 0.9f
    PathColumnKey.Time -> 1.5f
    PathColumnKey.Od -> 0.8f
    PathColumnKey.Score -> 1.1f
}

@Composable
private fun PathRow(row: PathActivationRow, columns: List<PathColumnKey>) {
    val spoken = "Activation ${row.number}: frets ${row.fretsText}, beat ${row.beatText()}, time ${row.timeText}, OD ${row.odText}, score ${row.scoreText()}" +
        (row.instruction?.let { ". $it" } ?: "")
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp).semantics(mergeDescendants = true) { contentDescription = spoken }.testTag("fst.paths.row.${row.number}")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            columns.forEach { column ->
                Box(Modifier.weight(weight(column))) {
                    when (column) {
                        PathColumnKey.Note -> Frets(row.frets)
                        PathColumnKey.Beat -> Cell(row.beatText())
                        PathColumnKey.Time -> Cell(row.timeText)
                        PathColumnKey.Od -> Cell(row.odText)
                        PathColumnKey.Score -> Cell(row.scoreText())
                    }
                }
            }
        }
        row.instruction?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary) }
    }
}

@Composable
private fun Cell(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textPrimary, fontFamily = FontFamily.Monospace, maxLines = 1)
}

@Composable
private fun Frets(frets: List<String>) {
    if (frets.isEmpty()) {
        Text("—", color = BrandTokens.textMuted)
        return
    }
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        frets.forEach { fret ->
            Box(Modifier.size(14.dp).background(fretColor(fret), if (fret == "open") RoundedCornerShape(3.dp) else CircleShape))
        }
    }
}

private fun fretColor(fret: String): Color = when (fret) {
    "green" -> Color(0xFF2ECC71)
    "red" -> Color(0xFFE53935)
    "yellow" -> Color(0xFFFFD700)
    "blue" -> Color(0xFF2D82E6)
    "orange" -> Color(0xFFFF8C00)
    else -> Color(0xFFB39DDB)
}

// endregion
