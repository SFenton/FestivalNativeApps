package com.festivalscoretracker.android.ui.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.festivalscoretracker.android.core.format.ScoreAccuracyBadge
import com.festivalscoretracker.android.ui.theme.BrandTokens
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `badge-contrast`: across the whole accuracy ramp, on every surface a score row sits on
 * (card, frosted card over the app background, the selected player's purple row), the
 * badge text meets WCAG 4.5:1 and the full-combo outline meets the 3:1 non-text minimum.
 */
class ScoreAccuracyContrastTest {
    private fun rgb(color: Color) = color.toArgb() and 0xFFFFFF

    private fun over(color: Color, bottom: Int) = ScoreAccuracyContrast.composite(rgb(color), color.alpha, bottom)

    private val frosted = over(BrandTokens.surfaceFrosted, rgb(BrandTokens.appBackground))

    private val backdrops = mapOf(
        "card" to rgb(BrandTokens.cardBackground),
        "frosted" to frosted,
        "selected" to over(BrandTokens.purpleHighlight, frosted),
    )

    @Test
    fun gradedTextMeetsFourAndAHalfToOneOnEveryBackdrop() {
        backdrops.forEach { (name, backdrop) ->
            for (step in 0..100) {
                val tint = ScoreAccuracyBadge.of(step * 10_000.0, false)!!.tint!!
                val fill = ScoreAccuracyContrast.composite(tint, ScoreAccuracyBadge.GRADED_TINT_ALPHA, backdrop)
                val ratio = ScoreAccuracyContrast.ratio(rgb(BrandTokens.textPrimary), fill)
                assertTrue("$name $step%: $ratio", ratio >= 4.5)
            }
        }
    }

    @Test
    fun goldTextAndOutlineMeetTheirMinimums() {
        backdrops.forEach { (name, backdrop) ->
            val text = ScoreAccuracyContrast.ratio(rgb(BrandTokens.gold), backdrop)
            val outline = ScoreAccuracyContrast.ratio(rgb(BrandTokens.goldStroke), backdrop)
            assertTrue("$name gold text $text", text >= 4.5)
            assertTrue("$name gold outline $outline", outline >= 3.0)
        }
    }

    @Test
    fun invalidPillTextMeetsFourAndAHalfToOne() {
        val ratio = ScoreAccuracyContrast.ratio(rgb(BrandTokens.textPrimary), rgb(BrandTokens.surfaceMuted))
        assertTrue("$ratio", ratio >= 4.5)
    }
}
