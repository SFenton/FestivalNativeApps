package com.festivalscoretracker.android.ui.design

import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonColors
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
import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.isTraversalGroup
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
 * Floating controls over rows (the boards' pager, issue #319) use it too, so they share
 * the rows' fill, translucency, border and contrast fallback.
 *
 * @param modifier Modifier.
 * @param shape Card shape.
 * @param onClick Optional tap action; the whole card becomes the target.
 * @param accent Optional 2 dp accent border (e.g. Shop New/Leaving highlights).
 * @param enabled Whether [onClick] can be pressed (the surface stays the same; dim the content).
 * @param content Card content.
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(12.dp),
    onClick: (() -> Unit)? = null,
    accent: Color? = null,
    enabled: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val accessibility = LocalFestivalAccessibility.current
    val contrast = accessibility.increaseContrast
    val color = if (contrast || accessibility.reduceTransparency) BrandTokens.cardBackground else BrandTokens.surfaceFrosted
    val border = when {
        accent != null -> BorderStroke(2.dp, accent)
        contrast -> BorderStroke(2.dp, BrandTokens.textPrimary)
        else -> BorderStroke(1.dp, BrandTokens.glassBorder)
    }
    if (onClick != null) {
        Surface(onClick = onClick, modifier = modifier.readingGroup(), enabled = enabled, shape = shape, color = color, border = border) {
            Column(content = content)
        }
    } else {
        Surface(modifier = modifier.readingGroup(), shape = shape, color = color, border = border) {
            Column(content = content)
        }
    }
}

/** Corner radius of [GlassCard] and [GlassCardSegment]. */
private val GLASS_CARD_CORNER = 12.dp

/**
 * Where a [GlassCardSegment] sits in its card: only the card's outer ends round their corners
 * and draw the border's top and bottom edges.
 */
enum class CardSegment {
    /** The whole card. */
    Only,

    /** The card's top. */
    First,

    /** Between the top and the bottom. */
    Middle,

    /** The card's bottom. */
    Last;

    /** Whether the segment rounds its top corners and draws the border's top edge. */
    val isTop: Boolean get() = this == Only || this == First

    /** Whether the segment rounds its bottom corners and draws the border's bottom edge. */
    val isBottom: Boolean get() = this == Only || this == Last

    companion object {
        /**
         * The segment for the row at [index] of a card of [count] rows.
         *
         * @param index Zero-based row index.
         * @param count Rows in the card.
         * @return Segment position.
         */
        fun of(index: Int, count: Int): CardSegment = when {
            count <= 1 -> Only
            index <= 0 -> First
            index >= count - 1 -> Last
            else -> Middle
        }
    }
}

/**
 * One lazy item's slice of a [GlassCard] (`surface-materials` R8): the same fill, border and
 * contrast fallback, with the corners and the border's top and bottom edges only at the card's
 * ends, so segments stacked with no gap read as one card. Use it where a card's rows are
 * unbounded and must stay lazy (All Rivals, Rivalry); a bounded card is one [GlassCard].
 *
 * @param segment Position in the card.
 * @param modifier Modifier.
 * @param content Segment content.
 */
@Composable
fun GlassCardSegment(segment: CardSegment, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val accessibility = LocalFestivalAccessibility.current
    val contrast = accessibility.increaseContrast
    val color = if (contrast || accessibility.reduceTransparency) BrandTokens.cardBackground else BrandTokens.surfaceFrosted
    val stroke = if (contrast) 2.dp else 1.dp
    val strokeColor = if (contrast) BrandTokens.textPrimary else BrandTokens.glassBorder
    val top = if (segment.isTop) GLASS_CARD_CORNER else 0.dp
    val bottom = if (segment.isBottom) GLASS_CARD_CORNER else 0.dp
    val shape = RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
    Column(
        modifier
            .clip(shape)
            .background(color, shape)
            .drawWithContent {
                drawContent()
                // The card's outline, extended past an open end so the clip leaves only the sides there.
                val width = stroke.toPx()
                val radius = GLASS_CARD_CORNER.toPx()
                val startY = if (segment.isTop) width / 2 else -radius * 2
                val endY = if (segment.isBottom) size.height - width / 2 else size.height + radius * 2
                drawRoundRect(
                    color = strokeColor,
                    topLeft = Offset(width / 2, startY),
                    size = Size(size.width - width, endY - startY),
                    cornerRadius = CornerRadius(radius - width / 2),
                    style = Stroke(width),
                )
            },
        content = content,
    )
}

// endregion

// region Section header

/**
 * Space a [SectionHeader] keeps above its title, inside its own bounds. A Quick Links section that starts
 * with one declares it as its heading inset so a jump lands the title, not this space, on the landing
 * line (`section-jump-landing` R2, issue #587).
 */
val SECTION_HEADER_TOP_PADDING = 16.dp

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
            .padding(top = SECTION_HEADER_TOP_PADDING, bottom = 8.dp)
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
        painter = bundledPainter(instrumentIconRes(instrument, keyboard)),
        contentDescription = if (decorative) null else instrument.label,
        modifier = modifier.size(size),
    )
}

// endregion

// region Difficulty meter

/**
 * The branded seven-bar parallelogram meter (62 × 20), one image-like accessible element
 * (decorative polygons are drawn, not separate nodes). A parent that speaks its own level
 * (a row or bucket switch) clears the meter's semantics.
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
            .semantics {
                contentDescription = label
                role = Role.Image
            },
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

// region Filled buttons

/**
 * Colours for a filled (primary) button: [BrandTokens.accentBlueFill] behind white text,
 * so labels meet WCAG AA contrast (the theme primary is tuned for blue text on dark).
 *
 * @return Button colours.
 */
@Composable
fun festivalFilledButtonColors(): ButtonColors =
    ButtonDefaults.buttonColors(containerColor = BrandTokens.accentBlueFill, contentColor = BrandTokens.textPrimary)

// endregion

// region Reading groups

/**
 * Make this element one TalkBack traversal group: its content is read in full before
 * anything beside it. Compose otherwise orders every non-grouped descendant of a list or
 * grid geometrically, so two cards side by side (grid columns, either side of a hinge)
 * were read row by row across both cards.
 *
 * @return Modifier.
 */
fun Modifier.readingGroup(): Modifier = semantics { isTraversalGroup = true }

// endregion
