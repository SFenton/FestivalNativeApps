package com.festivalscoretracker.android.bands

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.abs
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Band Detail on an unfolded book foldable (issue #361, owner override): flat, its two panes
 * divide the free content area beside the rail at its midpoint, not the fold; half open (book
 * posture) they meet at the hinge; folding and unfolding reflows the same page in place.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w852dp-h883dp-xhdpi")
class BandDetailFoldUiTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    private fun settle() {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.waitForIdle()
        }
    }

    private fun launch() {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(10_000) {
            settle()
            rule.onAllNodesWithTag("fst.band.pane.leading", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Publish one vertical fold at the window centre to Jetpack WindowManager. */
    private fun fold(state: State) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))),
        )
        settle()
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow

    private fun bandRequests() = transport.requests.count { it.url.contains("/rankings/bands") }

    /** Flat: equal panes centred on the content area beside the rail, so their gap lies trailing of the fold. */
    private fun assertPanesMeetAtTheContentMidpoint(hinge: Float) {
        val leading = bounds("fst.band.pane.leading")
        val trailing = bounds("fst.band.pane.trailing")
        assertEquals("equal panes $leading | $trailing", leading.width, trailing.width, 2f)
        val gapCentre = (leading.right + trailing.left) / 2
        assertTrue("gap $gapCentre should leave the fold $hinge (rail on the leading edge)", gapCentre > hinge + 20f)
    }

    @Test
    fun flatSplitsAtTheContentMidpointAndBookPostureAtTheHinge() {
        launch()
        val hinge = rule.activity.window.decorView.width / 2f
        fold(State.FLAT)
        assertPanesMeetAtTheContentMidpoint(hinge)
        val requests = bandRequests()

        fold(State.HALF_OPENED)
        val leading = bounds("fst.band.pane.leading")
        val trailing = bounds("fst.band.pane.trailing")
        assertTrue("leading pane $leading ends before the hinge $hinge", leading.right <= hinge && abs(leading.right - hinge) <= 40f)
        assertTrue("trailing pane $trailing starts after the hinge $hinge", trailing.left >= hinge && abs(trailing.left - hinge) <= 40f)

        fold(State.FLAT)
        assertPanesMeetAtTheContentMidpoint(hinge)
        // Reflow in place (#346): folding and unfolding never reloads the band.
        assertEquals(requests, bandRequests())
    }
}
