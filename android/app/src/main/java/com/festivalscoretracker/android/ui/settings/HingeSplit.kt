package com.festivalscoretracker.android.ui.settings

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import com.festivalscoretracker.android.core.quicklinks.QuickLinks

// region Hinge split

/**
 * A page's book-posture split.
 *
 * @property value (start pane width, hinge width) in pixels, or null without a separating vertical hinge in the page.
 * @property modifier Apply to the page root so its window position is known.
 */
class HingeSplit(val value: Pair<Float, Float>?, val modifier: Modifier)

/**
 * Observe a separating vertical hinge (Jetpack WindowManager via
 * `currentWindowAdaptiveInfo`, never product checks) relative to the page.
 *
 * @return Split for this composition.
 */
@Composable
fun rememberHingeSplit(): HingeSplit {
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    var left by remember { mutableFloatStateOf(0f) }
    var width by remember { mutableFloatStateOf(0f) }
    val modifier = Modifier.onGloballyPositioned {
        left = it.positionInWindow().x
        width = it.size.width.toFloat()
    }
    return HingeSplit(hinge?.let { QuickLinks.hingeSplit(left, width, it.bounds.left, it.bounds.right) }, modifier)
}

// endregion
