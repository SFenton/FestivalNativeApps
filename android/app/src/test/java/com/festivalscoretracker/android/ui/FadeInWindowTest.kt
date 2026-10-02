package com.festivalscoretracker.android.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FadeInWindow
import com.festivalscoretracker.android.ui.common.LocalFadeInWindow
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberFadeInWindow
import com.festivalscoretracker.android.ui.common.rememberRevealed
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/**
 * The page fade window (issue #60): only content visible at a page's load fades in;
 * content that finishes loading after the page has scrolled shows in place.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FadeInWindowTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Window state

    @Test
    fun staysOpenAtRestAndWhileIdlePositionChanges() {
        val window = FadeInWindow(thresholdPx = 4f)
        assertTrue(window.note(0, 0, scrolling = false))
        // Items inserted above (or a restored position) move the list without a scroll.
        assertTrue(window.note(3, 120, scrolling = false))
        // A scroll that stays within the threshold of the resting position (settling).
        assertTrue(window.note(3, 123, scrolling = true))
        assertTrue(window.isOpen)
    }

    @Test
    fun closesWhenAScrollMovesBeyondTheThreshold() {
        val window = FadeInWindow(thresholdPx = 4f)
        window.note(0, 0, scrolling = false)
        assertFalse(window.note(0, 5, scrolling = true))
        // Closed for good, even back at rest.
        assertFalse(window.note(0, 0, scrolling = false))
        assertFalse(window.isOpen)
    }

    @Test
    fun closesWhenAScrollChangesTheFirstVisibleItem() {
        val window = FadeInWindow(thresholdPx = 4f)
        window.note(2, 10, scrolling = false)
        assertFalse(window.note(3, 0, scrolling = true))
    }

    @Test
    fun firstObservationIsTheRestingPositionEvenMidScroll() {
        val window = FadeInWindow(thresholdPx = 4f)
        assertTrue(window.note(5, 40, scrolling = true))
        assertFalse(window.note(6, 0, scrolling = true))
    }

    // endregion

    // region Pixels

    @Test
    fun withoutAWindowContentLoadedAfterScrollingFadesIn() {
        // The reported behaviour: a section that loads once scrolled to fades in.
        val trace = loadAfterScroll(window = false)
        // Still part-way through the 400 ms fade three frames after it is composed.
        assertTrue("fading $trace", trace.last() < 0.6f)
        rule.mainClock.advanceTimeBy(600)
        assertEquals(1f, brightness(), 0.02f)
    }

    @Test
    fun contentLoadedAfterScrollingShowsInPlace() {
        // Fully drawn in the frame that composes it (the first sample precedes that frame).
        val trace = loadAfterScroll(window = true)
        assertTrue("frames $trace", trace.drop(1).all { it > 0.98f })
    }

    @Test
    fun contentLoadedBeforeScrollingStillFadesIn() {
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            val state = rememberLazyListState()
            CompositionLocalProvider(LocalFadeInWindow provides rememberFadeInWindow(state)) { Page(state, loaded, target = 0) }
        }
        rule.mainClock.advanceTimeBy(300)
        assertEquals(0f, brightness(), 0.02f)
        loaded = true
        val trace = (0 until 4).map { rule.mainClock.advanceTimeByFrame(); brightness() }
        assertTrue("fading $trace", trace.last() < 0.6f)
        rule.mainClock.advanceTimeBy(600)
        assertEquals(1f, brightness(), 0.02f)
    }

    /** Scroll the target into view, then load it; brightness over the first frames. */
    private fun loadAfterScroll(window: Boolean): List<Float> {
        var loaded by mutableStateOf(false)
        lateinit var state: LazyListState
        lateinit var scope: CoroutineScope
        rule.mainClock.autoAdvance = false
        rule.setContent {
            state = rememberLazyListState()
            scope = rememberCoroutineScope()
            if (window) {
                CompositionLocalProvider(LocalFadeInWindow provides rememberFadeInWindow(state)) { Page(state, loaded, target = 4) }
            } else {
                Page(state, loaded, target = 4)
            }
        }
        rule.mainClock.advanceTimeBy(300)
        val distance = with(rule.density) { (ROW_DP * 4).dp.toPx() }
        rule.runOnUiThread { scope.launch { state.animateScrollBy(distance) } }
        rule.mainClock.advanceTimeBy(1_000)
        assertEquals(4, state.firstVisibleItemIndex)
        assertEquals(0f, brightness(), 0.02f)
        loaded = true
        return (0 until 4).map { rule.mainClock.advanceTimeByFrame(); brightness() }
    }

    @Composable
    private fun Page(state: LazyListState, loaded: Boolean, target: Int) {
        LazyColumn(Modifier.size(ROW_DP.dp, (ROW_DP * 2).dp), state = state) {
            items(10) { index ->
                if (index == target) {
                    val revealed = rememberRevealed(loaded)
                    Box(Modifier.fillMaxWidth().height(ROW_DP.dp).background(Color.Black).testTag("host")) {
                        if (loaded) Box(Modifier.fillMaxWidth().height(ROW_DP.dp).festivalFadeIn(revealed).background(Color.White))
                    }
                } else {
                    Box(Modifier.fillMaxWidth().height(ROW_DP.dp).background(Color.Black))
                }
            }
        }
    }

    /** Red channel (0–1) at the centre of `host`, drawn from the window (works with the clock paused). */
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
        val y = origin[1] + ((bounds.top.value + bounds.bottom.value) / 2 * density).toInt()
        return ((bitmap.getPixel(x, y) shr 16) and 0xFF) / 255f
    }

    private companion object {
        const val ROW_DP = 60
    }

    // endregion
}
