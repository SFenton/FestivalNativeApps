package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.feedback.FeedbackCopy
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Settings → Report an Issue / Request a Feature (issue #78) on a phone window (Robolectric, fake transport only). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FeedbackUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard().apply {
        on("/api/service-info") { """{"contractVersion":2}""" }
        on("/api/version") { """{"version":"9.9.9"}""" }
        on("/api/features") { """{"appManual":false,"feedback":true}""" }
    }
    private val jobId = "0123456789abcdef0123456789abcdef"

    private fun launch() {
        val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
        waitFor("fst.settings.list")
        rule.waitUntil(10_000) { settle(100); transport.sent("/api/features").isNotEmpty() }
        settle()
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun waitFor(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
    }

    private fun openForm(kind: FeedbackKind) {
        val tag = "fst.settings.feedback.${kind.wire}"
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(tag))
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        waitFor("fst.settings.feedback.dialog")
    }

    private fun type(field: String, text: String) {
        rule.onNodeWithTag("fst.settings.feedback.field.$field").performScrollTo().performTextReplacement(text)
        settle()
    }

    @Test
    fun bugFormGuardsDiscardAndSubmits() {
        transport.on("/api/feedback", status = 202) { """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") { """{"id":"$jobId","status":"submitted","issueNumber":42,"attachments":[]}""" }
        launch()
        openForm(FeedbackKind.Bug)
        rule.onNodeWithTag("fst.settings.feedback.title").assertIsDisplayed()
        rule.onNodeWithText("[Bug] ").assertIsDisplayed()
        listOf("title", "description", "repro", "expected").forEach { rule.onNodeWithTag("fst.settings.feedback.field.$it").assertIsDisplayed() }
        rule.onNodeWithText(FeedbackCopy.REPRO_HELP).assertIsDisplayed()
        rule.onNodeWithText(FeedbackCopy.EXPECTED_HELP).assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.attach").performScrollTo().assertIsDisplayed()

        // Submit with only the prefix explains what is missing and sends nothing.
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        settle()
        waitFor("fst.settings.feedback.error")
        assertTrue(transport.sent("/api/feedback").isEmpty())

        type("title", "[Bug] Songs crash")
        type("description", "Opening Songs crashes.")
        type("repro", "1. Open Songs")

        // Close with input asks first; Keep Editing keeps everything.
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithTag("fst.settings.feedback.discard.cancel").performClick()
        waitGone("fst.settings.feedback.discard.dialog")
        rule.onNodeWithText("[Bug] Songs crash").assertIsDisplayed()

        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.sent")
        rule.onNodeWithText("Thanks! Your report was filed as issue #42.").assertIsDisplayed()
        assertEquals("GET", transport.sent("/api/feedback/$jobId").first().method)
        val request = transport.sent("/api/feedback").single()
        assertEquals("POST", request.method)
        val body = java.io.ByteArrayOutputStream().also { request.body!!.writeTo(it) }.toString(Charsets.UTF_8)
        assertTrue(body.contains("[Bug] Songs crash"))
        assertTrue(body.contains("name=\"platform\"\r\n\r\nandroid"))

        rule.onNodeWithTag("fst.settings.feedback.done").performClick()
        waitGone("fst.settings.feedback.dialog")
    }

    @Test
    fun rowsStayHiddenUntilTheServiceEnablesFeedback() {
        transport.on("/api/features") { """{"appManual":false}""" }
        launch()
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.bug").fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.feature").fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithText("Report an Issue").fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun featureFormHasNoBugBoxesAndShowsErrors() {
        transport.on("/api/feedback", status = 503) { "{}" }
        launch()
        openForm(FeedbackKind.Feature)
        rule.onNodeWithText("[Feature] ").assertIsDisplayed()
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.field.repro").fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.field.expected").fetchSemanticsNodes().isEmpty())

        // A clean form closes without asking.
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitGone("fst.settings.feedback.dialog")

        openForm(FeedbackKind.Feature)
        type("title", "[Feature] Dark mode")
        type("description", "Please add it.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.error")
        rule.onNodeWithText(FeedbackException.forStatus(503).message!!).assertIsDisplayed()
        rule.onNodeWithText("[Feature] Dark mode").assertIsDisplayed()

        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithTag("fst.settings.feedback.discard.confirm").performClick()
        waitGone("fst.settings.feedback.dialog")
    }
}
