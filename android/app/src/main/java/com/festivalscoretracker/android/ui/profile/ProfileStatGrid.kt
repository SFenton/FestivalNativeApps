package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.StatGridColumns
import com.festivalscoretracker.android.core.profile.StatTints
import com.festivalscoretracker.android.presentation.profile.PlayerStatTile
import com.festivalscoretracker.android.ui.common.StatTileGrid
import com.festivalscoretracker.android.ui.common.StatTileText
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Stat grid

/**
 * Stat tiles in the shared [StatTileGrid] (web `StatBox` items, each its own frosted card):
 * two columns on phones, three or four as the grid widens ([StatGridColumns]). A tile whose
 * value or label would wrap in one slot spans two, and every tile takes the grid's tallest
 * height so values and chevrons line up (pattern `stat-tile-grid`, #591).
 *
 * @param tiles Tiles in web order (stable ids).
 * @param scope Test-tag scope: `overview` or an instrument's wire ID.
 * @param canRun Whether a tile's action is available now (else it draws flat).
 * @param onAction Tile tap.
 * @param modifier Modifier.
 */
@Composable
internal fun StatGrid(
    tiles: List<PlayerStatTile>,
    scope: String,
    canRun: (PlayerTileAction) -> Boolean,
    onAction: (PlayerTileAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    val fontScale = LocalDensity.current.fontScale
    val texts = statTileTexts()
    StatTileGrid(tiles, columns = { StatGridColumns.count(it, fontScale) }, texts = texts, inset = STAT_TILE_INSET, modifier = modifier) { tile, _, tileModifier ->
        val action = tile.action?.takeIf { !tile.placeholder && canRun(it) }
        StatTile(
            tile,
            onClick = action?.let { { onAction(it) } },
            modifier = tileModifier.testTag("fst.player.tile.$scope.${tile.id}"),
        )
    }
}

// endregion

// region Tile

/** TalkBack action label for a tile. */
internal fun actionLabel(action: PlayerTileAction): String = when (action) {
    is PlayerTileAction.FilterSongs -> "Show in Songs"
    is PlayerTileAction.OpenSong -> "Open song"
    is PlayerTileAction.OpenRankings -> "Open rankings"
}

/** `0xRRGGBB` stat tint → colour. */
private fun tintColor(rgb: Int?): Color = rgb(rgb ?: StatTints.DEFAULT)

/** A tile's horizontal padding (both sides): room for the chevron, kept symmetric. */
internal val STAT_TILE_INSET = 56.dp

/** The value's style (web `StatBox` `value`: `Font.xl`, bold). */
@Composable
private fun statValueStyle(): TextStyle = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)

/** The label's style (web `StatBox` `label`: `Font.xs`, uppercase, wide tracking). */
@Composable
private fun statLabelStyle(): TextStyle = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.6.sp)

/**
 * What a [StatTile] draws on one line each, for [StatTileGrid]'s span rule: the value
 * (unless it is star images) and the uppercase label.
 *
 * @return Texts for a tile.
 */
@Composable
internal fun statTileTexts(): (PlayerStatTile) -> List<StatTileText> {
    val value = statValueStyle()
    val label = statLabelStyle()
    return remember(value, label) {
        { tile -> listOfNotNull(StatTileText(tile.value, value).takeIf { tile.stars == null }, StatTileText(tile.label.uppercase(), label)) }
    }
}

/**
 * One tile: its own frosted card with the value over an uppercase label, centred; a
 * clickable tile adds a trailing chevron and web `StatBox` press feedback (ripple).
 * Horizontal padding is symmetric ([STAT_TILE_INSET]), so the centred text stays centred
 * either way. Text wraps rather than truncating when even a two-slot tile is too narrow.
 *
 * @param tile Tile.
 * @param onClick Tap, or null for a flat tile.
 * @param modifier Modifier.
 */
@Composable
internal fun StatTile(tile: PlayerStatTile, onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    val accessibility = LocalFestivalAccessibility.current
    val color = if (accessibility.increaseContrast || accessibility.reduceTransparency) BrandTokens.cardBackground else BrandTokens.surfaceFrosted
    val border = BorderStroke(if (accessibility.increaseContrast) 2.dp else 1.dp, if (accessibility.increaseContrast) BrandTokens.textPrimary else BrandTokens.glassBorder)
    val shape = RoundedCornerShape(12.dp)
    val content: @Composable () -> Unit = {
        Box(Modifier.fillMaxWidth().heightIn(min = 72.dp), contentAlignment = Alignment.Center) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = STAT_TILE_INSET / 2, vertical = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                val stars = tile.stars
                if (stars != null) {
                    StarRating(stars, Modifier.heightIn(min = 28.dp), size = 18.dp)
                } else {
                    Text(
                        tile.value,
                        style = statValueStyle(),
                        color = tintColor(tile.tint),
                        textAlign = TextAlign.Center,
                        // Loading: the same text, invisible, so the tile has its final size.
                        modifier = if (tile.placeholder) Modifier.alpha(0f) else Modifier,
                    )
                }
                Text(
                    tile.label.uppercase(),
                    style = statLabelStyle(),
                    color = BrandTokens.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            if (tile.placeholder) {
                // Redacted value bar where the value will appear.
                Surface(color = BrandTokens.textPrimary.copy(alpha = 0.12f), shape = RoundedCornerShape(6.dp), modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp).width(64.dp).height(20.dp)) {}
            }
            if (onClick != null) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = BrandTokens.textPrimary,
                    modifier = Modifier.align(Alignment.CenterEnd).padding(end = 6.dp).size(20.dp),
                )
            }
        }
    }
    if (onClick == null) {
        Surface(color = color, shape = shape, border = border, modifier = modifier.clearAndSetSemantics { contentDescription = tile.announcement }, content = content)
    } else {
        val label = tile.action?.let(::actionLabel)
        Surface(
            onClick = onClick,
            color = color,
            shape = shape,
            border = border,
            modifier = modifier.heightIn(min = 48.dp).clearAndSetSemantics {
                contentDescription = tile.announcement
                role = Role.Button
                onClick(label = label) { onClick(); true }
            },
            content = content,
        )
    }
}

// endregion
