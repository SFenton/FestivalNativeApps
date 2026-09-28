package com.festivalscoretracker.android.suggestions

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Suggestions screen states, rows, incremental loading and the filter sheet (Robolectric, synthetic fixtures). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SuggestionsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private fun launch(transport: FakeTransport = SuggestionFixtures.transport(), debug: DebugLaunch = playerLaunch()) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun playerLaunch() = DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true, suggestionsSeed = 7)

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(15_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun count(tagPrefix: String) = rule.onAllNodes(hasTestTagPrefix(tagPrefix)).fetchSemanticsNodes().size

    private fun hasTestTagPrefix(prefix: String) = androidx.compose.ui.test.SemanticsMatcher("tag starts with $prefix") { node ->
        node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.TestTag)?.startsWith(prefix) == true
    }

    @Test
    fun cardsLoadIncrementallyAndRowsOpenSongDetail() {
        launch()
        waitForTag("fst.suggestions.list")
        assertTrue(count("fst.suggestions.category.") > 0)
        rule.onNodeWithContentDescription("Filter Suggestions").assertIsDisplayed()
        rule.onNodeWithTag("fst.suggestions.list").performScrollToIndex(9)
        settle()
        rule.waitUntil(15_000) {
            settle(100)
            runCatching { rule.onNodeWithTag("fst.suggestions.list").performScrollToIndex(14) }.isSuccess
        }
        val row = rule.onAllNodes(hasTestTagPrefix("fst.suggestions.row.")).onFirst()
        row.performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-detail.list")
    }

    @Test
    fun filterSheetAppliesResetsAndDiscards() {
        launch()
        waitForTag("fst.suggestions.list")
        rule.onNodeWithTag("fst.suggestions.filter-button").performClick()
        waitForTag("fst.suggestions.filter.form")
        rule.onNodeWithTag("fst.suggestions.filter.apply").assertIsNotEnabled()
        rule.onNodeWithTag("fst.suggestions.filter.instrument.Solo_Guitar").assertIsOn().performSemanticsAction(SemanticsActions.OnClick); settle()
        rule.onNodeWithTag("fst.suggestions.filter.instrument.Solo_Guitar").assertIsOff()
        rule.onNodeWithTag("fst.suggestions.filter.apply").assertIsEnabled().performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        rule.onNodeWithContentDescription("Filter Suggestions, filters on").assertIsDisplayed()
        assertTrue(rule.onAllNodes(hasTestTagPrefix("fst.suggestions.row.")).fetchSemanticsNodes().none {
            it.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.TestTag)!!.endsWith("|Solo_Guitar")
        })

        // General + instrument-specific toggles, then Cancel asks before discarding.
        rule.onNodeWithTag("fst.suggestions.filter-button").performClick()
        waitForTag("fst.suggestions.filter.form")
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.type.stale"))
        rule.onNodeWithTag("fst.suggestions.filter.type.stale").performSemanticsAction(SemanticsActions.OnClick); settle()
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.instrument-picker"))
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(androidx.compose.ui.test.hasText("Choose an instrument to fine-tune its suggestion types."))
        rule.onNodeWithTag("fst.suggestions.filter.instrument-picker.Solo_Bass").performSemanticsAction(SemanticsActions.OnClick); settle()
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.type.Solo_Bass.nearFC"))
        rule.onNodeWithTag("fst.suggestions.filter.type.Solo_Bass.nearFC").assertIsOn().performSemanticsAction(SemanticsActions.OnClick); settle()
        rule.onNodeWithTag("fst.suggestions.filter.type.Solo_Bass.nearFC").assertIsOff()
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.type.Solo_Bass.stale"))
        rule.onNodeWithTag("fst.suggestions.filter.type.Solo_Bass.stale").assertIsOff()
        rule.onNodeWithTag("fst.suggestions.filter.cancel").performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        rule.onNodeWithTag("fst.suggestions.filter.keep-editing").performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        rule.onNodeWithTag("fst.suggestions.filter.cancel").performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        rule.onNodeWithTag("fst.suggestions.filter.discard").performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.filter.form").fetchSemanticsNodes().size)

        // Reset back to defaults.
        rule.onNodeWithTag("fst.suggestions.filter-button").performClick()
        waitForTag("fst.suggestions.filter.form")
        rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.reset"))
        rule.onNodeWithTag("fst.suggestions.filter.reset").performSemanticsAction(SemanticsActions.OnClick); settle()
        rule.onNodeWithTag("fst.suggestions.filter.apply").performSemanticsAction(SemanticsActions.OnClick); settle()
        settle()
        rule.onNodeWithContentDescription("Filter Suggestions").assertIsDisplayed()
    }

    @Test
    fun everyTypeOffShowsResetFilters() {
        launch()
        waitForTag("fst.suggestions.list")
        rule.onNodeWithTag("fst.suggestions.filter-button").performClick()
        waitForTag("fst.suggestions.filter.form")
        listOf("nearFC", "starProgress", "unplayed", "varietyPack", "artistEssentials", "artistDiscover", "sameName", "almostElite",
            "percentilePush", "stale", "pctImprove", "nearMax", "songRivals").forEach { key ->
            rule.onNodeWithTag("fst.suggestions.filter.form").performScrollToNode(hasTestTag("fst.suggestions.filter.type.$key"))
            rule.onNodeWithTag("fst.suggestions.filter.type.$key").performSemanticsAction(SemanticsActions.OnClick); settle()
        }
        rule.onNodeWithTag("fst.suggestions.filter.apply").performSemanticsAction(SemanticsActions.OnClick); settle()
        waitForTag("fst.suggestions.reset-filters")
        rule.onNodeWithText("Try changing your filters to see more suggestions.").assertIsDisplayed()
        rule.onNodeWithTag("fst.suggestions.reset-filters").performClick()
        waitForTag("fst.suggestions.list")
    }

    @Test
    fun noPlayerOffersProfileSelection() {
        launch(debug = DebugLaunch(route = SuggestionsRoute, anonymous = true, stillBackground = true))
        waitForTag("fst.suggestions.choose-profile")
        rule.onNodeWithText("Select a player profile to get personalized suggestions.").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.filter-button").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.suggestions.choose-profile").performClick()
        waitForTag("fst.profile.search")
    }

    @Test
    fun syncingAndFailureStatesRetry() {
        val transport = SuggestionFixtures.transport().apply {
            on("/api/player/${Fixtures.ACCOUNT_A}", status = 202) {
                """{"accountId":"${Fixtures.ACCOUNT_A}","totalScores":0,"scores":[],"status":"syncing","notYetPublished":true}"""
            }
        }
        launch(transport)
        waitForTag("fst.suggestions.syncing")
        rule.onNodeWithText("Still syncing").assertIsDisplayed()
        transport.on("/api/player/${Fixtures.ACCOUNT_A}", status = 500) { "" }
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        waitForTag("fst.suggestions.error")
        transport.on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { SuggestionFixtures.playerJson() }
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        waitForTag("fst.suggestions.list")
    }

    @Test
    fun emptyCatalogueAsksToPlaySongs() {
        val transport = SuggestionFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"count":0,"songs":[]}""" }
            on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) {
                """{"accountId":"${Fixtures.ACCOUNT_A}","totalScores":0,"scores":[]}"""
            }
        }
        launch(transport)
        waitForTag("fst.suggestions.no-results")
        rule.onNodeWithText("Play some songs first!").assertIsDisplayed()
    }
}

/** Expanded window: the card grid uses several columns and still loads. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class SuggestionsExpandedUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun expandedGridShowsCardsSideBySide() {
        val debug = DebugLaunch(section = FestivalSection.Suggestions, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true, suggestionsSeed = 7)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = SuggestionFixtures.transport(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(15_000) {
            repeat(2) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50)); rule.waitForIdle() }
            rule.onAllNodesWithTag("fst.suggestions.list").fetchSemanticsNodes().isNotEmpty()
        }
        val cards = rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("card") { node ->
            node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.TestTag)?.startsWith("fst.suggestions.category.") == true
        }).fetchSemanticsNodes()
        assertTrue(cards.size >= 2)
        assertTrue("two columns", cards.map { it.boundsInRoot.left }.toSet().size >= 2)
    }
}
