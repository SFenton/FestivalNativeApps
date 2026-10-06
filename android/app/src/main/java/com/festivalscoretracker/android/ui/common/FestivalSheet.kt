package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.nav.SheetHinge

// region Sheet top

/** Gap between the status bar / camera cutout and a fully expanded sheet's top edge. */
const val SHEET_TOP_GAP_DP = 8

/**
 * Keep a `ModalBottomSheet` below the status bar and camera cutout (batch 6.28).
 *
 * Material 3's expanded modal sheet is drawn to the very top of the window and only pads its
 * content (so the drag handle sits below the camera while the sheet surface covers the status
 * bar). Pass this as the sheet's `modifier`: the surface then stops [SHEET_TOP_GAP_DP] below the
 * status bar, and because the padding consumes the top insets the sheet's own content insets
 * do not add the status bar a second time.
 *
 * @return Modifier for the sheet surface.
 */
@Composable
fun Modifier.festivalSheetTop(): Modifier = this
    .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top))
    .padding(top = SHEET_TOP_GAP_DP.dp)

// endregion

// region Sheet hinge side

/**
 * The shell's window posture, already collected by `FestivalApp`, so a sheet opened on a
 * half-open fold sees the hinge on its first frame. Null outside the shell, where
 * [festivalSheetHingeSide] reads the posture itself.
 */
val LocalShellPosture = staticCompositionLocalOf<Posture?> { null }

/**
 * The window posture to lay out against: the shell's ([LocalShellPosture]) when inside it,
 * otherwise collected here. Pages must read hinges through this, not
 * `currentWindowAdaptiveInfo()`. That collector starts with an empty hinge list, so a
 * destination recomposed on Back would draw one frame as if unfolded (issue #185).
 *
 * @return The current window posture.
 */
@Composable
fun shellPosture(): Posture = LocalShellPosture.current ?: currentWindowAdaptiveInfo().windowPosture

/**
 * Keep a `ModalBottomSheet` on one side of a separating fold or hinge ([SheetHinge]): the
 * leading (or wider) half in book posture, the lower half in tabletop posture. Material
 * centres the sheet across the whole window, which on a half-open foldable puts its rows
 * and buttons across the hinge. Call it from the sheet's caller (the activity window), not
 * from inside the sheet.
 *
 * @return Modifier for the sheet surface (no-op without a separating hinge).
 */
@Composable
fun Modifier.festivalSheetHingeSide(): Modifier {
    val posture = shellPosture()
    val hinge = posture.hingeList.firstOrNull { it.isSeparating } ?: return this
    val density = LocalDensity.current
    val root = LocalView.current.rootView
    val sheetTop = WindowInsets.statusBars.union(WindowInsets.displayCutout).getTop(density) + with(density) { SHEET_TOP_GAP_DP.dp.toPx() }
    val insets = SheetHinge.insets(
        windowWidthPx = root.width.toFloat(),
        windowHeightPx = root.height.toFloat(),
        left = hinge.bounds.left,
        right = hinge.bounds.right,
        top = hinge.bounds.top,
        bottom = hinge.bounds.bottom,
        vertical = hinge.isVertical,
        separating = hinge.isSeparating,
        rtl = LocalLayoutDirection.current == LayoutDirection.Rtl,
        sheetTopPx = sheetTop,
        gapPx = with(density) { SHEET_TOP_GAP_DP.dp.toPx() },
    )
    return with(density) { this@festivalSheetHingeSide.absolutePadding(left = insets.left.toDp(), right = insets.right.toDp(), top = insets.top.toDp(), bottom = insets.bottom.toDp()) }
}

// endregion
