package com.festivalscoretracker.android.ui.design

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.songs.SongMetadataPill
import com.festivalscoretracker.android.core.songs.SongPercentileTier
import com.festivalscoretracker.android.ui.songs.MetadataPill
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The shared season and percentile pills (pattern `metadata-pills`, issue #606): one size on
 * every page (Songs rows draw the same composable as Suggestions, Song Detail, history and the
 * song boards), the web/iOS season contrast with the current season inverted, the web
 * percentile tiers, TalkBack labels and growth with the font scale.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w600dp-h900dp-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class MetadataPillsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var fontScale by mutableFloatStateOf(1f)

    private fun show(currentSeason: Int? = 15) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale), LocalCurrentSeason provides currentSeason) {
                FestivalTheme {
                    Column(Modifier.background(BrandTokens.cardBackground).padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SeasonPill(9, Modifier.testTag("old"))
                        SeasonPill(15, Modifier.testTag("current"))
                        PercentilePill("Top 1%", Modifier.testTag("top1"))
                        PercentilePill("Top 5%", Modifier.testTag("top5"))
                        PercentilePill("Top 40%", Modifier.testTag("top40"))
                        MetadataPill(SongMetadataPill(MetadataField.Season, "S9", "Season 9", season = 9), "songs")
                        MetadataPill(SongMetadataPill(MetadataField.Percentile, "Top 40%", "Top 40%", percentile = SongPercentileTier.Ordinary), "songs")
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    private fun description(tag: String): String =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()

    private fun px(dp: Float): Float = dp * rule.activity.resources.displayMetrics.density

    /** The rendered pixels, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun capture(tag: String): Bitmap {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        val b = bounds(tag)
        return Bitmap.createBitmap(whole, b.left.toInt(), b.top.toInt(), b.width.toInt().coerceAtLeast(1), b.height.toInt().coerceAtLeast(1))
    }

    /** The fill colour just inside the 2 dp border at the pill's leading edge (left of the centred label). */
    private fun fill(tag: String): Color {
        val bitmap = capture(tag)
        return Color(bitmap.getPixel(px(3.5f).toInt(), bitmap.height / 2))
    }

    private fun near(actual: Color, expected: Color, tolerance: Int = 3): Boolean {
        val a = actual.toArgb()
        val e = expected.toArgb()
        return abs(android.graphics.Color.red(a) - android.graphics.Color.red(e)) <= tolerance &&
            abs(android.graphics.Color.green(a) - android.graphics.Color.green(e)) <= tolerance &&
            abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(e)) <= tolerance
    }

    private fun hasColour(bitmap: Bitmap, colour: Color, tolerance: Int = 6): Boolean {
        val target = colour.toArgb()
        for (x in 0 until bitmap.width) for (y in 0 until bitmap.height) {
            val p = bitmap.getPixel(x, y)
            if (abs(android.graphics.Color.red(p) - android.graphics.Color.red(target)) <= tolerance &&
                abs(android.graphics.Color.green(p) - android.graphics.Color.green(target)) <= tolerance &&
                abs(android.graphics.Color.blue(p) - android.graphics.Color.blue(target)) <= tolerance
            ) {
                return true
            }
        }
        return false
    }

    private fun contrast(a: Color, b: Color): Double {
        val l1 = a.luminance().toDouble()
        val l2 = b.luminance().toDouble()
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test
    fun everyPillSharesOneHeightAndTheSongsRowDrawsTheSameComposable() {
        show()
        val tags = listOf("old", "current", "top1", "top5", "top40", "fst.songs.metadata.season.songs", "fst.songs.metadata.percentile.songs")
        tags.forEach { assertEquals("$it height", px(24f), bounds(it).height, 1.5f) }
        // Songs rows use the shared pills, so they match the standalone ones exactly.
        assertEquals(bounds("old").width, bounds("fst.songs.metadata.season.songs").width, 0.5f)
        assertEquals(bounds("top40").width, bounds("fst.songs.metadata.percentile.songs").width, 0.5f)
        // Web `IconSize.xl` season width and `5.5em` percentile minimum (14 sp label → 77 dp).
        assertTrue(bounds("old").width >= px(48f) - 0.5f)
        listOf("top1", "top5", "top40").forEach { assertTrue("$it min width", bounds(it).width >= px(77f) - 1f) }
    }

    @Test
    fun seasonPillsSpeakAndTheCurrentSeasonInverts() {
        show()
        assertEquals("Season 9", description("old"))
        assertEquals("Current season 15", description("current"))
        assertTrue("neutral fill ${fill("old")}", near(fill("old"), BrandTokens.surfaceSubtle))
        assertTrue("neutral label", hasColour(capture("old"), BrandTokens.textSecondary, tolerance = 40))
        assertTrue("inverted fill ${fill("current")}", near(fill("current"), BrandTokens.textSecondary))
        assertTrue("inverted label", hasColour(capture("current"), BrandTokens.surfaceSubtle, tolerance = 40))
    }

    @Test
    fun withoutACurrentSeasonEverySeasonIsNeutral() {
        show(currentSeason = null)
        assertEquals("Season 15", description("current"))
        assertTrue(near(fill("current"), BrandTokens.surfaceSubtle))
    }

    @Test
    fun percentileTiersFollowTheWeb() {
        show()
        assertTrue("Top 1% gold outline", hasColour(capture("top1"), BrandTokens.goldStroke, tolerance = 24))
        assertTrue("Top 5% gold outline", hasColour(capture("top5"), BrandTokens.goldStroke, tolerance = 24))
        val neutral = capture("top40")
        assertFalse("neutral has no gold", hasColour(neutral, BrandTokens.goldStroke, tolerance = 24))
        assertTrue("neutral text", hasColour(neutral, BrandTokens.textSecondary, tolerance = 40))
    }

    @Test
    fun pillsGrowWithTheFontScale() {
        show()
        val defaultWidth = bounds("top40").width
        fontScale = 2f
        rule.waitForIdle()
        listOf("old", "current", "top1", "top40").forEach { assertTrue("$it grows at 200%", bounds(it).height >= px(36f)) }
        // The percentile minimum is 5.5 em, so it scales with the (non-linearly scaled) text.
        assertTrue("${bounds("top40").width} vs $defaultWidth", bounds("top40").width >= defaultWidth * 1.4f)
    }

    @Test
    fun seasonColoursMeetIosContrast() {
        val card = BrandTokens.cardBackground
        val normal = seasonPillColors(current = false)
        val current = seasonPillColors(current = true)
        assertEquals(BrandTokens.textSecondary, normal.text)
        assertEquals(BrandTokens.surfaceSubtle, normal.fill)
        assertEquals(BrandTokens.borderSubtle, normal.stroke)
        assertEquals(BrandTokens.surfaceSubtle, current.text)
        assertEquals(BrandTokens.textSecondary, current.fill)
        assertTrue(contrast(normal.text, normal.fill) >= 7.0)
        assertTrue(contrast(current.text, current.fill) >= 7.0)
        // The inverted current-season chip stands off the card (non-text contrast ≥ 3:1).
        assertTrue(contrast(current.fill, card) >= 3.0)
        assertEquals("S9", seasonPillText(9))
        assertEquals("Season 9", seasonPillDescription(9, current = false))
        assertEquals("Current season 9", seasonPillDescription(9, current = true))
    }
}
