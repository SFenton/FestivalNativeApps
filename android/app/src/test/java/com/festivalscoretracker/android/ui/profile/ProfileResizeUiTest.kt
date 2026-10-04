package com.festivalscoretracker.android.ui.profile

import android.content.res.Configuration
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.WindowInfo
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntSize
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
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
 * The page keeps its place when the window crosses the expanded width (issue #106: rotating a
 * tablet or unfolding switches the permanent drawer and the rail, which used to rebuild the
 * NavHost and send the profile back to the top), and the modal drawer stays closed when the
 * window or display density changes.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-mdpi")
class ProfileResizeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private val configuration by lazy { mutableStateOf(Configuration(rule.activity.resources.configuration)) }
    private val window = mutableStateOf(IntSize(1280, 800))
    private val density = mutableStateOf(Density(1f))

    /** Hosts the app on the profile route with a test-controlled window size and density. */
    private fun launchProfile() {
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
        }
        val debug = DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        val windowInfo = object : WindowInfo {
            override val isWindowFocused = true
            override val containerSize get() = window.value
        }
        rule.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides configuration.value,
                LocalWindowInfo provides windowInfo,
                LocalDensity provides density.value,
            ) {
                FestivalApp(container, debug)
            }
        }
    }

    private fun drawerSheetHidden() =
        rule.onAllNodesWithTag("fst.nav.drawer-sheet").fetchSemanticsNodes().none { it.layoutInfo.isPlaced && it.boundsInRoot.right > 0f }

    @Test
    fun scrollPositionSurvivesLeavingThePermanentDrawer() {
        launchProfile()
        waitForTag("fst.nav.permanent-drawer")
        waitForTag("fst.player.available")
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.top-songs"))
        settle()
        assertTrue(rule.onAllNodesWithTag("fst.player.overview").fetchSemanticsNodes().isEmpty())

        // Portrait tablet / medium window: the rail replaces the permanent drawer.
        window.value = IntSize(700, 1000)
        configuration.value = Configuration(configuration.value).apply {
            screenWidthDp = 700
            screenHeightDp = 1000
            orientation = Configuration.ORIENTATION_PORTRAIT
        }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.nav.permanent-drawer").fetchSemanticsNodes().isEmpty() }
        waitForTag("fst.player.available")

        assertEquals(0, rule.onAllNodesWithTag("fst.player.overview").fetchSemanticsNodes().size)
        assertTrue(rule.onAllNodesWithTag("fst.player.top-songs").fetchSemanticsNodes().isNotEmpty())
        // The modal drawer that hosts the pages again starts closed (off-screen).
        assertTrue(drawerSheetHidden())
    }

    @Test
    fun aDensityChangeLeavesTheModalDrawerClosed() {
        launchProfile()
        waitForTag("fst.nav.permanent-drawer")

        // Desktop (mdpi) → phone (420 dpi): the modal sheet grows from 360 px to 945 px, which
        // Material's nearest-anchor re-targeting used to read as an open drawer.
        density.value = Density(2.625f)
        window.value = IntSize(1080, 2400)
        configuration.value = Configuration(configuration.value).apply {
            screenWidthDp = 411
            screenHeightDp = 914
            densityDpi = 420
            orientation = Configuration.ORIENTATION_PORTRAIT
        }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.nav.permanent-drawer").fetchSemanticsNodes().isEmpty() }
        settle()

        assertTrue(drawerSheetHidden())
    }
}