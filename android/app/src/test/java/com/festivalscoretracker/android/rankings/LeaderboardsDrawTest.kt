package com.festivalscoretracker.android.rankings

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.ui.test.click
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeRight
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Draws the Leaderboards Rank History chart on the native canvas (every draw lambda runs). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LeaderboardsDrawTest : LeaderboardsHarness() {
    /** Draw the window into a bitmap; true when something was painted. */
    private fun draw(): Boolean {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return (0 until bitmap.height step 16).any { y -> (0 until bitmap.width step 16).any { x -> bitmap.getPixel(x, y) != 0 } }
    }

    @Test
    fun rankHistoryDrawsSelectsAndPages() {
        launch("leaderboards", selected)
        waitForTag("fst.leaderboards.rank-history.plot")
        assertTrue(draw())
        // Tap a bar: the detail card appears and the selected bar draws its outline.
        node("fst.leaderboards.rank-history.plot").performTouchInput { click(centerRight.copy(x = right - 4f)) }
        settle()
        waitForTag("fst.leaderboards.rank-history.detail")
        assertTrue(draw())
        // Swipe towards older days, then page back with the frosted pager.
        node("fst.leaderboards.rank-history.plot").performTouchInput { swipeRight() }
        settle()
        if (exists("fst.leaderboards.rank-history.back-page")) click("fst.leaderboards.rank-history.back-page")
        assertTrue(draw())
    }
}
