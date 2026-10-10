package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Paths sheet's content swap (issue #70, row stagger and `ease` fades #177; accessibility
 * backfill #506) on a device, with ATF on every interaction. Each switch's table read is held
 * open so the spinner state can be inspected (`load-transition` R2, R4, R6):
 * - While the new path loads, TalkBack meets **one** spinner stop named for what is loading
 *   ("Loading Lead Hard path") with indeterminate progress semantics: no unnamed "In progress"
 *   stop and no second copy of the name. No row of the previous table stays in the
 *   accessibility tree, and the Instrument, Difficulty and View buttons stay readable, usable and
 *   at least 48 dp, read after the spinner.
 * - Once the rows stagger in, TalkBack reads "Paths", Close, the loaded announcement, then
 *   the activations in order (all three at 100% text; those on screen at 200%), then the
 *   controls, with no spinner left behind.
 * - The same at 200% text (the sheet reopened, then switched again), and under the in-app
 *   Reduce Motion setting, where the swap has no fades or stagger (R6) but the same accessible
 *   contract.
 *
 * `device.py test com.festivalscoretracker.android.journeys.PathsSwapAccessibilityJourneyTest --avd …`
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class PathsSwapAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val holds = CopyOnWriteArrayList<Pair<(String) -> Boolean, CompletableDeferred<Unit>>>()
    private val controls = listOf("fst.paths.instrument.open", "fst.paths.difficulty.open", "fst.paths.display.open")
    private var savedAnimatorScale: String? = null

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        listOf("expert", "hard").forEach { difficulty ->
            on("/api/paths/s-alpha/Solo_Guitar/$difficulty/data", headers = mapOf("X-FST-Publication-Id" to "7")) {
                SongsFixtures.pathJson.replace("\"difficulty\":\"expert\"", "\"difficulty\":\"$difficulty\"")
            }
        }
        ProfileFixtures.register(this)
        beforeRespond = { request -> holds.firstOrNull { (matches, _) -> matches(request.url) }?.second?.await() }
    }

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(fd).bufferedReader().readText().trim()
        }

    @Before
    fun saveAnimatorScale() {
        savedAnimatorScale = shell("settings get global animator_duration_scale")
    }

    @After
    fun restoreAnimatorScale() {
        holds.forEach { it.second.complete(Unit) }
        val saved = savedAnimatorScale
        shell(if (saved == null || saved == "null" || saved.isEmpty()) "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
    }

    /** Hold the [difficulty] table read until the returned gate completes. */
    private fun hold(difficulty: String): CompletableDeferred<Unit> =
        CompletableDeferred<Unit>().also { gate -> holds += { url: String -> url.contains("/api/paths/s-alpha/Solo_Guitar/$difficulty/data") } to gate }

    /** Karaoke hidden and Text saved as the default view: the sheet opens straight on the table. */
    private fun preferences(reduceMotion: Boolean) = MemoryPreferences(
        mutablePreferencesOf(
            stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Bass",
            stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW) to PathDisplayMode.Text.token,
            booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to reduceMotion,
        ),
    )

    /** Visible accessibility nodes whose resource id starts with [prefix]. */
    private fun visibleNodes(prefix: String): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName?.startsWith(prefix) == true && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    /** Assert the control [tag] is on screen, readable, enabled and at least 48 × 48 dp. */
    private fun assertTarget(tag: String) {
        val node = visibleNodes(tag).firstOrNull { it.viewIdResourceName == tag }
        assertTrue("$tag is not readable", node != null)
        val box = android.graphics.Rect().also(node!!::getBoundsInScreen)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$tag is ${box.width()}×${box.height()} px, under 48 dp", box.width() >= min && box.height() >= min)
        assertTrue("$tag is disabled while the path loads", node.isEnabled)
    }

    /**
     * Pick [difficulty] (closing its panel again) with its table read held, then assert the
     * spinner state: one indeterminate stop named "Loading Lead <Difficulty> path", no row of
     * the previous table readable, the controls usable and read after the spinner.
     */
    private fun assertSwitchSpinner(screen: String, difficulty: String): CompletableDeferred<Unit> {
        val gate = hold(difficulty)
        h.tap("fst.paths.difficulty.open")
        h.waitForTag("fst.paths.difficulty.$difficulty")
        h.tap("fst.paths.difficulty.$difficulty")
        h.waitForTag("fst.paths.loading")
        // R4: the panel's own button still works while the path loads.
        h.tap("fst.paths.difficulty.open")
        h.waitGone("fst.paths.difficulty.$difficulty")
        h.awaitAccessibilityTree(present = "fst.paths.status", absent = "fst.paths.row.1")
        val label = "Loading Lead ${difficulty.replaceFirstChar(Char::uppercase)} path"

        val named = rule.onAllNodes(hasContentDescription(label, substring = true)).fetchSemanticsNodes()
        assertEquals("one \"$label\" node in $screen", 1, named.size)
        assertEquals("$screen: the spinner stop is not indeterminate progress", ProgressBarRangeInfo.Indeterminate, named.single().config.getOrNull(SemanticsProperties.ProgressBarRangeInfo))
        val leaked = visibleNodes("fst.paths.row.").map { it.viewIdResourceName }
        assertTrue("$screen: stale rows readable under the spinner: $leaked", leaked.isEmpty())
        controls.forEach(::assertTarget)

        val order = h.readingOrder(screen, fresh = true)
        assertEquals("$screen: the spinner is not one stop in $order", 1, order.count { it.contains(label) })
        val heading = order.indexOf("Paths")
        val spinner = order.indexOfFirst { it.contains(label) }
        val firstControl = order.indexOfFirst { it.startsWith("Instrument:") || it.startsWith("Difficulty:") }
        assertTrue("$screen: Paths → spinner → controls in $order", heading in 0 until spinner && firstControl > spinner)
        // The sheet chrome above the heading (drag handle) is outside the Paths swap region.
        val region = order.subList(heading, firstControl)
        assertTrue("$screen: an unnamed spinner stop in $region", region.none { it == "<unlabelled>" || it.startsWith("In progress") })
        assertTrue("$screen: the button speaks the new choice in $order", order.any { it.startsWith("Difficulty: ${difficulty.replaceFirstChar(Char::uppercase)}") })
        return gate
    }

    /**
     * After the held read is released: the rows of the new table read in order between the
     * loaded announcement and the controls, and no spinner stop is left.
     */
    private fun assertRowsRevealed(screen: String, difficulty: String, minRows: Int = 3) {
        h.waitForTag("fst.paths.row.3")
        h.waitGone("fst.paths.loading")
        h.awaitAccessibilityTree(present = "fst.paths.row.$minRows")
        val loaded = "Lead ${difficulty.replaceFirstChar(Char::uppercase)} path loaded, 3 activations"
        val order = h.readingOrder(screen, fresh = true)
        assertTrue("$screen: a spinner stop is left in $order", order.none { it.startsWith("Loading ") || it.startsWith("In progress") })
        val close = order.indexOf("Close")
        val status = order.indexOf(loaded)
        // Rows scrolled off screen (200% text on a phone) are not in the tree; those shown read from Activation 1.
        val rows = (1..3).map { n -> order.indexOfFirst { it.startsWith("Activation $n:") } }.takeWhile { it >= 0 }
        val firstControl = order.indexOfFirst { it.startsWith("Instrument:") || it.startsWith("Difficulty:") }
        assertTrue("$screen: \"$loaded\" not read once in $order", order.count { it == loaded } == 1)
        assertTrue("$screen: under $minRows rows readable in $order", rows.size >= minRows)
        assertTrue(
            "$screen: Close → status → Activation 1…3 → controls in $order",
            close in 0 until status && status < rows.first() && rows.zipWithNext().all { (a, b) -> b > a } && firstControl > rows.last(),
        )
    }

    private fun open(reduceMotion: Boolean, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, preferences(reduceMotion), fontScale = fontScale)
        h.waitForTag("fst.song-detail.list")
        h.tap("fst.song-detail.paths.open")
        assertRowsRevealed("paths-swap-first-load", "expert")
    }

    // endregion

    /** Animations on (animator duration scale 1): Expert → Hard at 100% text, then reopened at 200% and switched again. */
    @Test
    fun switchReadsOneNamedSpinnerThenTheStaggeredRowsInOrder() {
        shell("settings put global animator_duration_scale 1")
        var scale by mutableFloatStateOf(1f)
        open(reduceMotion = false) { scale }

        val hard = assertSwitchSpinner("paths-swap-loading", "hard")
        hard.complete(Unit)
        assertRowsRevealed("paths-swap-hard", "hard")

        val rowHeight = rule.onNodeWithTag("fst.paths.row.1").fetchSemanticsNode().size.height
        // The sheet is its own window: it renders at a new text scale when it opens again.
        h.tap("fst.paths.close")
        h.waitGone("fst.song-detail.paths")
        scale = 2f
        rule.waitForIdle()
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.row.3")
        rule.waitUntil(10_000) { rule.onNodeWithTag("fst.paths.row.1").fetchSemanticsNode().size.height > rowHeight }
        h.awaitAccessibilityTree(present = "fst.paths.row.1", absent = "fst.song-detail.paths.open")
        val reopened = h.readingOrder("paths-swap-reopen-200", fresh = true).firstOrNull { it.startsWith("Difficulty:") }.orEmpty()
        val (from, to) = if (reopened.startsWith("Difficulty: Hard")) "hard" to "expert" else "expert" to "hard"
        assertRowsRevealed("paths-swap-reopen-200", from, minRows = 2)
        val next = assertSwitchSpinner("paths-swap-loading-200", to)
        next.complete(Unit)
        assertRowsRevealed("paths-swap-$to-200", to, minRows = 2)
        h.assertAccessible()
    }

    /** The in-app Reduce Motion setting: the same accessible swap with no fades or stagger (R6). */
    @Test
    fun switchUnderReduceMotionKeepsTheSameAccessibleSwap() {
        shell("settings put global animator_duration_scale 1")
        open(reduceMotion = true) { 1f }
        val hard = assertSwitchSpinner("paths-swap-reduce-motion-loading", "hard")
        hard.complete(Unit)
        assertRowsRevealed("paths-swap-reduce-motion-hard", "hard")
        h.assertAccessible()
    }
}
