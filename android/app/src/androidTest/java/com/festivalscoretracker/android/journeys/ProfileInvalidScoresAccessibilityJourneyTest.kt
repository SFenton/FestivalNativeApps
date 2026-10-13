package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.net.URI
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Filtered ranks retain their labels, actions and TalkBack order at both text sizes. */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class ProfileInvalidScoresAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()
    private val h = JourneyHarness(rule)

    @Test
    fun otherPlayerFilteredFiguresStayAccessible() = checkProfile(1f)

    @Test
    fun otherPlayerFilteredFiguresStayAccessibleAtLargeText() = checkProfile(2f)

    private fun checkProfile(scale: Float) {
        val preferences = MemoryPreferences()
        val settings = SettingsRepository(preferences)
        runBlocking { settings.update { it.copy(visibleInstruments = setOf(Instrument.Lead), reduceMotion = true) } }
        val transport = FakeTransport.standard().also { ProfileFixtures.register(it); ProfileFixtures.register(it, Fixtures.ACCOUNT_B) }.apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { ProfileFixtures.invalidScoresSongs }
            on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { ProfileFixtures.invalidScoresProfile() }
        }
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"), route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true),
            transport, preferences, fontScale = { scale },
        )
        h.waitForTag(LIST)
        h.publishTalkBackTree()
        h.scrollTo(LIST, BEST_RANK)
        rule.onNodeWithTag(BEST_RANK).assertContentDescriptionEquals("Best Song Rank: #1")
        val reads = transport.requests.count { URI(it.url).path == "/api/player/${Fixtures.ACCOUNT_A}" }

        runBlocking { settings.update { it.copy(filterInvalidScores = true, leeway = 1.0) } }
        rule.waitUntil(15_000) { rule.onAllNodes(hasContentDescription("Best Song Rank: #6")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag(BEST_RANK)
            .assertContentDescriptionEquals("Best Song Rank: #6")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        h.assertTouchTarget("profile-filtered ${scale}x", BEST_RANK)
        h.assertTextUnclipped("profile-filtered ${scale}x", BEST_RANK, "#6", scale)
        h.readingOrder("profile-filtered ${scale}x", fresh = true).let { order ->
            val average = order.indexOfFirst { it.startsWith("Avg Accuracy:") }
            val best = order.indexOf("Best Song Rank: #6")
            assertTrue("Avg Accuracy precedes Best Song Rank: $order", average >= 0 && best > average)
            assertFalse("Raw rank is no longer spoken: $order", order.contains("Best Song Rank: #1"))
        }

        h.scrollTo(LIST, "fst.player.percentile-row.10")
        rule.onNodeWithTag("fst.player.percentile-row.10").assertContentDescriptionEquals("Top 10%: 1 song")
        h.assertTouchTarget("profile-percentiles ${scale}x", "fst.player.percentile-row.10")
        runBlocking { settings.update { it.copy(leeway = 2.0) } }
        h.scrollTo(LIST, "fst.player.percentile-row.4")
        rule.onNodeWithTag("fst.player.percentile-row.4").assertContentDescriptionEquals("Top 4%: 1 song")
        h.readingOrder("profile-percentiles ${scale}x", fresh = true).let { order ->
            val first = order.indexOf("Top 1%: 1 song")
            val second = order.indexOf("Top 2%: 1 song")
            val third = order.indexOf("Top 4%: 1 song")
            assertTrue("Percentile rows read best first: $order", first >= 0 && second > first && third > second)
        }
        runBlocking { settings.update { it.copy(filterInvalidScores = false) } }
        h.scrollTo(LIST, BEST_RANK)
        rule.onNodeWithTag(BEST_RANK).assertContentDescriptionEquals("Best Song Rank: #1")
        assertEquals(reads, transport.requests.count { URI(it.url).path == "/api/player/${Fixtures.ACCOUNT_A}" })
        h.assertAccessible()
    }

    private companion object {
        const val LIST = "fst.player.available"
        const val BEST_RANK = "fst.player.tile.overview.best-rank"
    }
}
