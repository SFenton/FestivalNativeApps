package com.festivalscoretracker.android.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
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
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FadeInWindow
import com.festivalscoretracker.android.ui.common.FadeTimeline
import com.festivalscoretracker.android.ui.common.LocalFadeInWindow
import com.festivalscoretracker.android.ui.common.fadeInRushOnScroll
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberPageFadeInWindow
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.GraphicsMode

/**
 * The page fade window's shared timeline (issue #323, load-transition R5): a scroll during
 * the first-load stagger fades the rest in together (web `useStaggerRush`), rows a scroll
 * reaches mid-entrance join it instead of popping in, and a finished entrance never replays.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StaggerRushTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Timeline

    @Test
    fun fadesStartAfterTheirStaggerWithoutARush() {
        assertEquals(MS * 500, FadeTimeline.startNanos(0, MS * 500, emptyList()))
        // A rush before the fade was armed, or after it started, does not move it.
        assertEquals(MS * 600, FadeTimeline.startNanos(MS * 100, MS * 500, listOf(MS * 50, MS * 700)))
    }

    @Test
    fun aRushStartsEveryFadeThatHasNotStarted() {
        assertEquals(MS * 200, FadeTimeline.startNanos(0, MS * 500, listOf(MS * 200)))
        assertEquals(MS * 200, FadeTimeline.startNanos(0, MS * 1_500, listOf(MS * 200, MS * 300)))
    }

    @Test
    fun progressIsLinearFromTheStart() {
        assertEquals(0f, FadeTimeline.progress(MS * 100, MS * 200, MS * 400), 0f)
        assertEquals(0.5f, FadeTimeline.progress(MS * 400, MS * 200, MS * 400), 0.001f)
        assertEquals(1f, FadeTimeline.progress(MS * 900, MS * 200, MS * 400), 0f)
        assertEquals(1f, FadeTimeline.progress(MS * 200, MS * 200, 0), 0f)
    }

    @Test
    fun windowRushesOncePerRevealAndSettles() {
        val window = FadeInWindow(thresholdPx = 0f, closesOnScroll = false)
        // Nothing to rush before an entrance.
        window.rush()
        assertFalse(window.isRushPending)
        window.arm(0, 0)
        window.arm(0, 1_500)
        window.tick(MS * 100)
        assertEquals(0f, window.progress(0, 1_500), 0f)
        window.rush()
        window.tick(MS * 200)
        // The 1.5 s row starts with the rush, together with the rest.
        assertEquals(0f, window.progress(0, 1_500), 0f)
        window.tick(MS * 400)
        assertEquals(0.5f, window.progress(0, 1_500), 0.001f)
        // A second scroll in the same reveal does not restart started fades.
        window.rush()
        window.tick(MS * 500)
        assertEquals(0.75f, window.progress(0, 1_500), 0.001f)
        assertTrue(window.isAnimating)
        // The rushed entrance ends 400 ms after the rush, not after the full stagger.
        window.tick(MS * 600)
        assertFalse(window.isAnimating)
        assertEquals(1f, window.progress(0, 1_500), 0f)
        // Later scrolls never replay it (R5); loaded content composed now shows.
        window.rush()
        assertFalse(window.isRushPending)
        assertEquals(FadeInWindow.SHOWN, window.initialAnchor(isLoaded = true, reduceMotion = false))
    }

    @Test
    fun contentComposedMidEntranceJoinsIt() {
        val window = FadeInWindow(thresholdPx = 0f, closesOnScroll = false)
        assertEquals(FadeInWindow.PENDING, window.initialAnchor(isLoaded = false, reduceMotion = false))
        window.arm(MS * 50, 0)
        window.tick(MS * 60)
        // A row the scroll reaches now fades on the entrance's clock, not opaque.
        assertEquals(MS * 50, window.initialAnchor(isLoaded = true, reduceMotion = false))
        assertEquals(FadeInWindow.SHOWN, window.initialAnchor(isLoaded = true, reduceMotion = true))
    }

    @Test
    fun aNewRevealCanBeRushedAgain() {
        val window = FadeInWindow(thresholdPx = 0f, closesOnScroll = false)
        window.arm(0, 1_000)
        window.rush()
        window.tick(MS * 100)
        // Another result set reveals while the first still runs (web resetRush).
        window.arm(MS * 200, 1_000)
        window.rush()
        window.tick(MS * 300)
        assertEquals(0f, window.progress(MS * 200, 1_000), 0f)
        window.tick(MS * 400)
        assertEquals(0.25f, window.progress(MS * 200, 1_000), 0.001f)
    }

    // endregion

    // region Pixels

    @Test
    fun rowsAScrollReachesMidEntranceFadeInTogether() {
        lateinit var state: LazyListState
        lateinit var scope: CoroutineScope
        lateinit var window: FadeInWindow
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            state = rememberLazyListState()
            scope = rememberCoroutineScope()
            window = rememberPageFadeInWindow()
            CompositionLocalProvider(LocalFadeInWindow provides window) { Rows(state, loaded) }
        }
        frames(100)
        loaded = true
        // A state write is applied on the next frame; the reveal then arms the row fades.
        repeat(3) { frame() }
        frames(100)
        // A programmatic scroll (the selected-row reveal) to rows still waiting on their stagger.
        rule.runOnUiThread {
            window.rush()
            scope.launch { state.scrollToItem(8) }
        }
        frame()
        frame()
        assertEquals(8, state.firstVisibleItemIndex)
        val early = listOf(brightness("row8"), brightness("row9"))
        assertTrue("not opaque $early", early.all { it < 0.6f })
        frames(160)
        val mid = listOf(brightness("row8"), brightness("row9"))
        // Together (not 125 ms apart) and still fading.
        assertEquals(mid[0], mid[1], 0.05f)
        assertTrue("fading $mid", mid[0] in 0.2f..0.98f)
        frames(400)
        assertEquals(1f, brightness("row8"), 0.02f)
        // Scrolling back after the entrance never replays it.
        rule.runOnUiThread { scope.launch { state.scrollToItem(0) } }
        frame()
        frame()
        assertEquals(1f, brightness("row0"), 0.02f)
        assertEquals(1f, brightness("row1"), 0.02f)
    }

    @Test
    fun withoutAScrollTheStaggerRuns() {
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            val window = rememberPageFadeInWindow()
            CompositionLocalProvider(LocalFadeInWindow provides window) { Rows(rememberLazyListState(), loaded) }
        }
        frames(100)
        loaded = true
        frames(250)
        // Row 0 is well into its fade; row 1 (125 ms later) is behind it.
        val pair = listOf(brightness("row0"), brightness("row1"))
        assertTrue("stagger $pair", pair[0] > pair[1] + 0.1f)
        frames(1_000)
        assertEquals(1f, brightness("row1"), 0.02f)
    }

    @Test
    fun aDragRushesThePage() {
        lateinit var window: FadeInWindow
        var loaded by mutableStateOf(false)
        rule.setContent {
            window = rememberPageFadeInWindow()
            CompositionLocalProvider(LocalFadeInWindow provides window) {
                Box(Modifier.fadeInRushOnScroll(window)) { Rows(rememberLazyListState(), loaded) }
            }
        }
        rule.waitForIdle()
        assertEquals(0, window.userScrolls)
        rule.onNodeWithTag("list").performTouchInput { swipeUp() }
        rule.waitForIdle()
        assertTrue(window.userScrolls > 0)
    }

    @Test
    fun reduceMotionShowsRowsAtOnce() {
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true)) {
                val window = rememberPageFadeInWindow()
                CompositionLocalProvider(LocalFadeInWindow provides window) { Rows(rememberLazyListState(), loaded) }
            }
        }
        frames(100)
        loaded = true
        repeat(3) { frame() }
        assertEquals(1f, brightness("row0"), 0.02f)
        assertEquals(1f, brightness("row1"), 0.02f)
    }

    @Composable
    private fun Rows(state: LazyListState, loaded: Boolean) {
        val revealed = rememberRevealed(loaded)
        LazyColumn(Modifier.size(ROW_DP.dp, (ROW_DP * 2).dp).testTag("list"), state = state) {
            items(ROWS) { index ->
                Box(Modifier.fillMaxWidth().height(ROW_DP.dp).background(Color.Black).testTag("row$index")) {
                    Box(Modifier.fillMaxWidth().height(ROW_DP.dp).festivalFadeIn(revealed, fadeInStagger(index)).background(Color.White))
                }
            }
        }
    }

    /** Run frames for [millis] (a bulk `advanceTimeBy` skips the per-frame layer updates the fades draw with). */
    private fun frames(millis: Int) = repeat(millis / FRAME_MS + 1) { frame() }

    /** One frame, then the main looper's posted work (layer updates), as a device runs it between frames. */
    private fun frame() {
        rule.mainClock.advanceTimeByFrame()
        shadowOf(Looper.getMainLooper()).idle()
    }

    /** Red channel (0–1) at the centre of [tag], drawn from the window (works with the clock paused). */
    private fun brightness(tag: String): Float {
        val bounds = rule.onNodeWithTag(tag).getBoundsInRoot()
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
        const val MS = 1_000_000L
        const val ROW_DP = 60
        const val ROWS = 12
        const val FRAME_MS = 16
    }

    // endregion
}
