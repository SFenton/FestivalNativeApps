package com.festivalscoretracker.android.songs

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.journeys.MemoryPreferences
import com.festivalscoretracker.android.testing.SectionIndexFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Songs section index on a real device (issue #138): each reachable state (`hidden` in Year
 * order, `title`, `artist`, `scrubbing`) with the Accessibility Test Framework over the
 * window, TalkBack's reading order (logged under `FST_A11Y`), the next/previous actions,
 * real touch injection for scrubbing, and double text. Run with `device.py test
 * com.festivalscoretracker.android.songs.SongsSectionIndexDeviceTest --avd <AVD>`.
 */
@RunWith(AndroidJUnit4::class)
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
class SongsSectionIndexDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val labels = SectionIndexFixtures.labels

    // region Helpers

    private fun launch(sort: String? = null, fontScale: Float = 1f) {
        val preferences = MemoryPreferences(sort?.let { mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to it) } ?: emptyPreferences())
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = SectionIndexFixtures.transport(), settingsStore = preferences)
        rule.setContent { DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale)) { FestivalApp(container, debug) } }
        h.waitForTag("fst.songs.row.s-0-1")
    }

    private fun railState(): String? =
        rule.onNodeWithTag(RAIL).fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    /**
     * TalkBack reads the rail once, as "Section index, <section>", and none of its letters is a
     * stop of its own. Retries while UiAutomation's node cache catches up with Compose.
     */
    private fun assertOneRailStop(screen: String, section: String) {
        var order = emptyList<String>()
        val expected = listOf("Section index, $section")
        runCatching { rule.waitUntil(10_000) { order = h.readingOrder(screen); order.filter { it.startsWith("Section index") } == expected } }
        assertEquals("one rail stop: $order", expected, order.filter { it.startsWith("Section index") })
        assertFalse("no letter stops: $order", order.any { it in labels })
    }

    /**
     * The rail's accessibility node, refreshed: without a screen reader running, Compose sends
     * no change events, so UiAutomation's cached copy keeps the state from before an action.
     */
    private fun railNode(): AccessibilityNodeInfo? {
        h.awaitAccessibilityTree(RAIL)
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            node ?: return null
            if (node.viewIdResourceName == RAIL) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)?.also { it.refresh() }
    }

    /** What TalkBack reads on the rail now: "Section index, <section>". */
    private fun railSpoken(): String = railNode()?.let { "${it.contentDescription}, ${it.stateDescription}" }.orEmpty()
    /**
     * Runs the rail's custom action [label] through the window's accessibility tree, as
     * TalkBack does (Compose's semantics-action test helper bypasses that path).
     */
    private fun railAction(label: String) {
        val rail = railNode()
        val action = rail?.actionList?.firstOrNull { it.label?.toString() == label }
        assertTrue("rail offers $label: ${rail?.actionList?.map { it.label }}", action != null && rail.performAction(action.id))
        rule.waitForIdle()
    }
    // endregion

    // region States

    /** `title`: one focusable element naming the top section; next/previous move one section. */
    @Test
    fun titleRailReadsAsOneElementWithSectionActions() {
        h.enableAccessibilityChecks()
        launch()
        h.waitForTag(RAIL)
        assertOneRailStop("section-index-title", "Numbers and symbols")

        railAction("Next section")
        rule.waitUntil(5_000) { railState() == "A" }
        assertEquals("Section index, A", railSpoken())
        railAction("Previous section")
        rule.waitUntil(5_000) { railState() == "Numbers and symbols" }
        // Before the far jump: the clipped-row exemption needs the cut-off bottom row on screen.
        h.assertAccessible()

        // Next section reaches every section, including the last ones the list cannot bring to the top.
        repeat(labels.size - 1) { railAction("Next section") }
        assertEquals("Z", railState())
        assertEquals("Section index, Z", railSpoken())
    }

    /** `artist`: the rail indexes artist initials. */
    @Test
    fun artistRailIndexesArtists() {
        h.enableAccessibilityChecks()
        launch(sort = "Artist")
        h.waitForTag(RAIL)
        assertOneRailStop("section-index-artist", "A")
        h.assertAccessible()
    }

    /** `year` (hidden): decade headers and Quick Links replace the rail. */
    @Test
    fun yearOrderHidesTheRail() {
        h.enableAccessibilityChecks()
        launch(sort = "Year")
        h.waitForTag("fst.songs.section.year.1990")
        assertFalse(h.exists(RAIL))
        assertTrue(h.exists("fst.quick-links.open"))
        assertFalse(h.readingOrder("section-index-year").any { it.startsWith("Section index") })
        h.assertAccessible()
    }

    /** `scrubbing`: a real drag shows the decorative indicator until the finger lifts. */
    @Test
    fun scrubbingShowsTheIndicatorUntilRelease() {
        launch()
        h.waitForTag(RAIL)
        val rail = rule.onNodeWithTag(RAIL)
        rail.performTouchInput { down(Offset(width / 2f, height * 0.5f / labels.size)) }
        rule.waitUntil(5_000) { h.exists(INDICATOR) }
        rail.performTouchInput { moveTo(Offset(width / 2f, height * 13.5f / labels.size)) }
        rule.waitUntil(5_000) { railState() == "M" }
        assertTrue("indicator while dragging", h.exists(INDICATOR))
        rail.performTouchInput { up() }
        rule.waitUntil(5_000) { !h.exists(INDICATOR) }
        assertEquals("M", railState())
        // The indicator never became a TalkBack stop; the rail names where the drag landed.
        assertOneRailStop("section-index-scrubbed", "M")
    }

    /** Double text: the rail stays one element inside the window, and the checks still pass. */
    @Test
    fun doubleTextKeepsTheRailInsideTheWindow() {
        h.enableAccessibilityChecks()
        launch(fontScale = 2f)
        h.waitForTag(RAIL)
        val rail = rule.onNodeWithTag(RAIL).fetchSemanticsNode().boundsInRoot
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("rail $rail inside $root", rail.top >= root.top && rail.bottom <= root.bottom && rail.right <= root.right)
        assertOneRailStop("section-index-2x", "Numbers and symbols")
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val RAIL = "fst.songs.section-index"
        const val INDICATOR = "fst.songs.section-index.indicator"
    }
}
