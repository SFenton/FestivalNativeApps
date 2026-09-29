package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

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
