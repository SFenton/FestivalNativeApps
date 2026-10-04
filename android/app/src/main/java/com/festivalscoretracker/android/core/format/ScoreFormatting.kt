package com.festivalscoretracker.android.core.format

import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

// region Score formatting

/** Shared score display policy (Apple `ScoreFormatting`). */
object ScoreFormatting {
    private val percentileBuckets = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)

    /**
     * Grouped integer score such as `95,198`.
     *
     * @param score Raw score.
     * @param locale Formatting locale.
     * @return Locale-grouped text.
     */
    fun score(score: Int, locale: Locale = Locale.getDefault()): String = NumberFormat.getIntegerInstance(locale).format(score)

    /**
     * Expanded accuracy (ten-thousandths of a percent) as a percent with one
     * fraction digit only when needed, without the `%` sign.
     *
     * @param expandedAccuracy Service accuracy, e.g. `987654` → `98.8`.
     * @param locale Formatting locale.
     * @return Formatted number.
     */
    fun accuracy(expandedAccuracy: Double, locale: Locale = Locale.getDefault()): String {
        val rounded = (expandedAccuracy / 1_000).roundToInt() / 10.0
        val format = NumberFormat.getNumberInstance(locale).apply {
            val digits = if (rounded == Math.floor(rounded)) 0 else 1
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }
        return format.format(rounded)
    }

    /**
     * Red-to-green accuracy pill color (caller applies 25% opacity).
     *
     * @param expandedAccuracy Service accuracy in ten-thousandths of a percent.
     * @return Packed `0xRRGGBB`, or null for non-finite data.
     */
    fun accuracyTint(expandedAccuracy: Double): Int? {
        if (!expandedAccuracy.isFinite()) return null
        val fraction = (expandedAccuracy / 1_000_000).coerceIn(0.0, 1.0)
        val red = (220 * (1 - fraction) + 46 * fraction).roundToInt()
        val green = (40 * (1 - fraction) + 204 * fraction).roundToInt()
        val blue = (40 * (1 - fraction) + 113 * fraction).roundToInt()
        return (red shl 16) or (green shl 8) or blue
    }

    /**
     * Bucket a rank as the web Songs row does ("Top 5%").
     *
     * @param rank One-based rank.
     * @param totalEntries Positive chart population.
     * @return Bucket label, or null when rank or total is invalid.
     */
    fun percentileBucket(rank: Int, totalEntries: Int): String? {
        if (rank <= 0 || totalEntries <= 0) return null
        val percentile = (rank.toDouble() / totalEntries * 100).coerceIn(1.0, 100.0)
        val bucket = percentileBuckets.first { percentile <= it }
        return "Top $bucket%"
    }
}

// endregion

// region Difficulty meter

/**
 * Geometry and value mapping for the branded seven-bar meter
 * (`.agents/controls/difficulty-meter/spec.md`).
 */
object DifficultyMeterSpec {
    /** Canvas width in logical units. */
    const val WIDTH = 62f

    /** Canvas height in logical units. */
    const val HEIGHT = 20f

    /** Number of bars. */
    const val BARS = 7

    /** Filled bar color (sRGB). */
    const val FILLED = 0xFFFFFFFF

    /** Unfilled bar color (sRGB). */
    const val UNFILLED = 0xFF666666

    /**
     * Parallelogram vertices for bar [index]: `(x+2,0) (x+8,0) (x+6,20) (x,20)` with `x = 9i`.
     *
     * @param index Bar index in `0..6`.
     * @return Four `(x, y)` pairs in drawing order.
     */
    fun barVertices(index: Int): List<Pair<Float, Float>> {
        require(index in 0 until BARS)
        val x = index * 9f
        return listOf(x + 2 to 0f, x + 8 to 0f, x + 6 to HEIGHT, x to HEIGHT)
    }

    /**
     * Map a service value to filled bars.
     *
     * Raw 0–6 levels truncate, clamp and add one (5.9 → 6, 99 → 7); display
     * 1–7 levels clamp without truncation (3.5 → 3 filled).
     *
     * @param level Service or display value.
     * @param raw Whether [level] is a raw 0–6 value.
     * @return Filled bars in `1..7`, or null for a non-finite value.
     */
    fun filledBars(level: Double, raw: Boolean): Int? {
        if (!level.isFinite()) return null
        return if (raw) {
            level.toInt().coerceIn(0, 6) + 1
        } else {
            level.coerceIn(1.0, 7.0).toInt()
        }
    }

    /**
     * Accessible value: "Difficulty 6 of 7", keeping a display fraction ("3.5 of 7").
     *
     * @param level Service or display value.
     * @param raw Whether [level] is a raw 0–6 value.
     * @return Spoken label, or "Difficulty unavailable".
     */
    fun accessibilityLabel(level: Double, raw: Boolean): String {
        val bars = filledBars(level, raw) ?: return "Difficulty unavailable"
        if (raw) return "Difficulty $bars of 7"
        val clamped = level.coerceIn(1.0, 7.0)
        val text = if (clamped == Math.floor(clamped)) clamped.toInt().toString() else clamped.toString()
        return "Difficulty $text of 7"
    }
}

// endregion

// region Star rating

/**
 * What a star row draws and speaks (`.agents/controls/star-rating/spec.md`; web
 * `MiniStars.tsx`/`GoldStars.tsx` and `en.json` `common.starCount`/`goldStarCount`).
 */
object StarRatingSpec {
    /** Service value of a gold (top) result. */
    const val GOLD = 6

    /** Most star images drawn; a gold result draws this many gold stars. */
    const val MAX_IMAGES = 5

    /**
     * A resolved star row.
     *
     * @property count Star images to draw, `1..5`.
     * @property gold Whether they are the gold images.
     */
    data class Display(val count: Int, val gold: Boolean) {
        /** Spoken label, e.g. "1 star", "4 stars" or "5 gold stars". */
        val label: String
            get() {
                val noun = if (count == 1) "star" else "stars"
                return if (gold) "$count gold $noun" else "$count $noun"
            }
    }

    /**
     * Resolve a service star count: 6 or more is five gold stars, anything else that
     * many white stars with a minimum of one (web `Math.max(1, starsCount)`).
     *
     * @param stars Service stars (0–6).
     * @param gold Force the gold treatment (a perfect average of six).
     * @return Images to draw and whether they are gold.
     */
    fun display(stars: Int, gold: Boolean = false): Display =
        if (gold || stars >= GOLD) Display(MAX_IMAGES, true) else Display(stars.coerceIn(1, MAX_IMAGES), false)
}

// endregion
