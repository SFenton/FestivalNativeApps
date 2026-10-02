package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.LoadSwapPhase
import com.festivalscoretracker.android.core.shell.LoadSwapPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Shared load/reload swap phases (issue #71, web `useLoadPhase`). */
class LoadSwapPolicyTest {
    @Test
    fun webTimings() {
        assertEquals(300, LoadSwapPolicy.CONTENT_OUT_MS)
        assertEquals(500, LoadSwapPolicy.SPINNER_FADE_MS)
    }

    @Test
    fun readyDataSkipsTheSpinnerOnFirstComposition() {
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.initial(ready = true))
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.initial(ready = false))
    }

    @Test
    fun firstLoadFadesTheSpinnerBeforeContent() {
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.onInputs(LoadSwapPhase.Loading, ready = false, swapped = false, reduceMotion = false))
        val out = LoadSwapPolicy.onInputs(LoadSwapPhase.Loading, ready = true, swapped = true, reduceMotion = false)
        assertEquals(LoadSwapPhase.SpinnerOut, out)
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.afterSpinnerFade(out))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.afterSpinnerFade(LoadSwapPhase.ContentIn))
    }

    @Test
    fun reloadFadesContentOutThenShowsTheSpinner() {
        assertEquals(LoadSwapPhase.ContentOut, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, ready = false, swapped = false, reduceMotion = false))
        // The fade-out finishes even if the data lands meanwhile.
        assertEquals(LoadSwapPhase.ContentOut, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentOut, ready = true, swapped = true, reduceMotion = false))
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.afterContentOut(ready = false, reduceMotion = false))
    }

    @Test
    fun cachedSwapStillRunsTheWholeCycle() {
        assertEquals(LoadSwapPhase.ContentOut, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, ready = true, swapped = true, reduceMotion = false))
        assertEquals(LoadSwapPhase.SpinnerOut, LoadSwapPolicy.afterContentOut(ready = true, reduceMotion = false))
    }

    @Test
    fun sameSelectionUpdatesStayInPlace() {
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, ready = true, swapped = false, reduceMotion = false))
    }

    @Test
    fun aNewerReloadWhileTheSpinnerFadesBringsItBack() {
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.onInputs(LoadSwapPhase.SpinnerOut, ready = false, swapped = true, reduceMotion = false))
        assertEquals(LoadSwapPhase.SpinnerOut, LoadSwapPolicy.onInputs(LoadSwapPhase.SpinnerOut, ready = true, swapped = true, reduceMotion = false))
    }

    @Test
    fun reduceMotionSwapsAtOnce() {
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, ready = false, swapped = false, reduceMotion = true))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentIn, ready = true, swapped = true, reduceMotion = true))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.onInputs(LoadSwapPhase.Loading, ready = true, swapped = true, reduceMotion = true))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.onInputs(LoadSwapPhase.SpinnerOut, ready = true, swapped = true, reduceMotion = true))
        assertEquals(LoadSwapPhase.Loading, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentOut, ready = false, swapped = false, reduceMotion = true))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.onInputs(LoadSwapPhase.ContentOut, ready = true, swapped = true, reduceMotion = true))
        assertEquals(LoadSwapPhase.ContentIn, LoadSwapPolicy.afterContentOut(ready = true, reduceMotion = true))
    }

    @Test
    fun entranceOnlyAfterTheSpinnerAndNotUnderReduceMotion() {
        assertTrue(LoadSwapPolicy.animatesEntrance(sawSpinner = true, reduceMotion = false))
        assertFalse(LoadSwapPolicy.animatesEntrance(sawSpinner = false, reduceMotion = false))
        assertFalse(LoadSwapPolicy.animatesEntrance(sawSpinner = true, reduceMotion = true))
    }
}
