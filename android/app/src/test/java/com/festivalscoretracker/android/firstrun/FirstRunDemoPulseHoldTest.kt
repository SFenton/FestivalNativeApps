package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog
import com.festivalscoretracker.android.ui.common.FestivalModalDialog
import com.festivalscoretracker.android.ui.common.LocalMotionProbe
import com.festivalscoretracker.android.ui.common.MotionProbes
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemo
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Issue #186 (`modal-shell` R10): a first-run demo's highlight pulse animates while its own
 * first-run dialog is the newest modal, holds its still frame while a newer modal covers it and
 * resumes once that modal closes. The pulse's drawn alpha is sampled through [LocalMotionProbe].
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunDemoPulseHoldTest {
    @get:Rule
    val rule = createComposeRule()

    private var alpha = Float.NaN

    /** Pulse alpha sampled over ~1 s (the pulse is a 900 ms reversing tween, 0.35 → 1). */
    private fun samples(): List<Float> = List(8) {
        rule.mainClock.advanceTimeBy(130)
        rule.waitForIdle()
        alpha
    }

    /** Steps the paused clock until [count] modals are registered (a dialog's window can take a few frames). */
    private fun awaitOpenModals(count: Int) {
        repeat(30) {
            if (ModalCoverage.shared.openCount.value == count) return
            rule.mainClock.advanceTimeBy(50)
            rule.waitForIdle()
        }
        assertEquals(count, ModalCoverage.shared.openCount.value)
    }

    private fun showTour(active: Boolean, alert: () -> Boolean = { false }) {
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalMotionProbe provides { loop, value -> if (loop == MotionProbes.FIRST_RUN_DEMO_PULSE) alpha = value }) {
                FestivalTheme {
                    FestivalModalDialog(title = "Welcome", closeTag = "fre.close", onDismissRequest = {}) {
                        FirstRunDemo("songinfo-shop-button", active = active)
                    }
                    if (alert()) {
                        FestivalAlertDialog(
                            title = "Newer modal", text = "Covers the first-run tour.", tag = "alert",
                            confirmLabel = "OK", confirmTag = "alert.ok", onConfirm = {},
                            dismissLabel = "Cancel", dismissTag = "alert.cancel", onDismissRequest = {},
                        )
                    }
                }
            }
        }
        rule.mainClock.advanceTimeBy(300)
        rule.waitForIdle()
    }

    @Test
    fun settledSlidePulsesHoldsUnderANewerModalAndResumes() {
        assertEquals("no modal leaked from another test", 0, ModalCoverage.shared.openCount.value)
        var alert by mutableStateOf(false)
        showTour(active = true) { alert }
        val pulsing = samples()
        assertTrue("the settled slide pulses while the tour is the newest modal: $pulsing", pulsing.toSet().size > 1 && pulsing.any { it < 0.9f })

        rule.runOnIdle { alert = true }
        awaitOpenModals(2)
        val held = samples()
        assertEquals("covered: the still, fully drawn frame", List(held.size) { 1f }, held)

        rule.runOnIdle { alert = false }
        awaitOpenModals(1)
        val resumed = samples()
        assertTrue("the pulse resumes once the newer modal closes: $resumed", resumed.toSet().size > 1 && resumed.any { it < 0.9f })
    }

    @Test
    fun unsettledSlideNeverPulses() {
        showTour(active = false)
        assertEquals(List(8) { 1f }, samples())
    }
}
