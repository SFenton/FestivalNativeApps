package com.festivalscoretracker.android.core.format

import java.util.Locale

// region Score accuracy badge

/**
 * What the score-accuracy control (`fst.score.accuracy.*`, `.agents/controls/score-accuracy/spec.md`)
 * draws for one score: the web `AccuracyDisplay` notation (percentage in a red→green pill, or
 * in the gold outline for a full combo) with the native rules for data the web papers over —
 * a full combo without accuracy reads `FC` instead of an invented `0%`, a non-finite accuracy
 * is rejected instead of tinted, and FC is never inferred from the number.
 *
 * @property kind Which treatment to draw.
 * @property text Compact visible label (`98.7%`, `FC`, `—`).
 * @property announcement TalkBack label; also the visible label at large font scales.
 * @property tint Packed `0xRRGGBB` pill tint for [Kind.Graded] (the caller applies
 *   [GRADED_TINT_ALPHA]); null for every other kind.
 */
data class ScoreAccuracyBadge(
    val kind: Kind,
    val text: String,
    val announcement: String,
    val tint: Int?,
) {
    /** Badge treatments. */
    enum class Kind {
        /** Accuracy without a full combo: tinted pill. */
        Graded,

        /** Full combo with accuracy: gold outlined percentage. */
        FullCombo,

        /** Full combo whose accuracy is missing or non-finite: gold outlined `FC`. */
        FullComboNoAccuracy,

        /** Non-finite accuracy without a full combo: neutral pill, never a tint. */
        Invalid,
    }

    companion object {
        /** Web `accuracyBgColor`: the graded tint is drawn at 25% opacity. */
        const val GRADED_TINT_ALPHA = 0.25f

        /**
         * The badge for one score, or null when there is nothing to show (no accuracy and no
         * full combo): the row keeps an empty slot in the column instead.
         *
         * @param accuracy Accuracy in ten-thousandths of a percent (1,000,000 = 100%), or null.
         *   Out-of-range values keep their number; only the tint clamps.
         * @param isFullCombo The service's full-combo flag (null = not a full combo).
         * @param locale Number formatting locale.
         * @return Badge, or null for the absent state.
         */
        fun of(accuracy: Double?, isFullCombo: Boolean?, locale: Locale = Locale.getDefault()): ScoreAccuracyBadge? {
            val fullCombo = isFullCombo == true
            if (accuracy == null || !accuracy.isFinite()) {
                return when {
                    fullCombo -> ScoreAccuracyBadge(Kind.FullComboNoAccuracy, "FC", "Full combo; accuracy unavailable", null)
                    accuracy == null -> null
                    else -> ScoreAccuracyBadge(Kind.Invalid, "—", "Accuracy unavailable", null)
                }
            }
            val percent = "${ScoreFormatting.accuracy(accuracy, locale)}%"
            return if (fullCombo) {
                ScoreAccuracyBadge(Kind.FullCombo, percent, "Full combo, accuracy $percent", null)
            } else {
                ScoreAccuracyBadge(Kind.Graded, percent, "Accuracy $percent", ScoreFormatting.accuracyTint(accuracy))
            }
        }
    }

    /** Whether the badge uses the gold full-combo outline. */
    val isGold: Boolean get() = kind == Kind.FullCombo || kind == Kind.FullComboNoAccuracy
}

// endregion
