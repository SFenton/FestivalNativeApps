package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.ShellHitTargets
import com.festivalscoretracker.android.testing.ShellTool
import com.festivalscoretracker.android.testing.SongsFixtures
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
import org.robolectric.annotation.GraphicsMode

// region Harness

/** One unread notification, so the bell shows its badge over the button. */
private const val UNREAD_FEED = """{"sourceRunId":3,"items":[
  {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-1","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"}]}"""

/**
 * Launches the whole shell on Songs (Year sort, so Quick Links has sections) and probes the
 * navigation-bar and toolbar buttons' hit regions (issues #72, #179).
 */
private class HitTargetHarness(val rule: AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>) {
    val probe = ShellHitTargets(rule, settle = ::settle, refocus = { rule.focusTopWindow() })

    fun settle() {
        repeat(2) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.waitForIdle()
        }
    }

    /**
     * @param player Selected player (adds the bell; Profile then opens Statistics), or none.
     */
    fun launchSongs(player: SelectedPlayer? = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")) {
        val transport = SongsFixtures.scrollingCatalogueTransport()
        if (player != null) {
            ProfileFixtures.register(transport)
            transport.on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) { UNREAD_FEED }
        }
        val prefs = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        val debug = DebugLaunch(profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        probe.await("Songs rows") { probe.exists("fst.songs.row.s-1") }
        probe.await("Quick Links or ⋮") { probe.exists("fst.quick-links.open") || probe.exists("fst.nav.overflow") }
        if (player != null) probe.await("the bell") { probe.exists("fst.shell.notifications") }
    }

    fun within(ancestor: String, tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(ancestor))).fetchSemanticsNodes().isNotEmpty()

    /**
     * Every tool's target is at least 48 dp and apart from its neighbours, and four touches 22 dp
     * off-centre activate each tool. The bell is also touched on its unread badge.
     *
     * @param tools Tools to touch.
     * @return Activations.
     */
    fun assertForgiving(tools: List<ShellTool>): Int {
        val targets = probe.assertTargets(ShellHitTargets.SHELL_TAGS)
        tools.forEach { assertTrue("${it.tag} measured: ${targets.keys}", it.tag in targets) }
        return tools.sumOf { tool ->
            val extra = if (tool == ShellHitTargets.BELL && probe.exists("fst.shell.notifications.badge")) {
                listOf(badgeOffset())
            } else {
                emptyList()
            }
            probe.assertOffCentreTouchesActivate(tool, extra)
        }
    }

    private fun badgeOffset() = rule.onNodeWithTagUnmerged("fst.shell.notifications.badge").center -
        rule.onNodeWithTagUnmerged("fst.shell.notifications").center
}

private fun AndroidComposeTestRule<*, *>.onNodeWithTagUnmerged(tag: String) =
    onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot

private val SELECTED_TOOLS = listOf(
    ShellHitTargets.QUICK_LINKS,
    ShellHitTargets.SORT,
    ShellHitTargets.FILTER,
    ShellHitTargets.SEARCH,
    ShellHitTargets.BELL,
    ShellHitTargets.PROFILE_OPEN,
)

private val PAGE_TOOLS = listOf("fst.quick-links.open", "fst.songs.sort.open", "fst.songs.filter.open")

// endregion

// region Compact

/** Compact phone: page tools in the floating toolbar, Search, bell and Profile in the top app bar. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PhoneShellHitTargetUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { HitTargetHarness(rule) }

    @Test
    fun everyBarAndToolbarButtonHasAForgivingSeparateTarget() {
        h.launchSongs()
        PAGE_TOOLS.forEach { assertTrue("$it in the floating toolbar", h.within("fst.nav.floating-toolbar", it)) }
        assertTrue("badge shown", h.probe.exists("fst.shell.notifications.badge"))
        assertEquals(6 * 4 + 1, h.assertForgiving(SELECTED_TOOLS))
    }

    /** Without a player there is no bell, and Profile opens the profile sheet. */
    @Test
    fun noPlayerProfileOpensTheSheetFromOffCentreTouches() {
        h.launchSongs(player = null)
        assertTrue("no bell without a player", !h.probe.exists("fst.shell.notifications"))
        assertEquals(5 * 4, h.assertForgiving(listOf(ShellHitTargets.QUICK_LINKS, ShellHitTargets.SORT, ShellHitTargets.FILTER, ShellHitTargets.SEARCH, ShellHitTargets.PROFILE_CHOOSE)))
    }
}

/** Compact phone at 200 % text: the targets still hold (icons don't scale, labels are spoken). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
class LargeTextShellHitTargetUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { HitTargetHarness(rule) }

    @Test
    fun targetsHoldAtDoubleFontScale() {
        h.launchSongs()
        assertEquals(6 * 4 + 1, h.assertForgiving(SELECTED_TOOLS))
    }
}

// endregion

// region Medium and expanded

/** Medium window (rail): every tool in the top app bar. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w700dp-h1000dp-xhdpi")
class MediumShellHitTargetUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { HitTargetHarness(rule) }

    @Test
    fun topBarButtonsHaveForgivingSeparateTargets() {
        h.launchSongs()
        PAGE_TOOLS.forEach { assertTrue("$it in the top app bar", h.within("fst.nav.top-bar", it)) }
        assertEquals(6 * 4 + 1, h.assertForgiving(SELECTED_TOOLS))
    }
}

/** Expanded window: the top app bar over Songs, which fills the window (no list/detail split, #581). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedShellHitTargetUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { HitTargetHarness(rule) }

    @Test
    fun topBarButtonsHaveForgivingSeparateTargets() {
        h.launchSongs()
        PAGE_TOOLS.forEach { assertTrue("$it in the top app bar", h.within("fst.nav.top-bar", it)) }
        assertEquals(6 * 4 + 1, h.assertForgiving(SELECTED_TOOLS))
    }
}

/**
 * Landscape phone: Songs fills the window in two columns (`wide-columns`, issue #581), so the
 * page tools sit in the top app bar beside Search, the bell and Profile (no narrow list pane
 * pushing them behind ⋮ any more, issue #101), each with a forgiving, separate target. Native
 * graphics, so the title measures real text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w923dp-h411dp-land-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LandscapePhoneShellHitTargetUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h by lazy { HitTargetHarness(rule) }

    @Test
    fun topBarButtonsHaveForgivingSeparateTargets() {
        h.launchSongs()
        assertTrue("no ⋮ once Songs fills the window", !h.probe.exists("fst.nav.overflow"))
        PAGE_TOOLS.forEach { assertTrue("$it in the top app bar", h.within("fst.nav.top-bar", it)) }
        assertEquals(6 * 4 + 1, h.assertForgiving(SELECTED_TOOLS))
    }
}

// endregion
