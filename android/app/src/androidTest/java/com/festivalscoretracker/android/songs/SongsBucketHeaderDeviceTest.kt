package com.festivalscoretracker.android.songs

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.journeys.MemoryPreferences
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import kotlin.math.abs
import okhttp3.OkHttpClient
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Songs bucket headers on a real device (issues #91, #189): in the Duration and Year sorts the
 * header has no backing, at rest and pinned over scrolled rows (its empty end shows the same
 * background as the list's side padding), stays a TalkBack heading with its spoken label, is
 * not clipped at font scale 2.0, and a Quick Links jump lands its section with a bare pinned
 * title. Run with `device.py test com.festivalscoretracker.android.songs.SongsBucketHeaderDeviceTest --avd <AVD>`.
 */
@RunWith(AndroidJUnit4::class)
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
class SongsBucketHeaderDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Helpers

    private fun launch(sort: String, fontScale: Float = 1f) {
        val preferences = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to sort))
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = BucketHeaderFixtures.transport(), settingsStore = preferences)
        rule.setContent { DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale)) { FestivalApp(container, debug) } }
        h.waitForTag("fst.songs.row.s-0")
    }

    private val isBucketHeader = SemanticsMatcher("Songs bucket header") {
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith("fst.songs.section.")
    }

    /** Headers fully inside the list and clear of the bottom page tools. */
    private fun visibleHeaders(): List<Rect> {
        val list = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot
        val clearance = TOOLBAR_CLEARANCE_DP * rule.density.density
        return rule.onAllNodes(isBucketHeader, useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInRoot }
            .filter { it.top >= list.top - 1 && it.bottom <= list.bottom - clearance }
    }

    /**
     * Every visible header's empty trailing end matches the list's own start padding at the same
     * height (not the window edge, which a navigation rail or drawer covers on wider windows).
     */
    private fun assertHeadersBare(what: String) {
        rule.waitForIdle()
        val headers = visibleHeaders()
        assertTrue("$what: a header is visible", headers.isNotEmpty())
        val list = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot
        val pixels = rule.onRoot().captureToImage().toPixelMap()
        headers.forEach { bounds ->
            assertTrue("$what: the list pads its headers", bounds.left - list.left >= 8 * rule.density.density)
            val y = bounds.center.y.toInt()
            val inside = pixels[bounds.right.toInt() - 2, y]
            val outside = pixels[(list.left + 4 * rule.density.density).toInt(), y]
            val diff = maxOf(
                abs(inside.red - outside.red),
                abs(inside.green - outside.green),
                abs(inside.blue - outside.blue),
                abs(inside.alpha - outside.alpha),
            )
            assertTrue("$what: header end $inside differs from the background $outside", diff <= TOLERANCE)
        }
    }

    /** Each composed header is a heading with its spoken label, and its text fits without clipping. */
    private fun assertHeadersReadable(what: String) {
        rule.onAllNodes(isBucketHeader, useUnmergedTree = true).fetchSemanticsNodes().forEach { node ->
            val tag = node.config[SemanticsProperties.TestTag]
            assertTrue("$what: $tag is a heading", node.config.contains(SemanticsProperties.Heading))
            assertFalse("$what: $tag has a spoken label", node.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty())
            val layouts = mutableListOf<TextLayoutResult>()
            node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            layouts.forEach { assertFalse("$what: $tag text is clipped", it.hasVisualOverflow) }
        }
    }

    // endregion

    // region States

    /** Duration: bare headers at rest and while rows scroll under the pinned title; ATF clean. */
    @Test
    fun durationHeadersAreBareAtRestAndPinned() {
        h.enableAccessibilityChecks()
        launch("Duration")
        h.waitForTag("fst.songs.section.duration.1to2")
        assertHeadersBare("Duration at rest")
        assertHeadersReadable("Duration")
        rule.onNodeWithTag(LIST).performScrollToIndex(5)
        assertHeadersBare("Duration pinned")
        h.assertAccessible()
    }

    /** Year at font scale 2.0: bare at rest and pinned, headings unclipped. */
    @Test
    fun yearHeadersAreBareAndUnclippedAtDoubleText() {
        launch("Year", fontScale = 2f)
        h.waitForTag("fst.songs.section.year.1970")
        assertHeadersBare("Year 2.0 at rest")
        assertHeadersReadable("Year 2.0")
        rule.onNodeWithTag(LIST).performScrollToIndex(9)
        assertHeadersBare("Year 2.0 pinned")
        assertHeadersReadable("Year 2.0 pinned")
    }

    /** Quick Links: jumping to a later bucket pins its bare title at the top of the list. */
    @Test
    fun quickLinksJumpPinsABareHeader() {
        launch("Duration")
        h.waitForTag("fst.songs.section.duration.1to2")
        h.tap("fst.quick-links.open")
        val item = "fst.quick-links.item.duration:3to4"
        if (h.exists("fst.quick-links.list")) {
            rule.onNodeWithTag("fst.quick-links.list").performScrollToNode(hasTestTag(item))
        }
        h.tap(item)
        // Phones show a sheet, wider windows a menu.
        rule.waitUntil(15_000) { !h.exists("fst.quick-links.sheet") && !h.exists("fst.quick-links.menu") }
        rule.waitUntil(5_000) {
            val list = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot
            rule.onAllNodes(hasTestTag("fst.songs.section.duration.3to4"), useUnmergedTree = true).fetchSemanticsNodes()
                .any { abs(it.boundsInRoot.top - list.top) < rule.density.density * 2 }
        }
        assertHeadersBare("Duration after a Quick Links jump")
    }

    // endregion

    private companion object {
        const val LIST = "fst.songs.list"

        /** Keeps sampled headers above the phone's pinned floating toolbar. */
        const val TOOLBAR_CLEARANCE_DP = 120

        /** Largest channel difference (of 1.0) between the header end and the background. */
        const val TOLERANCE = 0.03f
    }
}
