package com.festivalscoretracker.android.rivals

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// region Return columns

/**
 * Compete on a wide window, where board rows have room for the songs column (issue #38), with
 * real text measurement. Returning from View Full Leaderboard (issues #82, #185) must not drop
 * the column for a frame while the card re-measures its rows.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CompeteReturnColumnsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val songsCell = SemanticsMatcher("songs cell") { node ->
        node.config.getOrElse(SemanticsProperties.Text) { emptyList() }.any { Regex("""^\d+ / \d+$""").matches(it.text) }
    }

    @Test
    fun returningFromFullLeaderboardKeepsTheSongsColumnOnEveryFrame() {
        val debug = DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = CompeteFixtures.transport(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        val card = "fst.compete.leaderboard-card.Solo_Guitar"
        val button = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag(card)))
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.waitForIdle()
            rule.onAllNodes(button).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNode(hasTestTag("fst.compete.grid")).performScrollToNode(button)
        repeat(20) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        val cells = songsCell.and(hasAnyAncestor(hasTestTag(card)))
        fun songsShown() = rule.onAllNodes(cells, useUnmergedTree = true).fetchSemanticsNodes().size
        val before = songsShown()
        assertTrue("Wide Compete rows should show the songs column", before > 0)

        rule.onNode(button).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.onAllNodesWithTag("fst.compete.grid").fetchSemanticsNodes().isEmpty()
        }
        repeat(10) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }

        rule.mainClock.autoAdvance = false
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        val frames = mutableListOf<Int>()
        repeat(60) {
            rule.mainClock.advanceTimeByFrame()
            shadowOf(Looper.getMainLooper()).idle()
            if (rule.onAllNodes(button).fetchSemanticsNodes().isNotEmpty()) frames += songsShown()
        }
        rule.mainClock.autoAdvance = true
        assertTrue("Compete never reappeared", frames.isNotEmpty())
        assertTrue("The songs column dropped out while returning: $before before, frames $frames", frames.all { it == before })
    }
}

// endregion
