package com.festivalscoretracker.android.ui.songs

import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.lerp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.IconButton
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.core.songs.InvalidScoreWarning
import com.festivalscoretracker.android.core.songs.SongLastPlayed
import com.festivalscoretracker.android.core.songs.SongMaxScorePill
import com.festivalscoretracker.android.core.songs.SongInstrumentBadge
import com.festivalscoretracker.android.core.songs.SongInstrumentStatus
import com.festivalscoretracker.android.core.songs.SongMetadataPill
import com.festivalscoretracker.android.core.songs.SongPercentileTier
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.ceil
import kotlin.math.max
import com.festivalscoretracker.android.ui.design.instrumentIconRes
import com.festivalscoretracker.android.ui.design.BundledBitmaps
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.foundation.layout.Spacer

// region Tokens

/** Songs-specific colors from `contracts/fluent-tokens.json` (not yet in the shared theme). */
internal object SongsTokens {
    val goldStroke = Color(0xFFCFA500)
    val statusGreenStroke = Color(0xFF1E7F46)
    val statusRedStroke = Color(0xFF8B0000)
    val statusAmber = Color(0xFFF5A623)
    val statusAmberStroke = Color(0xFFAB7419)
    val diffEasy = Color(0xFF2ECC71)
    val diffMedium = Color(0xFFC62828)
    val diffHard = Color(0xFF2D82E6)
    val diffExpert = Color(0xFF7C3AED)
    val darkGlyph = Color(0xFF0B1220)

    /**
     * Fill and stroke for a chip status (color is the only visual cue; the row speaks the status).
     *
     * @param status Status.
     * @return Fill to stroke.
     */
    fun chip(status: SongInstrumentStatus): Pair<Color, Color> = when (status) {
        SongInstrumentStatus.Unavailable -> BrandTokens.surfaceMuted to BrandTokens.textDisabled
        SongInstrumentStatus.FullCombo -> BrandTokens.gold to goldStroke
        SongInstrumentStatus.Scored -> BrandTokens.statusGreen to statusGreenStroke
        SongInstrumentStatus.NoScore -> BrandTokens.statusRed to statusRedStroke
        SongInstrumentStatus.InconsistentFullCombo -> statusAmber to statusAmberStroke
    }

    /**
     * Shop outline pulse color (web `shopHighlight*`: the chips' green/gold/red).
     *
     * @param pulse Pulse.
     * @return Green in the Shop, gold New, red Leaving Tomorrow.
     */
    fun pulse(pulse: ShopPulse): Color = when (pulse) {
        ShopPulse.InShop -> BrandTokens.statusGreen
        ShopPulse.New -> BrandTokens.gold
        ShopPulse.LeavingTomorrow -> BrandTokens.statusRed
    }

    /** Web `--shop-pulse-base` (rgb 18 24 38 / 96%). */
    val breatheBase = Color(red = 18, green = 24, blue = 38, alpha = 245)

    /**
     * Filled Shop indicator color at a breathe fraction (web `shopBreathe*` targets:
     * green stroke in Shop, gold stroke New, leaving red).
     *
     * @param pulse Status.
     * @param fraction 0 = surface, 1 = status color.
     * @return Fill.
     */
    fun breathe(pulse: ShopPulse, fraction: Float): Color {
        val target = when (pulse) {
            ShopPulse.InShop -> statusGreenStroke
            ShopPulse.New -> goldStroke
            ShopPulse.LeavingTomorrow -> BrandTokens.statusRed
        }
        return lerp(breatheBase, target, fraction.coerceIn(0f, 1f))
    }

    /**
     * Web `maxScoreColor`: red at 0% of the CHOpt maximum to green at 100%.
     *
     * @param percent Score as a percent of the maximum.
     * @return Fill.
     */
    fun maxScore(percent: Double): Color {
        val t = (percent / 100).coerceIn(0.0, 1.0).toFloat()
        return Color(red = (220 * (1 - t) + 34 * t) / 255f, green = (40 * (1 - t) + 139 * t) / 255f, blue = (40 * (1 - t) + 34 * t) / 255f)
    }
}

// endregion

// region Row card

/**
 * The shared song card used by every song list (Songs, Item Shop list): the glass
 * surface, 48 dp art, marquee title and subtitle, an optional pulsing outline and
 * slots for page-specific content. Pages must build song rows on this card rather
 * than copying its layout, so the surface, spacing and marquee stay identical.
 *
 * Semantics: with a [description] the card is one TalkBack stop that speaks it (the
 * art/text column is cleared); without one, the card merges its texts. [end] sits
 * outside the cleared column, so a button there stays its own focus stop.
 *
 * @param title Song title (marquee when too long).
 * @param subtitle Secondary line, e.g. `artist · year · duration` (marquee).
 * @param artUrl Resolved artwork, or null.
 * @param onClick Primary row action.
 * @param modifier Applied to the card (test tags).
 * @param description Whole-card spoken description, or null to merge the texts.
 * @param selected Highlighted in two-pane layouts.
 * @param outline Pulsing outline color, or null for none.
 * @param pulse Shared outline alpha, read only while drawing.
 * @param details Extra lines under the subtitle (chart label, Shop badge).
 * @param trailing Content after the text column (metadata, Shop indicator).
 * @param below Full-width content under the art row (chips, pills, score state).
 * @param end Interactive content after the padded column (invalid-score icon, Shop link).
 */
@Composable
fun SongRowCard(
    title: String,
    subtitle: String,
    artUrl: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    description: String? = null,
    selected: Boolean = false,
    outline: Color? = null,
    pulse: () -> Float = { 0f },
    details: @Composable ColumnScope.() -> Unit = {},
    trailing: @Composable RowScope.() -> Unit = {},
    below: @Composable ColumnScope.() -> Unit = {},
    end: @Composable RowScope.() -> Unit = {},
) {
    GlassCard(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (outline != null) Modifier.pulseOutline(outline, pulse) else Modifier)
            .then(modifier)
            .then(
                if (description != null || selected) {
                    Modifier.semantics {
                        // Only the highlighted row carries selection state; single-pane rows are not
                        // selectable, so TalkBack should not prefix every row with "Not selected".
                        if (selected) this.selected = true
                        if (description != null) contentDescription = description
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.background(if (selected) BrandTokens.accentPurple.copy(alpha = 0.35f) else Color.Transparent)) {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 12.dp, vertical = 10.dp)
                    .then(if (description != null) Modifier.clearAndSetSemantics { } else Modifier),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    AsyncImage(
                        model = artUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
                    )
                    Column(Modifier.weight(1f)) {
                        FestivalMarqueeText(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = BrandTokens.textPrimary)
                        FestivalMarqueeText(subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
                        details()
                    }
                    trailing()
                }
                below()
            }
            end()
        }
    }
}

// endregion

// region Row

/**
 * One glass Songs card ([SongRowCard]): art, marquee title and `artist · year · duration`,
 * the pulsing Shop outline, then selected-player chips or metadata pills (or an
 * explicit score state). The card is one tap target and one TalkBack stop that
 * speaks [SongRowModel.announcement]; an invalid-score icon is a second stop.
 *
 * @param row Projected row.
 * @param artUrl Resolved artwork, or null.
 * @param selected Highlighted in two-pane layouts.
 * @param pulse Shared Shop outline alpha, read only while drawing.
 * @param breathe Shared Shop badge breathe fraction, read only while drawing.
 * @param onWarning Open the invalid-score alert (shown when the row has a warning).
 * @param onClick Open the song.
 */
@Composable
fun SongRow(
    row: SongRowModel,
    artUrl: String?,
    selected: Boolean = false,
    pulse: () -> Float = { 0f },
    breathe: () -> Float = { 1f },
    onWarning: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val song = row.song
    SongRowCard(
        title = song.title,
        subtitle = song.subtitle,
        artUrl = artUrl,
        onClick = onClick,
        modifier = Modifier.testTag("fst.songs.row.${song.songId}"),
        description = row.announcement,
        selected = selected,
        outline = row.pulse?.let(SongsTokens::pulse),
        pulse = pulse,
        details = {
            if (row.namesChart) {
                Text(
                    "${row.chart!!.label} chart",
                    style = MaterialTheme.typography.labelMedium,
                    color = BrandTokens.textSecondary,
                    modifier = Modifier.testTag("fst.songs.metadata.chart.${song.songId}"),
                )
            }
        },
        trailing = {
            val lastPlayed = row.lastPlayed
            val maxScore = row.maxScore
            when {
                lastPlayed != null -> LastPlayedEntry(lastPlayed, song)
                maxScore != null -> MaxScoreDual(maxScore, song.songId)
                else -> row.metadata.firstOrNull()?.let { MetadataPill(it, song.songId) }
            }
            val raw = row.chartRaw
            if (row.metadata.isEmpty() && maxScore == null && raw != null) DifficultyMeter(raw)
            row.pulse?.let { ShopBadge(it, song.songId, breathe) }
        },
        below = {
            if (row.chips.isNotEmpty()) StatusChips(row.chips, song.songId, song.usesKeyboardIcon)
            val rest = if (row.lastPlayed == null && row.maxScore == null) row.metadata.drop(1) else row.metadata
            if (rest.isNotEmpty() || row.maxScore != null) {
                MetadataPills(rest, song.songId, row.maxScore)
            }
            row.scoreState?.let { ScoreState(it, song.songId) }
        },
        end = {
            if (row.warning != null && onWarning != null) InvalidScoreIcon(row.warning.warning, song.songId, pulse, onWarning)
        },
    )
}

/**
 * The Shop outline pulse (web `shopPulse::after`: a 2 px border fading 0 -> 0.7 -> 0),
 * drawn over the card. [alpha] is read in the draw phase only.
 *
 * @param color Outline color.
 * @param alpha Current alpha.
 * @param corner Card corner radius.
 * @return Modifier.
 */
internal fun Modifier.pulseOutline(color: Color, alpha: () -> Float, corner: Dp = 12.dp): Modifier = drawWithContent {
    drawContent()
    val stroke = 2.dp.toPx()
    drawRoundRect(
        color = color,
        alpha = alpha().coerceIn(0f, 1f),
        topLeft = Offset(stroke / 2, stroke / 2),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius(corner.toPx()),
        style = Stroke(stroke),
    )
}

/**
 * The invalid-score indicator (web `InvalidScoreIcon`): red alert for a filtered
 * score, gold warning when only raw over-threshold scores are shown; it pulses
 * (1 -> 0.4 opacity, still under reduced motion) and opens the Filtered Score alert.
 */
@Composable
private fun InvalidScoreIcon(warning: Boolean, songId: String, pulse: () -> Float, onClick: () -> Unit) {
    val still = LocalFestivalAccessibility.current.reduceMotion
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .testTag("fst.songs.invalid-score.$songId")
            .semantics { contentDescription = InvalidScoreWarning.LABEL }
            .graphicsLayer { alpha = if (still) 1f else 1f - pulse() / SHOP_PULSE_PEAK * 0.6f },
    ) {
        Icon(
            if (warning) Icons.Filled.Warning else Icons.Outlined.ErrorOutline,
            contentDescription = null,
            tint = if (warning) BrandTokens.gold else BrandTokens.statusRed,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun LastPlayedEntry(entry: SongLastPlayed, song: Song) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("fst.songs.last-played.${song.songId}")) {
        val keys = song.usesKeyboardIcon && (entry.chart == Instrument.Lead || entry.chart == Instrument.ProLead)
        InstrumentIcon(entry.chart, keyboard = keys, size = 24.dp, decorative = true)
        Text(
            entry.text.removePrefix("Last played "),
            style = MaterialTheme.typography.labelLarge,
            color = BrandTokens.textSecondary,
            modifier = Modifier.padding(start = 6.dp),
        )
    }
}

@Composable
private fun MaxScoreDual(pill: SongMaxScorePill, songId: String) {
    Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.testTag("fst.songs.max-score.$songId")) {
        Text(pill.score, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        Text(" / ", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
        Text(pill.max ?: "—", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = if (pill.max == null) BrandTokens.textMuted else BrandTokens.textPrimary)
    }
}

/**
 * The row's Item Shop indicator: a circle breathing in the status color (green in
 * Shop, gold New, red Leaving Tomorrow) with a clock, sparkle or bag glyph.
 */
@Composable
private fun ShopBadge(pulse: ShopPulse, songId: String, breathe: () -> Float) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(30.dp)
            .drawBehind { drawCircle(SongsTokens.breathe(pulse, breathe())) }
            .testTag("fst.songs.shop-badge.$songId"),
    ) {
        Icon(
            when (pulse) {
                ShopPulse.LeavingTomorrow -> Icons.Filled.Schedule
                ShopPulse.New -> Icons.Filled.AutoAwesome
                ShopPulse.InShop -> Icons.Filled.ShoppingBag
            },
            contentDescription = null,
            tint = BrandTokens.textPrimary,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun ScoreState(text: String, songId: String) {
    val paused = text.contains("paused", ignoreCase = true)
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("fst.songs.score-state.$songId")) {
        if (paused) Icon(Icons.Filled.PauseCircle, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(16.dp).padding(end = 2.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = if (paused) BrandTokens.gold else BrandTokens.textSecondary)
    }
}

// endregion

// region Status chips

/**
 * Balanced wrapping chip rows (nine chips wrap 5+4 on a phone, one row on wide cards).
 *
 * Performance: one layout node measured and drawn directly (circle fill, 2 dp ring, the
 * shared decoded icon from [BundledBitmaps]) instead of a `BoxWithConstraints`
 * subcomposition plus a Box and an Image per chip (about twenty nodes composed for every
 * Songs row that scrolls in). The row's description speaks the statuses; the chips carry
 * [SongChipStatuses] for tests.
 *
 * @param badges Chips in service order.
 * @param songId Song (test tag).
 * @param keyboard Keys icon variant for Lead/Pro Lead.
 */
@Composable
fun StatusChips(badges: List<SongInstrumentBadge>, songId: String, keyboard: Boolean) {
    val resources = LocalContext.current.resources
    val icons = remember(badges, keyboard) {
        badges.map { badge ->
            val keys = keyboard && (badge.instrument == Instrument.Lead || badge.instrument == Instrument.ProLead)
            BundledBitmaps.get(resources, instrumentIconRes(badge.instrument, keys))
        }
    }
    val colors = remember(badges) { badges.map { SongsTokens.chip(it.status) } }
    Spacer(
        Modifier
            .fillMaxWidth()
            .testTag("fst.songs.instrument-status.$songId")
            .semantics { this[SongChipStatuses] = badges.map { "${it.instrument.wireId}.${it.status.name}" } }
            .layout { measurable, constraints ->
                val grid = ChipGrid(badges.size, constraints.maxWidth.toFloat(), CHIP_SIDE.toPx(), CHIP_SPACING.toPx())
                val placeable = measurable.measure(constraints.copy(minHeight = grid.height.toInt(), maxHeight = grid.height.toInt()))
                layout(placeable.width, placeable.height) { placeable.place(0, 0) }
            }
            .drawBehind {
                val side = CHIP_SIDE.toPx()
                val ring = 2.dp.toPx()
                val iconSide = (side * 0.7f).toInt()
                val grid = ChipGrid(badges.size, size.width, side, CHIP_SPACING.toPx())
                badges.indices.forEach { index ->
                    val topLeft = grid.topLeft(index)
                    val center = Offset(topLeft.x + side / 2, topLeft.y + side / 2)
                    val (fill, stroke) = colors[index]
                    drawCircle(fill, radius = side / 2, center = center)
                    drawCircle(stroke, radius = side / 2 - ring / 2, center = center, style = Stroke(ring))
                    val inset = ((side - iconSide) / 2).toInt()
                    drawImage(
                        icons[index],
                        dstOffset = IntOffset(topLeft.x.toInt() + inset, topLeft.y.toInt() + inset),
                        dstSize = IntSize(iconSide, iconSide),
                        filterQuality = FilterQuality.Medium,
                    )
                }
            },
    )
}

/**
 * Balanced chip rows: as many chips per row as fit, the rows evened out (9 → 5 + 4), each
 * row centred (web `InstrumentStatusRow`).
 *
 * @param count Chips.
 * @param width Available width in px.
 * @param side Chip diameter in px.
 * @param spacing Gap in px (both axes).
 */
internal class ChipGrid(count: Int, width: Float, private val side: Float, private val spacing: Float) {
    private val fit = max(1, ((width + spacing) / (side + spacing)).toInt())
    private val rows = ceil(count / fit.toDouble()).toInt().coerceAtLeast(1)
    private val perRow = ceil(count / rows.toDouble()).toInt().coerceAtLeast(1)
    private val count = count
    private val width = width

    /** Total height in px. */
    val height: Float get() = rows * side + (rows - 1) * spacing

    /**
     * Top-left of chip [index].
     *
     * @param index Chip index.
     * @return Offset in px.
     */
    fun topLeft(index: Int): Offset {
        val row = index / perRow
        val inRow = if (row == rows - 1) count - row * perRow else perRow
        val rowWidth = inRow * side + (inRow - 1) * spacing
        val x = (width - rowWidth) / 2 + (index % perRow) * (side + spacing)
        return Offset(x, row * (side + spacing))
    }
}

/** Test hook: the chips' `<wireId>.<status>` in order. */
internal val SongChipStatuses = SemanticsPropertyKey<List<String>>("SongChipStatuses")

/** Gap between chips (both axes). */
private val CHIP_SPACING = 4.dp

/** Chip diameter (web 34 px chip with a 24 px icon). */
private val CHIP_SIDE = 34.dp

// endregion

// region Metadata pills

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MetadataPills(pills: List<SongMetadataPill>, songId: String, maxScore: SongMaxScorePill? = null) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().testTag("fst.songs.metadata.$songId"),
    ) {
        maxScore?.let { pill ->
            val fill = pill.percent?.let(SongsTokens::maxScore) ?: BrandTokens.surfaceMuted
            PillBox(pill.metric, fill, null, BrandTokens.textPrimary, Modifier.testTag("fst.songs.metadata.max-metric.$songId"))
        }
        pills.forEach { MetadataPill(it, songId) }
    }
}

/**
 * One metadata field (score, accuracy/FC, percentile, stars, season, intensity,
 * game difficulty, last played) styled like the web pills.
 *
 * @param pill Field.
 * @param songId Song (test tag).
 */
@Composable
fun MetadataPill(pill: SongMetadataPill, songId: String) {
    val tag = Modifier.testTag("fst.songs.metadata.${pill.kind.name.lowercase()}.$songId")
    val label = MaterialTheme.typography.labelLarge
    when (pill.kind) {
        MetadataField.Score -> Text(pill.text, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = tag)
        MetadataField.Percentage -> {
            val tint = pill.tint?.let { Color(0xFF000000 or it.toLong()).copy(alpha = 0.25f) } ?: Color.Transparent
            PillBox(
                text = pill.text,
                fill = if (pill.fullCombo) BrandTokens.gold.copy(alpha = 0.18f) else tint,
                stroke = if (pill.fullCombo) BrandTokens.gold else null,
                textColor = if (pill.fullCombo) BrandTokens.gold else BrandTokens.textPrimary,
                modifier = tag,
            )
        }
        MetadataField.Percentile -> when (pill.percentile) {
            SongPercentileTier.TopOne -> PillBox(pill.text, BrandTokens.gold, null, SongsTokens.darkGlyph, tag)
            SongPercentileTier.TopFive -> PillBox(pill.text, Color.Transparent, BrandTokens.gold, BrandTokens.gold, tag)
            SongPercentileTier.Ordinary -> PillBox(pill.text, BrandTokens.surfaceMuted, null, BrandTokens.textPrimary, tag)
        }
        // Stars and the intensity meter sit in a pill-height box so every pill in a row shares one height (7.18).
        MetadataField.Stars -> Box(Modifier.heightIn(min = PILL_HEIGHT), contentAlignment = Alignment.Center) { StarRating(if (pill.goldStars) 6 else pill.starCount, tag) }
        MetadataField.Season -> PillBox(
            pill.text,
            if (pill.currentSeason) BrandTokens.textPrimary else BrandTokens.surfaceMuted,
            null,
            if (pill.currentSeason) SongsTokens.darkGlyph else BrandTokens.textPrimary,
            tag,
        )
        MetadataField.Intensity -> pill.intensityRaw?.let { Box(Modifier.heightIn(min = PILL_HEIGHT), contentAlignment = Alignment.Center) { DifficultyMeter(it, modifier = tag) } }
        MetadataField.Difficulty -> {
            val (fill, glyph) = when (pill.gameDifficulty) {
                0 -> SongsTokens.diffEasy to SongsTokens.darkGlyph
                1 -> SongsTokens.diffMedium to BrandTokens.textPrimary
                2 -> SongsTokens.diffHard to SongsTokens.darkGlyph
                else -> SongsTokens.diffExpert to BrandTokens.textPrimary
            }
            PillBox(pill.text, fill, null, glyph, tag.heightIn(min = 22.dp))
        }
        MetadataField.LastPlayed -> Text(pill.text, style = label, color = BrandTokens.textSecondary, modifier = tag)
    }
}

/** Height of one metadata pill (label text plus its 2 dp vertical padding). */
private val PILL_HEIGHT = 24.dp

@Composable
private fun PillBox(text: String, fill: Color, stroke: Color?, textColor: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(6.dp)
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = textColor,
        maxLines = 1,
        modifier = modifier
            .clip(shape)
            .background(fill, shape)
            .then(if (stroke != null) Modifier.border(1.5.dp, stroke, shape) else Modifier)
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

// endregion
