package com.festivalscoretracker.android.songs

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
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.ui.songs.pinnedHeaderEdgeFade
import com.festivalscoretracker.android.ui.songs.rememberPinnedHeaderEdge
import com.festivalscoretracker.android.ui.songs.rememberPinnedHeaderRecorder
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Songs pinned section header edge on a real device (issues #49, #157), driven by the real
 * system settings through [FestivalTheme]: rows fade out over 28 dp below the pinned header, and
 * system High contrast text or Remove animations (animator duration scale 0) switch to a hard
 * edge, live, while the header stays opaque. Run with `device.py test
 * com.festivalscoretracker.android.songs.PinnedHeaderEdgeFadeDeviceTest --avd <AVD>`.
 */
@RunWith(AndroidJUnit4::class)
class PinnedHeaderEdgeFadeDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var savedAnimatorScale = ""
    private var savedHighContrastText = ""

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    private fun setHighContrastText(on: Boolean) = shell("settings put secure $HIGH_CONTRAST_TEXT ${if (on) 1 else 0}")

    private fun setAnimatorScale(scale: String) = shell("settings put global animator_duration_scale $scale")

    @Before
    fun saveSettings() {
        savedAnimatorScale = shell("settings get global animator_duration_scale")
        savedHighContrastText = shell("settings get secure $HIGH_CONTRAST_TEXT")
        setAnimatorScale("1")
        setHighContrastText(false)
    }

    @After
    fun restoreSettings() {
        shell(if (savedAnimatorScale == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $savedAnimatorScale")
        shell(if (savedHighContrastText == "null") "settings delete secure $HIGH_CONTRAST_TEXT" else "settings put secure $HIGH_CONTRAST_TEXT $savedHighContrastText")
    }

    /**
     * A 400 × 800 dp list on blue inside [FestivalTheme]: three sections, each a 100 × 40 dp
     * green sticky header and ten full-width 40 dp red rows, opened in the second section with a
     * row 10 dp under the pinned header.
     */
    private fun launch() {
        rule.setContent {
            FestivalTheme {
                val state = remember { LazyListState(3, 10) }
                val edge = rememberPinnedHeaderEdge(state, "h0", 0.dp, IS_HEADER)
                Box(Modifier.size(400.dp, 800.dp).background(Color.Blue).testTag(FRAME)) {
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
    }

    /** The frame's pixels, sampled in dp from its top-left corner. */
    private inner class Shot(image: ImageBitmap) {
        private val pixels = image.toPixelMap()
        private val density = rule.density.density
        private fun at(dx: Int, dy: Int) = pixels[(dx * density).toInt(), (dy * density + density / 2).toInt().coerceAtMost(pixels.height - 1)]
        fun red(dy: Int) = at(200, dy).red
        fun green(dy: Int) = at(50, dy).green
    }

    private fun shot() = Shot(rule.onNodeWithTag(FRAME).captureToImage())

    private fun isFade(shot: Shot): Boolean =
        shot.green(20) > 0.9f && (2 until 38).none { shot.red(it) > 0.05f } &&
            shot.red(41) < 0.3f && (70 until 200).all { shot.red(it) > 0.95f }

    private fun isHardEdge(shot: Shot): Boolean =
        shot.green(20) > 0.9f && (2 until 38).none { shot.red(it) > 0.05f } && (41 until 200).all { shot.red(it) > 0.95f }

    private fun awaitEdge(label: String, hard: Boolean) {
        runCatching { rule.waitUntil(5_000) { val s = shot(); if (hard) isHardEdge(s) else isFade(s) } }
        val s = shot()
        assertTrue("$label: expected ${if (hard) "a hard edge" else "a fade"}; red at 41..69 dp = ${(41 until 70).map { "%.2f".format(s.red(it)) }}", if (hard) isHardEdge(s) else isFade(s))
    }

    // endregion

    // region States

    /** Default settings: rows fade out below the pinned header and never show beside it. */
    @Test
    fun rowsFadeUnderThePinnedHeader() {
        launch()
        awaitEdge("default", hard = false)
        assertFalse(isHardEdge(shot()))
    }

    /** System High contrast text keeps a hard edge, and switching it while open updates the edge. */
    @Test
    fun highContrastTextSwitchesToAHardEdgeLive() {
        launch()
        awaitEdge("before High contrast text", hard = false)
        setHighContrastText(true)
        awaitEdge("High contrast text on", hard = true)
        setHighContrastText(false)
        awaitEdge("High contrast text off", hard = false)
    }

    /** Remove animations (animator duration scale 0) keeps a hard edge, live. */
    @Test
    fun removeAnimationsSwitchesToAHardEdgeLive() {
        launch()
        awaitEdge("animations on", hard = false)
        setAnimatorScale("0")
        awaitEdge("Remove animations on", hard = true)
        setAnimatorScale("1")
        awaitEdge("animations back on", hard = false)
    }

    // endregion

    private companion object {
        const val FRAME = "edge-frame"
        const val HIGH_CONTRAST_TEXT = "high_text_contrast_enabled"
        val IS_HEADER: (Any) -> Boolean = { it is String && it.startsWith("h") }
    }
}
