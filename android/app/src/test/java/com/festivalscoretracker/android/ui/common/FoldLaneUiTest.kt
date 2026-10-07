package com.festivalscoretracker.android.ui.common

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
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
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsPhase
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsUiState
import com.festivalscoretracker.android.ui.rivals.AdaptiveCardGrid
import com.festivalscoretracker.android.ui.suggestions.SuggestionsActions
import com.festivalscoretracker.android.ui.suggestions.SuggestionsScreenContent
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Issue #343: in book posture (separating vertical hinge) full-line titles, subtitles and
 * messages in hinge-splitting grids stay in the leading pane, and unfolding flat reflows
 * them to the full line without recreating their content.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h800dp-xhdpi")
class FoldLaneUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    private fun bookHinge(width: Float) =
        HingeInfo(Rect(width * 0.5f, 0f, width * 0.5f, 5000f), isFlat = false, isVertical = true, isSeparating = true, isOccluding = false)

    private fun right(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow.right

    @Test
    fun cardGridHeaderStaysOnItsSideAndReflowsWhenUnfolded() {
        var folded by mutableStateOf(true)
        var hingeX = 0f
        val created = mutableListOf<Any>()
        rule.setContent {
            val width = LocalView.current.rootView.width.toFloat()
            hingeX = width * 0.5f
            val posture = if (folded) Posture(isTabletop = false, hingeList = listOf(bookHinge(width))) else Posture()
            CompositionLocalProvider(LocalShellPosture provides posture) {
                FestivalTheme(appReduceMotion = true) {
                    AdaptiveCardGrid(contentPadding = PaddingValues(0.dp), maxColumns = 2) {
                        foldLaneItem(key = "header") {
                            created += remember { Any() }
                            Box(Modifier.fillMaxWidth().testTag("header")) {
                                Text("Instrument Statistics " + "subtitle words that keep going ".repeat(12))
                            }
                        }
                        items(4) { index -> Box(Modifier.height(80.dp).testTag("card$index")) }
                    }
                }
            }
        }
        settle()
        assertTrue("header ends before the hinge (${right("header")} > $hingeX)", right("header") <= hingeX + 1f)
        assertTrue("cards fill the trailing pane", right("card1") > hingeX)

        folded = false
        settle()
        assertTrue("unfolded header uses the full line (${right("header")})", right("header") > hingeX + 1f)
        assertEquals("unfolding reflows without recreating the header", 1, created.distinct().size)
    }

    @Test
    fun suggestionsMixLimitFooterStaysOffTheFold() {
        var hingeX = 0f
        val song = Song("a", "Fold Track", "Fold Artist", year = 1999, difficulty = SongDifficulty(guitar = 2.0))
        val category = SuggestionCategory("pct_push", "Title", "Description", SuggestionCategoryType.NearFC, null, listOf(SuggestionSongItem(song, Instrument.Lead)))
        val rows = category.songs.map { SuggestionRow(it.id, SuggestionRowPresentation.create(category, it, emptyMap(), Instrument.entries.take(3)), it.song.songId, null, false) }
        val state = SuggestionsUiState(SuggestionsPhase.Loaded, cards = listOf(SuggestionCard("pct_push", category, rows)), reachedLimit = true)
        rule.setContent {
            val width = LocalView.current.rootView.width.toFloat()
            hingeX = width * 0.5f
            CompositionLocalProvider(LocalShellPosture provides Posture(isTabletop = false, hingeList = listOf(bookHinge(width)))) {
                FestivalTheme(appReduceMotion = true) {
                    SuggestionsScreenContent(state, isRoot = true, artworkUrl = { null }, onSong = {}, actions = SuggestionsActions({}, {}, {}, {}))
                }
            }
        }
        settle()
        rule.onNodeWithTag("fst.suggestions.list").performScrollToNode(hasTestTag("fst.suggestions.mix-limit"))
        settle()
        assertTrue("Start a New Mix stays before the hinge", right("fst.suggestions.start-new-mix") <= hingeX + 1f)
        assertTrue("the limit message stays before the hinge", right("fst.suggestions.mix-limit") <= hingeX + 1f)
    }
}
