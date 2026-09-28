package com.festivalscoretracker.android.ui.songs

import androidx.compose.foundation.MarqueeAnimationMode
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.Star
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.songs.SongInstrumentBadge
import com.festivalscoretracker.android.core.songs.SongInstrumentStatus
import com.festivalscoretracker.android.core.songs.SongMetadataPill
import com.festivalscoretracker.android.core.songs.SongPercentileTier
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.ceil
import kotlin.math.max

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
     * Shop row border.
     *
     * @param highlight Accent.
     * @return Red for Leaving Tomorrow, gold for New.
     */
    fun shop(highlight: ShopHighlight): Color = if (highlight == ShopHighlight.LeavingTomorrow) BrandTokens.statusRed else BrandTokens.gold
}

// endregion

// region Row

/**
 * One glass Songs card: art, marquee title and `artist · year · duration`, the
 * Shop accent, then selected-player chips or metadata pills (or an explicit score
 * state). The whole card is one tap target and one TalkBack stop that speaks
 * [SongRowModel.announcement].
 *
 * @param row Projected row.
 * @param artUrl Resolved artwork, or null.
 * @param selected Highlighted in two-pane layouts.
 * @param onClick Open the song.
 */
@Composable
fun SongRow(row: SongRowModel, artUrl: String?, selected: Boolean = false, onClick: () -> Unit) {
    val song = row.song
    GlassCard(
        onClick = onClick,
        accent = row.highlight?.let(SongsTokens::shop),
        modifier = Modifier
            .fillMaxWidth()
            .testTag("fst.songs.row.${song.songId}")
            .semantics {
                this.selected = selected
                contentDescription = row.announcement
            },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .background(if (selected) BrandTokens.accentPurple.copy(alpha = 0.35f) else Color.Transparent)
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .clearAndSetSemantics { },
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AsyncImage(
                    model = artUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
                )
                Column(Modifier.weight(1f)) {
                    MarqueeLine(song.title, MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), BrandTokens.textPrimary)
                    MarqueeLine(song.subtitle, MaterialTheme.typography.bodyMedium, BrandTokens.textSecondary)
                    if (row.namesChart) {
                        Text(
                            "${row.chart!!.label} chart",
                            style = MaterialTheme.typography.labelMedium,
                            color = BrandTokens.textSecondary,
                            modifier = Modifier.testTag("fst.songs.metadata.chart.${song.songId}"),
                        )
                    }
                }
                row.metadata.firstOrNull()?.let { MetadataPill(it, song.songId) }
                val raw = row.chartRaw
                if (row.metadata.isEmpty() && raw != null) DifficultyMeter(raw)
                row.highlight?.let { ShopBadge(it, song.songId) }
            }
            if (row.chips.isNotEmpty()) StatusChips(row.chips, song.songId, song.usesKeyboardIcon)
            if (row.metadata.size > 1) {
                MetadataPills(row.metadata.drop(1), song.songId)
            }
            row.scoreState?.let { ScoreState(it, song.songId) }
        }
    }
}

/**
 * Single-line text that marquees only when it overflows, and truncates instead
 * under reduced motion (web `MarqueeText`). `basicMarquee` animates in the draw
 * phase only, so it never recomposes the row.
 *
 * @param text Text.
 * @param style Style.
 * @param color Color.
 */
@Composable
internal fun MarqueeLine(text: String, style: TextStyle, color: Color) {
    val still = LocalFestivalAccessibility.current.reduceMotion
    Text(
        text,
        style = style,
        color = color,
        maxLines = 1,
        overflow = if (still) TextOverflow.Ellipsis else TextOverflow.Clip,
        modifier = if (still) {
            Modifier
        } else {
            Modifier.basicMarquee(
                iterations = Int.MAX_VALUE,
                animationMode = MarqueeAnimationMode.Immediately,
                repeatDelayMillis = MARQUEE_DWELL_MS,
                initialDelayMillis = MARQUEE_DWELL_MS,
            )
        },
    )
}

/** Dwell at each end, like the web keyframe's pauses. */
private const val MARQUEE_DWELL_MS = 1_200

@Composable
private fun ShopBadge(highlight: ShopHighlight, songId: String) {
    val leaving = highlight == ShopHighlight.LeavingTomorrow
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(30.dp)
            .background(if (leaving) BrandTokens.statusRed else BrandTokens.appBackground, CircleShape)
            .testTag("fst.songs.shop-badge.$songId"),
    ) {
        Icon(
            if (leaving) Icons.Filled.Schedule else Icons.Filled.AutoAwesome,
            contentDescription = null,
            tint = if (leaving) BrandTokens.textPrimary else BrandTokens.gold,
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
 * @param badges Chips in service order.
 * @param songId Song (test tag).
 * @param keyboard Keys icon variant for Lead/Pro Lead.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StatusChips(badges: List<SongInstrumentBadge>, songId: String, keyboard: Boolean) {
    BoxWithConstraints(Modifier.fillMaxWidth().testTag("fst.songs.instrument-status.$songId")) {
        val side = CHIP_SIDE
        val spacing = 4.dp
        val fit = max(1, ((maxWidth + spacing) / (side + spacing)).toInt())
        val rows = ceil(badges.size / fit.toDouble()).toInt().coerceAtLeast(1)
        val perRow = ceil(badges.size / rows.toDouble()).toInt()
        FlowRow(
            maxItemsInEachRow = perRow,
            horizontalArrangement = Arrangement.spacedBy(spacing, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(spacing),
            modifier = Modifier.fillMaxWidth(),
        ) {
            badges.forEach { badge -> StatusChip(badge, keyboard, side) }
        }
    }
}

@Composable
private fun StatusChip(badge: SongInstrumentBadge, keyboard: Boolean, side: Dp) {
    val (fill, stroke) = SongsTokens.chip(badge.status)
    val keys = keyboard && (badge.instrument == Instrument.Lead || badge.instrument == Instrument.ProLead)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(side)
            .background(fill, CircleShape)
            .border(2.dp, stroke, CircleShape)
            .testTag("fst.songs.chip.${badge.instrument.wireId}.${badge.status.name}"),
    ) {
        InstrumentIcon(badge.instrument, keyboard = keys, size = side * 0.7f, decorative = true)
    }
}

/** Chip diameter (web 34 px chip with a 24 px icon). */
private val CHIP_SIDE = 34.dp

// endregion

// region Metadata pills

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MetadataPills(pills: List<SongMetadataPill>, songId: String) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().testTag("fst.songs.metadata.$songId"),
    ) {
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
        MetadataField.Stars -> Row(tag) {
            repeat(pill.starCount) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = if (pill.goldStars) BrandTokens.gold else BrandTokens.textPrimary, modifier = Modifier.size(16.dp))
            }
        }
        MetadataField.Season -> PillBox(
            pill.text,
            if (pill.currentSeason) BrandTokens.textPrimary else BrandTokens.surfaceMuted,
            null,
            if (pill.currentSeason) SongsTokens.darkGlyph else BrandTokens.textPrimary,
            tag,
        )
        MetadataField.Intensity -> pill.intensityRaw?.let { DifficultyMeter(it, modifier = tag) }
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
