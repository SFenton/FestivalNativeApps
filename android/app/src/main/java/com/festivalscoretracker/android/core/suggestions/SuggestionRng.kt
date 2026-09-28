package com.festivalscoretracker.android.core.suggestions

// region RNG

/** Pluggable random source so [SuggestionGenerator] tests can force deterministic output. */
interface SuggestionRng {
    /** Next value in `[0, 1)`. */
    fun nextDouble(): Double

    /**
     * Next integer in `[0, maxExclusive)`.
     *
     * @param maxExclusive Upper bound; `0` or less always yields `0`.
     * @return Truncated `nextDouble() * maxExclusive`.
     */
    fun nextInt(maxExclusive: Int): Int
}

/**
 * Mulberry32, the small seeded PRNG the web generator uses, ported bit-for-bit
 * (32-bit wrapping arithmetic) so a fixed seed reproduces the Apple/Windows/web
 * shuffle order exactly (Apple `SeededSuggestionRng`).
 *
 * @param seed Any 32-bit value (`0..4294967295`); only the low 32 bits are used.
 */
class SeededSuggestionRng(seed: Long) : SuggestionRng {
    private var state: Int = seed.toInt()

    override fun nextDouble(): Double {
        state += 0x6D2B79F5
        val t1 = (state xor (state ushr 15)) * (state or 1)
        val t2 = (t1 + ((t1 xor (t1 ushr 7)) * (t1 or 61))) xor t1
        val out = t2 xor (t2 ushr 14)
        return (out.toLong() and 0xFFFF_FFFFL).toDouble() / 4_294_967_296.0
    }

    override fun nextInt(maxExclusive: Int): Int {
        if (maxExclusive <= 0) return 0
        return (nextDouble() * maxExclusive).toInt()
    }
}

// endregion
