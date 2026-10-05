package com.festivalscoretracker.android.suggestions

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
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
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsPhase
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsUiState
import com.festivalscoretracker.android.ui.suggestions.SuggestionsActions
import com.festivalscoretracker.android.ui.suggestions.SuggestionsScreenContent
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Suggestions fades only newly generated batches (issues #60 and #168, web
 * `getCardDelay`): cards already shown stay drawn in full while the next batch fades in.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SuggestionsBatchFadeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Helpers

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4)); rule.waitForIdle()
    }

    private fun card(key: String): SuggestionCard {
        val item = SuggestionSongItem(Song(key, "Track $key", "Artist $key", year = 2001, difficulty = SongDifficulty(guitar = 2.0)), Instrument.Lead)
        val category = SuggestionCategory(key, "Title $key", "Description $key", SuggestionCategoryType.NearFC, Instrument.Lead, listOf(item))
        val row = SuggestionRow(item.id, SuggestionRowPresentation.create(category, item, null, listOf(Instrument.Lead)), key, null, false)
        return SuggestionCard(key, category, listOf(row))
    }

    private fun bounds(key: String): Rect = rule.onNodeWithTag("fst.suggestions.category.$key").fetchSemanticsNode().boundsInRoot

    /** ARGB pixels of the window inside [bounds] (root px), drawn with the clock paused. */
    private fun pixels(bounds: Rect): IntArray {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        val origin = IntArray(2)
        rule.runOnUiThread {
            root.draw(Canvas(bitmap))
            rule.activity.findViewById<View>(android.R.id.content).getLocationInWindow(origin)
        }
        val left = (origin[0] + bounds.left).toInt().coerceIn(0, bitmap.width - 1)
        val top = (origin[1] + bounds.top).toInt().coerceIn(0, bitmap.height - 1)
        val right = (origin[0] + bounds.right).toInt().coerceIn(left + 1, bitmap.width)
        val bottom = (origin[1] + bounds.bottom).toInt().coerceIn(top + 1, bitmap.height)
        val out = IntArray((right - left) * (bottom - top))
        bitmap.getPixels(out, 0, right - left, left, top, right - left, bottom - top)
        return out
    }

    /** Share of pixels whose channels differ by more than 24 levels. */
    private fun changedShare(a: IntArray, b: IntArray): Float {
        if (a.size != b.size) return 1f
        val changed = a.indices.count { i ->
            (0..16 step 8).any { shift -> kotlin.math.abs(((a[i] shr shift) and 0xFF) - ((b[i] shr shift) and 0xFF)) > 24 }
        }
        return changed.toFloat() / a.size
    }

    // endregion

    @Test
    fun aNewBatchFadesInWhileShownCardsStayDrawn() {
        var state by mutableStateOf(SuggestionsUiState(SuggestionsPhase.Loaded, cards = listOf(card("first")), hasMore = true))
        rule.setContent {
            FestivalTheme(appReduceMotion = false) {
                SuggestionsScreenContent(state, isRoot = true, artworkUrl = { null }, onSong = {}, actions = SuggestionsActions())
            }
        }
        settle(3_000)
        val first = bounds("first")
        val firstSettled = pixels(first)

        rule.mainClock.autoAdvance = false
        state = state.copy(cards = listOf(card("first"), card("second")))
        val firstFrames = mutableListOf<Float>()
        val secondFrames = mutableListOf<IntArray>()
        var second: Rect? = null
        repeat(6) {
            rule.mainClock.advanceTimeByFrame()
            firstFrames += changedShare(pixels(first), firstSettled)
            if (second == null && rule.onAllNodesWithTag("fst.suggestions.category.second").fetchSemanticsNodes().isNotEmpty()) second = bounds("second")
            second?.let { secondFrames += pixels(it) }
        }
        rule.mainClock.advanceTimeBy(3_000)
        val secondSettled = pixels(checkNotNull(second) { "the new card never composed" })
        rule.mainClock.autoAdvance = true

        assertTrue("shown card unchanged while the batch arrives: $firstFrames", firstFrames.all { it < MAX_CHANGED })
        val fading = secondFrames.map { changedShare(it, secondSettled) }
        assertTrue("new card fades in: $fading", fading.last() > FADING)
    }

    private companion object {
        const val MAX_CHANGED = 0.005f

        /** Mid-fade, a card's text and surface differ from its settled pixels. */
        const val FADING = 0.05f
    }
}
