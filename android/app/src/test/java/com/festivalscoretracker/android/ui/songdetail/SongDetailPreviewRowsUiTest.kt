package com.festivalscoretracker.android.ui.songdetail

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Song Detail top-ten preview rows (issue #63, iOS #33): account rows are one TalkBack
 * button whose click label names the destination and open the player; a row without an
 * account is not actionable; Back returns to Song Detail.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongDetailPreviewRowsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val other = "abcdefabcdefabcdefabcdefabcdef01"
    private val board = """{"songId":"s-alpha","instrument":"Solo_Guitar","count":3,"totalEntries":60,"localEntries":60,"entries":[
      {"accountId":"$other","displayName":"Other Player","score":99999,"rank":1,"accuracy":990000,"isFullCombo":false},
      {"accountId":"","displayName":"","score":99998,"rank":2,"accuracy":990000,"isFullCombo":false},
      {"accountId":"${Fixtures.ACCOUNT_B}","displayName":"Second Player","score":99997,"rank":3,"accuracy":990000,"isFullCombo":false}]}"""

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":1,"scores":[
          {"si":"s-alpha","ins":"01","sc":50000,"acc":900,"fc":false,"st":5,"sn":15,"dif":3,"rk":42,"te":60,"lp":"2026-09-01T12:00:00Z"}]}
    """.trimIndent()

    private val transport = FakeTransport.standard().apply {
        on("/api/leaderboard/s-alpha/Solo_Guitar") { board }
        on("/api/player/${Fixtures.ACCOUNT_A}") { profileJson }
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4)); rule.waitForIdle()
    }

    private fun waitForTag(tag: String) = rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun row(id: String) = "fst.song-detail.preview-row.Solo_Guitar.$id"

    @Test
    fun previewRowsOpenProfilesAndBackReturns() {
        val debug = DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), songQuery = "s-alpha", stillBackground = true)
        rule.setContent { FestivalApp(AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences()), debug) }
        settle()
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        waitForTag(row(other))

        // Account rows: one merged node, Button role, a click label naming the destination.
        mapOf(
            row(other) to "Open profile",
            row(Fixtures.ACCOUNT_B) to "Open profile",
            "fst.song-detail.your-rank.Solo_Guitar" to "Open your page of the full leaderboard",
        ).forEach { (tag, label) ->
            val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
            val clickable = if (tag.startsWith("fst.song-detail.your-rank")) node.children.single() else node
            assertEquals(tag, Role.Button, clickable.config.getOrNull(SemanticsProperties.Role))
            assertEquals(tag, label, clickable.config.getOrNull(SemanticsActions.OnClick)?.label)
            assertTrue(tag, clickable.config.isMergingSemanticsOfDescendants)
        }
        // No-account row: not actionable.
        val anon = rule.onNodeWithTag(row("rank-2")).fetchSemanticsNode()
        assertNull(anon.config.getOrNull(SemanticsActions.OnClick))
        assertNull(anon.config.getOrNull(SemanticsProperties.Role))
        assertEquals("Profile unavailable", anon.config.getOrNull(SemanticsProperties.StateDescription))

        // Tap opens the player profile; Back returns to Song Detail.
        rule.onNodeWithTag(row(other)).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.player")
        assertTrue(rule.onAllNodesWithTag("fst.song-detail.list").fetchSemanticsNodes().isEmpty())
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        waitForTag("fst.song-detail.list")
        waitForTag(row(Fixtures.ACCOUNT_B))
        rule.onNodeWithTag(row(Fixtures.ACCOUNT_B)).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.player")
        rule.onNodeWithTag("fst.nav.back").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-detail.list")
    }
}
