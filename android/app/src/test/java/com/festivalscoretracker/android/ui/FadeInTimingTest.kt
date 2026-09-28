package com.festivalscoretracker.android.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FadeInEasing
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/** Pixel check of the shared fade-in against the web `fadeInUp` timing (400 ms, CSS ease-out). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FadeInTimingTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun easingIsCssEaseOut() {
        assertEquals(0f, FadeInEasing.transform(0f), 0.001f)
        assertEquals(1f, FadeInEasing.transform(1f), 0.001f)
        // CSS ease-out at t = 0.5 is ≈ 0.685.
        assertEquals(0.685f, FadeInEasing.transform(0.5f), 0.01f)
    }

    @Test
    fun hiddenWhileLoadingThenRisesOverFourHundredMillis() {
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent { Harness(loaded) }
        rule.mainClock.advanceTimeBy(500)
        assertEquals(0f, brightness(), 0.02f)
        loaded = true
        // Sampled every 50 ms: a monotonic rise that is part-way at 200 ms and settled by ~500 ms.
        val trace = (0 until 8).map { rule.mainClock.advanceTimeBy(50); brightness() }
        assertEquals(trace.sorted(), trace)
        assertTrue("mid-fade $trace", trace[3] in 0.2f..0.95f)
        rule.mainClock.advanceTimeBy(150)
        assertEquals(1f, brightness(), 0.02f)
    }

    @Test
    fun reduceMotionShowsAtOnce() {
        var loaded by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true)) { Harness(loaded) }
        }
        rule.mainClock.advanceTimeBy(100)
        assertEquals(0f, brightness(), 0.02f)
        loaded = true
        // Fully drawn within the frames that compose it, not over the 400 ms fade.
        val trace = (0 until 3).map { rule.mainClock.advanceTimeByFrame(); brightness() }
        assertEquals("frames $trace", 1f, trace.last(), 0.02f)
    }

    @androidx.compose.runtime.Composable
    private fun Harness(loaded: Boolean) {
        val revealed = rememberRevealed(loaded)
        Box(Modifier.size(40.dp).background(Color.Black).testTag("host")) {
            if (loaded) Box(Modifier.size(40.dp).festivalFadeIn(revealed).background(Color.White))
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
}
