package com.festivalscoretracker.android.bands

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.bands.BAND_MISSING_ID_MESSAGE
import com.festivalscoretracker.android.ui.bands.BAND_NOT_FOUND_TITLE
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.abs
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * `/bands` without a band id (issue #118): the shared empty state with the web's copy, centred
 * lines at every size, scrolling instead of clipping at font scale 2, and kept off a half-open
 * fold, all without a single request to the band endpoints.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class BandNotFoundUiTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard()

    private fun launch() {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute("bands"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(10_000) {
            repeat(4) {
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
                rule.waitForIdle()
            }
            rule.onAllNodesWithTag("fst.bands.not-found", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** The message's laid-out text. */
    private fun messageLayout(): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        val node = rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).fetchSemanticsNode()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(results)
        return results.single()
    }

    /** Every line of the message is centred in its box (web `EmptyState` `text-align: center`). */
    private fun assertMessageLinesCentred() {
        val layout = messageLayout()
        val width = layout.size.width.toFloat()
        for (line in 0 until layout.lineCount) {
            val leading = layout.getLineLeft(line)
            val trailing = width - layout.getLineRight(line)
            assertTrue("line $line: $leading vs $trailing", abs(leading - trailing) <= 2f)
        }
        assertFalse("message overflows its box (${layout.size})", layout.hasVisualOverflow)
    }

    private fun assertNoBandRequests() {
        assertTrue(transport.requests.none { it.url.contains("/api/bands") || it.url.contains("/rankings/bands") })
        assertTrue(transport.requests.all { it.method == "GET" })
    }

    @Test
    fun phoneShowsTheWebCopyAsAHeadingAndMessage() {
        launch()
        rule.onNodeWithTag("fst.bands.screen").assertIsDisplayed()
        rule.onNodeWithText(BAND_NOT_FOUND_TITLE)
            .assertIsDisplayed()
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).assertIsDisplayed()
        assertEquals("Band not found", BAND_NOT_FOUND_TITLE)
        assertMessageLinesCentred()
        assertNoBandRequests()
    }

    /** Line wrapping at 200% is checked on the emulator: Robolectric does not measure real glyph widths. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largeTextKeepsCentredUnclippedText() {
        launch()
        rule.onNodeWithText(BAND_NOT_FOUND_TITLE).assertIsDisplayed()
        rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).assertIsDisplayed()
        assertMessageLinesCentred()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi", fontScale = 2f)
    fun landscapeLargeTextScrollsRatherThanClips() {
        launch()
        rule.onNodeWithTag("fst.bands.not-found.pane").assert(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollBy))
        rule.onNodeWithText(BAND_NOT_FOUND_TITLE).performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).performScrollTo().assertIsDisplayed()
        assertMessageLinesCentred()
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
    fun expandedWindowCentresInTheFullContentWidth() {
        launch()
        val pane = rule.onNodeWithTag("fst.bands.not-found.pane").fetchSemanticsNode().boundsInWindow
        val title = rule.onNodeWithText(BAND_NOT_FOUND_TITLE).fetchSemanticsNode().boundsInWindow
        assertTrue(abs(pane.center.x - title.center.x) <= 2f)
        assertMessageLinesCentred()
        assertNoBandRequests()
    }

    /** Publish one fold to Jetpack WindowManager once the shell is observing it. */
    private fun fold(state: State, orientation: Orientation = Orientation.VERTICAL) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = orientation))),
        )
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.waitForIdle()
        }
    }

    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun halfOpenBookPostureKeepsTheMessageInTheLeadingPane() {
        launch()
        fold(State.HALF_OPENED)
        val hingeLeft = rule.activity.window.decorView.width / 2f
        val pane = rule.onNodeWithTag("fst.bands.not-found.pane").fetchSemanticsNode().boundsInWindow
        val message = rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).fetchSemanticsNode().boundsInWindow
        val title = rule.onNodeWithText(BAND_NOT_FOUND_TITLE).fetchSemanticsNode().boundsInWindow
        assertTrue("pane ${pane.right} vs hinge $hingeLeft", abs(pane.right - hingeLeft) <= 2f)
        assertTrue(message.right <= hingeLeft && title.right <= hingeLeft)
        assertMessageLinesCentred()
    }

    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun flatFoldKeepsOneCentredColumn() {
        launch()
        fold(State.FLAT)
        val pane = rule.onNodeWithTag("fst.bands.not-found.pane").fetchSemanticsNode().boundsInWindow
        val screen = rule.onNodeWithTag("fst.bands.not-found").fetchSemanticsNode().boundsInWindow
        assertEquals(screen.width, pane.width, 2f)
        assertTrue(pane.right > rule.activity.window.decorView.width / 2f + 100f)
    }

    @Test
    @Config(qualifiers = "w883dp-h852dp-land-xhdpi")
    fun tabletopPostureCentresTheMessageAboveTheFold() {
        launch()
        fold(State.HALF_OPENED, Orientation.HORIZONTAL)
        val hingeTop = rule.activity.window.decorView.height / 2f
        val title = rule.onNodeWithText(BAND_NOT_FOUND_TITLE).fetchSemanticsNode().boundsInWindow
        val message = rule.onNodeWithText(BAND_MISSING_ID_MESSAGE).fetchSemanticsNode().boundsInWindow
        assertTrue("message ${message.bottom} vs fold $hingeTop", message.bottom <= hingeTop && title.top < hingeTop)
        assertMessageLinesCentred()
    }

    @Test
    @Config(qualifiers = "w883dp-h852dp-land-xhdpi")
    fun flatHorizontalFoldKeepsTheStateCentredInTheViewport() {
        launch()
        fold(State.FLAT, Orientation.HORIZONTAL)
        val box = rule.onNodeWithTag("fst.bands.not-found").fetchSemanticsNode().boundsInWindow
        val pane = rule.onNodeWithTag("fst.bands.not-found.pane").fetchSemanticsNode().boundsInWindow
        assertEquals(pane.height, box.height, 2f)
    }
}
