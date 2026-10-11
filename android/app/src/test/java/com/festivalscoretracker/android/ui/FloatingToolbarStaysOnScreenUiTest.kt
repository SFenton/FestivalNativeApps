package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.assertTouchWidthIsEqualTo
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
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

/**
 * Issue #577 (`page-tools-and-nav-chrome` R7): the shell's floating toolbar, and Quick Links in
 * it, stays on screen while a page scrolls by touch, on every page rather than only Songs and
 * Suggestions. Each test scrolls a page and checks the toolbar keeps its bounds above the bottom
 * bar, Quick Links stays a named 48 dp button, and at the end the last row clears the toolbar
 * (the reserved bottom band matches a toolbar that is always shown). Song Details is covered by
 * `SongsUiTest.songDetailToolbarStaysAboveTheBottomBarWhileScrolled`; the device journey
 * `FloatingToolbarStaysOnScreenAccessibilityJourneyTest` repeats these pages with ATF and
 * TalkBack's reading order.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FloatingToolbarStaysOnScreenUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    // region Tests

    @Test
    fun statisticsKeepsQuickLinksOnScreenWhileScrolled() = journey(
        DebugLaunch(section = FestivalSection.Statistics, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true),
        FakeTransport.standard().apply(songs).also { ProfileFixtures.register(it) },
        list = "fst.player.available",
    )

    @Test
    fun leaderboardsKeepsQuickLinksOnScreenWhileScrolled() = journey(
        DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
        RankingsFixtures.install(FakeTransport.standard().apply(songs)),
        list = "fst.leaderboards",
    )

    @Test
    fun competeKeepsQuickLinksOnScreenWhileScrolled() = journey(
        DebugLaunch(route = DebugLaunch.parseRoute("compete"), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true),
        RivalsFixtures.transport().apply(songs).also { RankingsFixtures.install(it) },
        list = "fst.compete.grid",
    )

    @Test
    fun settingsKeepsQuickLinksOnScreenWhileScrolled() = journey(
        DebugLaunch(section = FestivalSection.Settings, stillBackground = true),
        FakeTransport.standard(),
        list = "fst.settings.list",
    )

    // endregion

    // region Journey

    /**
     * Launch [debug], scroll [list] by touch, and check the toolbar at the top, while scrolled
     * and at the end.
     */
    private fun journey(debug: DebugLaunch, transport: FakeTransport, list: String) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        waitForTag(list)
        waitForTag(QUICK_LINKS)
        val atTop = bounds(TOOLBAR)
        val barTop = bounds("fst.nav.bar").top
        assertTrue("$list: toolbar $atTop is above the bottom bar ($barTop)", atTop.height > 0f && atTop.bottom <= barTop + 1)
        assertQuickLinks(list)

        repeat(3) { swipe(list) }
        assertTrue("$list did not scroll", scrollOffset(list) > 0f)
        assertSame("$list while scrolled", atTop, bounds(TOOLBAR))
        assertQuickLinks(list)

        var last = -1f
        repeat(40) {
            val now = scrollOffset(list)
            if (now == last) return@repeat
            last = now
            swipe(list)
        }
        assertSame("$list at the end", atTop, bounds(TOOLBAR))
        val viewport = bounds(list)
        val lowest = rule.onAllNodes(hasAnyAncestor(hasTestTag(list)), useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.boundsInRoot }
            .filter { it.height > 0f && it.bottom <= viewport.bottom + 1 }
            .maxOf { it.bottom }
        assertTrue("$list: last row ends at $lowest, under the toolbar's top ${atTop.top}", lowest <= atTop.top + 1)
    }

    // endregion

    // region Helpers

    private fun assertQuickLinks(list: String) {
        val button = rule.onNodeWithTag(QUICK_LINKS)
        // A 40 dp IconButton whose touch target is padded to 48 dp (minimumInteractiveComponentSize).
        button.assertIsDisplayed().assertTouchWidthIsEqualTo(48.dp).assertTouchHeightIsEqualTo(48.dp)
        val config = button.fetchSemanticsNode().config
        assertEquals("$list: Quick Links is a button", Role.Button, config.getOrNull(SemanticsProperties.Role))
        assertTrue("$list: Quick Links is clickable", SemanticsActions.OnClick in config)
        val name = config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString(" ")
        assertTrue("$list: Quick Links is named '$name'", name.contains("Quick Links"))
    }

    private fun assertSame(phase: String, expected: Rect, now: Rect) =
        listOf(expected.left to now.left, expected.top to now.top, expected.right to now.right, expected.bottom to now.bottom).forEach { (a, b) ->
            assertEquals("toolbar moved $phase: $now vs $expected", a, b, 1f)
        }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    /** Touch swipe in the list's middle third, so it never starts on the toolbar. */
    private fun swipe(list: String) {
        rule.onNodeWithTag(list).performTouchInput { swipeUp(startY = centerY + height / 6f, endY = centerY - height / 6f) }
        settle()
    }

    private fun scrollOffset(list: String): Float =
        rule.onNodeWithTag(list).fetchSemanticsNode().config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)?.value?.invoke() ?: 0f

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

    // endregion

    private companion object {
        const val TOOLBAR = "fst.nav.floating-toolbar"
        const val QUICK_LINKS = "fst.quick-links.open"
    }
}
