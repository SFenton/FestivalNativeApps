package com.festivalscoretracker.android.journeys

import android.content.ContentValues
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.annotation.RequiresApi
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
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
import androidx.core.app.ActivityOptionsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import com.festivalscoretracker.android.core.feedback.FeedbackCopy
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import java.io.OutputStream
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

    private fun openForm(
        kind: String,
        fontScale: (() -> Float)? = null,
        wrap: @Composable (@Composable () -> Unit) -> Unit = { it() },
    ) {
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport, fontScale = fontScale, wrap = wrap)
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

    /** The busy view (issue #634) reads header, spinner, title, sentence; none of the hidden fields. */
    private fun assertBusyOrder(order: List<String>) {
        val header = order.indexOfFirst { it.contains("Report an Issue") }
        val spinner = order.indexOfFirst { it.contains("Sending your issue") }
        val title = order.indexOfFirst { it.contains("Filing Issue") }
        val sentence = order.indexOfFirst { it.contains("Please wait while we upload it.") }
        assertTrue("reading order $order", header >= 0 && spinner > header && title > spinner && sentence > title)
        assertTrue("reading order $order", order.none { it.contains("[Bug]") || it.contains("Opening Songs crashes.") || it.contains("Attach") })
    }

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
        // Issue #634: the fields fade out to a centred busy view. No media, so it reads as filing:
        // one named spinner, then the title (a heading), then the sentence; the fields are gone.
        waitForText("Filing Issue")
        val sending = orderWith("feedback-sending", "Filing Issue")
        assertBusyOrder(sending)
        h.assertAccessible()
        h.tap("fst.settings.feedback.close")
        h.waitForTag("fst.settings.feedback.discard.dialog")
        val discard = orderWith("feedback-discard", "Sending will stop")
        assertTrue("reading order $discard", discard.any { it.contains("Sending will stop") })
        h.tap("fst.settings.feedback.discard.cancel")
        h.waitGone("fst.settings.feedback.discard.dialog")

        release.countDown()
        rule.waitUntil(15_000) { polls.get() > 0 }
        assertBusyOrder(orderWith("feedback-filing", "Filing Issue"))
        h.waitForTag("fst.settings.feedback.sent")
        // Issue #565: the form has closed by itself; the result alert alone reads title, message, Done.
        h.waitGone("fst.settings.feedback.dialog")
        val sent = orderWith("feedback-sent", "filed as issue #42")
        val sentTitle = sent.indexOfFirst { it.contains("Report Sent") }
        val sentMessage = sent.indexOfFirst { it.contains("filed as issue #42") }
        val done = sent.indexOfFirst { it.contains("Done") }
        assertTrue("reading order $sent", sentTitle >= 0 && sentMessage > sentTitle && done > sentMessage)
        assertTrue("reading order $sent", sent.none { it.contains("Close") || it.contains("Submit") || it.contains("Cancel") })
        h.assertFullTouchTarget("fst.settings.feedback.done")
        h.assertNothingStraddles("fst.settings.feedback.sent", "fst.settings.feedback.done")
        h.tap("fst.settings.feedback.done")
        h.waitGone("fst.settings.feedback.sent")
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
     * Issue #634 with media: Attach Media (a fixture registry stands in for the system photo
     * picker) adds an image this test put in MediaStore, and the fixture `POST /api/feedback`
     * writes the real multipart body into a sink that holds halfway. TalkBack then reads the
     * named spinner, the "Uploading Media" heading and "Upload progress" with a determinate
     * value, and none of the hidden fields; releasing the upload hands off to "Filing Issue"
     * with the same spinner on screen, and the form closes before Report Sent (#565).
     */
    @DeviceCi
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    @Test
    fun mediaUploadReadsUploadingThenFilingAndPassesChecks() {
        val image = insertFixtureImage()
        val halfway = CountDownLatch(1)
        val upload = CountDownLatch(1)
        val filing = CountDownLatch(1)
        val polls = AtomicInteger()
        transport.on("/api/feedback", status = 202) { request ->
            val body = checkNotNull(request.body) { "feedback POST without a body" }
            body.writeTo(HoldingSink(body.contentLength / 2, halfway, upload))
            """{"id":"$jobId","status":"queued"}"""
        }
        transport.on("/api/feedback/$jobId") {
            if (polls.getAndIncrement() > 0) filing.await(15, TimeUnit.SECONDS)
            if (filing.count > 0) """{"id":"$jobId","status":"processing"}"""
            else """{"id":"$jobId","status":"submitted","issueNumber":44,"attachments":[{"outcome":"uploaded"}]}"""
        }
        try {
            h.enableAccessibilityChecks()
            openForm("bug", wrap = { content ->
                CompositionLocalProvider(LocalActivityResultRegistryOwner provides PickerResult(listOf(image))) { content() }
            })
            type("title", "[Bug] Songs crash")
            type("description", "Opening Songs crashes.")
            rule.onNodeWithTag("fst.settings.feedback.attach").performScrollTo()
            h.tap("fst.settings.feedback.attach")
            h.waitForTag("fst.settings.feedback.attach.media")
            h.tap("fst.settings.feedback.attach.media")
            h.waitForTag("fst.settings.feedback.attachment")

            h.tap("fst.settings.feedback.submit")
            assertTrue("upload never reached halfway", halfway.await(15, TimeUnit.SECONDS))
            h.waitForTag("fst.settings.feedback.progress.bar")
            waitForText(FeedbackCopy.UPLOADING_TITLE)
            val spinner = rule.onNodeWithTag("fst.settings.feedback.progress.spinner").fetchSemanticsNode().id

            // The bar is determinate: a range TalkBack reads, held mid-upload.
            rule.waitUntil(15_000) {
                val range = rule.onNodeWithTag("fst.settings.feedback.progress.bar").fetchSemanticsNode()
                    .config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)
                range != null && range.current > 0f && range.current < 1f
            }
            val platformBar = checkNotNull(h.accessibilityNode("fst.settings.feedback.progress.bar")) { "bar not published to TalkBack" }
            val published = checkNotNull(platformBar.rangeInfo) { "bar publishes no range" }
            assertTrue("published range $published", published.current > published.min && published.current < published.max)

            val uploading = orderWith("feedback-uploading", FeedbackCopy.UPLOAD_PROGRESS_LABEL)
            val header = uploading.indexOfFirst { it.contains("Report an Issue") }
            val named = uploading.indexOfFirst { it.contains(FeedbackCopy.busyLabel(FeedbackKind.Bug)) }
            val title = uploading.indexOfFirst { it.contains(FeedbackCopy.UPLOADING_TITLE) }
            val bar = uploading.indexOfFirst { it.contains(FeedbackCopy.UPLOAD_PROGRESS_LABEL) }
            assertTrue("reading order $uploading", header >= 0 && named > header && title > named && bar > title)
            // Compose speaks the range as its state (API 30+): "Upload progress, 46 percent."
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                assertTrue("bar reads no value: ${uploading[bar]}", Regex("""\d+ percent""").containsMatchIn(uploading[bar]))
            }
            assertTrue("reading order $uploading", uploading.count { it.contains(FeedbackCopy.busyLabel(FeedbackKind.Bug)) } == 1)
            assertTrue("reading order $uploading", uploading.none { it.contains("Filing Issue") || it.contains("Please wait while we upload it.") })
            assertTrue("reading order $uploading", uploading.none { it.contains("[Bug]") || it.contains("Opening Songs crashes.") || it.contains("Attach") })
            val titleNode = checkNotNull(h.accessibilityNode("fst.settings.feedback.progress.title")) { "title not published" }
            assertTrue("busy title is a heading", titleNode.isHeading)
            h.assertAccessible()

            // Hand-off: the text and bar swap to the filing step; the spinner node stays.
            upload.countDown()
            h.waitGone("fst.settings.feedback.progress.bar")
            waitForText("Filing Issue")
            assertBusyOrder(orderWith("feedback-media-filing", "Filing Issue"))
            assertTrue(
                "spinner was replaced",
                rule.onNodeWithTag("fst.settings.feedback.progress.spinner").fetchSemanticsNode().id == spinner,
            )
            h.assertAccessible()

            filing.countDown()
            h.waitForTag("fst.settings.feedback.sent")
            h.waitGone("fst.settings.feedback.dialog")
            h.tap("fst.settings.feedback.done")
            h.waitGone("fst.settings.feedback.sent")
        } finally {
            upload.countDown()
            filing.countDown()
            rule.activity.contentResolver.delete(image, null, null)
        }
    }

    /**
     * A PNG this app owns in MediaStore (no permission needed on API 29+), large enough that
     * the multipart body is mostly media. Deleted by the test that made it.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insertFixtureImage(): Uri {
        val resolver = rule.activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "fst-634-journey-${System.nanoTime()}.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = checkNotNull(resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values))
        val random = java.util.Random(634)
        val bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888).apply {
            setPixels(IntArray(256 * 256) { random.nextInt() or 0xFF000000.toInt() }, 0, 256, 0, 0, 256, 256)
        }
        checkNotNull(resolver.openOutputStream(uri)).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
        return uri
    }

    /** Answers every picker launch with [uris] at once, in place of the system photo picker. */
    private class PickerResult(private val uris: List<Uri>) : ActivityResultRegistryOwner {
        override val activityResultRegistry = object : ActivityResultRegistry() {
            override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
                @Suppress("UNCHECKED_CAST")
                dispatchResult(requestCode, uris as O)
            }
        }
    }

    /** Discards bytes, holding the writer once [threshold] bytes are in until [release] opens. */
    private class HoldingSink(private val threshold: Long, private val reached: CountDownLatch, private val release: CountDownLatch) : OutputStream() {
        private var written = 0L

        override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)

        override fun write(b: ByteArray, off: Int, len: Int) {
            written += len
            if (written >= threshold && release.count > 0) {
                reached.countDown()
                release.await(15, TimeUnit.SECONDS)
            }
        }
    }

    /**
     * Issue #634 at 200% text: the busy view's title and sentence wrap inside the form, stay
     * centred under the header and keep Close reachable; ATF checks the busy state.
     */
    @Test
    fun busyViewWrapsCentredAtLargeText() {
        val release = CountDownLatch(1)
        transport.on("/api/feedback", status = 202) { release.await(15, TimeUnit.SECONDS); """{"id":"$jobId","status":"queued"}""" }
        transport.on("/api/feedback/$jobId") { """{"id":"$jobId","status":"submitted","issueNumber":43,"attachments":[]}""" }
        h.enableAccessibilityChecks()
        openForm("bug", fontScale = { 2f })
        type("title", "[Bug] Songs crash")
        type("description", "Opening Songs crashes.")
        h.tap("fst.settings.feedback.submit")
        h.waitForTag("fst.settings.feedback.progress.subtitle")
        rule.waitForIdle()
        val region = rule.onNodeWithTag("fst.settings.feedback.progress").fetchSemanticsNode().boundsInRoot
        val spinner = rule.onNodeWithTag("fst.settings.feedback.progress.spinner").fetchSemanticsNode().boundsInRoot
        val sentence = rule.onNodeWithTag("fst.settings.feedback.progress.subtitle").fetchSemanticsNode().boundsInRoot
        val header = rule.onNodeWithTag("fst.settings.feedback.close").fetchSemanticsNode().boundsInRoot
        assertTrue("spinner $spinner centred in $region", kotlin.math.abs(spinner.center.x - region.center.x) <= 2f)
        assertTrue("sentence $sentence wraps inside $region", sentence.left >= region.left && sentence.right <= region.right)
        assertTrue("busy region $region under the header $header", region.top >= header.bottom - 1f)
        assertBusyOrder(orderWith("feedback-sending-large-text", "Filing Issue"))
        h.assertFullTouchTarget("fst.settings.feedback.close")
        h.assertAccessible()
        release.countDown()
        h.waitForTag("fst.settings.feedback.sent")
        h.tap("fst.settings.feedback.done")
        h.waitGone("fst.settings.feedback.sent")
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
