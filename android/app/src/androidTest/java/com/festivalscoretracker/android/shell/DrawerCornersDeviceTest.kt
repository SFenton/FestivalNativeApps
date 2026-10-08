package com.festivalscoretracker.android.shell

import android.os.Build
import android.view.RoundedCorner
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.shell.ConcentricDrawerShape
import com.festivalscoretracker.android.ui.shell.rememberConcentricDrawerShape
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The modal drawer's corners follow the display corners the system reports through public
 * `WindowInsets.getRoundedCorner` (issue #55). Run with `device.py test
 * com.festivalscoretracker.android.shell.DrawerCornersDeviceTest --avd FST_Phone`; skipped on a
 * display without rounded corners, an edge-inset window, a radius no larger than Material's
 * fallback, or below API 31.
 */
@RunWith(AndroidJUnit4::class)
class DrawerCornersDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun edgeAttachedStartCornersMatchTheReportedDisplayRadius() {
        assumeTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
        var shape: Shape? = null
        rule.setContent { Box(Modifier.fillMaxSize()) { shape = rememberConcentricDrawerShape() } }
        rule.waitForIdle()
        val insets = rule.activity.window.decorView.rootWindowInsets
        val topLeft = insets.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT)
        val bottomLeft = insets.getRoundedCorner(RoundedCorner.POSITION_BOTTOM_LEFT)
        assumeTrue("display reports no rounded corners", topLeft != null && topLeft.radius > 0)
        rule.waitUntil(5_000) { shape is ConcentricDrawerShape }
        val drawn = shape as ConcentricDrawerShape
        // The test activity is edge-to-edge (target SDK 35+), so the sheet's start corners touch the display corners.
        assumeTrue("window is not edge attached", drawn.window.container.top == 0f)
        val decor = rule.activity.window.decorView
        val materialEnd = 16f * rule.activity.resources.displayMetrics.density
        assumeTrue("display corner is no larger than the Material fallback", topLeft!!.radius.toFloat() > materialEnd)
        val outline = drawn.createOutline(
            Size(decor.width * 0.8f, decor.height.toFloat()),
            LayoutDirection.Ltr,
            Density(rule.activity),
        ) as Outline.Rounded
        assertEquals(topLeft!!.radius.toFloat(), outline.roundRect.topLeftCornerRadius.x)
        assertEquals(bottomLeft!!.radius.toFloat(), outline.roundRect.bottomLeftCornerRadius.x)
        // The end corners sit far from the right display corners and keep Material's 16 dp.
        assertEquals(materialEnd, outline.roundRect.topRightCornerRadius.x, 0.5f)
        assertTrue(outline.roundRect.bottomRightCornerRadius.x < topLeft.radius)
    }
}
