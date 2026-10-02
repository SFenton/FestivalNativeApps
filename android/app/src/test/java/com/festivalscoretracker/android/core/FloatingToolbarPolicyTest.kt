package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.FloatingToolbarLift
import com.festivalscoretracker.android.core.shell.FloatingToolbarMinimizer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Floating toolbar minimize-on-scroll and keyboard lift (issue #84). */
class FloatingToolbarPolicyTest {
    @Test
    fun scrollingDownPastTheThresholdMinimizes() {
        val minimizer = FloatingToolbarMinimizer(thresholdPx = 30f)
        assertFalse(minimizer.onScroll(-10f))
        assertFalse(minimizer.onScroll(-19f))
        assertTrue(minimizer.onScroll(-1f))
        // Further scrolling down keeps it minimized.
        assertTrue(minimizer.onScroll(-500f))
    }

    @Test
    fun scrollingBackUpPastTheThresholdExpands() {
        val minimizer = FloatingToolbarMinimizer(thresholdPx = 30f)
        minimizer.onScroll(-100f)
        assertTrue(minimizer.minimized)
        assertTrue(minimizer.onScroll(29f))
        assertFalse(minimizer.onScroll(1f))
    }

    @Test
    fun directionChangesRestartTheTravel() {
        val minimizer = FloatingToolbarMinimizer(thresholdPx = 30f)
        // Jitter that never travels 30 px one way never minimizes.
        repeat(10) {
            assertFalse(minimizer.onScroll(-20f))
            assertFalse(minimizer.onScroll(15f))
        }
        minimizer.onScroll(-40f)
        assertTrue(minimizer.minimized)
        repeat(10) {
            assertTrue(minimizer.onScroll(20f))
            assertTrue(minimizer.onScroll(-15f))
        }
    }

    @Test
    fun zeroStepsAndDisallowedScrollsKeepOrExpand() {
        val minimizer = FloatingToolbarMinimizer(thresholdPx = 30f)
        minimizer.onScroll(-40f)
        assertTrue(minimizer.onScroll(0f))
        // TalkBack on or search open: never minimized.
        assertFalse(minimizer.onScroll(-400f, allowed = false))
        assertFalse(minimizer.minimized)
    }

    @Test
    fun reachingTheTopExpandsAtOnce() {
        val minimizer = FloatingToolbarMinimizer(thresholdPx = 30f)
        minimizer.onScroll(-200f)
        assertFalse(minimizer.expand())
        // Travel was reset too: a short scroll down does not minimize again.
        assertFalse(minimizer.onScroll(-29f))
        assertEquals(24, FloatingToolbarMinimizer.THRESHOLD_DP)
    }

    @Test
    fun keyboardLiftCountsOnlyTheHeightAboveTheContentBottom() {
        // Keyboard hidden: no lift.
        assertEquals(0, FloatingToolbarLift.liftPx(imeBottomPx = 0, gapBelowContentPx = 240))
        // Keyboard shorter than the bottom bar strip: still no lift.
        assertEquals(0, FloatingToolbarLift.liftPx(imeBottomPx = 200, gapBelowContentPx = 240))
        assertEquals(760, FloatingToolbarLift.liftPx(imeBottomPx = 1000, gapBelowContentPx = 240))
        // Content reaching the window bottom (no bar): the full keyboard height.
        assertEquals(1000, FloatingToolbarLift.liftPx(imeBottomPx = 1000, gapBelowContentPx = 0))
        assertEquals(1000, FloatingToolbarLift.liftPx(imeBottomPx = 1000, gapBelowContentPx = -5))
    }
}
