package com.festivalscoretracker.android.ui.shell

import android.os.Build
import android.view.RoundedCorner
import android.view.View
import androidx.annotation.RequiresApi
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.material3.DrawerDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.festivalscoretracker.android.core.shell.CornerRadii
import com.festivalscoretracker.android.core.shell.DisplayCorner
import com.festivalscoretracker.android.core.shell.DisplayCorners
import com.festivalscoretracker.android.core.shell.DrawerCornerPolicy
import com.festivalscoretracker.android.core.shell.WindowRect

// region Concentric drawer shape

/**
 * The window's display corners and where this composition sits in the window.
 *
 * @property corners Rounded display corners from the root window insets.
 * @property container The composition's (Compose view's) bounds in window pixels.
 */
internal data class WindowCorners(val corners: DisplayCorners, val container: WindowRect)

/**
 * Modal drawer sheet shape whose corners are concentric with the display corners
 * ([DrawerCornerPolicy]); [fallback] (Material's `DrawerDefaults.shape`) supplies each corner's
 * default and minimum radius.
 *
 * @property window Display corners and container bounds.
 * @property fallback Material's default drawer shape.
 */
internal data class ConcentricDrawerShape(val window: WindowCorners, val fallback: CornerBasedShape) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val rtl = layoutDirection == LayoutDirection.Rtl
        fun px(corner: CornerSize) = corner.toPx(size, density)
        val start = CornerRadii(px(fallback.topStart), px(fallback.topEnd), px(fallback.bottomEnd), px(fallback.bottomStart))
        val defaults = if (rtl) CornerRadii(start.topRight, start.topLeft, start.bottomLeft, start.bottomRight) else start
        val sheet = DrawerCornerPolicy.sheetBounds(window.container, size.width, size.height, rtl)
        val radii = DrawerCornerPolicy.radii(window.corners, sheet, defaults)
        return Outline.Rounded(
            RoundRect(
                left = 0f,
                top = 0f,
                right = size.width,
                bottom = size.height,
                topLeftCornerRadius = CornerRadius(radii.topLeft),
                topRightCornerRadius = CornerRadius(radii.topRight),
                bottomRightCornerRadius = CornerRadius(radii.bottomRight),
                bottomLeftCornerRadius = CornerRadius(radii.bottomLeft),
            ),
        )
    }
}

/**
 * The modal drawer sheet's shape: concentric with the display corners on API 31+ when the window
 * reports rounded corners (public `WindowInsets.getRoundedCorner`), else Material's
 * `DrawerDefaults.shape` unchanged.
 *
 * @return The drawer shape.
 */
@Composable
internal fun rememberConcentricDrawerShape(): Shape {
    val fallback = DrawerDefaults.shape
    val window = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) rememberWindowCorners() else null
    return remember(fallback, window) { concentricDrawerShape(window, fallback) }
}

/**
 * Pick the concentric shape or Material's fallback.
 *
 * @param window Display corners, or null when unavailable (API < 31, insets not dispatched).
 * @param fallback Material's default drawer shape.
 * @return [ConcentricDrawerShape] when a rounded corner is reported, else [fallback].
 */
internal fun concentricDrawerShape(window: WindowCorners?, fallback: Shape): Shape =
    if (window == null || window.corners.isEmpty || fallback !is CornerBasedShape) fallback else ConcentricDrawerShape(window, fallback)

/**
 * Display corners for this composition, re-read on every layout of the Compose view (rotation,
 * resize, fold posture) and configuration change.
 *
 * @return Display corners, or null until the window insets are dispatched.
 */
@RequiresApi(Build.VERSION_CODES.S)
@Composable
private fun rememberWindowCorners(): WindowCorners? {
    val view = LocalView.current
    val configuration = LocalConfiguration.current
    var corners by remember(view) { mutableStateOf<WindowCorners?>(null) }
    DisposableEffect(view, configuration) {
        val listener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> corners = readWindowCorners(view) }
        view.addOnLayoutChangeListener(listener)
        corners = readWindowCorners(view)
        onDispose { view.removeOnLayoutChangeListener(listener) }
    }
    return corners
}

/**
 * Read the root window insets' rounded corners and the view's window bounds.
 *
 * @param view The Compose view.
 * @return Display corners, or null before insets are dispatched.
 */
@RequiresApi(Build.VERSION_CODES.S)
internal fun readWindowCorners(view: View): WindowCorners? {
    val insets = view.rootWindowInsets ?: return null
    fun corner(position: Int): DisplayCorner? = insets.getRoundedCorner(position)
        ?.takeIf { it.radius > 0 && it.center.x > 0 && it.center.y > 0 }
        ?.let { DisplayCorner(it.radius.toFloat(), it.center.x.toFloat(), it.center.y.toFloat()) }
    val location = IntArray(2)
    view.getLocationInWindow(location)
    return WindowCorners(
        corners = DisplayCorners(
            topLeft = corner(RoundedCorner.POSITION_TOP_LEFT),
            topRight = corner(RoundedCorner.POSITION_TOP_RIGHT),
            bottomRight = corner(RoundedCorner.POSITION_BOTTOM_RIGHT),
            bottomLeft = corner(RoundedCorner.POSITION_BOTTOM_LEFT),
        ),
        container = WindowRect(
            left = location[0].toFloat(),
            top = location[1].toFloat(),
            right = (location[0] + view.width).toFloat(),
            bottom = (location[1] + view.height).toFloat(),
        ),
    )
}

// endregion
