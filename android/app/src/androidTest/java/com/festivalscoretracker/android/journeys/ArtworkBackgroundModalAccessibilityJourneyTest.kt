package com.festivalscoretracker.android.journeys

import android.accessibilityservice.AccessibilityServiceInfo
import android.os.ParcelFileDescriptor
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.background.ARTWORK_BACKGROUND_TAG
import com.festivalscoretracker.android.ui.background.ArtworkBackgroundStateKey
import com.festivalscoretracker.android.ui.common.MODAL_CLOSE_LABEL
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The album-art backdrop behind Festival modals on a real device (issue #436, the accessibility
 * tests for #83): every modal kind that registers with `ModalCoverage` (the first-run tour's
 * `FestivalModalDialog`, the Privacy Policy `FestivalModalSheet`, the Feedback form's own
 * `Dialog` and the Reset `FestivalAlertDialog`) holds the backdrop (`covered`) while open and
 * releases it on close (`animated`, open count back to 0), at font scale 1.0 and 2.0. While a
 * modal is open, the modal's window is the one TalkBack reads, it reads its title before its
 * actions, Close and the alert buttons are labelled 48 dp buttons, and no window exposes the
 * backdrop to TalkBack. With Remove animations (animator scale 0) the backdrop stays
 * `reduced-motion` under and after a modal. ATF runs on every interaction. Covers point at
 * `art.invalid`, so no image is fetched; the state machine does not depend on a cover loading.
 *
 * `device.py test com.festivalscoretracker.android.journeys.ArtworkBackgroundModalAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`. `@DeviceCi`: both Android device pull-request checks
 * run it on a plain phone against fixtures.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ArtworkBackgroundModalAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "\"https://art.invalid/alpha.jpg\"")
        }
        on("/api/features") { """{"appManual":false,"feedback":true}""" }
    }
    private var animatorScale = "1"

    // region Setup

    private fun shell(command: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().decodeToString().trim() }
    }

    /** Animations on (CI and `device.py` turn them off), and every window visible to the tree walks. */
    @Before
    fun setUp() {
        animatorScale = shell("settings get global animator_duration_scale").takeIf { it != "null" && it.isNotEmpty() } ?: "1"
        shell("settings put global animator_duration_scale 1")
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply { flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS }
    }

    @After
    fun restore() {
        shell("settings put global animator_duration_scale $animatorScale")
    }

    // endregion

    // region Tests

    /** The first-run tour (the #83 report's FRE, over Songs) holds the backdrop and is what TalkBack reads. */
    @Test
    fun firstRunTourHoldsTheBackdropAndKeepsItOutOfTalkBack() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(firstRun = "force"), transport)
        h.waitForTag(ARTWORK_BACKGROUND_TAG)
        assertModalHoldsBackdrop("first-run", close = "fst.first-run.close", heading = "fst.first-run.title")
        h.tap("fst.first-run.close")
        h.waitGone("fst.first-run.dialog")
        assertReleased("first-run", page = "fst.songs.list")
        h.assertAccessible()
    }

    /** Settings' sheet, full-screen form and alert each hold and release the backdrop at 1.0 and 2.0 text. */
    @Test
    fun settingsModalsHoldAndReleaseTheBackdropAtEveryTextSize() {
        var scale by mutableFloatStateOf(SCALES.first())
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings), transport, fontScale = { scale })
        h.waitForTag("fst.settings.list")
        waitForState("animated")
        SCALES.forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "fs $s"

            // List/detail windows (issue #371) show the policy in the detail pane, not a modal.
            h.scrollTo("fst.settings.list", "fst.settings.privacy-policy")
            val panes = h.exists("fst.settings.detail-pane")
            h.tap("fst.settings.privacy-policy")
            if (!panes) {
                assertModalHoldsBackdrop("privacy-sheet $config", close = "fst.privacy-policy.close", heading = "fst.privacy-policy.title")
                h.tap("fst.privacy-policy.close")
                h.waitGone("fst.privacy-policy.sheet")
                assertReleased("privacy-sheet $config")
            }

            h.scrollTo("fst.settings.list", "fst.settings.feedback.bug")
            h.tap("fst.settings.feedback.bug")
            assertModalHoldsBackdrop("feedback $config", close = "fst.settings.feedback.close", heading = "fst.settings.feedback.title")
            h.tap("fst.settings.feedback.close")
            h.waitGone("fst.settings.feedback.dialog")
            assertReleased("feedback $config")

            openResetAlert()
            assertAlertHoldsBackdrop(config)
            h.tap("fst.settings.reset.cancel")
            h.waitGone("fst.settings.reset.dialog")
            assertReleased("reset-alert $config")
        }
        h.assertAccessible()
    }

    /** Remove animations wins over coverage: still under the alert and still after it, then live again. */
    @Test
    fun removeAnimationsKeepsTheBackdropStillUnderAndAfterAModal() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings), transport)
        h.waitForTag("fst.settings.list")
        waitForState("animated")
        shell("settings put global animator_duration_scale 0")
        waitForState("reduced-motion")
        openResetAlert()
        assertEquals("reduce motion outranks covered", "reduced-motion", state())
        assertEquals(1, ModalCoverage.shared.openCount.value)
        assertBackdropSilent("reset-alert reduced-motion")
        h.tap("fst.settings.reset.cancel")
        h.waitGone("fst.settings.reset.dialog")
        rule.waitUntil(10_000) { ModalCoverage.shared.openCount.value == 0 }
        assertEquals("reduced-motion", state())
        shell("settings put global animator_duration_scale 1")
        waitForState("animated")
        h.assertAccessible()
    }

    // endregion

    // region Modal checks

    private fun openResetAlert() {
        h.scrollTo("fst.settings.list", "fst.settings.reset")
        h.tap("fst.settings.reset")
        h.waitForTag("fst.settings.reset.dialog")
    }

    /**
     * An open header modal holds the backdrop, is the window TalkBack reads, reads its heading
     * before Close, and its Close is a labelled 48 dp button; no window exposes the backdrop.
     *
     * @param screen Reading-order log name.
     * @param close Close button test tag.
     * @param heading Header title test tag.
     */
    private fun assertModalHoldsBackdrop(screen: String, close: String, heading: String) {
        h.waitForTag(close)
        waitForState("covered")
        assertEquals("$screen: one modal registered", 1, ModalCoverage.shared.openCount.value)
        val button = rule.onAllNodesWithTag(close)[0].fetchSemanticsNode()
        assertEquals("$screen: Close label", listOf(MODAL_CLOSE_LABEL), button.config.getOrNull(SemanticsProperties.ContentDescription))
        assertEquals("$screen: Close role", Role.Button, button.config.getOrNull(SemanticsProperties.Role))
        assertMinTarget("$screen Close", button.touchBoundsInRoot.width, button.touchBoundsInRoot.height)
        h.awaitAccessibilityTree(present = close)
        assertBackdropSilent(screen)
        val title = rule.onAllNodesWithTag(heading, useUnmergedTree = true)[0].fetchSemanticsNode()
        assertTrue("$screen: the title is a heading", SemanticsProperties.Heading in title.config)
        val titleText = title.config[SemanticsProperties.Text].joinToString { it.text }
        val order = h.readingOrder("backdrop-$screen", fresh = true)
        val titleAt = order.indexOfFirst { it.startsWith(titleText) }
        val closeAt = order.indexOf(MODAL_CLOSE_LABEL)
        assertTrue("$screen: \"$titleText\" reads before Close: $order", titleAt >= 0 && closeAt > titleAt)
    }

    /**
     * The open Reset alert holds the backdrop, reads title → message → Cancel/Reset, and both
     * buttons are labelled 48 dp buttons inside the alert; no window exposes the backdrop.
     *
     * @param config Configuration name for messages.
     */
    private fun assertAlertHoldsBackdrop(config: String) {
        waitForState("covered")
        assertEquals("reset-alert $config: one modal registered", 1, ModalCoverage.shared.openCount.value)
        val dialog = rule.onNodeWithTag("fst.settings.reset.dialog").fetchSemanticsNode().boundsInRoot
        for ((tag, label) in listOf("fst.settings.reset.cancel" to "Cancel", "fst.settings.reset.confirm" to "Reset")) {
            val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
            assertEquals("$tag label", label, node.config[SemanticsProperties.Text].joinToString { it.text })
            assertEquals("$tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            assertMinTarget("$config $tag", node.touchBoundsInRoot.width, node.touchBoundsInRoot.height)
            val box = node.boundsInRoot
            assertTrue("$config: $tag $box inside the alert $dialog", box.left >= dialog.left - 1 && box.right <= dialog.right + 1 && box.bottom <= dialog.bottom + 1)
        }
        h.awaitAccessibilityTree(present = "fst.settings.reset.cancel")
        assertBackdropSilent("reset-alert $config")
        val order = h.readingOrder("backdrop-reset-alert $config", fresh = true)
        val at = listOf("Reset Settings", "Are you sure", "Cancel", "Reset").map { label -> order.indexOfFirst { it.startsWith(label) && (label != "Reset" || it == "Reset") } }
        assertTrue("$config: alert reads title, message, Cancel, Reset: $order", at.all { it >= 0 } && at == at.sorted())
    }

    /**
     * After a modal closes the backdrop animates again, no modal stays registered and TalkBack
     * is back on the page without meeting the backdrop.
     *
     * @param screen Name for messages.
     * @param page Test tag of the page under the modal.
     */
    private fun assertReleased(screen: String, page: String = "fst.settings.list") {
        waitForState("animated")
        assertEquals("$screen: modal count leaked", 0, ModalCoverage.shared.openCount.value)
        h.awaitAccessibilityTree(present = page)
        val order = h.readingOrder("backdrop-after-$screen", fresh = true)
        assertTrue("$screen: backdrop reached TalkBack: $order", order.none { it.contains("artwork", ignoreCase = true) })
        assertBackdropSilent("after $screen")
    }

    private fun assertMinTarget(what: String, width: Float, height: Float) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$what target ${width}x$height px < 48 dp", width >= min && height >= min)
    }

    // endregion

    // region Backdrop

    private fun state(): String =
        rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG, useUnmergedTree = true).fetchSemanticsNode().config[ArtworkBackgroundStateKey]

    private fun waitForState(expected: String) {
        runCatching { rule.waitUntil(10_000) { runCatching { state() }.getOrNull() == expected } }
            .onFailure { throw AssertionError("backdrop never reached $expected (was ${runCatching { state() }.getOrNull()})", it) }
    }

    /**
     * In every window TalkBack can reach (the page and the modal above it), the backdrop node is
     * absent or a silent leaf: not focusable or clickable, no label and no children.
     *
     * @param where Name for messages.
     */
    private fun assertBackdropSilent(where: String) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun backdrops(node: AccessibilityNodeInfo?, into: MutableList<AccessibilityNodeInfo> = mutableListOf()): List<AccessibilityNodeInfo> {
            node ?: return into
            if (node.viewIdResourceName?.endsWith(ARTWORK_BACKGROUND_TAG) == true) into += node
            for (i in 0 until node.childCount) backdrops(node.getChild(i), into)
            return into
        }
        val roots = automation.windows.mapNotNull { it.root } + listOfNotNull(automation.rootInActiveWindow)
        roots.flatMap { backdrops(it) }.forEach { node ->
            assertTrue("$where: backdrop is focusable", !node.isFocusable && !node.isScreenReaderFocusable && !node.isClickable && !node.isLongClickable)
            assertTrue("$where: backdrop has a label", node.text.isNullOrEmpty() && node.contentDescription.isNullOrEmpty() && node.stateDescription.isNullOrEmpty())
            assertTrue("$where: backdrop has children", node.childCount == 0)
        }
    }

    // endregion

    private companion object {
        /** Default and largest Android font scale (200%). */
        val SCALES = listOf(1f, 2f)
    }
}
