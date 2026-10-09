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

    /** Rotates before the activity launches (within `device.py test`'s lock hold) and restores after. */
    @get:Rule
    val chain: RuleChain = RuleChain.outerRule(DisplayRotation(rotation)).around(rule)

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
 * The whole connected suite shares one device, so the restore must not hand a later test a
 * rotated display (issue #528). With auto-rotate on, the orientation listener can still propose
 * the test's quarter turn for a while after the freeze ends; the next activity with an
 * unspecified orientation then turned landscape (`ShopFilterAccessibilityJourneyTest` failed on
 * CI's API 35 emulator). [after] therefore waits, while the launcher holds the natural rotation,
 * until the sensor agrees with it, and keeps the display locked at the natural rotation if it
 * never does.
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
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(ROTATION_SETTLE_MS)
    }

    override fun after() {
        val (accelerometer, user) = saved ?: return
        automation.setRotation(UiAutomation.ROTATION_FREEZE_0)
        restoreSetting("user_rotation", user)
        restoreSetting("accelerometer_rotation", accelerometer)
        if (accelerometer == "1" && !awaitSensorAtNaturalRotation()) {
            automation.setRotation(UiAutomation.ROTATION_FREEZE_0)
            Log.w(TAG, "sensor still proposes a turned display; left rotation locked at 0 (${rotationState()})")
        }
        Log.i(TAG, "restored accelerometer_rotation=$accelerometer user_rotation=$user (${rotationState()})")
    }

    /**
     * Puts a saved system setting back, deleting it when it was unset.
     *
     * @param name `Settings.System` key.
     * @param value Value read before the test (`null` when it was unset).
     */
    private fun restoreSetting(name: String, value: String) {
        shell(if (value.isEmpty() || value == "null") "settings delete system $name" else "settings put system $name $value")
    }

    /**
     * Waits until the display is at its natural rotation and the orientation listener's proposal
     * stays natural (or empty) for [SENSOR_AGREE_POLLS] polls in a row.
     *
     * @return `true` once the sensor agrees, `false` after [SENSOR_SETTLE_TIMEOUT_MS].
     */
    private fun awaitSensorAtNaturalRotation(): Boolean {
        val deadline = SystemClock.uptimeMillis() + SENSOR_SETTLE_TIMEOUT_MS
        var agreeing = 0
        while (SystemClock.uptimeMillis() < deadline) {
            val (display, proposed) = rotations(shell("dumpsys window displays"))
            agreeing = if (display == 0 && (proposed == null || proposed <= 0)) agreeing + 1 else 0
            if (agreeing >= SENSOR_AGREE_POLLS) return true
            Thread.sleep(SENSOR_POLL_MS)
        }
        return false
    }

    /** @return The default display's rotation and the sensor's proposal, for logcat `FST_ROTATION`. */
    private fun rotationState(): String = rotations(shell("dumpsys window displays")).let { "display=${it.first} proposed=${it.second}" }

    /**
     * Reads `dumpsys window displays`' `DisplayRotation` section.
     *
     * @param dump Command output.
     * @return The display's `mRotation` and the accelerometer judge's `mProposedRotation`
     *   (`null` when the listener isn't reported).
     */
    private fun rotations(dump: String): Pair<Int?, Int?> =
        Regex("""\bmRotation=(\d) mDeferredRotationPauseCount""").find(dump)?.groupValues?.get(1)?.toInt() to
            Regex("""mProposedRotation=(-?\d+)""").find(dump)?.groupValues?.get(1)?.toInt()

    private companion object {
        const val TAG = "FST_ROTATION"
        const val ROTATION_SETTLE_MS = 1_000L
        const val SENSOR_SETTLE_TIMEOUT_MS = 15_000L
        const val SENSOR_POLL_MS = 300L
        const val SENSOR_AGREE_POLLS = 4
    }
}
