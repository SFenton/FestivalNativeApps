package com.festivalscoretracker.android.ui.settings

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.ui.common.rememberSingleColumn
import com.festivalscoretracker.android.ui.common.rememberMeasuredPx

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
 * @param keepWhenSingleColumn Report the hinge even under TalkBack or large text, for multi-column content that never collapses to one column (the Item Shop grid).
 * @return Split for this composition.
 */
@Composable
fun rememberHingeSplit(keepWhenSingleColumn: Boolean = false): HingeSplit {
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isSeparating && it.isVertical }
    var left by rememberMeasuredPx(0f)
    var width by rememberMeasuredPx(0f)
    val modifier = Modifier.onGloballyPositioned {
        left = it.positionInWindow().x
        width = it.size.width.toFloat()
    }
    // No split under TalkBack or at large text: one column, full width (rememberSingleColumn).
    val split = if (!keepWhenSingleColumn && rememberSingleColumn()) null else hinge?.let { QuickLinks.hingeSplit(left, width, it.bounds.left, it.bounds.right) }
    return HingeSplit(split, modifier)
}

// endregion
