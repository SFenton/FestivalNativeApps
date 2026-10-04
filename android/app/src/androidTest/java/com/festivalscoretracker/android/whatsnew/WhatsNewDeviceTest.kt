package com.festivalscoretracker.android.whatsnew

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogGroup
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenRecord
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.WhatsNewBlock
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.journeys.MemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewSheet
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * What's New control on a real device (issue #142): every reachable state (`hidden-seen`,
 * `waiting-for-first-run`, `presented`, `dismissed`, `replay`) through the whole shell against
 * fixtures, with the Accessibility Test Framework on each state (labels, contrast, 48 dp targets),
 * TalkBack's reading order logged under `FST_A11Y`, the compact sheet's pinned Dismiss bar and
 * hinge avoidance. Run with
 * `device.py test com.festivalscoretracker.android.whatsnew.WhatsNewDeviceTest --avd <AVD>`.
 */
@RunWith(AndroidJUnit4::class)
class WhatsNewDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    // region Helpers

    private val compact get() = rule.activity.resources.configuration.screenWidthDp < 600

    private fun seenOf(preferences: MemoryPreferences): String? =
        runBlocking { preferences.data.first()[stringPreferencesKey(SettingsRegistry.CHANGELOG_SEEN)] }

    /** [first] is read before [second]; `"Close"` matches the header button exactly, not the scrim's "Close sheet". */
    private fun before(order: List<String>, first: String, second: String) {
        fun at(key: String) = order.indexOfFirst { if (key == "Close") it == key || it.startsWith("$key,") else it.contains(key) }
        val a = at(first)
        val b = at(second)
        assertTrue("'$first' before '$second' in $order", a >= 0 && b > a)
    }

    /** Touch bounds of every [tags] node are at least 48 dp. */
    private fun assertTargets(vararg tags: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        tags.forEach { tag ->
            val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot
            assertTrue("$tag touch target is ${bounds.width} x ${bounds.height} px", bounds.width >= min && bounds.height >= min)
        }
    }

    /**
     * No [tags] node crosses a separating vertical hinge. Compares screen positions: the sheet
     * and dialog live in their own windows, so their `boundsInWindow` are not in the activity
     * window's coordinates that WindowManager reports hinges in.
     */
    private fun assertOffHinges(vararg tags: String) {
        val origin = IntArray(2).also { rule.activity.window.decorView.getLocationOnScreen(it) }
        val folds = h.hinges()
        tags.forEach { tag ->
            val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
            val left = node.positionOnScreen.x - origin[0]
            val right = left + node.size.width
            folds.forEach { fold -> assertTrue("$tag ($left..$right) straddles the fold at ${fold.left}", right <= fold.left || left >= fold.right) }
        }
    }

    /** Presented-state checks shared by every entry path. */
    private fun assertPresented(screen: String) {
        val order = h.readingOrder(screen)
        before(order, "What's New", "Close")
        before(order, "Close", "first release")
        before(order, "first release", "Dismiss")
        assertTargets("fst.whats-new.close", "fst.whats-new.dismiss")
        assertOffHinges("fst.whats-new.sheet", "fst.whats-new.dismiss", "fst.whats-new.close")
        if (compact || h.hinges().isNotEmpty()) {
            val sheet = rule.onNodeWithTag("fst.whats-new.sheet").fetchSemanticsNode().boundsInWindow
            val dismiss = rule.onNodeWithTag("fst.whats-new.dismiss").fetchSemanticsNode().boundsInWindow
            val gap = with(rule.density) { (sheet.bottom - dismiss.bottom).toDp() }
            // Bar padding plus the gesture/navigation inset; never the empty band below short notes.
            assertTrue("Dismiss is $gap above the sheet's bottom edge", gap.value in 0f..80f)
        }
    }

    // endregion

    // region States

    /** `presented` → `dismissed`: Dismiss records the hash and closes the sheet. */
    @Test
    fun presentedReadsInOrderAndDismissRecordsSeen() {
        h.enableAccessibilityChecks()
        val preferences = MemoryPreferences()
        h.launch(DebugLaunch(stillBackground = true, whatsNew = "force"), transport, preferences)
        h.waitForTag("fst.whats-new.dismiss")
        assertPresented("whats-new-presented")
        h.tap("fst.whats-new.dismiss")
        h.waitGone("fst.whats-new.sheet")
        assertEquals(Changelog.currentHash, ChangelogSeenStore.decode(seenOf(preferences))!!.hash)
        h.assertAccessible()
    }

    /** `hidden-seen`: the current hash already recorded presents nothing on a normal launch. */
    @Test
    fun seenHashStaysHidden() {
        val record = ChangelogSeenStore.encode(ChangelogSeenRecord("2610.01.01", Changelog.currentHash))
        val preferences = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.CHANGELOG_SEEN) to record))
        h.launch(DebugLaunch(stillBackground = true, whatsNew = "on"), transport, preferences)
        h.waitForTag("fst.nav.tab.songs")
        Thread.sleep(2_000)
        rule.waitForIdle()
        assertFalse(h.exists("fst.whats-new.sheet"))
    }

    /** `waiting-for-first-run`: the launch carousel holds the slot; the sheet follows its close. */
    @Test
    fun waitsForTheFirstRunCarousel() {
        h.enableAccessibilityChecks()
        val preferences = MemoryPreferences()
        h.launch(DebugLaunch(stillBackground = true, firstRun = "force", whatsNew = "force"), transport, preferences)
        h.waitForTag("fst.first-run.dialog")
        Thread.sleep(1_500)
        rule.waitForIdle()
        assertFalse(h.exists("fst.whats-new.sheet"))
        h.tap("fst.first-run.close")
        h.waitGone("fst.first-run.dialog")
        h.waitForTag("fst.whats-new.dismiss")
        assertPresented("whats-new-after-first-run")
        assertNull(seenOf(preferences))
        h.assertAccessible()
    }

    /** `replay`: Settings reopens the notes with the default-off debug gate; Close records them. */
    @Test
    fun settingsReplayShowsAndCloseRecordsSeen() {
        h.enableAccessibilityChecks()
        val preferences = MemoryPreferences()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport, preferences)
        h.waitForTag("fst.settings.list")
        assertFalse(h.exists("fst.whats-new.sheet"))
        h.scrollTo("fst.settings.list", "fst.settings.whats-new")
        h.tap("fst.settings.whats-new")
        h.waitForTag("fst.whats-new.dismiss")
        assertPresented("whats-new-replay")
        h.tap("fst.whats-new.close")
        h.waitGone("fst.whats-new.sheet")
        assertEquals(Changelog.currentHash, ChangelogSeenStore.decode(seenOf(preferences))!!.hash)
        h.assertAccessible()
    }

    /** Double text keeps the headings, notes and both buttons in order and ≥ 48 dp. */
    @Test
    fun doubleTextKeepsOrderAndTargets() {
        h.enableAccessibilityChecks()
        val blocks = listOf(
            WhatsNewBlock("Changes Since Release 2610.01.03", listOf(ChangelogGroup("Songs", listOf("Rows load faster when you scroll the full catalogue.")))),
            WhatsNewBlock("Version 2610.01.03", listOf(ChangelogGroup(null, listOf("The first release.")))),
        )
        var dismissed = 0
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale * 2f)) {
                FestivalTheme {
                    WhatsNewSheet("What's New · 2610.02.02", blocks, compact = LocalConfiguration.current.screenWidthDp < 600) { dismissed++ }
                }
            }
        }
        h.waitForTag("fst.whats-new.dismiss")
        val order = h.readingOrder("whats-new-2x")
        before(order, "What's New", "Close")
        before(order, "Changes Since Release", "Songs")
        before(order, "Songs", "Rows load faster")
        assertTargets("fst.whats-new.close", "fst.whats-new.dismiss")
        assertTrue(rule.onAllNodesWithTag("fst.whats-new.group.0.0").fetchSemanticsNodes().isNotEmpty())
        h.tap("fst.whats-new.dismiss")
        rule.waitUntil(5_000) { dismissed > 0 }
        h.assertAccessible()
    }

    // endregion
}
