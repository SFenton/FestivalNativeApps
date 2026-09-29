package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoadGate
import com.festivalscoretracker.android.ui.common.festivalEmptyStateItem
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Shared load gate (6.41) and empty state (6.33). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class LoadGateUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun count(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    @Test
    fun spinnerUntilReadyThenFadeThenContent() {
        var ready by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                FestivalLoadGate(ready, Modifier.fillMaxSize()) { Text("Row", Modifier.staggered(0).testTag("row")) }
            }
        }
        rule.mainClock.advanceTimeByFrame()
        assertTrue(count("fst.load-gate.spinner") == 1 && count("row") == 0)
        ready = true
        rule.mainClock.advanceTimeBy(100)
        // Still fading the spinner: content is not composed yet.
        assertTrue(count("fst.load-gate.spinner") == 1 && count("row") == 0)
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(count("fst.load-gate.spinner") == 0 && count("row") == 1)
        rule.mainClock.autoAdvance = true
        // Content already in stays up through a refresh.
        ready = false
        rule.waitForIdle()
        assertTrue(count("row") == 1)
    }

    @Test
    fun readyDataShowsAtOnce() {
        rule.setContent { FestivalTheme { FestivalLoadGate(true, Modifier.fillMaxSize()) { Text("Row", Modifier.staggered(3).testTag("row")) } } }
        rule.onNodeWithTag("row").assertIsDisplayed()
        assertTrue(count("fst.load-gate.spinner") == 0)
    }

    @Test
    fun emptyStateCentresVerticallyInAList() {
        rule.setContent {
            FestivalTheme {
                LazyColumn(Modifier.fillMaxSize().testTag("list")) {
                    item { Text("Header") }
                    festivalEmptyStateItem("No songs", subtitle = "Try another search", tag = "empty")
                }
            }
        }
        val list = rule.onNodeWithTag("list").getBoundsInRoot()
        val title = rule.onNodeWithText("No songs").getBoundsInRoot()
        val centre = (title.top + title.bottom) / 2
        // Vertically near the middle of the viewport, not just below the header row.
        assertTrue("title centre $centre in list ${list.top}..${list.bottom}", centre > list.top + (list.bottom - list.top) / 3)
        rule.onNodeWithText("Try another search").assertIsDisplayed()
    }

    @Test
    fun standaloneEmptyStateWithIcon() {
        rule.setContent { FestivalTheme { FestivalEmptyState("Nothing here", icon = { Text("★") }) } }
        rule.onNodeWithText("Nothing here").assertIsDisplayed()
        rule.onNodeWithText("★").assertIsDisplayed()
    }
}
