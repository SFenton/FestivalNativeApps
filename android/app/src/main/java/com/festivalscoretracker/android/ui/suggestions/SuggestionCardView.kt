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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.suggestions.PercentileTier
import com.festivalscoretracker.android.core.suggestions.SuggestionRowLayout
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.presentation.suggestions.SuggestionCard
import com.festivalscoretracker.android.presentation.suggestions.SuggestionRow
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Tokens

/** Web values for the Suggestions card (`CategoryCard.tsx`, `@festival/theme`). */
internal object SuggestionTokens {
    /** `Colors.textTertiary` (card description). */
    val textTertiary = Color(0xFF9AA6B2)

    /** `Colors.textSubtle` (artist · year). */
    val textSubtle = Color(0xFFB8C0CC)

    /** `Colors.borderSubtle` (row dividers, season pill border). */
    val borderSubtle = Color(0xFF1E2A3A)

    /** `Colors.surfaceWhiteSubtle` (default percentile pill). */
    val surfaceWhiteSubtle = Color(0x1AFFFFFF)

    /** `Colors.goldStroke`. */
    val goldStroke = Color(0xFFCFA500)

    /** Status chip strokes (`statusGreenStroke`, `statusRedStroke`). */
    val greenStroke = Color(0xFF1E7F46)
    val redStroke = Color(0xFF8B0000)

    /** Song-rival badge (blue) and leaderboard-rival badge (yellow). */
    val songRival = Color(0xFF4285F4)
    val leaderboardRival = Color(0xFFFBBC04)

    /** `Radius.xs` pills. */
    val pillShape = RoundedCornerShape(8.dp)
}

// endregion

// region Card

/**
 * One category: the Title Case title, description and (single-chart categories) instrument icon
 * sit **above** the glass card (operator 2026-09-28: headers outside cards, like Leaderboards),
 * and the card holds the flat tappable song rows (web `CategoryCard`).
 *
 * @param card Card model.
 * @param narrow Whether rows move their metadata to a second line (web `useIsNarrow`).
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
    Column(modifier.fillMaxWidth().testTag("fst.suggestions.category.${card.id}")) {
        SuggestionCardHeader(card)
        GlassCard(modifier = Modifier.fillMaxWidth()) {
            card.rows.forEachIndexed { index, row ->
                if (index > 0) HorizontalDivider(color = SuggestionTokens.borderSubtle)
                SuggestionRowView(row, narrow, artworkUrl(row.albumArt)) { onSong(row.songId) }
            }
        }
    }
}

/** Title (16 sp bold), description (12 sp tertiary) and a 36 dp instrument icon above the card. */
@Composable
private fun SuggestionCardHeader(card: SuggestionCard) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, bottom = 8.dp).testTag("fst.suggestions.header.${card.id}"),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                card.category.title,
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, lineHeight = 22.sp),
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.semantics { heading() },
            )
            Text(card.category.description, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp), color = SuggestionTokens.textTertiary)
        }
        card.category.instrument?.let { InstrumentIcon(it, size = 36.dp, decorative = true) }
    }
}

// endregion

// region Row

/**
 * One song row (web `SongRow`): 44 dp artwork, marquee title (14 sp semibold) and
 * "Artist · Year" (12 sp), then the category's metadata — beside the text, or on a second
 * right-aligned line on narrow cards. The whole row is one TalkBack element announcing every cue.
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
            .padding(horizontal = ROW_PADDING_H, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(6.dp)).background(BrandTokens.surfaceMuted),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                FestivalMarqueeText(p.title, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp), color = BrandTokens.textPrimary, fontWeight = FontWeight.SemiBold)
                FestivalMarqueeText(p.subtitle, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp), color = SuggestionTokens.textSubtle)
            }
            if (!twoRow) RowMetadata(p, row.usesKeyboardIcon)
            RowChevron()
        }
        if (twoRow) {
            Box(Modifier.fillMaxWidth().padding(top = 4.dp), contentAlignment = Alignment.CenterEnd) { RowMetadata(p, row.usesKeyboardIcon) }
        }
    }
}

/** Horizontal row inset: the Material list-item 16 dp (web uses 24 px), leaving room for metadata beside the text on phones. */
private val ROW_PADDING_H = 16.dp

/** Right-side metadata by layout (web `RightContent`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RowMetadata(p: SuggestionRowPresentation, keyboard: Boolean) {
    val badges = Arrangement.spacedBy(8.dp, Alignment.End)
    when (p.layout) {
        SuggestionRowLayout.Hidden -> Unit
        SuggestionRowLayout.InstrumentChips -> FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            p.chips.forEach { chip ->
                val (fill, stroke) = when {
                    chip.isFullCombo -> BrandTokens.gold to SuggestionTokens.goldStroke
                    chip.hasScore -> BrandTokens.statusGreen to SuggestionTokens.greenStroke
                    else -> BrandTokens.statusRed to SuggestionTokens.redStroke
                }
                Box(
                    Modifier.size(34.dp).background(fill, CircleShape).border(2.dp, stroke, CircleShape),
                    contentAlignment = Alignment.Center,
                ) { InstrumentIcon(chip.instrument, keyboard = keyboard, size = 20.dp, decorative = true) }
            }
        }
        else -> Row(horizontalArrangement = badges, verticalAlignment = Alignment.CenterVertically) {
            when (p.layout) {
                SuggestionRowLayout.Rival -> {
                    p.rivalName?.let { RivalBadge(it, p.rivalFromSong) }
                    p.rivalDeltaText?.let { delta ->
                        Text(
                            delta,
                            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
                            color = if (p.rivalDeltaSign > 0) BrandTokens.statusGreen else BrandTokens.statusRed,
                        )
                    }
                }
                SuggestionRowLayout.UnfcAccuracy -> p.accuracyText?.let { text ->
                    val tint = p.accuracyExpanded?.let(ScoreFormatting::accuracyTint)?.let { Color(0xFF000000 or it.toLong()) } ?: BrandTokens.surfaceMuted
                    Pill("$text%", fill = tint, minWidth = 52)
                }
                SuggestionRowLayout.Season -> p.seasonText?.let { SeasonPill(it) }
                SuggestionRowLayout.Percentile -> p.percentileText?.let { PercentilePill(it, p.percentileTier) }
                SuggestionRowLayout.SingleInstrument -> StarRating(if (p.goldStars) 6 else p.starCount, size = 20.dp)
                else -> Unit
            }
            p.instrument?.let { InstrumentIcon(it, keyboard = keyboard, size = 28.dp, decorative = true) }
        }
    }
}

/** Rival name badge: blue for a song rival, yellow for a leaderboard rival (web `rivalBadge`). */
@Composable
private fun RivalBadge(name: String, fromSong: Boolean) {
    val color = if (fromSong) SuggestionTokens.songRival else SuggestionTokens.leaderboardRival
    Text(
        name,
        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
        color = color,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .widthIn(max = 100.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.2f))
            .padding(horizontal = 4.dp, vertical = 2.dp),
    )
}

/** Web metadata pill: 8 dp corners, semibold, 2 dp border. */
@Composable
private fun Pill(
    text: String,
    fill: Color,
    textColor: Color = BrandTokens.textPrimary,
    border: BorderStroke? = null,
    minWidth: Int = 0,
    italicSkew: Boolean = false,
    style: TextStyle = MaterialTheme.typography.labelMedium.copy(fontSize = 12.sp),
) {
    Text(
        text,
        style = style.copy(fontStyle = if (italicSkew) FontStyle.Italic else FontStyle.Normal),
        fontWeight = if (border != null) FontWeight.Bold else FontWeight.SemiBold,
        color = textColor,
        maxLines = 1,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .widthIn(min = minWidth.dp)
            .clip(SuggestionTokens.pillShape)
            .background(fill)
            .then(if (border != null) Modifier.border(border, SuggestionTokens.pillShape) else Modifier)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/** Web `SeasonPill`: 48 dp wide, 16 sp semibold, subtle surface with a 2 dp border. */
@Composable
private fun SeasonPill(text: String) = Pill(
    text,
    fill = BrandTokens.surfaceSubtle,
    textColor = BrandTokens.textSecondary,
    border = BorderStroke(2.dp, SuggestionTokens.borderSubtle),
    minWidth = 48,
    style = TextStyle(fontSize = 16.sp, lineHeight = 20.sp),
)

/** Web `PercentilePill`: gold outline, italic (web skews it), for Top 1%, gold outline for Top 5%, subtle white otherwise. */
@Composable
internal fun PercentilePill(text: String, tier: PercentileTier) = when (tier) {
    PercentileTier.Top1 -> Pill(text, Color.Transparent, BrandTokens.gold, BorderStroke(2.dp, SuggestionTokens.goldStroke), 72, italicSkew = true)
    PercentileTier.Top5 -> Pill(text, Color.Transparent, BrandTokens.gold, BorderStroke(2.dp, SuggestionTokens.goldStroke), 72)
    PercentileTier.Default -> Pill(text, SuggestionTokens.surfaceWhiteSubtle, BrandTokens.textSecondary, minWidth = 72)
}

// endregion
