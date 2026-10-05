package com.festivalscoretracker.android.ui

import android.view.RoundedCorner
import android.view.View
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DrawerDefaults
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.shell.DisplayCorner
import com.festivalscoretracker.android.core.shell.DisplayCorners
import com.festivalscoretracker.android.core.shell.WindowRect
import com.festivalscoretracker.android.ui.shell.ConcentricDrawerShape
import com.festivalscoretracker.android.ui.shell.WindowCorners
import com.festivalscoretracker.android.ui.shell.concentricDrawerShape
import com.festivalscoretracker.android.ui.shell.readWindowCorners
import com.festivalscoretracker.android.ui.shell.rememberConcentricDrawerShape
import com.festivalscoretracker.android.ui.shell.windowCorners
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The modal drawer's concentric corner shape (issue #55) and its Material fallback. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class DrawerShapeTest {
    @get:Rule
    val rule = createComposeRule()

    private val density = Density(2.625f)
    private val material = RoundedCornerShape(topStart = 0.dp, topEnd = 16.dp, bottomEnd = 16.dp, bottomStart = 0.dp)
    private val phone = WindowCorners(
        corners = DisplayCorners(
            topLeft = DisplayCorner(132f, 132f, 132f),
            topRight = DisplayCorner(132f, 948f, 132f),
            bottomRight = DisplayCorner(132f, 948f, 2292f),
            bottomLeft = DisplayCorner(132f, 132f, 2292f),
        ),
        container = WindowRect(0f, 0f, 1080f, 2424f),
    )

    private fun radii(shape: Shape, direction: LayoutDirection): List<Float> {
        val outline = shape.createOutline(Size(945f, 2424f), direction, density) as Outline.Rounded
        val r = outline.roundRect
        return listOf(r.topLeftCornerRadius.x, r.topRightCornerRadius.x, r.bottomRightCornerRadius.x, r.bottomLeftCornerRadius.x)
    }

    @Test
    fun startCornersFollowTheDisplayAndEndCornersKeepMaterialLarge() {
        val shape = ConcentricDrawerShape(phone, material)
        assertEquals(listOf(132f, 42f, 42f, 132f), radii(shape, LayoutDirection.Ltr))
        assertEquals(listOf(42f, 132f, 132f, 42f), radii(shape, LayoutDirection.Rtl))
    }

    @Test
    fun noReportedCornerOrNoCornerBasedDefaultKeepsMaterialShape() {
        assertSame(material, concentricDrawerShape(null, material))
        assertSame(material, concentricDrawerShape(phone.copy(corners = DisplayCorners()), material))
        assertSame(RectangleShape, concentricDrawerShape(phone, RectangleShape))
        assertEquals(ConcentricDrawerShape(phone, material), concentricDrawerShape(phone, material))
    }

    @Test
    fun withoutDisplayCornersTheSheetUsesDrawerDefaultsShape() {
        // Robolectric reports no rounded display corners: the drawer keeps Material's shape.
        lateinit var resolved: Shape
        lateinit var expected: Shape
        rule.setContent {
            expected = DrawerDefaults.shape
            resolved = rememberConcentricDrawerShape()
        }
        rule.waitForIdle()
        assertTrue(resolved !is ConcentricDrawerShape)
        assertEquals(expected, resolved)
    }

    // Not WindowInsets.Builder: on this SDK its setRoundedCorner mutates the shared
    // RoundedCorners.NO_ROUNDED_CORNERS, which leaks the corners into every later window in the JVM.
    private fun insets(radius: Int, centers: Map<Int, Pair<Int, Int>>): (Int) -> RoundedCorner? {
        val corners = centers.mapValues { (position, center) -> RoundedCorner(position, radius, center.first, center.second) }
        return { position -> corners[position] }
    }

    @Test
    fun reportedDisplayCornersMapToTheConcentricShape() {
        // FST_Phone (Pixel 9) as `dumpsys window` reports it (issue #163 validation).
        val reported = insets(
            132,
            mapOf(
                RoundedCorner.POSITION_TOP_LEFT to (132 to 132),
                RoundedCorner.POSITION_TOP_RIGHT to (948 to 132),
                RoundedCorner.POSITION_BOTTOM_RIGHT to (948 to 2292),
                RoundedCorner.POSITION_BOTTOM_LEFT to (132 to 2292),
            ),
        )
        val window = windowCorners(reported, phone.container)
        assertEquals(phone, window)
        assertEquals(listOf(132f, 42f, 42f, 132f), radii(concentricDrawerShape(window, material), LayoutDirection.Ltr))
    }

    @Test
    fun zeroRadiusCornersAreSquareSoTheSheetKeepsMaterialShape() {
        // FST_Tablet (Pixel Tablet) reports every corner as radius 0 at (0, 0); a missing corner is null.
        val tablet = windowCorners(insets(0, mapOf(RoundedCorner.POSITION_TOP_LEFT to (0 to 0), RoundedCorner.POSITION_BOTTOM_LEFT to (0 to 0))), phone.container)
        assertTrue(tablet.corners.isEmpty)
        assertSame(material, concentricDrawerShape(tablet, material))
        val unset = windowCorners(insets(40, mapOf(RoundedCorner.POSITION_TOP_LEFT to (0 to 40))), phone.container)
        assertNull(unset.corners.topLeft)
    }

    @Test
    fun aViewWithoutWindowInsetsReportsNoCorners() {
        assertNull(readWindowCorners(View(ApplicationProvider.getApplicationContext())))
    }
}
