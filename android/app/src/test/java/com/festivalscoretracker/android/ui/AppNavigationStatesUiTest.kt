package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import androidx.compose.ui.test.onNodeWithText

// region Harness

/**
 * Launches the whole shell against synthetic fixtures (no network) and waits on semantics.
 *
 * @property rule Compose rule hosting the shell.
 */
internal class NavigationHarness(private val rule: androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, ComponentActivity>) {
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    /**
     * Compose [FestivalApp] with [debug] and wait for the first Songs row.
     *
     * @param debug Debug launch (profile, start section).
     * @param firstTag Tag that proves the start page loaded.
     */
    fun launch(debug: DebugLaunch, firstTag: String = "fst.songs.row.s-alpha") {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        waitForTag(firstTag)
    }

    /** Advance the main looper and Compose until idle. */
    fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    /**
     * Wait until a node tagged [tag] exists.
     *
     * @param tag Test tag.
     */
    fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /**
     * Wait until a node whose tag starts with [prefix] exists (any phase of a page).
     *
     * @param prefix Test tag prefix, e.g. `fst.suggestions.`.
     */
    fun waitForTagPrefix(prefix: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodes(SemanticsMatcher("tag prefix $prefix") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true })
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    /**
     * Wait until no node tagged [tag] exists.
     *
     * @param tag Test tag.
     */
    fun waitForNoTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    /**
     * Tab tags in composition order (`fst.nav.tab.<section>`).
     *
     * @return Section names, lowercase, in reading order.
     */
    fun tabOrder(): List<String> =
        rule.onAllNodes(SemanticsMatcher("tab tag") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(TAB_PREFIX) == true })
            .fetchSemanticsNodes()
            .map { it.config[SemanticsProperties.TestTag].removePrefix(TAB_PREFIX) }

    private companion object {
        const val TAB_PREFIX = "fst.nav.tab."
    }
}

/** The synthetic selected player used by every player-state test. */
internal val navigationPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

// endregion

// region Compact (phone portrait)

/**
 * App Navigation control states on a compact phone (issue #132): `songs`, `leaderboards`,
 * `settings`, `player` and `reselect`. `band` cannot be selected at runtime (band search is
 * blocked by the service-safety allowlist); its tab set is covered by `NavigationPolicyTest`.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class AppNavigationStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val harness = NavigationHarness(rule)

    @Test
    fun songsLeaderboardsAndSettingsTabsSelectTheirPages() {
        harness.launch(DebugLaunch(stillBackground = true))
        rule.onNodeWithTag("fst.nav.bar").assertIsDisplayed()
        assertEquals(listOf("songs", "leaderboards", "settings"), harness.tabOrder())
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsNotSelected()

        rule.onNodeWithTag("fst.nav.tab.leaderboards").performClick()
        harness.waitForTag("fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsNotSelected()

        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        harness.waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.nav.tab.settings").assertIsSelected()
        harness.waitForNoTag("fst.leaderboards")

        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        harness.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
    }

    @Test
    fun anonymousDrawerOffersSelectProfileAndSettingsLast() {
        harness.launch(DebugLaunch(stillBackground = true))
        rule.onNodeWithTag("fst.nav.drawer").assert(hasContentDescription("Open menu")).performClick()
        harness.waitForTag("fst.nav.drawer-sheet")
        harness.waitForTag("fst.nav.drawer.leaderboards")
        rule.onNodeWithTag("fst.nav.drawer-sheet").assert(SemanticsMatcher.expectValue(SemanticsProperties.IsTraversalGroup, true))
        assertTrue(rule.onAllNodesWithTag("fst.nav.drawer.statistics").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.nav.drawer.leaderboards").performSemanticsAction(SemanticsActions.OnClick)
        harness.waitForTag("fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
    }

    @Test
    fun playerStateShowsPlayerTabsAndAvatar() {
        harness.launch(DebugLaunch(profile = navigationPlayer, stillBackground = true))
        assertEquals(listOf("songs", "suggestions", "compete", "statistics", "settings"), harness.tabOrder())
        rule.onNodeWithTag("fst.nav.profile").assert(hasContentDescription("Profile: Synthetic Player"))

        rule.onNodeWithTag("fst.nav.tab.suggestions").performClick()
        harness.waitForTagPrefix("fst.suggestions.")
        rule.onNodeWithTag("fst.nav.tab.suggestions").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.statistics").performClick()
        harness.waitForTag("fst.statistics")
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsSelected()

        // Compact player drawer: Leaderboards and Rivals push their non-root twins.
        rule.onNodeWithTag("fst.nav.drawer").performClick()
        harness.waitForTag("fst.nav.drawer.deselect")
        harness.waitForTag("fst.nav.drawer.rivals")
        harness.waitForTag("fst.nav.drawer.leaderboards")
    }

    @Test
    fun reselectPopsToRootAndSwitchingRestoresHistory() {
        harness.launch(DebugLaunch(stillBackground = true))
        rule.onNodeWithTag("fst.songs.row.s-alpha").performClick()
        harness.waitForTag("fst.song-detail.intensity")
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()

        // Switching away and back restores the Songs tab's pushed detail (per-tab history).
        rule.onNodeWithTag("fst.nav.tab.leaderboards").performClick()
        harness.waitForTag("fst.leaderboards")
        harness.waitForNoTag("fst.song-detail.intensity")
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        harness.waitForTag("fst.song-detail.intensity")

        // Re-tapping the selected tab pops to its root.
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        harness.waitForNoTag("fst.song-detail.intensity")
        harness.waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
    }

    @Test
    fun largeTextBarIsIconOnlyWithSpokenNames() {
        RuntimeEnvironment.setFontScale(2f)
        harness.launch(DebugLaunch(profile = navigationPlayer, stillBackground = true))
        listOf("songs" to "Songs", "suggestions" to "Suggestions", "compete" to "Compete", "statistics" to "Statistics", "settings" to "Settings")
            .forEach { (tag, name) ->
                rule.onNodeWithTag("fst.nav.tab.$tag").assert(hasContentDescription(name)).assert(!hasText(name))
            }
    }
}

/**
 * Real text measurement at 2.0× (native graphics): the modal drawer's wrapped title gets its
 * own height instead of being overlapped by the first entry (issue #132).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LargeTextDrawerHeaderUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val harness = NavigationHarness(rule)

    @Test
    fun wrappedDrawerTitleIsNotOverlappedByTheFirstEntry() {
        RuntimeEnvironment.setFontScale(2f)
        harness.launch(DebugLaunch(profile = navigationPlayer, opensDrawer = true, stillBackground = true))
        harness.waitForTag("fst.nav.drawer.songs")
        val titleNode = rule.onNodeWithText("Festival Score Tracker").fetchSemanticsNode()
        val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        titleNode.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        val title = titleNode.boundsInRoot
        val header = rule.onNodeWithTag("fst.nav.drawer-header").fetchSemanticsNode().boundsInRoot
        val first = rule.onNodeWithTag("fst.nav.drawer.songs").fetchSemanticsNode().boundsInRoot
        // Wrapped onto more than one line, laid out without overflow, entirely inside the header row.
        assertTrue("title lines ${layouts.single().lineCount}", layouts.single().lineCount > 1)
        assertTrue("title overflows its box", !layouts.single().hasVisualOverflow)
        assertTrue("title $title inside header $header", title.bottom <= header.bottom + 0.5f)
        assertTrue("first entry $first below header $header", first.top >= header.bottom - 0.5f)
    }
}

// endregion

// region Medium (rail) and expanded (permanent drawer)

/** Medium window: the rail with Profile and Settings pinned to its bottom edge. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w840dp-h1100dp-port-xhdpi")
class MediumAppNavigationStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val harness = NavigationHarness(rule)

    @Test
    fun railShowsRegularPlayerTabsAndReselects() {
        harness.launch(DebugLaunch(profile = navigationPlayer, stillBackground = true))
        rule.onNodeWithTag("fst.nav.rail").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.rail.profile").assert(hasContentDescription("Profile: Synthetic Player", substring = true))
        // Regular width: Compete splits into Leaderboards and Rivals.
        assertTrue(rule.onAllNodesWithTag("fst.nav.tab.compete").fetchSemanticsNodes().isEmpty())
        val order = harness.tabOrder()
        assertTrue(order.containsAll(listOf("songs", "suggestions", "leaderboards", "rivals", "statistics", "settings")))
        assertEquals("settings", order.last())

        rule.onNodeWithTag("fst.nav.tab.leaderboards").performClick()
        harness.waitForTag("fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.leaderboards").performClick()
        harness.settle()
        harness.waitForTag("fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
    }
}

/** Expanded window: the permanent drawer carries the tab rows. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedAppNavigationStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val harness = NavigationHarness(rule)

    @Test
    fun permanentDrawerSelectsSectionsForAnonymousUser() {
        harness.launch(DebugLaunch(stillBackground = true), firstTag = "fst.songs.row.s-gamma")
        rule.onNodeWithTag("fst.nav.permanent-drawer").assertIsDisplayed()
        assertTrue(rule.onAllNodesWithTag("fst.nav.bar").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.nav.tab.songs").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.leaderboards").performClick()
        harness.waitForTag("fst.leaderboards")
        rule.onNodeWithTag("fst.nav.tab.leaderboards").assertIsSelected()
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        harness.waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.nav.tab.settings").assertIsSelected()
    }

    @Test
    fun permanentDrawerPlayerStateShowsStatisticsAndDeselect() {
        harness.launch(DebugLaunch(profile = navigationPlayer, stillBackground = true), firstTag = "fst.songs.row.s-gamma")
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.tab.rivals").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.drawer.deselect").assertIsDisplayed()
        // TalkBack reads the whole drawer, footer included, as one unit before the page.
        rule.onNodeWithTag("fst.nav.drawer-sheet").assert(SemanticsMatcher.expectValue(SemanticsProperties.IsTraversalGroup, true))
        listOf("fst.nav.drawer.deselect", "fst.nav.tab.settings").forEach {
            rule.onNodeWithTag(it).assert(hasAnyAncestor(hasTestTag("fst.nav.drawer-sheet")))
        }
        rule.onNodeWithTag("fst.nav.tab.statistics").performClick()
        harness.waitForTag("fst.statistics")
        rule.onNodeWithTag("fst.nav.tab.statistics").assertIsSelected()
    }
}

// endregion
