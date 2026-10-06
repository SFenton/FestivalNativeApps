package com.festivalscoretracker.android.ui.songdetail

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Song Detail fades only what is visible when the page loads (issues #60 and #168, iOS
 * #27): every section is loaded behind the load gate, so a card scrolled into view
 * afterwards (or scrolled back to) is fully drawn in the first frame that composes it.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongDetailFadeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Helpers

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4)); rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun launch() {
        val debug = DebugLaunch(songQuery = "s-alpha", stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = FakeTransport.standard(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(20_000) { settle(100); exists(LIST) && exists(HEADER) }
        // Let the load fade and its stagger finish.
        settle(3_000)
    }

    /** Index of the page's last item, from the list's collection semantics. */
    private fun lastIndex(): Int {
        val info = rule.onNodeWithTag(LIST).fetchSemanticsNode().config.getOrNull(SemanticsProperties.CollectionInfo)
        return checkNotNull(info) { "list has no collection info" }.rowCount - 1
    }

    /** ARGB pixels of the window inside [bounds] (root px), drawn with the clock paused. */
    private fun pixels(bounds: Rect): IntArray {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        val origin = IntArray(2)
        rule.runOnUiThread {
            root.draw(Canvas(bitmap))
            rule.activity.findViewById<View>(android.R.id.content).getLocationInWindow(origin)
        }
        val left = (origin[0] + bounds.left).toInt().coerceIn(0, bitmap.width - 1)
        val top = (origin[1] + bounds.top).toInt().coerceIn(0, bitmap.height - 1)
        val right = (origin[0] + bounds.right).toInt().coerceIn(left + 1, bitmap.width)
        val bottom = (origin[1] + bounds.bottom).toInt().coerceIn(top + 1, bitmap.height)
        val out = IntArray((right - left) * (bottom - top))
        bitmap.getPixels(out, 0, right - left, left, top, right - left, bottom - top)
        return out
    }

    /** Share of pixels whose channels differ by more than 24 levels. */
    private fun changedShare(a: IntArray, b: IntArray): Float {
        if (a.size != b.size) return 1f
        val changed = a.indices.count { i ->
            (0..16 step 8).any { shift -> kotlin.math.abs(((a[i] shr shift) and 0xFF) - ((b[i] shr shift) and 0xFF)) > 24 }
        }
        return changed.toFloat() / a.size
    }

    /**
     * Scroll [index] into view with the clock paused and compare [tag]'s first frames with
     * the same area once any animation would have finished.
     *
     * @return The changed share for each of the first frames that show [tag].
     */
    private fun firstFramesAgainstSettled(index: Int, tag: String): List<Float> {
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag(LIST).performScrollToIndex(index)
        val frames = mutableListOf<IntArray>()
        var bounds: Rect? = null
        repeat(6) {
            rule.mainClock.advanceTimeByFrame()
            if (bounds == null && exists(tag)) bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
            bounds?.let { frames += pixels(it) }
        }
        val shown = checkNotNull(bounds) { "$tag never composed" }
        rule.mainClock.advanceTimeBy(3_000)
        val settled = pixels(shown)
        rule.mainClock.autoAdvance = true
        return frames.map { changedShare(it, settled) }
    }

    // endregion

    @Test
    fun cardsScrolledIntoViewAfterLoadAppearWithoutFading() {
        launch()
        assertTrue("the last band card starts below the fold", !exists(LAST_BAND))
        val down = firstFramesAgainstSettled(lastIndex(), LAST_BAND)
        assertTrue("band card drawn in full from its first frame: $down", down.all { it < MAX_CHANGED })
    }

    @Test
    fun headerScrolledBackIntoViewAppearsWithoutFading() {
        launch()
        rule.onNodeWithTag(LIST).performScrollToIndex(lastIndex())
        settle()
        rule.waitUntil(5_000) { settle(100); !exists(HEADER) }
        val up = firstFramesAgainstSettled(0, HEADER)
        assertTrue("header drawn in full from its first frame: $up", up.all { it < MAX_CHANGED })
    }

    private companion object {
        const val LIST = "fst.song-detail.list"
        const val HEADER = "fst.song-detail.header"
        const val LAST_BAND = "fst.song-detail.band-preview.Band_Quad"

        /** A 400 ms fade three frames in is at under a third of its opacity: most text pixels differ. */
        const val MAX_CHANGED = 0.005f
    }
}
