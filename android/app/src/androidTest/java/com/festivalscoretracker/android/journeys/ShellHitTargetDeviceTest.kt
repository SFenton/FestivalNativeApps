package com.festivalscoretracker.android.journeys

import android.app.UiAutomation
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.ShellHitTargets
import com.festivalscoretracker.android.testing.ShellTool
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/** One unread notification, so the bell shows its badge over the button. */
private const val UNREAD_FEED = """{"sourceRunId":3,"items":[
  {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-1","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"}]}"""

/**
 * Forgiving, separate hit regions for the shell's navigation-bar and toolbar buttons on a real
 * device (issues #72, #179): Quick Links, Sort, Filter, global Search, the bell, Profile and ⋮
 * each keep a touch target of at least 48 dp that doesn't overlap its neighbour's, and real
 * touches 22 dp off the glyph's centre (outside the 40 dp container) activate them. Follows the
 * window's placement of the page tools: the floating toolbar (compact), the top app bar (medium
 * and wider) or ⋮ on a narrow list pane. ATF runs on every interaction; TalkBack's reading order
 * and the measured targets go to logcat `FST_A11Y`. Run with
 * `device.py test com.festivalscoretracker.android.journeys.ShellHitTargetDeviceTest --avd … [--posture …]`
 * ([ShellHitTargetRotatedDeviceTest] for the display turned a quarter).
 *
 * @param rotation `UiAutomation.ROTATION_FREEZE_*` to apply before the activity starts, or `null`.
 */
abstract class ShellHitTargetJourney(rotation: Int?) {
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val turn = DisplayRotation(rotation)

    /** Rotates around the activity (within `device.py test`'s lock hold) and restores after. */
    @get:Rule
    val chain: RuleChain = RuleChain.outerRule(turn).around(rule)

    private val h = JourneyHarness(rule)
    private val probe = ShellHitTargets(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private var textScale = 1f
    private val pageTools = listOf("fst.quick-links.open", "fst.songs.sort.open", "fst.songs.filter.open")

    // region Helpers

    /**
     * Launches Songs (Year sort, so Quick Links has sections) with an unread notification.
     *
     * @param fontScale Text scale applied over the device's own (200 % checks large text).
     */
    private fun launchSongs(fontScale: Float? = null) {
        turn.awaitApplied()
        textScale = fontScale ?: rule.activity.resources.configuration.fontScale
        h.enableAccessibilityChecks()
        val transport = SongsFixtures.scrollingCatalogueTransport().also { ProfileFixtures.register(it) }
        transport.on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) { UNREAD_FEED }
        val prefs = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        val debug = DebugLaunch(profile = player, stillBackground = true)
        if (fontScale == null) {
            h.launch(debug, transport, prefs)
        } else {
            val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
            rule.setContent {
                val base = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale)) { FestivalApp(container, debug) }
            }
        }
        h.waitForTag("fst.songs.row.s-1")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.open") || h.exists("fst.nav.overflow") }
        h.waitForTag("fst.shell.notifications")
    }

    private fun within(ancestor: String, tag: String) =
        rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(ancestor))).fetchSemanticsNodes().isNotEmpty()

    /** Logs the measured targets (dp) for the configuration's findings. */
    private fun log(screen: String, targets: Map<String, Rect>) {
        val config = rule.activity.resources.configuration
        val d = rule.density.density
        targets.forEach { (tag, box) ->
            Log.i(
                JourneyHarness.READING_ORDER_TAG,
                "$screen | w${config.screenWidthDp}dp h${config.screenHeightDp}dp font $textScale | $tag | ${box.width / d}x${box.height / d} dp at ${box.left / d},${box.top / d}",
            )
        }
    }

    /**
     * Measures every shell target, touches each present tool off-centre and checks the bell
     * also activates from its badge; then, when the page tools sit behind ⋮, does the same for
     * them inside its menu.
     *
     * @param screen Name for the log.
     */
    private fun assertForgiving(screen: String) {
        val overflow = h.exists("fst.nav.overflow") && !h.exists("fst.songs.sort.open")
        val compact = rule.activity.resources.configuration.screenWidthDp < 600
        if (compact) pageTools.forEach { assertTrue("$it in the floating toolbar", within("fst.nav.floating-toolbar", it)) }
        val targets = probe.assertTargets(ShellHitTargets.SHELL_TAGS)
        log(screen, targets)
        h.assertNothingStraddles(*ShellHitTargets.SHELL_TAGS.toTypedArray())
        h.readingOrder(screen)

        val tools = if (overflow) {
            listOf(ShellHitTargets.OVERFLOW)
        } else {
            listOf(ShellHitTargets.QUICK_LINKS, ShellHitTargets.SORT, ShellHitTargets.FILTER)
        } + listOf(ShellHitTargets.SEARCH, ShellHitTargets.BELL, ShellHitTargets.PROFILE_OPEN)
        tools.forEach { tool: ShellTool ->
            val extra = if (tool == ShellHitTargets.BELL && h.exists("fst.shell.notifications.badge")) {
                val badge = rule.onAllNodes(hasTestTag("fst.shell.notifications.badge"), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot
                listOf(badge.center - targets.getValue(tool.tag).center)
            } else {
                emptyList()
            }
            probe.assertOffCentreTouchesActivate(tool, extra)
        }

        if (overflow) {
            h.tap("fst.nav.overflow")
            h.waitForTag("fst.nav.overflow-menu")
            pageTools.forEach { assertTrue("$it in ⋮", within("fst.nav.overflow-menu", it)) }
            log("$screen-overflow-menu", probe.assertTargets(pageTools))
            h.readingOrder("$screen-overflow-menu")
            probe.offCentre().forEach { offset ->
                probe.touch("fst.songs.sort.open", offset)
                h.waitForTag("fst.songs.sort.form")
                h.tap("fst.songs.sort.done")
                h.waitGone("fst.songs.sort.form")
                h.waitGone("fst.nav.overflow-menu")
                h.tap("fst.nav.overflow")
                h.waitForTag("fst.nav.overflow-menu")
            }
            // Close ⋮ through a tool (its menu closes once the tool's sheet closes, issue #160).
            h.tap("fst.songs.sort.open")
            h.waitForTag("fst.songs.sort.form")
            h.tap("fst.songs.sort.done")
            h.waitGone("fst.nav.overflow-menu")
        }
        h.assertAccessible()
    }

    // endregion

    @Test
    fun barAndToolbarButtonsHaveForgivingSeparateTargets() {
        launchSongs()
        assertForgiving("hit-targets")
    }

    @Test
    fun targetsHoldAtDoubleFontScale() {
        launchSongs(fontScale = 2f)
        assertForgiving("hit-targets-font-2")
    }
}

/** The display as the AVD or posture leaves it. */
@RunWith(AndroidJUnit4::class)
class ShellHitTargetDeviceTest : ShellHitTargetJourney(rotation = null)

/** The display turned a quarter (phone landscape, tablet portrait). */
@RunWith(AndroidJUnit4::class)
class ShellHitTargetRotatedDeviceTest : ShellHitTargetJourney(rotation = UiAutomation.ROTATION_FREEZE_90)

/**
 * Freezes the display at [rotation] for one test, then restores the device's previous rotation
 * settings (a shared AVD is left as found).
 *
 * A freeze cannot turn the display while a portrait-only window (the launcher between tests)
 * is focused, so [before] only issues it and the test calls [awaitApplied] once its activity
 * is up and before it sets content; the turn may recreate that activity. [after] waits until
 * the display is back upright before the next class starts. Sleeping a fixed time instead let
 * a late quarter turn land in the next test class on CI, which then ran in landscape or lost
 * its activity (issue #432).
 *
 * @property rotation `UiAutomation.ROTATION_FREEZE_*`, or `null` to leave the display alone.
 */
private class DisplayRotation(private val rotation: Int?) : ExternalResource() {
    private val automation get() = InstrumentationRegistry.getInstrumentation().uiAutomation
    private var saved: Pair<String, String>? = null

    private fun shell(command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command)).bufferedReader().use { it.readText().trim() }

    override fun before() {
        rotation ?: return
        saved = shell("settings get system accelerometer_rotation") to shell("settings get system user_rotation")
        automation.setRotation(rotation)
    }

    /**
     * Waits until the display has turned to [rotation] with the test's activity in front,
     * re-issuing the freeze if the system dropped it. No-op without a rotation.
     */
    fun awaitApplied() {
        val target = rotation ?: return
        val current = settle(target, reissue = target)
        assertTrue("display rotation $current, expected $target (Surface.ROTATION_*)", current == target)
    }

    override fun after() {
        val (accelerometer, user) = saved ?: return
        // With auto-rotate off the display returns to the saved user rotation; with it on, the
        // emulator's upright sensor turns it back to natural portrait.
        val restore = if (accelerometer == "1") UiAutomation.ROTATION_FREEZE_0 else user.toIntOrNull() ?: UiAutomation.ROTATION_FREEZE_0
        automation.setRotation(restore)
        shell("settings put system user_rotation $user")
        shell("settings put system accelerometer_rotation $accelerometer")
        // Only the natural rotation is guaranteed with the launcher in front; otherwise wait
        // until the display has left the test's rotation.
        settle(restore.takeIf { it == UiAutomation.ROTATION_FREEZE_0 }, avoid = rotation)
    }

    /**
     * Polls WindowManager until the display has held one rotation for [ROTATION_SETTLE_MS]
     * that matches [expected] (any, when `null`) and differs from [avoid].
     *
     * @param reissue Freeze re-issued every [ROTATION_REISSUE_MS] while unmet, or `null`.
     * @return The last rotation seen (the settled one unless [ROTATION_TIMEOUT_MS] ran out).
     */
    private fun settle(expected: Int?, reissue: Int? = null, avoid: Int? = null): Int {
        val deadline = SystemClock.uptimeMillis() + ROTATION_TIMEOUT_MS
        var stableSince = -1L
        var issuedAt = SystemClock.uptimeMillis()
        var last = -2
        while (SystemClock.uptimeMillis() < deadline) {
            val now = SystemClock.uptimeMillis()
            val current = displayRotation()
            val met = (expected == null || current == expected) && current != avoid && current >= 0
            if (met && current == last) {
                if (now - stableSince >= ROTATION_SETTLE_MS) break
            } else {
                stableSince = now
                if (!met && reissue != null && now - issuedAt >= ROTATION_REISSUE_MS) {
                    automation.setRotation(reissue)
                    issuedAt = now
                }
            }
            last = current
            Thread.sleep(ROTATION_POLL_MS)
        }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        return last
    }

    /**
     * The default display's rotation as WindowManager applied it (`DisplayRotation.mRotation`).
     * A non-activity context's `Display.getRotation()` does not follow it on API 37.
     *
     * @return `Surface.ROTATION_*`, or -1 when the dump has no rotation.
     */
    private fun displayRotation(): Int =
        ROTATION_LINE.find(shell("dumpsys window displays"))?.groupValues?.get(1)?.toInt() ?: -1

    private companion object {
        const val ROTATION_SETTLE_MS = 1_000L
        const val ROTATION_REISSUE_MS = 2_000L
        const val ROTATION_POLL_MS = 100L
        const val ROTATION_TIMEOUT_MS = 15_000L
        val ROTATION_LINE = Regex("""\bmRotation=(\d)\b""")
    }
}