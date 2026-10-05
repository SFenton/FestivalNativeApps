package com.festivalscoretracker.android.ui.songs

import android.graphics.Bitmap
import android.graphics.Canvas
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Pixels of the Songs pinned section header edge (issues #49, #157): rows scrolling under a
 * pinned header are hidden behind it and fade out over the 28 dp band below it, while the header
 * stays opaque. Increase Contrast, system High contrast text, Reduce Transparency and Remove
 * animations keep a hard edge at the header's bottom.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PinnedHeaderEdgeFadeDrawUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val isHeader: (Any) -> Boolean = { it is String && it.startsWith("h") }

    /**
     * A 400 × 800 dp list on blue: three sections, each a 100 × 40 dp green sticky header and ten
     * full-width 40 dp red rows, no gaps, opened at [index] scrolled by [offset] px.
     */
    private fun list(index: Int, offset: Int, accessibility: FestivalAccessibility = FestivalAccessibility()): Shot {
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides accessibility) {
                val state = remember { LazyListState(index, offset) }
                val edge = rememberPinnedHeaderEdge(state, "h0", 0.dp, isHeader)
                Box(Modifier.size(400.dp, 800.dp).background(Color.Blue).testTag("frame")) {
                    LazyColumn(state = state, modifier = Modifier.fillMaxSize().pinnedHeaderEdgeFade(edge, headerStart = 0f)) {
                        repeat(3) { section ->
                            stickyHeader(key = "h$section") {
                                Box(rememberPinnedHeaderRecorder("h$section", edge.layers).width(100.dp).height(40.dp).background(Color.Green))
                            }
                            items((0 until 10).map { "r$section.$it" }, key = { it }) {
                                Box(Modifier.fillMaxWidth().height(40.dp).background(Color.Red))
                            }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
        val origin = rule.onNodeWithTag("frame").fetchSemanticsNode().positionInWindow
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return Shot(bitmap, origin.x.toInt(), origin.y.toInt())
    }

    /** The window in [bitmap], with the list's top-left at ([x], [y]); 1 px = 1 dp. */
    private class Shot(val bitmap: Bitmap, val x: Int, val y: Int) {
        private fun channel(dx: Int, dy: Int, shift: Int) = ((bitmap.getPixel(x + dx, y + dy) shr shift) and 0xFF) / 255f
        fun redAt(dy: Int, dx: Int = 200): Float = channel(dx, dy, 16)
        fun greenAt(dy: Int, dx: Int = 50): Float = channel(dx, dy, 8)
    }

    @Test
    fun rowsAreHiddenUnderThePinnedHeaderAndFadeBelowIt() {
        val shot = list(index = 3, offset = 10)
        assertTrue("the pinned header stays opaque", shot.greenAt(20) > 0.9f)
        assertFalse("no row shows beside the header", (0 until 40).any { shot.redAt(it) > 0.05f })
        val band = (40 until 68).map { shot.redAt(it) }
        assertTrue("the band starts nearly clear", band.first() < 0.15f)
        assertTrue("the band eases in", band.zipWithNext().all { (a, b) -> b >= a - 0.01f })
        assertTrue("rows below the band are untouched", (70 until 200).all { shot.redAt(it) > 0.95f })
    }

    @Test
    fun nothingIsCutBeforeRowsScrollUnderTheFirstHeader() {
        val shot = list(index = 0, offset = 0)
        assertTrue(shot.greenAt(20) > 0.9f)
        assertTrue("the first row starts right below the resting header", (41 until 80).all { shot.redAt(it) > 0.95f })
    }

    @Test
    fun increaseContrastKeepsTheHardEdge() = assertHardEdge(list(3, 10, FestivalAccessibility(increaseContrast = true)))

    @Test
    fun reduceTransparencyKeepsTheHardEdge() = assertHardEdge(list(3, 10, FestivalAccessibility(reduceTransparency = true)))

    /** Issue #157: Remove animations / Reduce Motion is Android's stand-in for reduced transparency. */
    @Test
    fun removeAnimationsKeepsTheHardEdge() = assertHardEdge(list(3, 10, FestivalAccessibility(reduceMotion = true)))

    /** Issue #157: system High contrast text (its secure setting before API 36) keeps the hard edge. */
    @Test
    fun systemHighContrastTextKeepsTheHardEdge() {
        Settings.Secure.putInt(rule.activity.contentResolver, "high_text_contrast_enabled", 1)
        assertHardEdge(list(3, 10))
    }

    private fun assertHardEdge(shot: Shot) {
        assertTrue("the pinned header stays opaque", shot.greenAt(20) > 0.9f)
        assertFalse("rows stay hidden beside the header", (0 until 40).any { shot.redAt(it) > 0.05f })
        assertTrue("rows meet the header at a solid edge", (41 until 200).all { shot.redAt(it) > 0.95f })
    }
}
