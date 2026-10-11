package com.festivalscoretracker.android.settings

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Looper
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.ComponentDialog
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityOptionsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.feedback.FeedbackCopy
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackProblem
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowDialog
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

    private fun launch(wrap: @Composable (@Composable () -> Unit) -> Unit = { it() }) {
        val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { wrap { FestivalApp(container, debug) } }
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

        // Only the prefix: Submit stays disabled and the form says what is missing (no error banner).
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        rule.onNodeWithTag("fst.settings.feedback.validation").assertTextEquals(FeedbackProblem.MissingTitle.message)
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.error").fetchSemanticsNodes().isEmpty())

        type("title", "[Bug] Songs crash")
        rule.onNodeWithTag("fst.settings.feedback.validation").assertTextEquals(FeedbackProblem.MissingDescription.message)
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        type("description", "Opening Songs crashes.")
        waitGone("fst.settings.feedback.validation")
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsEnabled()
        assertTrue(transport.sent("/api/feedback").isEmpty())
        type("repro", "1. Open Songs")

        // Close with input asks first; Keep Editing keeps everything.
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithTag("fst.settings.feedback.discard.cancel").performClick()
        waitGone("fst.settings.feedback.discard.dialog")
        rule.onNodeWithText("[Bug] Songs crash").assertIsDisplayed()

        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        // Filed (issue #565): the form closes by itself, then the result alert shows over Settings
        // with a single Done and none of the form's Close or Submit controls.
        waitFor("fst.settings.feedback.sent")
        assertResultAlertOnly("Report Sent", "Thanks! Your report was filed as issue #42.")
        assertEquals("GET", transport.sent("/api/feedback/$jobId").first().method)
        val request = transport.sent("/api/feedback").single()
        assertEquals("POST", request.method)
        val body = java.io.ByteArrayOutputStream().also { request.body!!.writeTo(it) }.toString(Charsets.UTF_8)
        assertTrue(body.contains("[Bug] Songs crash"))
        assertTrue(body.contains("name=\"platform\"\r\n\r\nandroid"))

        rule.onNodeWithTag("fst.settings.feedback.done").performClick()
        waitGone("fst.settings.feedback.sent")
        rule.onNodeWithTag("fst.settings.list").assertIsDisplayed()
    }

    /** The result alert alone: the form (and its Close and Submit) has already closed. */
    private fun assertResultAlertOnly(title: String, message: String) {
        listOf("dialog", "close", "submit", "progress").forEach {
            assertTrue("$it still shown", rule.onAllNodesWithTag("fst.settings.feedback.$it").fetchSemanticsNodes().isEmpty())
        }
        rule.onNodeWithText(title).assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.sent.message").assertTextEquals(message)
        rule.onNodeWithTag("fst.settings.feedback.done").assertIsDisplayed().assertTextEquals("Done")
        assertEquals(1, rule.onAllNodesWithText("Done").fetchSemanticsNodes().size)
    }

    /** Back on the result alert closes it like Done; the form does not come back. */
    @Test
    fun backClosesTheResultAlert() {
        transport.on("/api/feedback", status = 202) { """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") { """{"id":"$jobId","status":"submitted","issueNumber":5,"attachments":[]}""" }
        launch()
        val before = ModalCoverage.shared.openCount.value
        openForm(FeedbackKind.Bug)
        type("title", "[Bug] Songs crash")
        type("description", "Opening Songs crashes.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.sent")
        // One modal at a time (modal-shell R7): only the alert covers the page.
        assertEquals(before + 1, ModalCoverage.shared.openCount.value)
        rule.runOnUiThread { (ShadowDialog.getLatestDialog() as ComponentDialog).onBackPressedDispatcher.onBackPressed() }
        waitGone("fst.settings.feedback.sent")
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.dialog").fetchSemanticsNodes().isEmpty())
        assertEquals(before, ModalCoverage.shared.openCount.value)
    }

    /** Issue #186: the form is its own Dialog (modal-shell R6), so it must still hold the backdrop while open. */
    @Test
    fun openFormCoversTheBackdropUntilItCloses() {
        val coverage = ModalCoverage.shared
        launch()
        val before = coverage.openCount.value
        openForm(FeedbackKind.Feature)
        assertEquals(before + 1, coverage.openCount.value)
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitGone("fst.settings.feedback.dialog")
        assertEquals(before, coverage.openCount.value)
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

    @Test
    fun sendingAndFilingShowProgressAndGuardDiscard() {
        val release = CountDownLatch(1)
        val polls = AtomicInteger()
        transport.on("/api/feedback", status = 202) { release.await(10, TimeUnit.SECONDS); """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") {
            if (polls.getAndIncrement() == 0) """{"id":"$jobId","status":"processing"}"""
            else """{"id":"$jobId","status":"submitted","issueNumber":7,"attachments":[]}"""
        }
        launch()
        openForm(FeedbackKind.Bug)
        rule.onNodeWithTag("fst.settings.feedback.dialog").assertWidthIsEqualTo(411.dp)
        type("title", "[Bug] Shop stalls")
        type("description", "The shop never loads.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()

        // Sending: progress with text, Submit and every input disabled.
        waitFor("fst.settings.feedback.progress")
        rule.onNodeWithText("Sending your report…").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        rule.onNodeWithTag("fst.settings.feedback.field.title").assertIsNotEnabled()
        rule.onNodeWithTag("fst.settings.feedback.attach").assertIsNotEnabled()

        // Close while sending asks first and says sending would stop.
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithText("Sending will stop and everything you entered will be lost.").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.discard.cancel").performClick()
        waitGone("fst.settings.feedback.discard.dialog")

        // Filing: the accepted job is polled until GitHub has the issue.
        release.countDown()
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithText("Filing your report on GitHub…").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        waitFor("fst.settings.feedback.sent")
        assertResultAlertOnly("Report Sent", "Thanks! Your report was filed as issue #7.")
        assertEquals(2, polls.get())
        rule.onNodeWithTag("fst.settings.feedback.done").performClick()
        waitGone("fst.settings.feedback.sent")
    }

    @Test
    fun discardWhileSendingClosesTheForm() {
        val release = CountDownLatch(1)
        transport.on("/api/feedback", status = 202) { release.await(10, TimeUnit.SECONDS); """{"id":"$jobId","status":"queued"}""" }
        launch()
        openForm(FeedbackKind.Feature)
        type("title", "[Feature] Themes")
        type("description", "More themes.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.progress")
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithText("Discard this request?").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.discard.confirm").performClick()
        waitGone("fst.settings.feedback.dialog")
        release.countDown()
        settle()
        assertTrue(rule.onAllNodesWithTag("fst.settings.feedback.sent").fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun unreadableStatusReportsReceived() {
        transport.on("/api/feedback", status = 202) { """{"id":"$jobId","status":"queued"}""" }
        // No status route: the read answers 404, so the accepted form is reported as received.
        launch()
        openForm(FeedbackKind.Feature)
        type("title", "[Feature] Themes")
        type("description", "More themes.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.sent")
        assertResultAlertOnly("Request Sent", "Thanks! Your request was received and will be filed on GitHub shortly.")
        rule.onNodeWithTag("fst.settings.feedback.done").performClick()
        waitGone("fst.settings.feedback.sent")
    }

    @Test
    fun failedFilingKeepsInputWithAnError() {
        transport.on("/api/feedback", status = 202) { """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") { """{"id":"$jobId","status":"failed"}""" }
        launch()
        openForm(FeedbackKind.Bug)
        type("title", "[Bug] fixture-failed")
        type("description", "Filing fails.")
        rule.onNodeWithTag("fst.settings.feedback.submit").performClick()
        waitFor("fst.settings.feedback.error")
        rule.onNodeWithText(FeedbackException.filingFailed(FeedbackKind.Bug).message!!).assertIsDisplayed()
        rule.onNodeWithText("[Bug] fixture-failed").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsEnabled()
    }

    @Test
    fun attachmentsShowTilesNoticesAndRemove() {
        Robolectric.buildContentProvider(FakeMediaProvider::class.java).create(FakeMediaProvider.AUTHORITY)
        var picks = listOf("shot.png", "clip.mp4", "notes.txt").map(FakeMediaProvider::uri)
        val registry = object : ActivityResultRegistry() {
            override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
                @Suppress("UNCHECKED_CAST")
                dispatchResult(requestCode, picks as O)
            }
        }
        val owner = object : ActivityResultRegistryOwner {
            override val activityResultRegistry: ActivityResultRegistry = registry
        }
        launch { content -> CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) { content() } }
        openForm(FeedbackKind.Feature)

        pick("fst.settings.feedback.attach.media")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.settings.feedback.attachment").fetchSemanticsNodes().size == 2 }
        rule.onNodeWithTag("fst.settings.feedback.attachments.notice").assertTextEquals("Only images and videos can be attached.")
        rule.onNodeWithContentDescription("Image, shot.png", substring = true).assertExists()
        rule.onNodeWithContentDescription("Video, clip.mp4", substring = true).assertExists()

        rule.onNodeWithContentDescription("Remove shot.png").performScrollTo().performClick()
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.settings.feedback.attachment").fetchSemanticsNodes().size == 1 }
        waitGone("fst.settings.feedback.attachments.notice")

        // Over the limit: the extra picks are skipped with a notice and Attach turns off at four.
        picks = listOf("a.png", "b.png", "c.png", "d.png").map(FakeMediaProvider::uri)
        pick("fst.settings.feedback.attach.files")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.settings.feedback.attachment").fetchSemanticsNodes().size == 4 }
        rule.onNodeWithTag("fst.settings.feedback.attachments.notice").assertTextEquals("You can attach up to 4 files.")
        rule.onNodeWithTag("fst.settings.feedback.attach").assertIsNotEnabled()

        // Attachments alone make the form dirty: Close asks first.
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.discard.dialog")
        rule.onNodeWithText("Your text and attachments will be lost.").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.discard.confirm").performClick()
        waitGone("fst.settings.feedback.dialog")
    }

    private fun pick(item: String) {
        rule.onNodeWithTag("fst.settings.feedback.attach").performScrollTo().performClick()
        waitFor(item)
        rule.onNodeWithTag(item).performClick()
        settle()
    }
}

/** Serves fake picked media: the type follows the file extension, nothing can be opened. */
class FakeMediaProvider : ContentProvider() {
    override fun onCreate() = true

    override fun getType(uri: Uri): String = when (uri.lastPathSegment?.substringAfterLast('.')) {
        "png" -> "image/png"
        "mp4" -> "video/mp4"
        else -> "text/plain"
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor =
        MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).apply { addRow(arrayOf<Any>(uri.lastPathSegment!!, 2_048L)) }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    companion object {
        const val AUTHORITY = "com.festivalscoretracker.android.test.media"

        fun uri(name: String): Uri = Uri.parse("content://$AUTHORITY/$name")
    }
}
