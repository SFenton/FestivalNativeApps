package com.festivalscoretracker.android.core.profile

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import kotlin.math.ceil

// region Axis ticks

/**
 * The web charts' axis ticks, ported from `recharts-scale` (the library Recharts uses
 * for every numeric `YAxis`), so native charts label and scale their axes exactly
 * like the web: "nice" ticks that round the data range outwards for an automatic
 * domain (`getNiceTickValues`), and evenly stepped ticks inside an explicit domain
 * (`getTickValuesFixedDomain`). Arithmetic uses [BigDecimal] like the library's
 * `decimal.js`, so steps such as 0.3 never pick up binary rounding error.
 */
object ChartScale {
    /** Recharts' default `YAxis` `tickCount`. */
    const val DEFAULT_TICK_COUNT = 5

    private val context = MathContext(20, RoundingMode.HALF_EVEN)

    /**
     * An axis: its domain and tick values, ascending.
     *
     * @property min Domain start.
     * @property max Domain end (equal to [min] for a single-valued domain).
     * @property ticks Tick values, ascending.
     */
    data class Axis(val min: Double, val max: Double, val ticks: List<Double>) {
        /**
         * Where [value] sits along the axis, 0 at [min] and 1 at [max]; a single-valued
         * domain puts everything in the middle (d3 `scaleLinear` with an empty span).
         *
         * @param value Data value.
         * @return Fraction (not clamped).
         */
        fun fraction(value: Double): Double = if (max == min) 0.5 else (value - min) / (max - min)
    }

    /**
     * Recharts' automatic domain (`[0, 'auto']` and similar): nice ticks covering
     * `[min, max]`, with the domain widened to the outermost ticks.
     *
     * @param min Data minimum.
     * @param max Data maximum.
     * @param tickCount Ticks wanted.
     * @param allowDecimals Whether steps may be fractional.
     * @return Axis.
     */
    fun nice(min: Double, max: Double, tickCount: Int = DEFAULT_TICK_COUNT, allowDecimals: Boolean = true): Axis {
        val ticks = niceTicks(min, max, tickCount, allowDecimals)
        return Axis(ticks.first(), ticks.last(), ticks)
    }

    /**
     * Recharts' explicit numeric domain: the domain is kept, ticks step evenly inside it
     * and always end on its maximum; a single-valued domain has one tick.
     *
     * @param min Domain start.
     * @param max Domain end.
     * @param tickCount Ticks wanted.
     * @param allowDecimals Whether steps may be fractional.
     * @return Axis.
     */
    fun fixed(min: Double, max: Double, tickCount: Int = DEFAULT_TICK_COUNT, allowDecimals: Boolean = true): Axis =
        Axis(minOf(min, max), maxOf(min, max), fixedDomainTicks(min, max, tickCount, allowDecimals))

    /**
     * `getNiceTickValues`.
     *
     * @param min Data minimum.
     * @param max Data maximum.
     * @param tickCount Ticks wanted.
     * @param allowDecimals Whether steps may be fractional.
     * @return Ticks, ascending.
     */
    fun niceTicks(min: Double, max: Double, tickCount: Int = DEFAULT_TICK_COUNT, allowDecimals: Boolean = true): List<Double> {
        val count = maxOf(tickCount, 2)
        val low = minOf(min, max)
        val high = maxOf(min, max)
        if (low == high) return singleValueTicks(low, tickCount, allowDecimals)
        val (step, tickMin, tickMax) = calculateStep(low, high, count, allowDecimals, 0)
        return rangeStep(tickMin, tickMax + BigDecimal("0.1").multiply(step, context), step)
    }

    /**
     * `getTickValuesFixedDomain`.
     *
     * @param min Domain start.
     * @param max Domain end.
     * @param tickCount Ticks wanted.
     * @param allowDecimals Whether steps may be fractional.
     * @return Ticks, ascending.
     */
    fun fixedDomainTicks(min: Double, max: Double, tickCount: Int = DEFAULT_TICK_COUNT, allowDecimals: Boolean = true): List<Double> {
        val low = minOf(min, max)
        val high = maxOf(min, max)
        if (low == high) return listOf(low)
        val count = maxOf(tickCount, 2)
        val step = formatStep(decimal(high).subtract(decimal(low)).divide(BigDecimal(count - 1), context), allowDecimals, 0)
        if (step.signum() == 0) return listOf(low, high)
        val end = decimal(high).subtract(BigDecimal("0.99").multiply(step, context))
        return rangeStep(decimal(low), end, step) + high
    }

    // region recharts-scale internals

    private fun decimal(value: Double): BigDecimal = BigDecimal(value.toString())

    /** `Arithmetic.getDigitCount`: `floor(log10(|value|)) + 1`, 1 for zero. */
    internal fun digitCount(value: BigDecimal): Int {
        if (value.signum() == 0) return 1
        val abs = value.abs().stripTrailingZeros()
        return abs.precision() - abs.scale()
    }

    /** `getFormatStep`: a round step at least [roughStep]. */
    internal fun formatStep(roughStep: BigDecimal, allowDecimals: Boolean, correctionFactor: Int): BigDecimal {
        if (roughStep.signum() <= 0) return BigDecimal.ZERO
        val digits = digitCount(roughStep)
        val unit = BigDecimal.ONE.scaleByPowerOfTen(digits)
        val ratio = roughStep.divide(unit, context)
        val ratioScale = if (digits != 1) BigDecimal("0.05") else BigDecimal("0.1")
        val steps = ratio.divide(ratioScale, context).setScale(0, RoundingMode.CEILING).add(BigDecimal(correctionFactor))
        val step = steps.multiply(ratioScale).multiply(unit)
        return if (allowDecimals) step else step.setScale(0, RoundingMode.CEILING)
    }

    /** `calculateStep`: step and outer ticks, widening the step until the ticks fit [tickCount]. */
    private fun calculateStep(min: Double, max: Double, tickCount: Int, allowDecimals: Boolean, correctionFactor: Int): Triple<BigDecimal, BigDecimal, BigDecimal> {
        val step = formatStep(decimal(max).subtract(decimal(min)).divide(BigDecimal(tickCount - 1), context), allowDecimals, correctionFactor)
        if (step.signum() == 0) return Triple(BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO)
        val middle = if (min <= 0 && max >= 0) {
            BigDecimal.ZERO
        } else {
            val mid = decimal(min).add(decimal(max)).divide(BigDecimal(2), context)
            mid.subtract(mid.remainder(step, context))
        }
        var below = ceil(middle.subtract(decimal(min)).divide(step, context).toDouble()).toInt()
        var up = ceil(decimal(max).subtract(middle).divide(step, context).toDouble()).toInt()
        val scaleCount = below + up + 1
        if (scaleCount > tickCount) return calculateStep(min, max, tickCount, allowDecimals, correctionFactor + 1)
        if (scaleCount < tickCount) {
            if (max > 0) up += tickCount - scaleCount else below += tickCount - scaleCount
        }
        return Triple(step, middle.subtract(BigDecimal(below).multiply(step)), middle.add(BigDecimal(up).multiply(step)))
    }

    /** `getTickOfSingleValue`: ticks around one value. */
    private fun singleValueTicks(value: Double, tickCount: Int, allowDecimals: Boolean): List<Double> {
        var step = BigDecimal.ONE
        var middle = decimal(value)
        val isInteger = middle.stripTrailingZeros().scale() <= 0
        if (!isInteger && allowDecimals) {
            val abs = middle.abs()
            if (abs < BigDecimal.ONE) {
                step = BigDecimal.ONE.scaleByPowerOfTen(digitCount(middle) - 1)
                middle = middle.divide(step, context).setScale(0, RoundingMode.FLOOR).multiply(step)
            } else if (abs > BigDecimal.ONE) {
                middle = middle.setScale(0, RoundingMode.FLOOR)
            }
        } else if (value == 0.0) {
            middle = BigDecimal((tickCount - 1) / 2)
        } else if (!allowDecimals) {
            middle = middle.setScale(0, RoundingMode.FLOOR)
        }
        val middleIndex = (tickCount - 1) / 2
        return (0 until tickCount).map { middle.add(BigDecimal(it - middleIndex).multiply(step)).toDouble() }
    }

    /** `Arithmetic.rangeStep`: `start`, `start + step`, … while below `end`. */
    private fun rangeStep(start: BigDecimal, end: BigDecimal, step: BigDecimal): List<Double> {
        val values = mutableListOf<Double>()
        var value = start
        while (value < end && values.size < MAX_TICKS) {
            values += value.toDouble()
            value = value.add(step)
        }
        return values
    }

    /** Guard against a degenerate step producing an endless range. */
    private const val MAX_TICKS = 64

    // endregion
}

// endregion
