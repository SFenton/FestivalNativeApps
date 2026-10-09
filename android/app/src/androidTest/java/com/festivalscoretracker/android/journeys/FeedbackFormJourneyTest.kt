package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.filterToOne
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onAncestors
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Report an Issue / Request a Feature on a device (issue #143), with Accessibility
 * Test Framework checks on every interaction and a TalkBack reading-order dump per state
 * (`device.py test com.festivalscoretracker.android.journeys.FeedbackFormJourneyTest --avd FST_Phone`,
 * and `--avd FST_Book_Fold --posture half`). Fixture transport only: nothing reaches the service.
 */
@RunWith(AndroidJUnit4::class)
class FeedbackFormJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val jobId = "0123456789abcdef0123456789abcdef"
    private val transport = FakeTransport.standard().apply {
        on("/api/service-info") { """{"contractVersion":2}""" }
        on("/api/version") { """{"version":"9.9.9"}""" }
        on("/api/features") { """{"appManual":false,"feedback":true}""" }
    }

    private fun openForm(kind: String, fontScale: (() -> Float)? = null) {
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport, fontScale = fontScale)
        h.publishTalkBackTree()
        h.waitForTag("fst.settings.list")
        h.scrollTo("fst.settings.list", "fst.settings.feedback.$kind")
        h.readingOrder("settings-feedback-rows")
        h.tap("fst.settings.feedback.$kind")
        h.waitForTag("fst.settings.feedback.dialog")
        h.assertNothingStraddles("fst.settings.feedback.dialog")
    }

    private fun type(field: String, text: String) {
        rule.onNodeWithTag("fst.settings.feedback.field.$field").performScrollTo().performTextReplacement(text)
        rule.waitForIdle()
    }

    /** Reading order once the accessibility tree (which trails Compose) shows [text]. */
    private fun orderWith(screen: String, text: String): List<String> {
        var order = emptyList<String>()
        rule.waitUntil(15_000) { order = h.readingOrder(screen); order.any { it.contains(text) } }
        return order
    }

    private fun waitForText(text: String) = rule.waitUntil(15_000) { rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun bugReportStatesReadInOrderAndPassChecks() {
        val release = CountDownLatch(1)
        val polls = AtomicInteger()
        transport.on("/api/feedback", status = 202) { release.await(15, TimeUnit.SECONDS); """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") {
            if (polls.getAndIncrement() == 0) """{"id":"$jobId","status":"processing"}"""
            else """{"id":"$jobId","status":"submitted","issueNumber":42,"attachments":[]}"""
        }
        h.enableAccessibilityChecks()
        openForm("bug")

        // Invalid: Submit is off and the reason reads after the title, before the fields.
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        val empty = orderWith("feedback-invalid", "Add a title after the prefix.")
        val title = empty.indexOfFirst { it.contains("Report an Issue") }
        val reason = empty.indexOfFirst { it.contains("Add a title after the prefix.") }
        val field = empty.indexOfFirst { it.contains("[Bug]") }
        assertTrue("reading order $empty", title >= 0 && reason > title && field > reason)
        assertTrue("reading order $empty", empty.any { it.contains("Close") } && empty.any { it.contains("Submit") })

        type("title", "[Bug] Songs crash")
        type("description", "Opening Songs crashes.")
        h.waitGone("fst.settings.feedback.validation")
        orderWith("feedback-dirty", "Opening Songs crashes.")

        h.tap("fst.settings.feedback.submit")
        h.waitForTag("fst.settings.feedback.progress")
        waitForText("Sending your report")
        orderWith("feedback-sending", "Sending your report")
        h.tap("fst.settings.feedback.close")
        h.waitForTag("fst.settings.feedback.discard.dialog")
        val discard = orderWith("feedback-discard", "Sending will stop")
        assertTrue("reading order $discard", discard.any { it.contains("Sending will stop") })
        h.tap("fst.settings.feedback.discard.cancel")
        h.waitGone("fst.settings.feedback.discard.dialog")

        release.countDown()
        waitForText("Filing your report on GitHub")
        orderWith("feedback-filing", "Filing your report on GitHub")
        h.waitForTag("fst.settings.feedback.sent")
        val sent = orderWith("feedback-sent", "filed as issue #42")
        assertTrue("reading order $sent", sent.any { it.contains("filed as issue #42") })
        h.assertNothingStraddles("fst.settings.feedback.dialog", "fst.settings.feedback.done")
        h.tap("fst.settings.feedback.done")
        h.waitGone("fst.settings.feedback.dialog")
        h.assertAccessible()
    }

    @Test
    fun featureRequestErrorKeepsInputAndPassesChecks() {
        transport.on("/api/feedback", status = 503) { """{"error":"feedback_busy"}""" }
        h.enableAccessibilityChecks()
        openForm("feature")
        type("title", "[Feature] Themes")
        type("description", "More themes, please.")
        h.tap("fst.settings.feedback.submit")
        h.waitForTag("fst.settings.feedback.error")
        val error = orderWith("feedback-error", "Feedback is busy")
        val banner = error.indexOfFirst { it.startsWith("Error") }
        val field = error.indexOfFirst { it.contains("[Feature] Themes") }
        assertTrue("reading order $error", banner >= 0 && field > banner)
        h.tap("fst.settings.feedback.close")
        h.waitForTag("fst.settings.feedback.discard.dialog")
        h.tap("fst.settings.feedback.discard.confirm")
        h.waitGone("fst.settings.feedback.dialog")
        h.assertAccessible()
    }

    /**
     * At 200% text a field scrolled partly under the modal header must not take TalkBack's touch
     * area from Submit or Close (modal-shell R5): Compose extends a clipped node's touch bounds
     * past its scroll viewport, and before `FestivalModalBody` clipped them Submit published a
     * 47 dp node (issue #422). The title field is scrolled so its top sits 16 dp above Submit's
     * bottom edge, the overlap the CI emulator reached with the keyboard up. TalkBack's published
     * order (`publishTalkBackTree`) still reads the title, Submit, then Close before the field.
     */
    @DeviceCi
    @Test
    fun headerActionsKeepFullTouchAreaOverAFieldScrolledUnderAtLargeText() {
        h.enableAccessibilityChecks()
        openForm("bug", fontScale = { 2f })
        type("title", "[Bug] Songs crash")
        type("description", "Opening Songs crashes.")
        val field = rule.onNodeWithTag("fst.settings.feedback.field.title", useUnmergedTree = true)
        val body = field.onAncestors().filterToOne(hasScrollAction())
        val overlap = with(rule.density) { 16.dp.toPx() }
        val submitBottom = rule.onNodeWithTag("fst.settings.feedback.submit").fetchSemanticsNode().boundsInRoot.bottom
        val fieldTop = field.fetchSemanticsNode().positionInRoot.y
        body.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, fieldTop - (submitBottom - overlap)) }
        rule.waitForIdle()
        val viewportTop = body.fetchSemanticsNode().boundsInRoot.top
        val scrolled = field.fetchSemanticsNode().let { it.positionInRoot.y to it.positionInRoot.y + it.size.height }
        assertTrue("title field $scrolled should straddle the body top $viewportTop", scrolled.first < submitBottom && scrolled.second > viewportTop)
        h.assertFullTouchTarget("fst.settings.feedback.submit")
        h.assertFullTouchTarget("fst.settings.feedback.close")
        val order = orderWith("feedback-scrolled-under", "Submit")
        val title = order.indexOfFirst { it.contains("Report an Issue") }
        val submit = order.indexOfFirst { it.contains("Submit") }
        val close = order.indexOfFirst { it.contains("Close") }
        val titleField = order.indexOfFirst { it.contains("[Bug] Songs crash") }
        assertTrue("reading order $order", title >= 0 && submit > title && close > submit)
        assertTrue("reading order $order", titleField < 0 || titleField > close)
        h.tap("fst.settings.feedback.close")
        h.waitForTag("fst.settings.feedback.discard.dialog")
        h.tap("fst.settings.feedback.discard.confirm")
        h.waitGone("fst.settings.feedback.dialog")
        h.assertAccessible()
    }
}
