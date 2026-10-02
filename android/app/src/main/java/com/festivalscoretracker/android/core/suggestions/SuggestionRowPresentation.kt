package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign

// region Row layout

/** Right-side metadata a suggestion row shows, chosen by category key (web `getRowLayout`). */
enum class SuggestionRowLayout {
    /** One played/FC status chip per visible instrument. */
    InstrumentChips,

    /** The row's instrument icon, plus stars for star-gain categories. */
    SingleInstrument,

    /** "Top N%" pill plus the row's instrument icon. */
    Percentile,

    /** Season the score was set ("S6"). */
    Season,

    /** Accuracy pill for a gold, not-yet-FC run. */
    UnfcAccuracy,

    /** No right-side metadata. */
    Hidden,

    /** Rival name badge (see [SuggestionRowPresentation.showsRivalName]), rank delta and instrument icon. */
    Rival,
}

/** Visual tier of a percentile pill (web `PercentilePill`). */
enum class PercentileTier {
    /** Neutral pill. */
    Default,

    /** Top 5% (gold outline). */
    Top5,

    /** Top 1% (filled gold). */
    Top1,
}

/**
 * One instrument status chip.
 *
 * @property instrument Chart.
 * @property hasScore At least one star on it.
 * @property isFullCombo Full combo on it.
 */
data class SuggestionInstrumentChip(val instrument: Instrument, val hasScore: Boolean, val isFullCombo: Boolean)

// endregion

// region Row presentation

/**
 * Display-ready values for one suggestion row; pure so it is unit-tested instead
 * of the composable (Windows `SuggestionRowPresentation`).
 *
 * @property layout Right-side metadata kind.
 * @property title Song title.
 * @property subtitle "Artist · Year".
 * @property instrument Instrument icon to show.
 * @property starCount Stars to draw (1–5).
 * @property goldStars Whether drawn stars are gold (six stars).
 * @property accuracyText Accuracy pill text (e.g. "97").
 * @property accuracyExpanded Expanded accuracy for the pill tint.
 * @property seasonText Season pill ("S6").
 * @property percentileText "Top N%".
 * @property percentileTier Pill tier.
 * @property rivalName Rival name badge text, truncated to 12 characters; null on single-rival
 *   cards, whose title already names the rival ([showsRivalName]).
 * @property rivalDeltaText "+5" / "-3", or null when zero.
 * @property rivalDeltaSign Sign of the rank delta (positive: the player leads).
 * @property rivalFromSong The rival comes from song rivals (blue badge), not leaderboard rivals (yellow).
 * @property chips Instrument chips for [SuggestionRowLayout.InstrumentChips].
 * @property accessibleLabel TalkBack description for the whole row.
 */
data class SuggestionRowPresentation(
    val layout: SuggestionRowLayout,
    val title: String,
    val subtitle: String,
    val instrument: Instrument? = null,
    val starCount: Int = 0,
    val goldStars: Boolean = false,
    val accuracyText: String? = null,
    val accuracyExpanded: Double? = null,
    val seasonText: String? = null,
    val percentileText: String? = null,
    val percentileTier: PercentileTier = PercentileTier.Default,
    val rivalName: String? = null,
    val rivalDeltaText: String? = null,
    val rivalDeltaSign: Int = 0,
    val rivalFromSong: Boolean = false,
    val chips: List<SuggestionInstrumentChip> = emptyList(),
    val accessibleLabel: String = "",
) {
    companion object {
        /**
         * Right-side layout for a category key (web `getRowLayout`, band keys omitted).
         *
         * @param categoryKey Generator key.
         * @return Layout.
         */
        fun layoutFor(categoryKey: String): SuggestionRowLayout {
            val k = categoryKey.lowercase(Locale.ROOT)
            fun has(prefix: String) = k.startsWith(prefix)
            return when {
                has("song_rival_") || has("lb_rival_") -> SuggestionRowLayout.Rival
                has("variety_pack") || has("artist_sampler_") || has("artist_unplayed_") || has("unplayed_") ||
                    (has("samename_") && !has("samename_nearfc_")) -> SuggestionRowLayout.Hidden
                has("unfc_") -> SuggestionRowLayout.UnfcAccuracy
                has("stale_") -> SuggestionRowLayout.Season
                has("almost_elite") || has("pct_push") || has("pct_improve") || has("same_pct") || has("improve_rankings") ->
                    SuggestionRowLayout.Percentile
                has("near_fc") || has("almost_six_star") || has("more_stars") || has("first_plays_mixed") || has("star_gains") ||
                    has("samename_nearfc_") || has("near_max_") -> SuggestionRowLayout.SingleInstrument
                else -> SuggestionRowLayout.InstrumentChips
            }
        }

        /**
         * Key prefixes of rival categories built around one rival, whose title already names
         * that rival ("Rival Spotlight: {name}", "Close the Gap vs {name}", …).
         */
        private val singleRivalPrefixes = listOf(
            "song_rival_spotlight_", "song_rival_gap_", "song_rival_protect_",
            "song_rival_slipping_", "song_rival_dominate_",
        )

        /**
         * Whether a rival row draws the rival's name badge beside its rank difference (Apple
         * `SuggestionRowLayout.showsRivalName`). Single-rival cards name the rival in their title,
         * so a per-row badge only repeats it (issue #29); mixed-rival cards (Battleground and the
         * cross-pollination families) keep it because each row can be about a different rival.
         *
         * @param categoryKey Generator key.
         * @return False for single-rival categories, true otherwise.
         */
        fun showsRivalName(categoryKey: String): Boolean {
            val k = categoryKey.lowercase(Locale.ROOT)
            return singleRivalPrefixes.none { k.startsWith(it) }
        }

        /**
         * Spoken rank difference that names the rival (Apple `rivalDeltaAccessibilityLabel`).
         *
         * @param delta Player rank minus rival rank, signed so positive means the player leads.
         * @param rivalName Rival to name, or null/empty to omit it.
         * @return e.g. "3 ranks ahead of Name", "1 rank behind" or "Tied with Name".
         */
        fun rivalDeltaAccessibilityLabel(delta: Int, rivalName: String?): String {
            val magnitude = abs(delta)
            val ranks = if (magnitude == 1) "rank" else "ranks"
            if (rivalName.isNullOrEmpty()) {
                return if (delta == 0) "Tied" else "$magnitude $ranks ${if (delta > 0) "ahead" else "behind"}"
            }
            if (delta == 0) return "Tied with $rivalName"
            return "$magnitude $ranks ${if (delta > 0) "ahead of" else "behind"} $rivalName"
        }

        /**
         * Tier of a "Top N%" label.
         *
         * @param display Label.
         * @return Tier; default for an unparsable label.
         */
        fun tierFor(display: String?): PercentileTier {
            if (display == null || !display.startsWith("Top ") || !display.endsWith("%")) return PercentileTier.Default
            val pct = display.substring(4, display.length - 1).trim().toDoubleOrNull() ?: return PercentileTier.Default
            return when {
                pct <= 1 -> PercentileTier.Top1
                pct <= 5 -> PercentileTier.Top5
                else -> PercentileTier.Default
            }
        }

        /**
         * Build the presentation for one row.
         *
         * @param category Owning category.
         * @param item Row.
         * @param scores Selected player's score index (season pills, chips).
         * @param chipInstruments Charts to show chips for (Settings-visible, display order).
         * @param locale Number locale.
         * @return Presentation.
         */
        fun create(
            category: SuggestionCategory,
            item: SuggestionSongItem,
            scores: SuggestionScoreIndex?,
            chipInstruments: List<Instrument>,
            locale: Locale = Locale.getDefault(),
        ): SuggestionRowPresentation {
            val layout = layoutFor(category.key)
            val song = item.song
            val songScores = scores?.get(song.songId)
            val subtitle = song.year?.let { "${song.artist} · $it" } ?: song.artist
            var result = SuggestionRowPresentation(layout, song.title, subtitle)
            val details = mutableListOf<String>()
            when (layout) {
                SuggestionRowLayout.Rival -> {
                    val delta = item.rivalRankDelta ?: 0
                    val showsName = showsRivalName(category.key)
                    val name = item.rivalName?.takeIf { showsName }?.let { if (it.length > 12) it.take(11) + "…" else it }
                    result = result.copy(
                        instrument = item.instrument,
                        rivalName = name,
                        rivalDeltaSign = delta.sign,
                        rivalFromSong = category.key.lowercase(Locale.ROOT).startsWith("song_rival_"),
                        rivalDeltaText = when {
                            delta == 0 -> null
                            delta > 0 -> "+$delta"
                            else -> delta.toString()
                        },
                    )
                    val rival = item.rivalName?.takeIf { it.isNotEmpty() }
                    if (!showsName && rival != null && delta != 0) {
                        // No visible badge: the delta itself says which rival ("1 rank behind Name").
                        details += rivalDeltaAccessibilityLabel(delta, rival)
                    } else {
                        rival?.let { details += "rival $it" }
                        val ranks = if (abs(delta) == 1) "rank" else "ranks"
                        if (delta != 0) details += if (delta > 0) "ahead by $delta $ranks" else "behind by ${-delta} $ranks"
                    }
                }
                SuggestionRowLayout.UnfcAccuracy -> {
                    val percent = item.percent
                    if (percent != null && percent > 0) {
                        val expanded = floor(percent).coerceIn(0.0, 99.0) * 10_000
                        val text = ScoreFormatting.accuracy(expanded, locale)
                        result = result.copy(accuracyExpanded = expanded, accuracyText = text)
                        details += "$text% accuracy"
                    }
                }
                SuggestionRowLayout.Season -> {
                    val season = if (item.instrument != null) {
                        songScores?.get(item.instrument)?.season ?: 0
                    } else {
                        songScores?.values?.maxOfOrNull { it.season ?: 0 } ?: 0
                    }
                    if (season > 0) {
                        result = result.copy(seasonText = "S$season")
                        details += "last played season $season"
                    }
                }
                SuggestionRowLayout.Percentile -> {
                    result = result.copy(
                        instrument = item.instrument,
                        percentileText = item.percentileDisplay,
                        percentileTier = tierFor(item.percentileDisplay),
                    )
                    item.percentileDisplay?.let { details += it }
                }
                SuggestionRowLayout.SingleInstrument -> {
                    val stars = item.stars ?: 0
                    val showStars = category.key.startsWith("star_gains") && stars > 0
                    result = result.copy(
                        instrument = item.instrument,
                        starCount = if (showStars) (if (stars >= 6) 5 else stars) else 0,
                        goldStars = showStars && stars >= 6,
                    )
                    if (showStars) details += if (stars >= 6) "gold stars" else if (stars == 1) "1 star" else "$stars stars"
                }
                SuggestionRowLayout.InstrumentChips -> {
                    result = result.copy(
                        chips = chipInstruments.map { instrument ->
                            val chart = songScores?.get(instrument)
                            SuggestionInstrumentChip(instrument, (chart?.stars ?: 0) > 0, chart?.isFullCombo == true)
                        },
                    )
                }
                SuggestionRowLayout.Hidden -> Unit
            }
            result.instrument?.let { details.add(0, it.label) }
            return result.copy(accessibleLabel = (listOf(song.title, subtitle) + details).joinToString(", "))
        }
    }
}

// endregion
