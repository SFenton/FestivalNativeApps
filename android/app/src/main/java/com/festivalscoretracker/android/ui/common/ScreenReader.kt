package com.festivalscoretracker.android.ui.common

import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

// region Screen reader

/**
 * Whether a screen reader's explore-by-touch (TalkBack) is on, updated live.
 *
 * Multi-column content grids fall back to one column while it is: TalkBack's linear
 * navigation only visits on-screen items and scrolls when it runs out, so when a tall card
 * in the leading column continues below the viewport while the trailing column is still on
 * screen, TalkBack moved on to the trailing column and never came back for the rest of the
 * leading card (real-TalkBack walk on the half-open book fold, 2026-09-29). The floating
 * toolbar also stops hiding on scroll.
 *
 * @return True while touch exploration is enabled.
 */
@Composable
fun rememberScreenReaderOn(): Boolean {
    val context = LocalContext.current
    val manager = remember(context) { context.getSystemService(AccessibilityManager::class.java) }
    var enabled by remember { mutableStateOf(manager?.isTouchExplorationEnabled == true) }
    DisposableEffect(manager) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

/**
 * Whether multi-column content grids and hinge splits fall back to one column: while a
 * screen reader runs ([rememberScreenReaderOn]) or at large font scales ([isLargeText]),
 * where a half-width column wrapped names a few letters per line.
 *
 * @return True when content should use one column.
 */
@Composable
fun rememberSingleColumn(): Boolean = rememberScreenReaderOn() || isLargeText()

// endregion
