package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// region Text safety

/** Display-text checks for server-provided profile strings (Windows `ProfileText`). */
object ProfileText {
    /**
     * Whether text contains control, line-separator or bidirectional-override characters.
     *
     * @param text Text to inspect.
     * @return True when unsafe to show or persist.
     */
    fun containsUnsafe(text: String): Boolean = text.any { c ->
        c.code < 0x20 || c.code in 0x7F..0x9F || c.code in 0x2028..0x202E || c.code in 0x2066..0x2069
    }
}

// endregion

// region Compact wire

/**
 * One precomputed filtered-rank changepoint (`rt` item).
 *
 * @property leeway Invalid-score leeway where this rank starts.
 * @property rank Rank at that leeway.
 */
@Serializable
data class PlayerRankTier(@SerialName("l") val leeway: Double, @SerialName("r") val rank: Int)

/**
 * A historical valid score held apart from the current score (`vs` item).
 *
 * @property score Score.
 * @property rawAccuracy Wire accuracy (percent × 10); use [accuracy].
 * @property isFullCombo Explicit full-combo flag.
 * @property stars Stars, 0–6.
 * @property minLeeway Minimum leeway at which this variant applies.
 * @property rankTiers Filtered-rank changepoints.
 */
@Serializable
data class PlayerValidScoreVariant(
    @SerialName("sc") val score: Int = 0,
    @SerialName("acc") val rawAccuracy: Double? = null,
    @SerialName("fc") val isFullCombo: Boolean? = null,
    @SerialName("st") val stars: Int? = null,
    @SerialName("ml") val minLeeway: Double = 0.0,
    @SerialName("rt") val rankTiers: List<PlayerRankTier>? = null,
) {
    /** Accuracy in ten-thousandths of a percent (0–1,000,000), the leaderboard scale. */
    val accuracy: Double? get() = rawAccuracy?.times(1_000)

    /** Whether every value is in range. */
    val isWellFormed: Boolean
        get() = score >= 0 && minLeeway.isFinite() && PlayerScore.inRange(accuracy) && (stars == null || stars in 0..6) &&
            (rankTiers ?: emptyList()).all { it.leeway.isFinite() && it.rank >= 0 }
}

/**
 * One compact-wire score from `GET /api/player/{accountId}` (keys are the service's
 * short names; `ins` is a single-bit hex instrument code; `acc` is percent × 10).
 * Optional flags are never inferred from accuracy.
 */
@Serializable
data class PlayerScore(
    @SerialName("si") val songId: String = "",
    @SerialName("ins") val instrumentCode: String = "",
    @SerialName("sc") val score: Int = 0,
    @SerialName("acc") val rawAccuracy: Double? = null,
    @SerialName("fc") val isFullCombo: Boolean? = null,
    @SerialName("st") val stars: Int? = null,
    @SerialName("sn") val season: Int? = null,
    @SerialName("dif") val difficulty: Double? = null,
    @SerialName("pct") val rawPercentile: Double? = null,
    @SerialName("rk") val rank: Int? = null,
    @SerialName("te") val totalEntries: Int? = null,
    @SerialName("isValid") val isValidScore: Boolean? = null,
    @SerialName("validScore") val validScore: Int? = null,
    @SerialName("validAccuracy") val rawValidAccuracy: Double? = null,
    @SerialName("validIsFullCombo") val validIsFullCombo: Boolean? = null,
    @SerialName("validRank") val validRank: Int? = null,
    @SerialName("validStars") val validStars: Int? = null,
    @SerialName("validTotalEntries") val validTotalEntries: Int? = null,
    @SerialName("ml") val minLeeway: Double? = null,
    @SerialName("vs") val validScores: List<PlayerValidScoreVariant>? = null,
    @SerialName("et") val endTime: String? = null,
    @SerialName("lp") val lastPlayedAt: String? = null,
    @SerialName("vlp") val validLastPlayedAt: String? = null,
) {
    /** Chart decoded from [instrumentCode], or null for an invalid code. */
    val instrument: Instrument? get() = PlayerInstrumentCode.parse(instrumentCode)

    /** Accuracy in ten-thousandths of a percent (0–1,000,000). */
    val accuracy: Double? get() = rawAccuracy?.times(1_000)

    /** Fallback valid accuracy on the leaderboard scale. */
    val validAccuracy: Double? get() = rawValidAccuracy?.times(1_000)

    /** Percentile, or null for the `-1` "unavailable" sentinel. */
    val percentile: Double? get() = rawPercentile?.takeUnless { it == -1.0 }

    /** Whether identity, code and every metric are in range. */
    val isWellFormed: Boolean
        get() = songId.length in 1..200 && !ProfileText.containsUnsafe(songId) && instrument != null && score >= 0 &&
            (rank == null || rank >= 0) && (totalEntries == null || totalEntries >= 0) && (stars == null || stars in 0..6) &&
            (season == null || season >= 0) && (validScore == null || validScore >= 0) && inRange(accuracy) && inRange(validAccuracy) &&
            (validRank == null || validRank >= 0) && (validStars == null || validStars in 0..6) && (validTotalEntries == null || validTotalEntries >= 0) &&
            (difficulty == null || (difficulty.isFinite() && difficulty >= 0)) && (minLeeway == null || minLeeway.isFinite()) &&
            percentile.let { it == null || (it.isFinite() && it in 0.0..100.0) } &&
            (validScores ?: emptyList()).all { it.isWellFormed }

    companion object {
        /**
         * Whether an expanded accuracy is absent or finite within 0–1,000,000.
         *
         * @param accuracy Expanded accuracy.
         * @return True when acceptable.
         */
        internal fun inRange(accuracy: Double?): Boolean = accuracy == null || (accuracy.isFinite() && accuracy in 0.0..1_000_000.0)
    }
}

/** The service's single-instrument hex bit codes (`FSTService/ComboIds.cs`). */
object PlayerInstrumentCode {
    /**
     * Decode exactly one of the nine solo bits in source order (bit 0 = Lead … bit 8 = Pro Drums).
     *
     * @param hex Canonical lower-case two- or three-digit hex, e.g. `01`, `100`.
     * @return The chart, or null for a composite, unknown or non-canonical code.
     */
    fun parse(hex: String?): Instrument? {
        if (hex == null || hex.length !in 2..3) return null
        val mask = hex.toIntOrNull(16) ?: return null
        if (mask <= 0 || Integer.bitCount(mask) != 1) return null
        val index = Integer.numberOfTrailingZeros(mask)
        if (index >= Instrument.entries.size || hex != Integer.toHexString(mask).padStart(2, '0')) return null
        return Instrument.entries[index]
    }

    /**
     * Encode a chart as its canonical hex code.
     *
     * @param instrument Chart.
     * @return Code such as `01`.
     */
    fun encode(instrument: Instrument): String = Integer.toHexString(1 shl instrument.ordinal).padStart(2, '0')
}

// endregion

// region Profile envelope

/** HTTP 200 public scores (not proof of registration) or an explicit 202 syncing envelope. */
enum class PlayerProfileState {
    /** Public scores are available (possibly empty). */
    Available,

    /** Registered but not yet published (HTTP 202 `status: syncing`). */
    Syncing,
}

/**
 * Compact public profile from `GET /api/player/{accountId}`; never a tracked identity.
 *
 * @property accountId Account.
 * @property displayName Server display name (normalized: trimmed, blank → null).
 * @property totalScores Declared score count.
 * @property scores Compact rows.
 * @property status `syncing` on a 202 envelope.
 * @property notYetPublished True on a 202 envelope.
 */
@Serializable
data class PlayerProfileResponse(
    val accountId: String = "",
    val displayName: String? = null,
    val totalScores: Int = 0,
    val scores: List<PlayerScore> = emptyList(),
    val status: String? = null,
    val notYetPublished: Boolean? = null,
) {
    /**
     * Validate identity, cardinality and every row.
     *
     * @param requestedAccountId Account that was requested.
     * @return Syncing or available.
     * @throws FestivalApiException.InvalidResponse for corrupt or mixed-identity data.
     */
    fun validate(requestedAccountId: String): PlayerProfileState {
        val name = displayName
        val valid = ProfileSearchText.isValidAccountId(requestedAccountId) && ProfileSearchText.isValidAccountId(accountId) &&
            accountId.equals(requestedAccountId, ignoreCase = true) && totalScores in 0..MAX_SCORES && totalScores == scores.size &&
            (name == null || (name.length in 1..200 && name == name.trim() && !ProfileText.containsUnsafe(name)))
        if (!valid) throw FestivalApiException.InvalidResponse()
        if (status == "syncing") {
            if (notYetPublished != true || scores.isNotEmpty()) throw FestivalApiException.InvalidResponse()
            return PlayerProfileState.Syncing
        }
        if (status != null || notYetPublished == true) throw FestivalApiException.InvalidResponse()
        val seen = HashSet<Pair<String, Instrument>>()
        for (row in scores) {
            val instrument = row.instrument
            if (!row.isWellFormed || instrument == null || !seen.add(row.songId to instrument)) throw FestivalApiException.InvalidResponse()
        }
        return PlayerProfileState.Available
    }

    /**
     * A copy whose display name is trimmed (blank becomes null); unsafe names are
     * left for [validate] to reject.
     *
     * @return Normalized response.
     */
    fun normalized(): PlayerProfileResponse {
        val raw = displayName ?: return this
        if (ProfileText.containsUnsafe(raw)) return this
        return copy(displayName = raw.trim().ifEmpty { null })
    }

    /**
     * One lookup per profile: song ID → chart → row (built once, not per visible row).
     *
     * @return Index over validated rows.
     */
    fun scoreIndex(): Map<String, Map<Instrument, PlayerScore>> {
        val index = HashMap<String, HashMap<Instrument, PlayerScore>>()
        for (row in scores) {
            val instrument = row.instrument ?: continue
            index.getOrPut(row.songId) { HashMap() }[instrument] = row
        }
        return index
    }

    companion object {
        /** Largest accepted score count. */
        const val MAX_SCORES = 20_000
    }
}

/**
 * A validated profile read with its publication provenance.
 *
 * @property profile Validated response.
 * @property state Available or syncing.
 * @property publicationId Header-verified publication, or null when headerless (preview only).
 * @property observedPublicationId Generation the client observed for this read.
 */
data class PlayerProfilePayload(
    val profile: PlayerProfileResponse,
    val state: PlayerProfileState,
    val publicationId: Int?,
    val observedPublicationId: Int,
) {
    /**
     * Whether this read may back an explicit Select (header-verified against the current generation).
     *
     * @param currentPublicationId Client's current publication.
     * @return True when selectable.
     */
    fun isSelectable(currentPublicationId: Int?): Boolean =
        state == PlayerProfileState.Available && publicationId != null && publicationId == currentPublicationId

    /**
     * Whether this read belongs to an account (case-insensitive).
     *
     * @param accountId Account.
     * @return True on a match.
     */
    fun belongsTo(accountId: String): Boolean = profile.accountId.equals(accountId, ignoreCase = true)
}

// endregion

// region Client-side statistics

/**
 * Player-page statistics computed only from the compact scores (web
 * `computeOverallStats`/`computeInstrumentStats`, `pages/player/helpers/playerStats.ts`),
 * never from the side-effecting player-stats GET.
 *
 * @property songsPlayed Unique songs across visible charts (rows for one chart).
 * @property fullComboCount Rows with an explicit full combo.
 * @property fullComboPercent FC share, floored to one decimal.
 * @property goldStarCount Rows with 6 stars.
 * @property fiveStarCount Rows with exactly 5 stars.
 * @property averageAccuracy Mean positive expanded accuracy.
 * @property averageStars Mean stars over rows with at least one star (web `averageStars`), or null.
 * @property bestRank Best positive rank.
 * @property bestRankSongId Song holding [bestRank].
 * @property bestRankInstrument Chart holding [bestRank].
 * @property fourStarCount Rows with exactly 4 stars.
 * @property threeStarCount Rows with exactly 3 stars.
 * @property twoStarCount Rows with exactly 2 stars.
 * @property oneStarCount Rows with exactly 1 star.
 * @property placements `rank / totalEntries` (0–1) for every ranked row (web `percentiled`).
 */
data class PlayerStats(
    val songsPlayed: Int,
    val fullComboCount: Int,
    val fullComboPercent: Double,
    val goldStarCount: Int,
    val fiveStarCount: Int,
    val averageAccuracy: Double?,
    val bestRank: Int?,
    val bestRankSongId: String?,
    val bestRankInstrument: Instrument?,
    val averageStars: Double? = null,
    val fourStarCount: Int = 0,
    val threeStarCount: Int = 0,
    val twoStarCount: Int = 0,
    val oneStarCount: Int = 0,
    val placements: List<Double> = emptyList(),
) {
    /** Web `fcPercent === '100.0'`: every played chart full-combed. */
    val allFullCombos: Boolean get() = fullComboCount > 0 && fullComboPercent >= 100.0

    /**
     * The web's star cards, best first (`STAR_CARDS`: key 6 = Gold Stars, then 5…1),
     * non-zero counts only.
     */
    val starCounts: List<Pair<Int, Int>>
        get() = listOf(6 to goldStarCount, 5 to fiveStarCount, 4 to fourStarCount, 3 to threeStarCount, 2 to twoStarCount, 1 to oneStarCount)
            .filter { it.second > 0 }

    /**
     * Web `avgPercentile`: the mean placement of ranked songs as a "Top N%" bucket.
     *
     * @return Text, or null with no ranked song.
     */
    fun averagePercentile(): String? =
        if (placements.isEmpty()) null else PlayerStatistics.percentileBucketText(placements.average() * 100)

    /**
     * Web `overallPercentile`: placements summed with every unplayed catalogue song
     * counted as last place, over the catalogue size, as a "Top N%" bucket.
     *
     * @param totalSongs Catalogue size (web `songs.length`).
     * @return Text, or null with no ranked song or an unknown catalogue.
     */
    fun overallPercentile(totalSongs: Int): String? {
        if (placements.isEmpty() || totalSongs <= 0) return null
        val unplayed = totalSongs - songsPlayed
        return PlayerStatistics.percentileBucketText((placements.sum() + unplayed) / totalSongs * 100)
    }
}

/**
 * One "Top N%" placement band (web `PlayerPercentileTable`).
 *
 * @property topPercent Band upper bound.
 * @property count Songs in `(previous, topPercent]`.
 */
data class PlayerPercentileBucket(val topPercent: Int, val count: Int) {
    /** "Top 5%". */
    val label: String get() = "Top $topPercent%"

    /** Whether the band is a top-5% (gold) band. */
    val isTopFive: Boolean get() = topPercent <= 5
}

/** Aggregation over the compact scores. */
object PlayerStatistics {
    /** Band upper bounds, matching the web's `pctThresholds` (`playerStats.ts:69`). */
    val PERCENTILE_THRESHOLDS = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)

    /**
     * Overview across Settings-visible charts; songs are counted once across charts.
     *
     * @param profile Validated profile.
     * @param visible Settings-visible charts.
     * @return Zeroed totals when nothing is visible.
     */
    fun overall(profile: PlayerProfileResponse, visible: Set<Instrument>): PlayerStats {
        val rows = profile.scores.filter { it.instrument in visible }
        return aggregate(rows, rows.map { it.songId }.toSet().size)
    }

    /**
     * One chart's summary.
     *
     * @param profile Validated profile.
     * @param instrument Chart.
     * @return Zeroed totals when the chart has no scores.
     */
    fun forInstrument(profile: PlayerProfileResponse, instrument: Instrument): PlayerStats {
        val rows = profile.scores.filter { it.instrument == instrument }
        return aggregate(rows, rows.size)
    }

    /**
     * Placement distribution: each ranked row contributes `rank / totalEntries` to its first band.
     *
     * @param profile Validated profile.
     * @param instrument Chart.
     * @return Non-empty bands, best first.
     */
    fun percentileBuckets(profile: PlayerProfileResponse, instrument: Instrument): List<PlayerPercentileBucket> {
        val fractions = profile.scores
            .filter { it.instrument == instrument && (it.rank ?: 0) > 0 && (it.totalEntries ?: 0) > 0 }
            .map { it.rank!!.toDouble() / it.totalEntries!! * 100 }
        val buckets = mutableListOf<PlayerPercentileBucket>()
        var previous = 0
        for (threshold in PERCENTILE_THRESHOLDS) {
            val count = fractions.count { it > previous && it <= threshold }
            if (count > 0) buckets += PlayerPercentileBucket(threshold, count)
            previous = threshold
        }
        return buckets
    }

    private fun aggregate(rows: List<PlayerScore>, songsPlayed: Int): PlayerStats {
        val fc = rows.count { it.isFullCombo == true }
        val fcPercent = if (rows.isEmpty()) 0.0 else Math.floor(fc.toDouble() / rows.size * 1_000) / 10
        val accuracies = rows.mapNotNull { it.accuracy }.filter { it > 0 }
        val best = rows.filter { (it.rank ?: 0) > 0 }.minByOrNull { it.rank!! }
        val starred = rows.mapNotNull { it.stars }.filter { it > 0 }
        return PlayerStats(
            songsPlayed = songsPlayed,
            fullComboCount = fc,
            fullComboPercent = fcPercent,
            goldStarCount = rows.count { (it.stars ?: 0) >= 6 },
            fiveStarCount = rows.count { it.stars == 5 },
            averageAccuracy = if (accuracies.isEmpty()) null else accuracies.average(),
            bestRank = best?.rank,
            bestRankSongId = best?.songId,
            bestRankInstrument = best?.instrument,
            averageStars = if (starred.isEmpty()) null else starred.average(),
            fourStarCount = rows.count { it.stars == 4 },
            threeStarCount = rows.count { it.stars == 3 },
            twoStarCount = rows.count { it.stars == 2 },
            oneStarCount = rows.count { it.stars == 1 },
            placements = rows.filter { (it.rank ?: 0) > 0 && (it.totalEntries ?: 0) > 0 }.map { it.rank!!.toDouble() / it.totalEntries!! },
        )
    }

    /**
     * Web `formatPercentileBucket`: clamp to 1–100 and name the first threshold at or above it.
     *
     * @param percent Placement percent.
     * @return "Top 5%".
     */
    fun percentileBucketText(percent: Double): String {
        val clamped = percent.coerceIn(1.0, 100.0)
        return "Top ${PERCENTILE_THRESHOLDS.firstOrNull { clamped <= it } ?: 100}%"
    }
}

// endregion
