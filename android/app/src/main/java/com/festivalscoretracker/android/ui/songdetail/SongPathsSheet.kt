package com.festivalscoretracker.android.ui.songdetail

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
 * CHOpt Paths sheet: chart chips, difficulty and image/text choices, then the
 * PNG (zoom 100–300%) or the activation table in the saved column order. The
 * sheet is modal, so the page behind cannot be used and focus returns on close.
 *
 * @param viewModel Paths logic (one per opening).
 * @param songTitle Song title for the header.
 * @param columns Saved text-table column order.
 * @param showKaraokeWarning Karaoke is visible and the warning wasn't dismissed permanently.
 * @param onDontShowAgain Persist the permanent dismissal.
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
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
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp).verticalScroll(rememberScrollState())) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Paths", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
                    Text(songTitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
                }
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("fst.paths.close")) { Icon(Icons.Filled.Close, contentDescription = "Close Paths") }
            }
            if (warning) {
                GlassCard(Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("fst.paths.karaoke-warning")) {
                    Column(Modifier.padding(12.dp)) {
                        Text("Karaoke doesn't have CHOpt paths, so it isn't listed here.", color = BrandTokens.textPrimary)
                        Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                            TextButton(onClick = { warning = false; onDontShowAgain() }, modifier = Modifier.testTag("fst.paths.warning.never")) { Text("Don't Show Again") }
                            TextButton(onClick = { warning = false }, modifier = Modifier.testTag("fst.paths.warning.ok")) { Text("OK") }
                        }
                    }
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 8.dp).testTag("fst.paths.instrument")) {
                viewModel.instruments.forEach { chart ->
                    FilterChip(
                        selected = chart == state.instrument,
                        onClick = { viewModel.selectInstrument(chart) },
                        label = { Text(chart.label) },
                        leadingIcon = { InstrumentIcon(chart, size = 20.dp, decorative = true) },
                        modifier = Modifier.testTag("fst.paths.instrument.${chart.wireId}"),
                    )
                }
            }
            Segmented(PathDifficulty.entries, state.difficulty, { it.label }, "fst.paths.difficulty", viewModel::selectDifficulty)
            Segmented(PathDisplayMode.entries, state.display, { it.label }, "fst.paths.display", viewModel::selectDisplay)
            Box(Modifier.padding(top = 12.dp)) {
                when (val load = state.load) {
                    PathLoad.Loading -> Box(Modifier.fillMaxWidth().heightIn(min = 160.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(32.dp).testTag("fst.paths.loading"))
                    }
                    PathLoad.NotGenerated -> Text(
                        "No ${state.difficulty.label} path has been generated for ${state.instrument.label} yet.",
                        color = BrandTokens.textSecondary,
                        modifier = Modifier.padding(vertical = 24.dp).testTag("fst.paths.not-generated"),
                    )
                    is PathLoad.Failed -> ServiceStatusInline(load.issue, "Path unavailable", null, viewModel::retry, Modifier.testTag("fst.paths.error"))
                    is PathLoad.Image -> PathImage(load.image, "${state.instrument.label} ${state.difficulty.label} CHOpt path")
                    is PathLoad.Text -> PathTable(load.data, columns)
                }
            }
        }
    }
}

@Composable
private fun <T> Segmented(options: List<T>, selected: T, label: (T) -> String, tag: String, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = 8.dp).testTag(tag)) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == selected,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                modifier = Modifier.testTag("$tag.${label(option).lowercase()}"),
            ) { Text(label(option), maxLines = 1) }
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
    Column(Modifier.testTag("fst.paths.image")) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
            IconButton(onClick = { zoom = max(1f, zoom - 0.5f) }, enabled = zoom > 1f, modifier = Modifier.testTag("fst.paths.zoom-out")) {
                Icon(Icons.Filled.ZoomOut, contentDescription = "Zoom out")
            }
            Text("${(zoom * 100).toInt()}%", color = BrandTokens.textSecondary, modifier = Modifier.testTag("fst.paths.zoom"))
            IconButton(onClick = { zoom = minOf(3f, zoom + 0.5f) }, enabled = zoom < 3f, modifier = Modifier.testTag("fst.paths.zoom-in")) {
                Icon(Icons.Filled.ZoomIn, contentDescription = "Zoom in")
            }
        }
        val decoded = bitmap?.firstOrNull()
        if (bitmap == null) {
            Box(Modifier.fillMaxWidth().heightIn(min = 160.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(28.dp)) }
        } else if (decoded == null) {
            Text("This path image couldn't be displayed.", color = BrandTokens.textSecondary, modifier = Modifier.padding(vertical = 24.dp).testTag("fst.paths.image-error"))
        } else {
            BoxWithConstraints(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
                Image(
                    bitmap = decoded,
                    contentDescription = description,
                    contentScale = ContentScale.FillWidth,
                    modifier = Modifier
                        .width(maxWidth * zoom)
                        .aspectRatio(image.width.toFloat() / image.height)
                        .background(Color.White),
                )
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

private fun weight(column: PathColumnKey): Float = if (column == PathColumnKey.Note) 1.3f else 1f

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
