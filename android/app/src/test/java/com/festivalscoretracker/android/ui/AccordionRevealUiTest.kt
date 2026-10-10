package com.festivalscoretracker.android.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.AccordionReveal
import com.festivalscoretracker.android.ui.common.AccordionRevealOf
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/**
 * Pixel and size trace of the shared accordion (issue #561, `load-transition` R10): opening
 * grows the height with the content hidden, then fades it in; closing fades it out at full
 * height, then collapses; reduced motion opens and closes at once.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AccordionRevealUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var open by mutableStateOf(false)

    @Test
    fun opensByGrowingThenFadingIn() {
        start(initiallyOpen = false)
        set { open = true }
        // The transition starts a frame after the toggle.
        rule.mainClock.advanceTimeBy(100)
        val growing = height()
        assertTrue("height part-way at 100 ms: $growing", growing > 1f && growing < CONTENT_DP - 1f)
        assertEquals("content hidden while the height grows", 0f, brightness(), 0.02f)
        rule.mainClock.advanceTimeBy(64)
        assertEquals("about full height as the height step ends", CONTENT_DP, height(), 1.5f)
        assertEquals("content still hidden until the height step ends", 0f, brightness(), 0.02f)
        rule.mainClock.advanceTimeBy(96)
        val fading = brightness()
        assertTrue("content part-way faded in at 260 ms: $fading", fading > 0.05f && fading < 0.95f)
        assertEquals(CONTENT_DP, height(), 0.5f)
        rule.mainClock.advanceTimeBy(200)
        assertEquals(1f, brightness(), 0.02f)
    }

    @Test
    fun closesByFadingOutThenCollapsing() {
        start(initiallyOpen = true)
        assertEquals(1f, brightness(), 0.02f)
        set { open = false }
        rule.mainClock.advanceTimeBy(80)
        val fading = brightness()
        assertTrue("content part-way faded out at 80 ms: $fading", fading > 0.05f && fading < 0.95f)
        assertEquals("full height while the content fades", CONTENT_DP, height(), 0.5f)
        rule.mainClock.advanceTimeBy(176)
        val collapsing = height()
        assertTrue("height part-way at 256 ms: $collapsing", collapsing > 1f && collapsing < CONTENT_DP - 1f)
        assertEquals("content gone while the height collapses", 0f, brightness(), 0.02f)
        rule.mainClock.advanceTimeBy(250)
        assertEquals(0, rule.onAllNodesWithTag("content").fetchSemanticsNodes().size)
    }

    @Test
    fun reducedMotionOpensAndClosesAtOnce() {
        start(initiallyOpen = false, reduceMotion = true)
        set { open = true }
        repeat(5) { rule.mainClock.advanceTimeByFrame() }
        assertEquals(CONTENT_DP, height(), 0.5f)
        assertEquals(1f, brightness(), 0.02f)
        set { open = false }
        repeat(5) { rule.mainClock.advanceTimeByFrame() }
        assertEquals(0, rule.onAllNodesWithTag("content").fetchSemanticsNodes().size)
    }

    @Test
    fun valueRevealKeepsTheLastValueWhileItCloses() {
        var value by mutableStateOf<String?>("Lead")
        rule.setContent { AccordionRevealOf(value) { Text(it) } }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
        assertEquals("open with its value", 1, rule.onAllNodesWithText("Lead").fetchSemanticsNodes().size)
        set { value = null }
        rule.mainClock.advanceTimeBy(100)
        assertEquals("closing content keeps the last value", 1, rule.onAllNodesWithText("Lead").fetchSemanticsNodes().size)
        rule.mainClock.advanceTimeBy(400)
        assertEquals(0, rule.onAllNodesWithText("Lead").fetchSemanticsNodes().size)
        set { value = "Bass" }
        rule.mainClock.advanceTimeBy(400)
        assertEquals(1, rule.onAllNodesWithText("Bass").fetchSemanticsNodes().size)
    }

    /** Applies a state change the way an input event would, so the next frame sees it. */
    private fun set(change: () -> Unit) {
        rule.runOnUiThread { change() }
        Snapshot.sendApplyNotifications()
    }

    private fun start(initiallyOpen: Boolean, reduceMotion: Boolean = false) {
        open = initiallyOpen
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduceMotion)) { Harness() }
        }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
    }

    @Composable
    private fun Harness() {
        Box(Modifier.size(40.dp, 80.dp).background(Color.Black).testTag("host")) {
            Column {
                AccordionReveal(open, Modifier.testTag("reveal")) {
                    Box(Modifier.fillMaxWidth().height(CONTENT_DP.dp).background(Color.White).testTag("content"))
                }
            }
        }
    }

    /** The reveal's laid-out height in dp (0 once it is gone). */
    private fun height(): Float {
        val nodes = rule.onAllNodesWithTag("reveal").fetchSemanticsNodes()
        if (nodes.isEmpty()) return 0f
        val bounds = rule.onNodeWithTag("reveal").getBoundsInRoot()
        return (bounds.bottom - bounds.top).value
    }

    /** Red channel (0–1) 4 dp below the host's top, drawn from the window (works with the clock paused). */
    private fun brightness(): Float {
        val bounds = rule.onNodeWithTag("host").getBoundsInRoot()
        val density = rule.density.density
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        val origin = IntArray(2)
        rule.runOnUiThread {
            root.draw(Canvas(bitmap))
            rule.activity.findViewById<View>(android.R.id.content).getLocationInWindow(origin)
        }
        val x = origin[0] + ((bounds.left.value + bounds.right.value) / 2 * density).toInt()
        val y = origin[1] + ((bounds.top.value + 4f) * density).toInt()
        return ((bitmap.getPixel(x, y) shr 16) and 0xFF) / 255f
    }

    private companion object {
        const val CONTENT_DP = 40f
    }
}
