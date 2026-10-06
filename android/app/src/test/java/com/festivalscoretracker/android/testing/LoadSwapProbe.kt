package com.festivalscoretracker.android.testing

import android.os.Looper
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import org.robolectric.Shadows.shadowOf

/**
 * Runs [action] (a semantics action, which needs no frames) with the Compose clock paused, then
 * steps the clock frame by frame through a load swap and reports whether the node tagged
 * [spinner] showed. Even a reload served at once fades the old content out and shows the
 * spinner (load-transition R2, issue #71), so a hard cut fails this probe.
 *
 * @param spinner Test tag of the swap's spinner.
 * @param frames 32 ms frames to step (the default covers the 300 ms fade-out and 500 ms spinner fade).
 * @param beforeSpinner Check run on every frame until the spinner first shows (the fade-out).
 * @param action Trigger of the reload.
 * @return Whether the spinner was composed during the swap.
 */
fun ComposeContentTestRule.spinnerShowsDuring(spinner: String, frames: Int = 80, beforeSpinner: () -> Unit = {}, action: () -> Unit): Boolean {
    mainClock.autoAdvance = false
    try {
        action()
        var saw = false
        repeat(frames) {
            mainClock.advanceTimeBy(32)
            shadowOf(Looper.getMainLooper()).idle()
            if (onAllNodesWithTag(spinner, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()) saw = true
            if (!saw) beforeSpinner()
        }
        return saw
    } finally {
        mainClock.autoAdvance = true
    }
}
