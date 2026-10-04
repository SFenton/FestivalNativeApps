package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.format.ScoreAccuracyBadge
import com.festivalscoretracker.android.core.format.ScoreAccuracyBadge.Kind
import com.festivalscoretracker.android.core.format.ScoreFormatting
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Score-accuracy control policy (`.agents/controls/score-accuracy/spec.md`), one test per state. */
class ScoreAccuracyBadgeTest {
    private fun badge(accuracy: Double?, fc: Boolean?) = ScoreAccuracyBadge.of(accuracy, fc, Locale.US)

    @Test
    fun absentWithoutAccuracyOrFullCombo() {
        assertNull(badge(null, null))
        assertNull(badge(null, false))
    }

    @Test
    fun gradedLowMidHighUseTheWebRamp() {
        val low = badge(0.0, false)!!
        assertEquals(Kind.Graded, low.kind)
        assertEquals("0%", low.text)
        assertEquals("Accuracy 0%", low.announcement)
        assertEquals(0xDC2828, low.tint)
        val mid = badge(500_000.0, false)!!
        assertEquals("50%", mid.text)
        // Web midpoint: round((220+46)/2, (40+204)/2, (40+113)/2) = (133,122,77).
        assertEquals(0x857A4D, mid.tint)
        val high = badge(987_654.0, null)!!
        assertEquals("98.8%", high.text)
        assertEquals("Accuracy 98.8%", high.announcement)
        assertEquals(ScoreFormatting.accuracyTint(987_654.0), high.tint)
        assertEquals(0x2ECC71, badge(1_000_000.0, false)!!.tint)
        assertFalse(high.isGold)
        assertEquals(0.25f, ScoreAccuracyBadge.GRADED_TINT_ALPHA)
    }

    @Test
    fun fullComboShowsThePercentInGoldAndSaysFullCombo() {
        val fc = badge(1_000_000.0, true)!!
        assertEquals(Kind.FullCombo, fc.kind)
        assertEquals("100%", fc.text)
        assertEquals("Full combo, accuracy 100%", fc.announcement)
        assertNull(fc.tint)
        assertTrue(fc.isGold)
    }

    @Test
    fun fullComboWithoutAccuracyNeverInventsZero() {
        val fc = badge(null, true)!!
        assertEquals(Kind.FullComboNoAccuracy, fc.kind)
        assertEquals("FC", fc.text)
        assertEquals("Full combo; accuracy unavailable", fc.announcement)
        assertTrue(fc.isGold)
        assertEquals(Kind.FullComboNoAccuracy, badge(Double.NaN, true)!!.kind)
    }

    @Test
    fun invalidAccuracyIsRejectedNotTinted() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY).forEach {
            val invalid = badge(it, false)!!
            assertEquals(Kind.Invalid, invalid.kind)
            assertEquals("—", invalid.text)
            assertEquals("Accuracy unavailable", invalid.announcement)
            assertNull(invalid.tint)
            assertFalse(invalid.isGold)
        }
    }

    @Test
    fun outOfRangeKeepsItsNumberAndClampsOnlyTheTint() {
        val over = badge(1_050_000.0, false)!!
        assertEquals("105%", over.text)
        assertEquals(0x2ECC71, over.tint)
        val under = badge(-5_000.0, false)!!
        assertEquals("-0.5%", under.text)
        assertEquals(0xDC2828, under.tint)
        // FC is never inferred from a perfect number.
        assertEquals(Kind.Graded, badge(1_000_000.0, false)!!.kind)
    }
}
