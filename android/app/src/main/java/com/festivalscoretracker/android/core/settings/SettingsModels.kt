package com.festivalscoretracker.android.core.settings

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

// region Metadata fields

/**
 * The eight independently visible Song-row metadata fields (web `SongRowVisualKey`).
 * Declaration order is the web `DEFAULT_METADATA_ORDER`; [token] is the web key.
 *
 * @property token Stored web key (`seasonachieved`, `lastplayed`, …).
 * @property label Title Case label (web `metadata.*`).
 */
enum class MetadataField(val token: String, val label: String) {
    Score("score", "Score"),
    Percentage("percentage", "Percentage"),
    Percentile("percentile", "Percentile"),
    Stars("stars", "Stars"),
    Season("seasonachieved", "Season Achieved"),
    Intensity("intensity", "Intensity"),
    Difficulty("difficulty", "Game Difficulty"),
    LastPlayed("lastplayed", "Last Played"),
    ;

    /** Stable test-tag token, e.g. `last-played`. */
    val tag: String get() = if (this == LastPlayed) "last-played" else name.lowercase()

    companion object {
        /** Settings "Show Instrument Metadata" toggle order (web `METADATA_TOGGLES`). */
        val toggleOrder = listOf(Score, Percentage, Percentile, Season, Intensity, Difficulty, Stars, LastPlayed)

        /**
         * Look up a stored token.
         *
         * @param token Web key.
         * @return Field, or null when unknown.
         */
        fun fromToken(token: String): MetadataField? = entries.firstOrNull { it.token == token }
    }
}

/**
 * The five CHOpt Paths text-table columns (web `ColumnKey`, `DEFAULT_COLUMN_ORDER`).
 *
 * @property token Stored web key.
 * @property label Column header shared by the Paths table and its Settings reorder row.
 */
enum class PathColumnKey(val token: String, val label: String) {
    Note("note", "Note"),
    Beat("beat", "Beat"),
    Time("time", "Time"),
    Od("od", "OD"),
    Score("score", "Score"),
    ;

    companion object {
        /**
         * Look up a stored token.
         *
         * @param token Web key.
         * @return Column, or null when unknown.
         */
        fun fromToken(token: String): PathColumnKey? = entries.firstOrNull { it.token == token }
    }
}

/**
 * How CHOpt paths open by default (web `pathDefaultView`).
 *
 * @property token Stored web value.
 * @property label Radio label.
 */
enum class PathDisplayMode(val token: String, val label: String) {
    Image("image", "Image"),
    Text("text", "Text"),
    ;

    companion object {
        /**
         * Decode a stored value; anything unknown is [Image].
         *
         * @param token Stored value.
         * @return Mode.
         */
        fun fromToken(token: String?): PathDisplayMode = entries.firstOrNull { it.token == token } ?: Image
    }
}

// endregion

// region Order codec

/** Repairs user-reorderable lists so they survive app updates and corrupt data (Apple `SettingsOrder`). */
object SettingsOrder {
    /**
     * Every case exactly once: the stored order first (unknown and duplicate
     * entries dropped), then any missing case in declaration order (web
     * `migrateMetadataOrder`).
     *
     * @param stored Persisted order, possibly partial or corrupt.
     * @param all Every case in default order.
     * @return A complete order.
     */
    fun <T> normalize(stored: List<T?>?, all: List<T>): List<T> {
        val seen = LinkedHashSet<T>()
        stored.orEmpty().forEach { value -> if (value != null && value in all) seen += value }
        all.forEach { seen += it }
        return seen.toList()
    }

    /**
     * Decode a comma-joined token list.
     *
     * @param raw Stored string or null.
     * @param all Every case in default order.
     * @param lookup Token → case.
     * @return A complete order.
     */
    fun <T> decode(raw: String?, all: List<T>, lookup: (String) -> T?): List<T> =
        normalize(raw?.split(',')?.map { lookup(it.trim()) }, all)

    /**
     * Encode an order as comma-joined tokens.
     *
     * @param values Order.
     * @param token Case → token.
     * @return Stored string.
     */
    fun <T> encode(values: List<T>, token: (T) -> String): String = values.joinToString(",", transform = token)

    /**
     * Move one item by an offset (keyboard/TalkBack-friendly reorder).
     *
     * @param order Current order.
     * @param index Item index.
     * @param offset −1 (up) or +1 (down), or any other distance.
     * @return New order, or the same items when the move is out of range.
     */
    fun <T> move(order: List<T>, index: Int, offset: Int): List<T> {
        val target = index + offset
        if (index !in order.indices || target !in order.indices) return order
        return order.toMutableList().apply { add(target, removeAt(index)) }
    }
}

// endregion

// region Leeway

/** Invalid-score leeway rules (web `LeewaySlider`: −5…+5 %, step 0.1, default +1). */
object ScoreLeeway {
    /** Lowest leeway percent. */
    const val MINIMUM = -5.0

    /** Highest leeway percent. */
    const val MAXIMUM = 5.0

    /** Default leeway percent. */
    const val DEFAULT = 1.0

    /** Number of 0.1 steps between the ends (Material `Slider` `steps` excludes both ends). */
    const val SLIDER_STEPS = 99

    /** Reference CHOpt maximum used in the Settings explanation. */
    const val REFERENCE_MAX_SCORE = 100_000

    /**
     * Clamp to range and round half away from zero to one decimal; non-finite values use the default.
     *
     * @param value Raw value.
     * @return Valid leeway.
     */
    fun clamp(value: Double): Double {
        if (!value.isFinite()) return DEFAULT
        return BigDecimal(value.coerceIn(MINIMUM, MAXIMUM).toString()).setScale(1, RoundingMode.HALF_UP).toDouble()
    }

    /**
     * Signed one-decimal display matching the web slider label: `+1.0%`, `-0.5%`, `0.0%`.
     *
     * @param value Leeway.
     * @return Label.
     */
    fun format(value: Double): String {
        val v = clamp(value)
        val text = String.format(Locale.US, "%.1f%%", abs(v))
        return when {
            v > 0 -> "+$text"
            v < 0 -> "-$text"
            else -> text
        }
    }

    /**
     * Highest score accepted for the reference maximum (web `100000 * (1 + leeway / 100)`).
     *
     * @param value Leeway.
     * @return Rounded score.
     */
    fun maxEffectiveScore(value: Double): Int = (REFERENCE_MAX_SCORE * (1 + clamp(value) / 100)).roundToInt()

    /**
     * Web `maxScoreLeewayDesc` with its `toLocaleString()` example score.
     *
     * @param value Leeway.
     * @return Explanation sentence.
     */
    fun description(value: Double): String {
        val v = clamp(value)
        val leeway = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
        val score = NumberFormat.getIntegerInstance(Locale.US).format(maxEffectiveScore(v))
        return "This slider controls a percentage value that allows for some expanded range of scores to still be valid. " +
            "For example, a CHOpt path with a max score of 100k and $leeway% leeway will allow the app to accept scores " +
            "up to $score as “valid”."
    }
}

// endregion
