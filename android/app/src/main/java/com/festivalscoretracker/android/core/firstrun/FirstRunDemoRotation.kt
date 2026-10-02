package com.festivalscoretracker.android.core.firstrun

// region Timing

/**
 * First-run demo animation timing, ported from the web theme
 * (`packages/theme/src/animation.ts`) so the demos rotate on the web's clock.
 */
object FirstRunDemoTiming {
    /** Time between two data swaps (web `DEMO_SWAP_INTERVAL_MS`). */
    const val SWAP_INTERVAL_MS: Long = 5_000

    /** Fade-out, then fade-in, time of one swap (web `FADE_DURATION`). */
    const val FADE_MS: Int = 400

    /** Delay between cascading rows on entrance (web `STAGGER_INTERVAL`). */
    const val STAGGER_MS: Int = 125

    /** Selection cycle of the Song Info bar-select demo (web `BarSelectDemo` `CYCLE_MS`). */
    const val BAR_SELECT_INTERVAL_MS: Long = 2_500

    /** Detail-card fade of the bar-select demo (web `BarSelectDemo`). */
    const val BAR_SELECT_FADE_MS: Int = 300

    /** Drop of the suggestions card while it fades (web `CategoryCardDemo`, 8 px). */
    const val CARD_DROP_DP: Int = 8

    /** Rise of the Compete hub while it fades (web `CompeteHubDemo`, 6 px). */
    const val HUB_RISE_DP: Int = 6

    /** Drop of a fading rival group (web `CompeteRivalsDemo`/`RivalsOverviewDemo`, 4 px). */
    const val GROUP_DROP_DP: Int = 4

    /** CSS `ease` control points, the web demos' fade curve. */
    val EASE: FloatArray = floatArrayOf(0.25f, 0.1f, 0.25f, 1f)
}

// endregion

// region Swap selection

/**
 * Which rows a demo swaps on each tick, ported from the web's `useDemoSongs` swap
 * cycle. The web picks rows with `Math.random`; this seeds a shuffle with the tick
 * (as on iOS) so runs and tests repeat, keeping the web's rules: how many rows swap,
 * and never exactly the same rows twice in a row.
 */
object FirstRunDemoRotation {
    /** Web `MAX_DEDUP_ATTEMPTS`. */
    private const val ATTEMPTS = 10

    /**
     * Rows swapped per tick: one for up to 3 rows, two for up to 6, otherwise three.
     *
     * @param rowCount Visible rows.
     * @return 0 for no rows, else 1, 2 or 3.
     */
    fun swapCount(rowCount: Int): Int = when {
        rowCount < 1 -> 0
        rowCount <= 3 -> 1
        rowCount <= 6 -> 2
        else -> 3
    }

    /**
     * The row indices to swap on [tick].
     *
     * @param rowCount Visible rows.
     * @param tick Zero-based swap number; seeds the deterministic shuffle.
     * @param previous Rows swapped on the previous tick, avoided when another choice exists.
     * @return [swapCount] distinct indices in ascending order.
     */
    fun swapIndices(rowCount: Int, tick: Int, previous: Set<Int> = emptySet()): List<Int> {
        val count = swapCount(rowCount)
        if (count == 0) return emptyList()
        for (attempt in 0 until ATTEMPTS) {
            val random = SplitMix64(tick.toLong() * 0x9E3779B9L + attempt)
            val picked = random.shuffled((0 until rowCount).toList()).take(count).sorted()
            if (picked.toSet() != previous || count == rowCount) return picked
        }
        // Web gives up after its retries; prefer rows that were not just swapped so the same row never swaps twice in a row.
        val fresh = (0 until rowCount).filter { it !in previous }
        return (fresh.take(count) + previous.filter { it in 0 until rowCount }.sorted()).take(count).sorted()
    }
}

/**
 * Small deterministic generator (SplitMix64) for repeatable demo shuffles.
 *
 * @param seed Initial state.
 */
internal class SplitMix64(seed: Long) {
    private var state = seed

    /**
     * Next 64 random bits.
     *
     * @return Random value.
     */
    fun next(): Long {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return z xor (z ushr 31)
    }

    /**
     * Uniform index below [bound].
     *
     * @param bound Exclusive upper bound (> 0).
     * @return Value in `0 until bound`.
     */
    fun nextInt(bound: Int): Int = ((next() ushr 1) % bound).toInt()

    /**
     * Fisher–Yates shuffle.
     *
     * @param items Items to shuffle.
     * @return A shuffled copy.
     */
    fun <T> shuffled(items: List<T>): List<T> {
        val result = items.toMutableList()
        for (i in result.lastIndex downTo 1) {
            val j = nextInt(i + 1)
            val swap = result[i]
            result[i] = result[j]
            result[j] = swap
        }
        return result
    }
}

// endregion

// region Row rotation

/**
 * Visible demo rows rotating through a larger pool (web `useDemoSongs`): each tick
 * swaps [FirstRunDemoRotation.swapCount] rows for pool items that are not visible.
 * Replacements walk the pool in order (the web picks at random) so every item
 * appears before any repeats.
 *
 * @param T Row item.
 * @property pool Everything the rows may show.
 * @property rows Rows currently shown, in stable positions.
 * @property key Identity used to keep rows distinct.
 */
class FirstRunRowRotation<T> private constructor(
    val pool: List<T>,
    val rows: List<T>,
    private val key: (T) -> Any,
    private val cursor: Int,
    private val tick: Int,
    private val lastSwapped: Set<Int>,
) {
    /** Whether a swap can show anything new: the pool must hold more distinct items than the rows. */
    val canRotate: Boolean
        get() = rows.isNotEmpty() && pool.map(key).toSet().size > rows.map(key).toSet().size

    /**
     * The rows the next swap fades out.
     *
     * @return Ascending row indices; empty when [canRotate] is false.
     */
    fun nextIndices(): List<Int> =
        if (canRotate) FirstRunDemoRotation.swapIndices(rows.size, tick, lastSwapped) else emptyList()

    /**
     * Swap [indices] (normally [nextIndices]) for the next pool items not already visible.
     *
     * @param indices Rows to replace; out-of-range indices are ignored.
     * @return The rotated state, with the tick advanced.
     */
    fun swapped(indices: List<Int>): FirstRunRowRotation<T> {
        if (pool.isEmpty()) return this
        val next = rows.toMutableList()
        var position = cursor
        for (index in indices) {
            if (index !in next.indices) continue
            val visible = next.map(key).toSet()
            var tries = 0
            while (tries < pool.size) {
                val candidate = pool[position % pool.size]
                position = (position + 1) % pool.size
                tries++
                if (key(candidate) !in visible) {
                    next[index] = candidate
                    break
                }
            }
        }
        return FirstRunRowRotation(pool, next, key, position, tick + 1, indices.toSet())
    }

    /** Factory. */
    companion object {
        /**
         * Start with the first [visible] pool items.
         *
         * @param pool Items to rotate through.
         * @param visible Rows to show.
         * @param key Row identity.
         * @return Initial state.
         */
        fun <T> start(pool: List<T>, visible: Int, key: (T) -> Any = { it as Any }): FirstRunRowRotation<T> {
            val rows = pool.take(visible.coerceAtLeast(0))
            return FirstRunRowRotation(pool, rows, key, if (pool.isEmpty()) 0 else rows.size % pool.size, 0, emptySet())
        }
    }
}

/**
 * A fixed-size window stepping through a pool, wrapping (web Rivals/Compete demos'
 * `poolIdxRef`): each step shows the next [count] items.
 *
 * @param T Item.
 * @property pool Items to page through.
 * @property start First visible index.
 * @property count Items shown at once (clamped to the pool).
 */
data class FirstRunWindowRotation<T>(val pool: List<T>, val count: Int, val start: Int = 0) {
    private val shown = count.coerceIn(0, pool.size)

    /** The items currently shown. */
    val rows: List<T> get() = if (pool.isEmpty()) emptyList() else List(shown) { pool[(start + it) % pool.size] }

    /**
     * The next window.
     *
     * @return The advanced window.
     */
    fun advanced(): FirstRunWindowRotation<T> =
        if (pool.isEmpty()) this else copy(start = (start + shown) % pool.size)
}

/**
 * Independent slots each paging through their own pool (web `RivalsInstrumentsDemo`):
 * each tick swaps [FirstRunDemoRotation.swapCount] random slots to their pool's next item.
 *
 * @property poolSizes Pool size per slot.
 * @property positions Item index shown per slot.
 */
data class FirstRunSlotRotation(val poolSizes: List<Int>, val positions: List<Int> = List(poolSizes.size) { 0 }, private val tick: Int = 0, private val lastSwapped: Set<Int> = emptySet()) {
    /**
     * The slots the next swap fades out.
     *
     * @return Ascending slot indices.
     */
    fun nextIndices(): List<Int> =
        if (poolSizes.any { it > 1 }) FirstRunDemoRotation.swapIndices(poolSizes.size, tick, lastSwapped) else emptyList()

    /**
     * Advance [indices] to their pools' next items, wrapping.
     *
     * @param indices Slots to advance.
     * @return Rotated state.
     */
    fun swapped(indices: List<Int>): FirstRunSlotRotation {
        val next = positions.toMutableList()
        for (index in indices) if (index in next.indices && poolSizes[index] > 0) next[index] = (next[index] + 1) % poolSizes[index]
        return copy(positions = next, tick = tick + 1, lastSwapped = indices.toSet())
    }
}

// endregion

// region Song icon pattern

/** One instrument's state in the Songs icons demo. */
enum class FirstRunDemoScoreState {
    /** No score. */
    NoScore,

    /** Scored. */
    Scored,

    /** Full combo. */
    FullCombo,
}

/**
 * The per-instrument pattern the Songs **icons** demo draws for a song (web
 * `SongIconsDemo` `buildScores`), so every rotated-in song shows a different mix.
 */
object FirstRunDemoScorePattern {
    /**
     * The web's 32-bit string hash: `h = ((h << 5) - h + charCode) | 0` over UTF-16 units.
     *
     * @param title Song title.
     * @return Signed 32-bit hash.
     */
    fun hash(title: String): Int {
        var h = 0
        for (unit in title) h = (h shl 5) - h + unit.code
        return h
    }

    /**
     * States for [count] instruments in order: bit `2i` of `|hash|` is "scored",
     * bit `2i+1` a full combo (only when scored).
     *
     * @param title Song title seeding the pattern.
     * @param count Instruments.
     * @return [count] states.
     */
    fun states(title: String, count: Int): List<FirstRunDemoScoreState> {
        val bits = kotlin.math.abs(hash(title).toLong())
        return List(count.coerceAtLeast(0)) { i ->
            val scored = (bits shr (i * 2)) and 1L == 1L
            val fullCombo = scored && (bits shr (i * 2 + 1)) and 1L == 1L
            when {
                fullCombo -> FirstRunDemoScoreState.FullCombo
                scored -> FirstRunDemoScoreState.Scored
                else -> FirstRunDemoScoreState.NoScore
            }
        }
    }
}

// endregion
