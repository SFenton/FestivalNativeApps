package com.festivalscoretracker.android.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import com.festivalscoretracker.android.core.rankings.FooterFade
import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import com.festivalscoretracker.android.ui.theme.rememberSystemHighContrastText

// region Scroll edge fade drawing

/**
 * Whether every scroll edge is a hard cut instead of a ramp ([ScrollEdgeFade.isHardEdge], R7):
 * Increase Contrast (the app toggle or the system contrast level), system High contrast text,
 * Reduce Transparency and Reduce Motion (the app toggle or system Remove animations). Followed
 * live, so flipping a system switch while a list is open updates its edges. The one R7 switch for
 * the pinned-title fade and the bottom-chrome fade.
 *
 * @return True for a hard edge.
 */
@Composable
fun rememberScrollEdgeHardEdge(): Boolean {
    val accessibility = LocalFestivalAccessibility.current
    val highContrastText = rememberSystemHighContrastText()
    return ScrollEdgeFade.isHardEdge(
        increaseContrast = accessibility.increaseContrast,
        highContrastText = highContrastText,
        reduceTransparency = accessibility.reduceTransparency,
        removeAnimations = accessibility.reduceMotion,
    )
}

/**
 * Masks the content already drawn (on an offscreen layer) with the linear scroll-edge ramp: fully
 * clear at [clearY], fully drawn at [opaqueY] and untouched beyond it (`BlendMode.DstIn`, R2, R3).
 * Works in either direction: a top edge ramps down from its cut, a bottom edge up from it. Draws
 * nothing when the two coincide (a hard edge or no ramp yet). The only scroll-edge alpha mask on
 * Android (scroll-edge R1, guard `android-dstin`).
 *
 * @param clearY Where content is fully clear (the edge), in px from the top.
 * @param opaqueY Where content is fully drawn again, in px from the top.
 */
fun DrawScope.drawScrollEdgeRamp(clearY: Float, opaqueY: Float) {
    if (clearY == opaqueY || clearY.isNaN() || opaqueY.isNaN()) return
    val top = minOf(clearY, opaqueY)
    drawRect(
        Brush.verticalGradient(listOf(Color.Transparent, Color.Black), startY = clearY, endY = opaqueY),
        topLeft = Offset(0f, top),
        size = Size(size.width, maxOf(clearY, opaqueY) - top),
        blendMode = BlendMode.DstIn,
    )
}

/**
 * Hides content beneath floating bottom chrome (the leaderboards' "your rank" footer and pager)
 * and fades it out over the linear ramp ending at the chrome's top edge ([FooterFade],
 * `useScrollFade`), so the chrome floats over the page background with nothing showing behind or
 * between it. A zero-depth edge (end of the list, or a hard edge, R7) still clears everything
 * below the cut. On an offscreen layer; drawing only, so hit testing, semantics and TalkBack order
 * are unchanged. Without an edge it draws nothing extra and skips the offscreen layer.
 *
 * @param edge Reads the current edge (draw phase only), or null for none.
 * @return Drawing modifier.
 */
fun Modifier.bottomChromeEdgeFade(edge: () -> FooterFade?): Modifier = this
    .graphicsLayer { compositingStrategy = if (edge() != null) CompositingStrategy.Offscreen else CompositingStrategy.Auto }
    .drawWithContent {
        drawContent()
        val fade = edge() ?: return@drawWithContent
        drawScrollEdgeRamp(clearY = fade.cut, opaqueY = (fade.cut - fade.depth).coerceAtLeast(0f))
        drawRect(Color.Transparent, topLeft = Offset(0f, fade.cut), size = Size(size.width, size.height - fade.cut), blendMode = BlendMode.Clear)
    }

// endregion
