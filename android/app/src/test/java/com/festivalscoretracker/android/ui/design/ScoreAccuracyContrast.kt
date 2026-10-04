package com.festivalscoretracker.android.ui.design

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** WCAG 2.x contrast arithmetic on packed `0xRRGGBB` colours, for the `badge-contrast` state. */
internal object ScoreAccuracyContrast {
    /**
     * Source-over composite of [top] at [alpha] onto opaque [bottom].
     *
     * @return Packed `0xRRGGBB`.
     */
    fun composite(top: Int, alpha: Float, bottom: Int): Int {
        fun channel(shift: Int): Int {
            val t = (top shr shift) and 0xFF
            val b = (bottom shr shift) and 0xFF
            return (t * alpha + b * (1 - alpha)).roundToInt()
        }
        return (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }

    /** WCAG relative luminance. */
    fun luminance(rgb: Int): Double {
        fun linear(shift: Int): Double {
            val c = ((rgb shr shift) and 0xFF) / 255.0
            return if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /** WCAG contrast ratio of two opaque colours. */
    fun ratio(a: Int, b: Int): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /** Whether every channel of [a] and [b] differs by at most [tolerance]. */
    fun close(a: Int, b: Int, tolerance: Int): Boolean =
        listOf(16, 8, 0).all { abs(((a shr it) and 0xFF) - ((b shr it) and 0xFF)) <= tolerance }
}
