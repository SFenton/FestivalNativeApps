package com.festivalscoretracker.android.firstrun

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
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

/** First-run dialog footer: Done-only single slides, M3 Back-then-Next order (issue #25), 48 dp named buttons, viewed count. */
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
    fun backSitsBeforeNextAndClosingReportsTheSlidesSeen() {
        var viewed = -1
        rule.setContent { FestivalTheme { FirstRunCarouselDialog(FirstRunCarousel(2, FirstRunPageKey.Songs, songs.take(3), isReplay = false), compact = true) { viewed = it } } }
        assertTrue(!exists("fst.first-run.skip") && !exists("fst.first-run.back"))
        val firstNext = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        val back = rule.onNodeWithTag("fst.first-run.back").fetchSemanticsNode().boundsInRoot
        // Material 3 dialog actions: the confirming action is last (issue #25).
        assertTrue("Back comes before Next/Done", back.right <= next.left)
        assertEquals("Next keeps its place when Back appears", firstNext, next)
        rule.onNodeWithTag("fst.first-run.back").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("fst.first-run.close").performClick()
        rule.waitForIdle()
        // Went back to slide 1, but slide 2 was displayed too.
        assertEquals(2, viewed)
    }

    @Test
    fun doneOnTheLastSlideStaysWhereNextWas() {
        rule.setContent { FestivalTheme { FirstRunCarouselDialog(FirstRunCarousel(3, FirstRunPageKey.Songs, songs.take(2), isReplay = false), compact = true) { } } }
        val next = rule.onNodeWithTag("fst.first-run.next").fetchSemanticsNode().boundsInRoot
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        assertTrue(!exists("fst.first-run.next"))
        assertEquals(next.right, rule.onNodeWithTag("fst.first-run.done").fetchSemanticsNode().boundsInRoot.right)
    }

    @Test
    fun everyControlIsANamedButtonWithA48dpTarget() {
        rule.setContent { FestivalTheme { FirstRunCarouselDialog(FirstRunCarousel(4, FirstRunPageKey.Songs, songs.take(3), isReplay = false), compact = true) { } } }
        val minTarget = with(rule.density) { 48.dp.toPx() } - 1f
        fun check(tag: String, name: String) {
            rule.onNodeWithTag(tag).assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
            assertTrue("$tag is at least 48 dp wide and tall", node.touchBoundsInRoot.width >= minTarget && node.touchBoundsInRoot.height >= minTarget)
            val config = node.config
            val label = config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() } + config.getOrElse(SemanticsProperties.Text) { emptyList() }.map { it.text }
            assertEquals(tag, listOf(name), label)
        }
        check("fst.first-run.close", "Close")
        check("fst.first-run.next", "Next")
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        check("fst.first-run.back", "Back")
        rule.onNodeWithTag("fst.first-run.next").performClick()
        rule.waitForIdle()
        check("fst.first-run.done", "Done")
    }
}
