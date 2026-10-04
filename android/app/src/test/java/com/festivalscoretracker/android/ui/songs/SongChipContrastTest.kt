package com.festivalscoretracker.android.ui.songs

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.festivalscoretracker.android.core.songs.SongInstrumentStatus
import com.festivalscoretracker.android.ui.design.ScoreAccuracyContrast
import com.festivalscoretracker.android.ui.theme.BrandTokens
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `high-contrast` / color-only cue (#134): every instrument status chip keeps a 3:1 non-text
 * boundary (fill or ring, WCAG 1.4.11; material-3 "3:1 for … borders") on each surface a
 * Songs row sits on: the opaque card (Increase Contrast / Reduce Transparency), the frosted
 * card over the app background, and the two-pane selected row's purple highlight over both.
 */
class SongChipContrastTest {
    private fun rgb(color: Color) = color.toArgb() and 0xFFFFFF

    private fun over(color: Color, alpha: Float, bottom: Int) = ScoreAccuracyContrast.composite(rgb(color), alpha, bottom)

    private val card = rgb(BrandTokens.cardBackground)
    private val frosted = over(BrandTokens.surfaceFrosted, BrandTokens.surfaceFrosted.alpha, rgb(BrandTokens.appBackground))

    /** `SongRowCard`'s selected background: `accentPurple` at 0.35. */
    private fun selected(bottom: Int) = over(BrandTokens.accentPurple, SELECTED_ALPHA, bottom)

    private fun boundary(status: SongInstrumentStatus, selectedRow: Boolean, backdrop: Int): Double {
        val (fill, stroke) = SongsTokens.chip(status, selectedRow)
        return maxOf(ScoreAccuracyContrast.ratio(rgb(fill), backdrop), ScoreAccuracyContrast.ratio(rgb(stroke), backdrop))
    }

    @Test
    fun everyStatusClearsThreeToOneOnPlainRows() {
        mapOf("card" to card, "frosted" to frosted).forEach { (name, backdrop) ->
            SongInstrumentStatus.entries.forEach { status ->
                val ratio = boundary(status, selectedRow = false, backdrop)
                assertTrue("$name $status $ratio", ratio >= 3.0)
            }
        }
    }

    @Test
    fun everyStatusClearsThreeToOneOnTheSelectedRow() {
        mapOf("selected-frosted" to selected(frosted), "selected-card" to selected(card)).forEach { (name, backdrop) ->
            SongInstrumentStatus.entries.forEach { status ->
                val ratio = boundary(status, selectedRow = true, backdrop)
                assertTrue("$name $status $ratio", ratio >= 3.0)
            }
        }
    }

    @Test
    fun plainRowsKeepTheSharedTokens() {
        assertEquals(BrandTokens.statusRed to SongsTokens.statusRedStroke, SongsTokens.chip(SongInstrumentStatus.NoScore))
        assertEquals(BrandTokens.surfaceMuted to BrandTokens.textDisabled, SongsTokens.chip(SongInstrumentStatus.Unavailable))
        assertEquals(SongsTokens.chip(SongInstrumentStatus.FullCombo), SongsTokens.chip(SongInstrumentStatus.FullCombo, selected = true))
        assertEquals(SongsTokens.chip(SongInstrumentStatus.Scored), SongsTokens.chip(SongInstrumentStatus.Scored, selected = true))
    }

    private companion object {
        const val SELECTED_ALPHA = 0.35f
    }
}
