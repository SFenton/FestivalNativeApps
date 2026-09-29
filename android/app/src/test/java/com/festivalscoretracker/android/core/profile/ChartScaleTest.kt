package com.festivalscoretracker.android.core.profile

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test

/** [ChartScale] against values `recharts-scale` produces for the same inputs. */
class ChartScaleTest {
    private fun assertTicks(expected: List<Double>, actual: List<Double>) {
        assertEquals(expected.size, actual.size)
        expected.zip(actual).forEach { (e, a) -> assertEquals(e, a, 1e-9) }
    }

    @Test
    fun niceTicksRoundTheDataRangeOutwards() {
        // A Total Score value axis ([0, auto]): SFentonX Lead, ~104.8M.
        assertTicks(listOf(0.0, 30e6, 60e6, 90e6, 120e6), ChartScale.niceTicks(0.0, 104_800_281.0))
        assertTicks(listOf(0.0, 0.25, 0.5, 0.75, 1.0), ChartScale.niceTicks(0.0, 0.93))
        assertTicks(listOf(-10.0, -8.0, -6.0, -4.0, -2.0), ChartScale.niceTicks(-10.0, -2.0))
        assertTicks(listOf(0.0, 2_500.0, 5_000.0, 7_500.0, 10_000.0), ChartScale.niceTicks(10_000.0, 0.0))
        val axis = ChartScale.nice(0.0, 104_800_281.0)
        assertEquals(120e6, axis.max, 0.0)
        assertEquals(0.5, axis.fraction(60e6), 1e-9)
    }

    @Test
    fun singleValueTicksSurroundTheValue() {
        assertTicks(listOf(0.0, 1.0, 2.0, 3.0, 4.0), ChartScale.niceTicks(0.0, 0.0))
        assertTicks(listOf(0.3, 0.4, 0.5, 0.6, 0.7), ChartScale.niceTicks(0.5, 0.5))
        assertTicks(listOf(0.0, 1.0, 2.0, 3.0, 4.0), ChartScale.niceTicks(2.5, 2.5))
        assertTicks(listOf(5.0, 6.0, 7.0, 8.0, 9.0), ChartScale.niceTicks(7.0, 7.0, allowDecimals = false))
        assertTicks(listOf(5.0, 6.0, 7.0, 8.0, 9.0), ChartScale.niceTicks(7.0, 7.0))
    }

    @Test
    fun fixedDomainKeepsItsBoundsAndEndsOnTheMaximum() {
        // Rank axis: getRankHistoryDomain [9, 21] with allowDecimals=false.
        assertTicks(listOf(9.0, 12.0, 15.0, 18.0, 21.0), ChartScale.fixedDomainTicks(9.0, 21.0, allowDecimals = false))
        assertTicks(listOf(6.0, 10.0, 14.0, 18.0, 22.0), ChartScale.fixedDomainTicks(6.0, 22.0, allowDecimals = false))
        assertTicks(listOf(1.0, 2.0, 3.0, 4.0), ChartScale.fixedDomainTicks(1.0, 4.0, allowDecimals = false))
        assertTicks(listOf(0.0, 0.25, 0.5, 0.75, 1.0), ChartScale.fixedDomainTicks(0.0, 1.0))
        assertTicks(listOf(4.0), ChartScale.fixedDomainTicks(4.0, 4.0))
        val axis = ChartScale.fixed(4.0, 4.0)
        assertEquals(0.5, axis.fraction(4.0), 0.0)
        assertEquals(ChartScale.Axis(9.0, 21.0, listOf(9.0, 12.0, 15.0, 18.0, 21.0)), ChartScale.fixed(21.0, 9.0, allowDecimals = false))
    }

    @Test
    fun stepsFollowTheDigitCount() {
        assertEquals(1, ChartScale.digitCount(BigDecimal.ZERO))
        assertEquals(0, ChartScale.digitCount(BigDecimal("0.3")))
        assertEquals(-1, ChartScale.digitCount(BigDecimal("0.03")))
        assertEquals(3, ChartScale.digitCount(BigDecimal("100.0")))
        assertEquals(BigDecimal.ZERO, ChartScale.formatStep(BigDecimal.ZERO, true, 0))
        assertEquals(0, BigDecimal("0.3").compareTo(ChartScale.formatStep(BigDecimal("0.3"), true, 0)))
        assertEquals(0, BigDecimal.ONE.compareTo(ChartScale.formatStep(BigDecimal("0.3"), false, 0)))
        assertEquals(0, BigDecimal("3").compareTo(ChartScale.formatStep(BigDecimal("3"), true, 0)))
    }
}
