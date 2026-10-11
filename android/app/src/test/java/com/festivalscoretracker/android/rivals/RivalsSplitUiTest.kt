package com.festivalscoretracker.android.rivals

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Rivals on a landscape tablet: Rival Detail opens beside the hub (#583, Duo `ListPage.rivals`). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class RivalsSplitUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val ids = RivalsFixtures.RIVALS

    private val transport = RivalsFixtures.transport().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(100); exists(tag) }

    private fun inPane(tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag("fst.split.trailing")), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun systemBack() {
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        settle()
    }

    @Test
    fun rivalDetailOpensBesideTheHubAndRivalryStaysInThePane() {
        val debug = DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
        waitForTag("fst.rivals.section.common")
        rule.onAllNodesWithTag("fst.rivals.row.${ids[1]}")[0].performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.split.trailing")
        waitForTag("fst.rival-detail.title")
        assertTrue(inPane("fst.rival-detail.title"))
        // The hub stays beside it.
        assertTrue(exists("fst.rivals.section.common"))

        // The open rival's own sub-page (Rivalry) pushes inside the pane, with Back instead of Close.
        rule.onAllNodesWithTag("fst.rival-detail.see-all.closest_battles")[0].performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rivalry.title")
        assertTrue(inPane("fst.rivalry.title"))
        assertFalse(inPane("fst.split.close"))
        assertTrue(exists("fst.rivals.section.common"))

        // Back walks the pane first: Rivalry → Rival Detail → pane closed, the hub kept.
        systemBack()
        rule.waitUntil(10_000) { settle(100); !exists("fst.rivalry.title") }
        assertTrue(inPane("fst.rival-detail.title"))
        assertTrue(inPane("fst.split.close"))
        systemBack()
        rule.waitUntil(10_000) { settle(100); !exists("fst.split.trailing") }
        assertTrue(exists("fst.rivals.section.common"))
        assertFalse(rule.activity.isFinishing)
    }
}
