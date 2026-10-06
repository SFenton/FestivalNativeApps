package com.festivalscoretracker.android.ui.songs

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.presentation.ModalCoverage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Issue #186 (`modal-shell` R10): the Shop pulse and breathe hold their still frame behind a modal. */
@RunWith(AndroidJUnit4::class)
class ShopMotionHoldTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun pulseAndBreatheHoldTheirReducedMotionFrameWhileCovered() {
        val coverage = ModalCoverage.shared
        var pulse: () -> Float = { -1f }
        var breathe: () -> Float = { -1f }
        rule.mainClock.autoAdvance = false
        rule.setContent {
            pulse = rememberShopPulse(active = true)
            breathe = rememberShopBreathe(active = true)
        }
        rule.mainClock.advanceTimeBy(500)
        assertTrue("pulse animates", pulse() in 0f..<SHOP_PULSE_PEAK)
        assertTrue("breathe animates", breathe() in 0f..<1f)
        coverage.open()
        try {
            rule.waitForIdle()
            rule.mainClock.advanceTimeBy(500)
            assertEquals(SHOP_PULSE_PEAK, pulse(), 0f)
            assertEquals(1f, breathe(), 0f)
        } finally {
            coverage.close()
        }
        rule.waitForIdle()
        val resumed = List(10) { rule.mainClock.advanceTimeBy(100); pulse() to breathe() }
        assertTrue("pulse resumes: $resumed", resumed.any { it.first < SHOP_PULSE_PEAK })
        assertTrue("breathe resumes: $resumed", resumed.any { it.second < 1f })
    }
}
