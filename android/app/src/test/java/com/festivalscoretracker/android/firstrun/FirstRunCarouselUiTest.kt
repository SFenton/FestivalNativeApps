package com.festivalscoretracker.android.firstrun

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel
import com.festivalscoretracker.android.ui.firstrun.FirstRunCarouselDialog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** First-run dialog footer (operator batch 6.7): Done-only single slides, Next before Back, viewed count. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunCarouselUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = FirstRunCatalog.slides(FirstRunPageKey.Songs, true)

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun oneSlideGuideShowsOnlyDone() {
        var viewed = -1
        rule.setContent { FestivalTheme { FirstRunCarouselDialog(FirstRunCarousel(1, FirstRunPageKey.Songs, songs.take(1), isReplay = false), compact = true) { viewed = it } } }
        assertTrue(exists("fst.first-run.done"))
        assertTrue(!exists("fst.first-run.skip") && !exists("fst.first-run.back") && !exists("fst.first-run.next"))
        rule.onNodeWithTag("fst.first-run.done").performClick()
        rule.waitForIdle()
        assertEquals(1, viewed)
    }

    @Test
    fun nextSitsBeforeBackAndClosingReportsTheSlidesSeen() {
        var viewed = -1
        rule.setContent { FestivalTheme { FirstRunCarouselDialog(FirstRunCarousel(2, FirstRunPageKey.Songs, songs.take(3), isReplay = false), compact = true) { viewed = it } } }
        assertTrue(!exists("fst.first-run.skip") && !exists("fst.first-run.back"))
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        val back = rule.onNodeWithTag("fst.first-run.back").fetchSemanticsNode().boundsInRoot
        assertTrue("Next/Done comes before Back", next.right <= back.left)
        rule.onNodeWithTag("fst.first-run.back").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("fst.first-run.close").performClick()
        rule.waitForIdle()
        // Went back to slide 1, but slide 2 was displayed too.
        assertEquals(2, viewed)
    }
}
