package com.festivalscoretracker.android.suggestions

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.core.suggestions.SuggestionCategory
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.core.suggestions.SuggestionSongItem
import com.festivalscoretracker.android.presentation.suggestions.SuggestionCard
import com.festivalscoretracker.android.presentation.suggestions.SuggestionRow
import com.festivalscoretracker.android.ui.suggestions.SuggestionCardView
import com.festivalscoretracker.android.ui.suggestions.SuggestionTokens
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Rival rows on Suggestions (issues #29/#59, validated in #167), checked on rendered pixels
 * because each row clears its children's semantics into one TalkBack label: single-rival cards
 * (Rival Spotlight) draw only the rank delta and icon — never the rival name badge — while
 * TalkBack still names the rival; mixed-rival cards keep the badge; the "behind" delta is
 * readable text (≥ 4.5:1) at phone and wide widths and font scale 1.0 and 2.0.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h1400dp-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SuggestionRivalRowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Fixtures

    private fun song(id: String) = Song(id, "Rival Track $id", "Rival Artist", year = 2001, difficulty = SongDifficulty(guitar = 2.0))

    private val behind = SuggestionSongItem(song("a"), Instrument.Lead, rivalName = "TempoTide", rivalRankDelta = -2)
    private val ahead = SuggestionSongItem(song("b"), Instrument.Bass, rivalName = "TempoTide", rivalRankDelta = 3)
    private val mixed = SuggestionSongItem(song("c"), Instrument.Drums, rivalName = "TempoTide", rivalRankDelta = -1)

    private fun card(key: String, title: String, vararg items: SuggestionSongItem): SuggestionCard {
        val category = SuggestionCategory(key, title, "Description", SuggestionCategoryType.SongRivals, null, items.toList())
        val rows = items.map { SuggestionRow(it.id, SuggestionRowPresentation.create(category, it, null, emptyList()), it.song.songId, null, false) }
        return SuggestionCard(key, category, rows)
    }

    private val spotlight = card("song_rival_spotlight_r1", "Rival Spotlight: TempoTide", behind, ahead)
    private val battleground = card("song_rival_battleground", "Rival Battleground", mixed)

    /** One rendered configuration: card, column width, narrow (two-line) rows and font scale. */
    private data class Setup(val card: SuggestionCard, val widthDp: Int, val narrow: Boolean, val fontScale: Float)

    private var setup by mutableStateOf(Setup(spotlight, 360, true, 1f))

    private val configurations = listOf(360 to true, 600 to false).flatMap { (w, n) -> listOf(1f, 2f).map { Triple(w, n, it) } }

    private fun showCard() {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                val base = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(base.density, setup.fontScale)) {
                    Column(Modifier.width(setup.widthDp.dp)) {
                        SuggestionCardView(setup.card, setup.narrow, artworkUrl = { null }, onSong = {})
                    }
                }
            }
        }
        settle()
    }

    private fun settle() = repeat(3) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    // endregion

    // region Tests

    @Test
    fun spotlightRowsDrawOnlyTheDeltaAndIconInEveryWidthAndFontScale() {
        showCard()
        for ((width, narrow, scale) in configurations) {
            setup = Setup(spotlight, width, narrow, scale)
            settle()
            val where = "width $width, narrow $narrow, font $scale"
            val behindRow = capture(rowTag(behind))
            assertFalse("song-rival badge on a Spotlight row ($where)", hasColour(behindRow, SuggestionTokens.songRival))
            assertFalse("leaderboard-rival badge on a Spotlight row ($where)", hasColour(behindRow, SuggestionTokens.leaderboardRival))
            assertTrue("readable behind delta missing or clipped ($where)", hasColour(behindRow, SuggestionTokens.rivalBehindText))
            assertFalse("behind delta still uses the statusRed fill ($where)", hasColour(behindRow, BrandTokens.statusRed))
            val aheadRow = capture(rowTag(ahead))
            assertFalse("song-rival badge on a Spotlight row ($where)", hasColour(aheadRow, SuggestionTokens.songRival))
            assertTrue("ahead delta missing or clipped ($where)", hasColour(aheadRow, BrandTokens.statusGreen))
            listOf(behind, ahead).forEach { rule.onNodeWithTag(rowTag(it)).assertHeightIsAtLeast(48.dp) }
        }
        rule.onNodeWithContentDescription("Rival Track a, Rival Artist · 2001, Lead, 2 ranks behind TempoTide").assertExists()
        rule.onNodeWithContentDescription("Rival Track b, Rival Artist · 2001, Bass, 3 ranks ahead of TempoTide").assertExists()
    }

    @Test
    fun mixedRivalRowsKeepTheBadgeBesideTheDelta() {
        showCard()
        for ((width, narrow, scale) in configurations) {
            setup = Setup(battleground, width, narrow, scale)
            settle()
            val row = capture(rowTag(mixed))
            val where = "width $width, narrow $narrow, font $scale"
            assertTrue("mixed-rival badge missing ($where)", hasColour(row, SuggestionTokens.songRival))
            assertTrue("behind delta missing ($where)", hasColour(row, SuggestionTokens.rivalBehindText))
        }
        rule.onNodeWithContentDescription("Rival Track c, Rival Artist · 2001, Drums, rival TempoTide, behind by 1 rank").assertExists()
    }

    @Test
    fun deltaTextMeetsAaContrastOnTheCardOverAnyBackdrop() {
        // Backdrops behind the frosted card: the plain brand surface, and the brightest
        // possible art (white multiplied by ArtworkBackground's 0.3 dim).
        val backdrops = listOf(BrandTokens.appBackground, Color(0.3f, 0.3f, 0.3f))
        val surfaces = backdrops.map { BrandTokens.surfaceFrosted.compositeOver(it) } + BrandTokens.cardBackground
        for (surface in surfaces) {
            assertTrue(contrast(SuggestionTokens.rivalBehindText, surface) >= 4.5)
            assertTrue(contrast(BrandTokens.statusGreen, surface) >= 4.5)
        }
        // The #167 finding: the statusRed fill as text fails AA on the card.
        assertTrue(surfaces.all { contrast(BrandTokens.statusRed, it) < 4.5 })
    }

    // endregion

    // region Helpers

    private fun rowTag(item: SuggestionSongItem) = "fst.suggestions.row.${item.id}"

    /** The rendered pixels of one node, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun capture(tag: String): Bitmap {
        val b = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        val bottom = min(b.bottom.toInt(), whole.height)
        assertTrue("$tag is off screen", b.top.toInt() < bottom)
        return Bitmap.createBitmap(whole, b.left.toInt(), b.top.toInt(), b.width.toInt().coerceAtLeast(1), bottom - b.top.toInt())
    }

    private fun hasColour(bitmap: Bitmap, colour: Color, tolerance: Int = 14): Boolean {
        val target = colour.toArgb()
        for (x in 0 until bitmap.width) for (y in 0 until bitmap.height) {
            val p = bitmap.getPixel(x, y)
            if (abs(android.graphics.Color.red(p) - android.graphics.Color.red(target)) <= tolerance &&
                abs(android.graphics.Color.green(p) - android.graphics.Color.green(target)) <= tolerance &&
                abs(android.graphics.Color.blue(p) - android.graphics.Color.blue(target)) <= tolerance
            ) {
                return true
            }
        }
        return false
    }

    private fun contrast(a: Color, b: Color): Double {
        val l1 = a.luminance().toDouble()
        val l2 = b.luminance().toDouble()
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // endregion
}
