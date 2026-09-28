package com.festivalscoretracker.android.ui.suggestions

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.suggestions.PercentileTier
import com.festivalscoretracker.android.core.suggestions.SuggestionRowLayout
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.presentation.suggestions.SuggestionCard
import com.festivalscoretracker.android.presentation.suggestions.SuggestionRow
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Card

/**
 * One category as a glass card: Title Case heading, description, an instrument
 * icon for single-chart categories, then flat tappable song rows (web `CategoryCard`).
 *
 * @param card Card model.
 * @param narrow Whether rows move their metadata to a second line (compact widths).
 * @param artworkUrl Resolves artwork references.
 * @param onSong Open Song Detail.
 * @param modifier Modifier.
 */
@Composable
fun SuggestionCardView(
    card: SuggestionCard,
    narrow: Boolean,
    artworkUrl: (String?) -> String?,
    onSong: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassCard(modifier = modifier.fillMaxWidth().testTag("fst.suggestions.category.${card.id}")) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    card.category.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.semantics { heading() },
                )
                Text(card.category.description, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
            card.category.instrument?.let { InstrumentIcon(it, Modifier.padding(start = 12.dp), size = 32.dp) }
        }
        card.rows.forEach { row ->
            HorizontalDivider(color = BrandTokens.glassBorder)
            SuggestionRowView(row, narrow, artworkUrl(row.albumArt)) { onSong(row.songId) }
        }
    }
}

// endregion

// region Row

/**
 * One song row: artwork, title, "Artist · Year", and the category's metadata
 * (web `SongRow`). The whole row is one TalkBack element announcing every cue.
 *
 * @param row Row model.
 * @param narrow Move non-icon metadata under the title line.
 * @param artUrl Resolved artwork.
 * @param onClick Open the song.
 */
@Composable
fun SuggestionRowView(row: SuggestionRow, narrow: Boolean, artUrl: String?, onClick: () -> Unit) {
    val p = row.presentation
    val iconOnly = (p.layout == SuggestionRowLayout.SingleInstrument && p.starCount == 0) || p.layout == SuggestionRowLayout.Season
    val twoRow = narrow && p.layout != SuggestionRowLayout.Hidden && !iconOnly
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .testTag("fst.suggestions.row.${row.key}")
            .clickable(onClickLabel = "Open song", onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = p.accessibleLabel
                role = Role.Button
            }
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted),
            )
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(
                    p.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandTokens.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(p.subtitle, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (!twoRow) RowMetadata(p, row.usesKeyboardIcon, Modifier.padding(start = 8.dp))
        }
        if (twoRow) RowMetadata(p, row.usesKeyboardIcon, Modifier.padding(start = 56.dp, top = 6.dp))
    }
}

/** Right-side metadata by layout (web `RightContent`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RowMetadata(p: SuggestionRowPresentation, keyboard: Boolean, modifier: Modifier = Modifier) {
    val spacing = Arrangement.spacedBy(6.dp, Alignment.End)
    when (p.layout) {
        SuggestionRowLayout.Hidden -> Unit
        SuggestionRowLayout.InstrumentChips -> FlowRow(modifier, horizontalArrangement = spacing, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            p.chips.forEach { chip ->
                val color = when {
                    chip.isFullCombo -> BrandTokens.gold
                    chip.hasScore -> BrandTokens.statusGreen
                    else -> BrandTokens.statusRed
                }
                Box(
                    Modifier.size(28.dp).clip(CircleShape).background(color.copy(alpha = 0.3f)).border(1.5.dp, color, CircleShape),
                    contentAlignment = Alignment.Center,
                ) { InstrumentIcon(chip.instrument, keyboard = keyboard, size = 20.dp, decorative = true) }
            }
        }
        else -> Row(modifier, horizontalArrangement = spacing, verticalAlignment = Alignment.CenterVertically) {
            when (p.layout) {
                SuggestionRowLayout.Rival -> {
                    p.rivalName?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textSecondary, maxLines = 1) }
                    p.rivalDeltaText?.let { Pill(it, if (p.rivalDeltaSign > 0) BrandTokens.statusGreen else BrandTokens.statusRed) }
                }
                SuggestionRowLayout.UnfcAccuracy -> p.accuracyText?.let { text ->
                    val tint = p.accuracyExpanded?.let(ScoreFormatting::accuracyTint)?.let { Color(0xFF000000 or it.toLong()) } ?: BrandTokens.surfaceMuted
                    Pill("$text%", tint)
                }
                SuggestionRowLayout.Season -> p.seasonText?.let { Pill(it, BrandTokens.surfaceMuted, fill = 1f) }
                SuggestionRowLayout.Percentile -> p.percentileText?.let { PercentilePill(it, p.percentileTier) }
                SuggestionRowLayout.SingleInstrument -> StarRating(if (p.goldStars) 6 else p.starCount, size = 14.dp)
                else -> Unit
            }
            p.instrument?.let { InstrumentIcon(it, keyboard = keyboard, size = 24.dp, decorative = true) }
        }
    }
}

/** Small rounded label on a tinted fill. */
@Composable
private fun Pill(text: String, color: Color, fill: Float = 0.3f, textColor: Color = BrandTokens.textPrimary, border: BorderStroke? = null) {
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = fill))
            .then(if (border != null) Modifier.border(border, RoundedCornerShape(50)) else Modifier)
            .padding(horizontal = 8.dp, vertical = 2.dp),
    ) { Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = textColor, maxLines = 1) }
}

/** Web `PercentilePill`: filled gold for Top 1%, gold outline for Top 5%, neutral otherwise. */
@Composable
private fun PercentilePill(text: String, tier: PercentileTier) = when (tier) {
    PercentileTier.Top1 -> Pill(text, BrandTokens.gold, fill = 1f, textColor = Color.Black)
    PercentileTier.Top5 -> Pill(text, BrandTokens.gold, fill = 0.12f, textColor = BrandTokens.gold, border = BorderStroke(1.dp, BrandTokens.gold))
    PercentileTier.Default -> Pill(text, BrandTokens.surfaceMuted, fill = 1f)
}

// endregion
