package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.AccordionMotion
import com.festivalscoretracker.android.core.shell.AccordionStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Accordion sequence rules (issue #561, `load-transition` R10). */
class AccordionMotionTest {
    @Test
    fun openingGrowsFirstThenFadesInOnceTheHeightIsDone() {
        val steps = AccordionMotion.opening(reduceMotion = false)
        assertEquals(listOf(AccordionStep.Kind.Height, AccordionStep.Kind.Fade), steps.map { it.kind })
        val height = AccordionMotion.step(steps, AccordionStep.Kind.Height)!!
        val fade = AccordionMotion.step(steps, AccordionStep.Kind.Fade)!!
        assertEquals(0, height.delayMillis)
        assertEquals(height.endMillis, fade.delayMillis)
    }

    @Test
    fun closingFadesOutFirstThenCollapsesOnceTheContentIsGone() {
        val steps = AccordionMotion.closing(reduceMotion = false)
        assertEquals(listOf(AccordionStep.Kind.Fade, AccordionStep.Kind.Height), steps.map { it.kind })
        val fade = AccordionMotion.step(steps, AccordionStep.Kind.Fade)!!
        val height = AccordionMotion.step(steps, AccordionStep.Kind.Height)!!
        assertEquals(0, fade.delayMillis)
        assertEquals(fade.endMillis, height.delayMillis)
    }

    @Test
    fun bothWaysTakeTheWebCollapseLengthWithQuickSteps() {
        // Web `CollapseOnExit` (300 ms) built from `QUICK_FADE_MS` (150 ms) steps; Material 3 "Small utility transition | 300ms".
        assertEquals(150, AccordionMotion.HEIGHT_MS)
        assertEquals(150, AccordionMotion.FADE_MS)
        assertEquals(300, AccordionMotion.totalMillis(AccordionMotion.opening(false)))
        assertEquals(300, AccordionMotion.totalMillis(AccordionMotion.closing(false)))
    }

    @Test
    fun reducedMotionOpensAndClosesAtOnce() {
        assertTrue(AccordionMotion.opening(reduceMotion = true).isEmpty())
        assertTrue(AccordionMotion.closing(reduceMotion = true).isEmpty())
        assertEquals(0, AccordionMotion.totalMillis(AccordionMotion.opening(true)))
        assertEquals(null, AccordionMotion.step(AccordionMotion.closing(true), AccordionStep.Kind.Height))
    }
}
