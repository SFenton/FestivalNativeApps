package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of the Songs pinned section header edge (issues #49, #417): rows scrolling under
 * the pinned Year header are cut and fade out just below it, and that edge is drawing only. ATF
 * runs throughout; TalkBack reads the pinned header as a heading before the rows of its section,
 * skips a row wholly hidden beneath the header (until it scrolls back out), still reaches the half-faded row below it as one
 * labelled ≥ 48 dp button, and reads exactly the same stops when the edge turns hard (Remove
 * animations, in-app Increase Contrast and Reduce Transparency) and at 200% text. Run with
 * `device.py test com.festivalscoretracker.android.journeys.SongsPinnedHeaderAccessibilityJourneyTest --avd …`.
 */
@RunWith(AndroidJUnit4::class)
class SongsPinnedHeaderAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val preferences = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
    private var savedAnimatorScale = ""

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    /** `device.py test` turns system animations off; the fade needs them on (Remove animations keeps a hard edge). */
    @Before
    fun enableAnimations() {
        savedAnimatorScale = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale 1")
    }

    @After
    fun restoreAnimations() {
        shell(if (savedAnimatorScale == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $savedAnimatorScale")
    }

    private fun launch(fontScale: Float? = null) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), BucketHeaderFixtures.transport(), preferences, fontScale?.let { scale -> { scale } })
        h.waitForTag("fst.songs.section.year.1970")
        h.publishTalkBackTree()
    }

    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInRoot

    /**
     * Pins the 1980s header over its section with [HIDDEN] scrolled wholly beneath it (its
     * bottom 1 px above the header's) and [FADING], the next row, starting in the fade band.
     */
    private fun pinOverSection() {
        rule.onNodeWithTag(LIST).performScrollToKey("s-10")
        rule.waitForIdle()
        val dy = bounds(HIDDEN).bottom - bounds(HEADER).bottom + 1f
        rule.onNodeWithTag(LIST).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, dy) }
        rule.waitForIdle()
        val header = bounds(HEADER)
        assertTrue("$HIDDEN ends under the pinned header", bounds(HIDDEN).bottom <= header.bottom)
        val fading = bounds(FADING)
        assertTrue("$FADING starts in the fade band: $fading under $header", fading.top >= header.bottom && fading.top < header.bottom + ScrollEdgeFade.TOP_DP * rule.density.density)
    }

    /** The current stops, once the accessibility tree has caught up with the scroll. */
    private fun stops(screen: String): List<JourneyHarness.ReadingStop> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        h.awaitAccessibilityTree(present = FADING)
        return h.readingStops(screen)
    }

    /**
     * The pinned header is a labelled heading read before its section's rows, the hidden row is
     * not a stop, and the fading row is one labelled ≥ 48 dp button.
     *
     * @return The stops' ids, for comparing edge modes.
     */
    private fun assertPinnedHeaderStops(screen: String): List<String?> {
        val stops = stops(screen)
        val dump = stops.joinToString("\n") { "${it.id} | ${it.label} | ${it.bounds.toShortString()}" }
        val header = stops.indexOfFirst { it.id == HEADER }
        assertTrue("$screen: the pinned header is read\n$dump", header >= 0)
        assertTrue("$screen: the pinned header is a heading", stops[header].isHeading)
        assertFalse("$screen: the pinned header has a spoken label", stops[header].label == "<unlabelled>")
        assertTrue("$screen: the row wholly beneath the pinned header is not a stop\n$dump", stops.none { it.id == HIDDEN })
        val fading = stops.indexOfFirst { it.id == FADING }
        assertTrue("$screen: the fading row is read after its header\n$dump", fading > header)
        assertTrue("$screen: the fading row is a button", stops[fading].isClickable)
        assertFalse("$screen: the fading row is labelled", stops[fading].label == "<unlabelled>")
        val rows = stops.mapNotNull { stop -> stop.id?.takeIf { it.startsWith(ROW_PREFIX) }?.removePrefix("${ROW_PREFIX}s-")?.toIntOrNull() }
        assertEquals("$screen: rows read in list order\n$dump", rows.sorted(), rows)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val row = bounds(FADING)
        assertTrue("$screen: the fading row is at least 48 dp tall", row.height >= min)
        return stops.map { it.id }
    }

    private fun setPreference(key: String, on: Boolean) = runBlocking {
        preferences.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(key)] = on } }
        rule.waitForIdle()
    }

    // endregion

    // region Journeys

    /**
     * Default settings fade the rows; Remove animations, then in-app Increase Contrast and Reduce
     * Transparency, switch to a hard edge in place, and TalkBack's stops never change.
     */
    @Test
    fun fadingRowsUnderThePinnedHeaderKeepTheReadingOrderInEveryEdgeMode() {
        launch()
        pinOverSection()
        val faded = assertPinnedHeaderStops("songs-pinned-fade")
        shell("settings put global animator_duration_scale 0")
        rule.waitForIdle()
        assertEquals("Remove animations (hard edge) reads the same stops", faded, assertPinnedHeaderStops("songs-pinned-remove-animations"))
        shell("settings put global animator_duration_scale 1")
        setPreference(SettingsRegistry.INCREASE_CONTRAST, true)
        assertEquals("Increase Contrast (hard edge) reads the same stops", faded, assertPinnedHeaderStops("songs-pinned-increase-contrast"))
        setPreference(SettingsRegistry.INCREASE_CONTRAST, false)
        setPreference(SettingsRegistry.REDUCE_TRANSPARENCY, true)
        assertEquals("Reduce Transparency (hard edge) reads the same stops", faded, assertPinnedHeaderStops("songs-pinned-reduce-transparency"))
        h.assertAccessible()
        // Scrolled back below the cut, the row is a stop again, read after its heading.
        val upBy = -2 * bounds(HEADER).height
        rule.onNodeWithTag(LIST).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, upBy) }
        rule.waitForIdle()
        var back = stops("songs-pinned-scrolled-back").map { it.id }
        val deadline = System.currentTimeMillis() + 5_000
        while (!(back.indexOf(HEADER) >= 0 && back.indexOf(HIDDEN) > back.indexOf(HEADER)) && System.currentTimeMillis() < deadline) {
            Thread.sleep(100)
            back = stops("songs-pinned-scrolled-back").map { it.id }
        }
        assertTrue("the uncovered row is read after its heading again\n$back", back.indexOf(HEADER) >= 0 && back.indexOf(HIDDEN) > back.indexOf(HEADER))
    }

    /** At 200% text the taller pinned header still reads first and the row fading under it stays reachable. */
    @Test
    fun pinnedHeaderEdgeAtDoubleTextKeepsItsRowsReachable() {
        launch(fontScale = 2f)
        pinOverSection()
        assertPinnedHeaderStops("songs-pinned-fade-2x")
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val LIST = "fst.songs.list"
        const val HEADER = "fst.songs.section.year.1980"
        const val ROW_PREFIX = "fst.songs.row."
        const val HIDDEN = "fst.songs.row.s-10"
        const val FADING = "fst.songs.row.s-11"
    }
}
