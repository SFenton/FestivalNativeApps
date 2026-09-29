package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.LoadGatePhase
import com.festivalscoretracker.android.core.shell.LoadGatePolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Shared load gate phases (batch 6.41, web `LoadPhase`). */
class LoadGatePolicyTest {
    @Test
    fun readyDataSkipsTheSpinner() {
        assertEquals(LoadGatePhase.ContentIn, LoadGatePolicy.initial(ready = true))
        assertEquals(LoadGatePhase.Loading, LoadGatePolicy.initial(ready = false))
    }

    @Test
    fun spinnerFadesOutBeforeContent() {
        val out = LoadGatePolicy.onReady(LoadGatePhase.Loading, ready = true, reduceMotion = false)
        assertEquals(LoadGatePhase.SpinnerOut, out)
        assertEquals(LoadGatePhase.ContentIn, LoadGatePolicy.afterFade(out))
        // Reduce Motion: straight to content.
        assertEquals(LoadGatePhase.ContentIn, LoadGatePolicy.onReady(LoadGatePhase.Loading, ready = true, reduceMotion = true))
    }

    @Test
    fun reloadsKeepShownContentButRestartAFadingSpinner() {
        assertEquals(LoadGatePhase.ContentIn, LoadGatePolicy.onReady(LoadGatePhase.ContentIn, ready = false, reduceMotion = false))
        assertEquals(LoadGatePhase.Loading, LoadGatePolicy.onReady(LoadGatePhase.SpinnerOut, ready = false, reduceMotion = false))
        assertEquals(LoadGatePhase.Loading, LoadGatePolicy.onReady(LoadGatePhase.Loading, ready = false, reduceMotion = false))
        assertEquals(LoadGatePhase.SpinnerOut, LoadGatePolicy.onReady(LoadGatePhase.SpinnerOut, ready = true, reduceMotion = false))
        assertEquals(LoadGatePhase.ContentIn, LoadGatePolicy.onReady(LoadGatePhase.ContentIn, ready = true, reduceMotion = false))
        assertEquals(LoadGatePhase.Loading, LoadGatePolicy.afterFade(LoadGatePhase.Loading))
    }

    @Test
    fun entranceOnlyAnimatesAfterASpinner() {
        assertTrue(LoadGatePolicy.animatesEntrance(sawSpinner = true, reduceMotion = false))
        assertFalse(LoadGatePolicy.animatesEntrance(sawSpinner = false, reduceMotion = false))
        assertFalse(LoadGatePolicy.animatesEntrance(sawSpinner = true, reduceMotion = true))
    }
}
