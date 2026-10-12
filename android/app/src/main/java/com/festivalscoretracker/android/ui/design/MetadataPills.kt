package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.suggestions.PercentileTier
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Metadata pills (pattern `metadata-pills`)

/**
 * The catalogue's current season for the screen below, or null when unknown. A [SeasonPill]
 * whose season equals it inverts its colours (web `SeasonPill` reads `FestivalContext.currentSeason`).
 * Screens that load the catalogue provide it; without it every season pill is the neutral one.
 */
val LocalCurrentSeason = compositionLocalOf<Int?> { null }

/**
 * The season a score was set in (web `SeasonPill`, iOS `ScoreSeasonPill`; pattern
 * `metadata-pills` R1–R3): "S9" in `textSecondary` on `surfaceSubtle` with a 2 dp
 * `borderSubtle` outline; the current season inverts (`surfaceSubtle` text on `textSecondary`).
 * One size everywhere: Label Large semibold, 24 dp tall, at least [SEASON_PILL_MIN_WIDTH] wide,
 * growing with the font scale. TalkBack reads "Season 9" or "Current season 9".
 *
 * @param season Season number.
 * @param modifier Modifier (test tags, column width).
 * @param current Whether [season] is the catalogue's current season; defaults to [LocalCurrentSeason].
 */
@Composable
fun SeasonPill(season: Int, modifier: Modifier = Modifier, current: Boolean = season == LocalCurrentSeason.current) {
    val colors = seasonPillColors(current)
    val shape = RoundedCornerShape(METADATA_PILL_RADIUS)
    Text(
        seasonPillText(season),
        style = metadataPillTextStyle(),
        fontWeight = FontWeight.SemiBold,
        color = colors.text,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = modifier
            .widthIn(min = SEASON_PILL_MIN_WIDTH)
            .heightIn(min = METADATA_PILL_HEIGHT)
            .clip(shape)
            .background(colors.fill, shape)
            .border(METADATA_PILL_STROKE, colors.stroke, shape)
            .padding(horizontal = METADATA_PILL_PADDING_H, vertical = METADATA_PILL_PADDING_V)
            .semantics { contentDescription = seasonPillDescription(season, current) },
    )
}

/**
 * A "Top N%" percentile (web `PercentilePill`; pattern `metadata-pills` R4–R5): Top 1% in the
 * skewed italic gold outline, Top 5% in the upright gold outline (both bold gold text), and
 * everything else in `textSecondary` on 10% white. Same height, font and corners as
 * [SeasonPill]; at least 5.5 em wide like the web so stacked rows line up.
 *
 * @param text Label ("Top 3%").
 * @param modifier Modifier (test tags).
 * @param tier Emphasis; parsed from [text] by default like the web.
 * @param bold Bold the neutral tier (web `bold`, the selected player's row).
 */
@Composable
fun PercentilePill(
    text: String,
    modifier: Modifier = Modifier,
    tier: PercentileTier = SuggestionRowPresentation.tierFor(text),
    bold: Boolean = false,
) {
    val style = metadataPillTextStyle()
    val minWidth = with(LocalDensity.current) { (style.fontSize * PERCENTILE_PILL_MIN_EM).toDp() }
    val shape = RoundedCornerShape(METADATA_PILL_RADIUS)
    val gold = tier != PercentileTier.Default
    val surface = when (tier) {
        PercentileTier.Top1 -> modifier.goldOutline(skewed = true)
        PercentileTier.Top5 -> modifier.goldOutline(skewed = false)
        PercentileTier.Default -> modifier.clip(shape).background(BrandTokens.surfaceWhiteSubtle, shape)
    }
    Text(
        text,
        style = style,
        fontWeight = if (gold || bold) FontWeight.Bold else FontWeight.SemiBold,
        fontStyle = if (tier == PercentileTier.Top1) FontStyle.Italic else FontStyle.Normal,
        color = if (gold) BrandTokens.gold else BrandTokens.textSecondary,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = surface
            .widthIn(min = minWidth)
            .heightIn(min = METADATA_PILL_HEIGHT)
            .padding(horizontal = METADATA_PILL_PADDING_H, vertical = METADATA_PILL_PADDING_V),
    )
}

/** Fill, text and outline of a season pill. */
data class SeasonPillColors(val fill: Color, val text: Color, val stroke: Color)

/**
 * Season pill colours (web `SeasonPill`): neutral, or inverted for the current season.
 *
 * @param current Whether the pill shows the current season.
 * @return Colours.
 */
fun seasonPillColors(current: Boolean): SeasonPillColors =
    if (current) {
        SeasonPillColors(fill = BrandTokens.textSecondary, text = BrandTokens.surfaceSubtle, stroke = BrandTokens.surfaceSubtle)
    } else {
        SeasonPillColors(fill = BrandTokens.surfaceSubtle, text = BrandTokens.textSecondary, stroke = BrandTokens.borderSubtle)
    }

/**
 * Visible season label.
 *
 * @param season Season number.
 * @return "S9".
 */
fun seasonPillText(season: Int): String = "S$season"

/**
 * TalkBack label of a season pill (iOS `ScoreSeasonPill.spokenLabel`).
 *
 * @param season Season number.
 * @param current Whether it is the current season.
 * @return "Season 9" or "Current season 9".
 */
fun seasonPillDescription(season: Int, current: Boolean): String =
    if (current) "Current season $season" else "Season $season"

/** Shared text style: Material 3 chip label (Label Large, 14 sp / 20 sp). */
@Composable
internal fun metadataPillTextStyle(): TextStyle = MaterialTheme.typography.labelLarge

/** Height of every metadata pill: the 20 sp label line plus 2 dp padding above and below. */
val METADATA_PILL_HEIGHT: Dp = 24.dp

/** Web `IconSize.xl`: the season pill's fixed width, here a minimum so large text grows it. */
val SEASON_PILL_MIN_WIDTH: Dp = 48.dp

/** Horizontal inner padding: web `Gap.sm` (4) plus the 2 dp outline. */
val METADATA_PILL_PADDING_H: Dp = 6.dp

/** Vertical inner padding (web `Gap.xs`). */
private val METADATA_PILL_PADDING_V: Dp = 2.dp

/** Web `Radius.xs` (Material 3 `small`, the chip corner). */
private val METADATA_PILL_RADIUS: Dp = 8.dp

/** Web `Border.thick`. */
private val METADATA_PILL_STROKE: Dp = 2.dp

/** Web `MetadataSize.percentilePillMinWidth` (5.5 em). */
private const val PERCENTILE_PILL_MIN_EM = 5.5f

// endregion
