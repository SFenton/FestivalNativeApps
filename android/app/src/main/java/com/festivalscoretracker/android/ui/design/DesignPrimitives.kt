package com.festivalscoretracker.android.ui.design

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.R
import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Glass surface

/**
 * Glass-like card: a translucent Material 3 surface with a hairline border over the
 * artwork backdrop. Increased contrast makes it opaque with a white border.
 * No blur (RenderEffect blur of a moving backdrop costs frames on mid-range GPUs).
 *
 * @param modifier Modifier.
 * @param shape Card shape.
 * @param onClick Optional tap action; the whole card becomes the target.
 * @param content Card content.
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(12.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val accessibility = LocalFestivalAccessibility.current
    val contrast = accessibility.increaseContrast
    val color = if (contrast || accessibility.reduceTransparency) BrandTokens.cardBackground else BrandTokens.surfaceFrosted
    val border = BorderStroke(if (contrast) 2.dp else 1.dp, if (contrast) BrandTokens.textPrimary else BrandTokens.glassBorder)
    if (onClick != null) {
        Surface(onClick = onClick, modifier = modifier, shape = shape, color = color, border = border) {
            Column(content = content)
        }
    } else {
        Surface(modifier = modifier, shape = shape, color = color, border = border) {
            Column(content = content)
        }
    }
}

// endregion

// region Section header

/**
 * White Title Case section header announced as a heading.
 *
 * @param title Title Case text.
 * @param modifier Modifier.
 */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 16.dp, bottom = 8.dp)
            .semantics { heading() },
    )
}

// endregion

// region Instrument icon

/**
 * Drawable for a chart's bundled icon.
 *
 * @param instrument Chart.
 * @param keyboard Keys variant for Lead/Pro Lead.
 * @return Drawable resource ID.
 */
@DrawableRes
fun instrumentIconRes(instrument: Instrument, keyboard: Boolean = false): Int = when (instrument.iconName(keyboard)) {
    "instrument_keys" -> R.drawable.instrument_keys
    "instrument_guitar" -> R.drawable.instrument_guitar
    "instrument_bass" -> R.drawable.instrument_bass
    "instrument_drums" -> R.drawable.instrument_drums
    "instrument_vocals" -> R.drawable.instrument_vocals
    "instrument_pro_keys" -> R.drawable.instrument_pro_keys
    "instrument_pro_guitar" -> R.drawable.instrument_pro_guitar
    "instrument_pro_bass" -> R.drawable.instrument_pro_bass
    "instrument_peripheral_vocals" -> R.drawable.instrument_peripheral_vocals
    "instrument_peripheral_cymbals" -> R.drawable.instrument_peripheral_cymbals
    else -> R.drawable.instrument_peripheral_drums
}

/**
 * Bundled instrument artwork matching the web's instrument PNG assets.
 *
 * @param instrument Chart.
 * @param modifier Modifier.
 * @param keyboard Keys variant for Lead/Pro Lead.
 * @param size Square size.
 * @param decorative Hide from accessibility when a sibling already names the chart.
 */
@Composable
fun InstrumentIcon(instrument: Instrument, modifier: Modifier = Modifier, keyboard: Boolean = false, size: Dp = 24.dp, decorative: Boolean = false) {
    Image(
        painter = painterResource(instrumentIconRes(instrument, keyboard)),
        contentDescription = if (decorative) null else instrument.label,
        modifier = modifier.size(size),
    )
}

// endregion

// region Difficulty meter

/**
 * The branded seven-bar parallelogram meter (62 × 20), one accessible element.
 *
 * @param level Service value.
 * @param modifier Modifier.
 * @param raw Whether [level] is a raw 0–6 value (Song Detail/Songs rows).
 */
@Composable
fun DifficultyMeter(level: Double, modifier: Modifier = Modifier, raw: Boolean = true) {
    val filled = DifficultyMeterSpec.filledBars(level, raw)
    if (filled == null) {
        Text(
            "Difficulty unavailable",
            style = MaterialTheme.typography.labelSmall,
            color = BrandTokens.textMuted,
            modifier = modifier.testTag("fst.songs.difficulty-unavailable"),
        )
        return
    }
    val label = DifficultyMeterSpec.accessibilityLabel(level, raw)
    val paths = remember {
        (0 until DifficultyMeterSpec.BARS).map { index -> DifficultyMeterSpec.barVertices(index) }
    }
    Canvas(
        modifier
            .size(DifficultyMeterSpec.WIDTH.dp, DifficultyMeterSpec.HEIGHT.dp)
            .testTag("fst.songs.difficulty-meter")
            .semantics { contentDescription = label },
    ) {
        val scale = size.width / DifficultyMeterSpec.WIDTH
        paths.forEachIndexed { index, vertices ->
            val path = Path().apply {
                moveTo(vertices[0].first * scale, vertices[0].second * scale)
                vertices.drop(1).forEach { (x, y) -> lineTo(x * scale, y * scale) }
                close()
            }
            drawPath(path, Color(if (index < filled) DifficultyMeterSpec.FILLED else DifficultyMeterSpec.UNFILLED))
        }
    }
}

// endregion
