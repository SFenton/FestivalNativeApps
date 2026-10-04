package com.festivalscoretracker.android.ui.design

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The star rating's reachable states (`.agents/controls/star-rating/spec.md`, issue #128):
 * `white-1`, `white-5`, `gold-6`, `minimum-one` (0 still draws one white star) and
 * `gold-average` (a perfect average of six), in the inline and web `MiniStars` styles.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StarRatingUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val backdrop = Color.Black
    private val density = 3f

    private data class State(val id: String, val stars: Int, val gold: Boolean, val images: Int, val label: String)

    private val states = listOf(
        State("white-1", 1, false, 1, "1 star"),
        State("white-5", 5, false, 5, "5 stars"),
        State("gold-6", 6, false, 5, "5 gold stars"),
        State("minimum-one", 0, false, 1, "1 star"),
        State("gold-average", 6, true, 5, "5 gold stars"),
    )

    private fun show(style: StarRatingStyle, size: Int = 20) {
        rule.setContent {
            FestivalTheme {
                Column {
                    states.forEach { state ->
                        Box(Modifier.background(backdrop).padding(4.dp)) {
                            StarRating(state.stars, Modifier.testTag("fst.star-rating.${state.id}"), size = size.dp, gold = state.gold, style = style)
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun node(id: String): SemanticsNode = rule.onNodeWithTag("fst.star-rating.$id", useUnmergedTree = true).fetchSemanticsNode()

    private fun snapshot(): Bitmap {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return bitmap
    }

    /**
     * Asserts every image slot of [state] shows the white or gold artwork at its centre,
     * never a platform glyph tint. Slots are [pitch] dp apart; the image centre is [offset] dp in.
     */
    private fun assertArtwork(bitmap: Bitmap, state: State, pitch: Float, offset: Float) {
        val bounds = node(state.id).boundsInWindow
        (0 until state.images).forEach { index ->
            val centre = bitmap.getPixel((bounds.left + (index * pitch + offset) * density).toInt(), bounds.center.y.toInt())
            val red = android.graphics.Color.red(centre)
            val green = android.graphics.Color.green(centre)
            val blue = android.graphics.Color.blue(centre)
            assertTrue("${state.id} $index lit ($red,$green,$blue)", red > 180 && green > 150)
            if (state.label.contains("gold")) {
                assertTrue("${state.id} $index gold ($red,$green,$blue)", blue < red - 60)
            } else {
                assertTrue("${state.id} $index white ($red,$green,$blue)", blue > 180)
            }
        }
    }

    @Test
    fun everyStateIsOneImageElementWithItsSpokenCount() {
        show(StarRatingStyle.Inline)
        states.forEach { state ->
            val row = node(state.id)
            assertEquals(state.id, listOf(state.label), row.config[SemanticsProperties.ContentDescription])
            assertEquals(state.id, Role.Image, row.config.getOrNull(SemanticsProperties.Role))
            // The star images carry no semantics of their own: TalkBack has one stop.
            assertTrue(state.id, row.children.all { child -> child.config.none() })
            // Inline: N × 20 dp images 2 dp apart.
            assertEquals(state.id, (state.images * 20 + (state.images - 1) * 2) * density, row.size.width.toFloat(), 0.5f)
            assertEquals(state.id, 20 * density, row.size.height.toFloat(), 0.5f)
        }
    }

    @Test
    fun everyStateDrawsThatManyStarImagesInItsColour() {
        show(StarRatingStyle.Inline)
        val bitmap = snapshot()
        // The row width (asserted with the semantics) bounds the count; every slot shows the artwork.
        states.forEach { state -> assertArtwork(bitmap, state, pitch = 22f, offset = 10f) }
    }

    @Test
    fun miniStarsSitInCirclesWithAGoldRingOnlyWhenGold() {
        show(StarRatingStyle.Mini)
        val bitmap = snapshot()
        val gold = BrandTokens.gold.toArgb()
        states.forEach { state ->
            val row = node(state.id)
            // Web MiniStars: N × 24 dp circles 3 dp apart (132 dp for five).
            assertEquals(state.id, (state.images * 24 + (state.images - 1) * 3) * density, row.size.width.toFloat(), 0.5f)
            assertEquals(state.id, 24 * density, row.size.height.toFloat(), 0.5f)
            val y = row.boundsInWindow.center.y.toInt()
            (0 until state.images).forEach { index ->
                // 0.75 dp into each circle: inside the 1.5 dp ring, outside the 20 dp image.
                val ring = bitmap.getPixel((row.boundsInWindow.left + (index * 27 + 0.75f) * density).toInt(), y)
                if (state.label.contains("gold")) assertEquals("${state.id} ring $index", gold, ring) else assertEquals("${state.id} no ring $index", backdrop.toArgb(), ring)
            }
            assertArtwork(bitmap, state, pitch = 27f, offset = 12f)
        }
    }

    @Test
    @Config(fontScale = 2.0f)
    fun atDoubleTextTheStarsKeepTheirGeometryLikeIcons() {
        show(StarRatingStyle.Mini)
        val five = node("white-5")
        assertEquals(132 * density, five.size.width.toFloat(), 0.5f)
        assertEquals(24 * density, five.size.height.toFloat(), 0.5f)
        assertEquals(listOf("5 stars"), five.config[SemanticsProperties.ContentDescription])
    }

    @Test
    fun theRowIsNotFocusableOrClickable() {
        show(StarRatingStyle.Inline)
        states.forEach { state ->
            val row = node(state.id)
            assertNull(state.id, row.config.getOrNull(androidx.compose.ui.semantics.SemanticsActions.OnClick))
            assertNotEquals(state.id, true, row.config.getOrNull(SemanticsProperties.Focused))
        }
    }

    @Test
    fun starsDescriptionMatchesTheSpokenRow() {
        assertEquals("1 star", starsDescription(0))
        assertEquals("1 star", starsDescription(1))
        assertEquals("4 stars", starsDescription(4))
        assertEquals("5 gold stars", starsDescription(6))
    }
}
