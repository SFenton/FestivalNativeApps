package com.festivalscoretracker.android.ui.leaderboards

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issue #319: the boards' pager (arrow circles and page badge) is drawn on the row
 * cards' own [GlassCard] surface, not a pager-only opaque plate, in every
 * accessibility mode, and keeps its 48 dp targets and disabled state.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w420dp-h700dp-xhdpi")
class RankingsPagerSurfaceUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** A white backdrop makes translucency visible: an opaque plate and a frosted card differ. */
    private fun show(accessibility: FestivalAccessibility) {
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides accessibility) {
                Column(
                    Modifier.fillMaxSize().background(Color.White).padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    GlassCard(Modifier.fillMaxWidth().testTag("row")) { Box(Modifier.height(48.dp)) }
                    RankingsPager(1, 5, "fst.test", {})
                }
            }
        }
        rule.waitForIdle()
    }

    @Test
    fun pagerUsesTheRowCardSurface() {
        show(FestivalAccessibility())
        val row = fill("row")
        assertTrue("row card should be translucent over white", distance(row, BrandTokens.cardBackground.toArgb()) > 40)
        for (tag in listOf("fst.test.page-first", "fst.test.page-previous", "fst.test.page-next", "fst.test.page-last")) {
            assertTrue("$tag fill ${hex(fill(tag))} differs from the row card ${hex(row)}", distance(fill(tag), row) <= 3)
        }
        assertTrue("badge fill differs from the row card", distance(badgeFill(), row) <= 3)
    }

    @Test
    fun increaseContrastMakesThePagerOpaqueLikeTheRows() = assertOpaque(FestivalAccessibility(increaseContrast = true))

    @Test
    fun reduceTransparencyMakesThePagerOpaqueLikeTheRows() = assertOpaque(FestivalAccessibility(reduceTransparency = true))

    private fun assertOpaque(mode: FestivalAccessibility) {
        show(mode)
        val opaque = BrandTokens.cardBackground.toArgb()
        assertTrue("$mode row", distance(fill("row"), opaque) <= 3)
        assertTrue("$mode next", distance(fill("fst.test.page-next"), opaque) <= 3)
        assertTrue("$mode badge", distance(badgeFill(), opaque) <= 3)
    }

    @Test
    fun buttonsKeepTargetsAndDisabledState() {
        show(FestivalAccessibility())
        for (tag in listOf("fst.test.page-first", "fst.test.page-previous", "fst.test.page-next", "fst.test.page-last")) {
            rule.onNodeWithTag(tag).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        }
        rule.onNodeWithTag("fst.test.pager").assertHeightIsAtLeast(48.dp)
        val previous = rule.onNodeWithTag("fst.test.page-previous").fetchSemanticsNode().config
        assertTrue(previous.contains(SemanticsProperties.Disabled))
        assertFalse(rule.onNodeWithTag("fst.test.page-next").fetchSemanticsNode().config.contains(SemanticsProperties.Disabled))
        assertTrue(rule.onNodeWithTag("fst.test.page-next").fetchSemanticsNode().config.contains(SemanticsActions.OnClick))
        assertEquals(
            listOf("Page 1 of 5"),
            rule.onNodeWithTag("fst.test.page-info", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription],
        )
    }

    // region Helpers

    /** The surface colour just inside the top edge of a node (clear of its border and glyph). */
    private fun fill(tag: String): Int {
        val b = bounds(tag)
        return screen().getPixel(b.center.x.toInt(), (b.top + 8.dp.value * density()).toInt())
    }

    /** The page badge's fill, in its padding left of the text at mid-height. */
    private fun badgeFill(): Int {
        val text = bounds("fst.test.page-info")
        return screen().getPixel((text.left - 6.dp.value * density()).toInt(), text.center.y.toInt())
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    private fun density(): Float = rule.activity.resources.displayMetrics.density

    /** The rendered window, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun screen(): Bitmap {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        return whole
    }

    private fun distance(a: Int, b: Int): Int = maxOf(
        abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)),
        abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)),
        abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b)),
    )

    private fun hex(colour: Int) = "#%06X".format(colour and 0xFFFFFF)

    // endregion
}
