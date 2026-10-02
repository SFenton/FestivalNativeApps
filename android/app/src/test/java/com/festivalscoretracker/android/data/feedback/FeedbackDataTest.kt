package com.festivalscoretracker.android.data.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackDraft
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackReceipt
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpBody
import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.FakeTransport
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FeedbackDataTest {
    private val png = byteArrayOf(1, 2, 3, 4)

    private fun bytesOf(body: HttpBody): ByteArray = ByteArrayOutputStream().also(body::writeTo).toByteArray()

    private fun submission(attachments: List<FeedbackAttachment> = emptyList()) =
        FeedbackDraft(FeedbackKind.Bug, "[Bug] Crash", "It crashes", "Tap", "No crash", attachments).submission("android", "1.0", "Android 15")

    private suspend fun expectFailure(block: suspend () -> Unit): FeedbackException {
        try {
            block()
        } catch (error: FeedbackException) {
            return error
        }
        fail("expected FeedbackException")
        throw AssertionError()
    }

    // region Multipart

    @Test
    fun multipartEncodesFieldsAndFilesExactly() {
        val body = MultipartFormBody(
            listOf("kind" to "bug", "title" to "[Bug] Ünïcode"),
            listOf(MultipartFormBody.FilePart("media", "shot.png", "image/png", png.size.toLong()) { ByteArrayInputStream(png) }),
            boundary = "B",
        )
        val expected = "--B\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nbug\r\n" +
            "--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n[Bug] Ünïcode\r\n" +
            "--B\r\nContent-Disposition: form-data; name=\"media\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\n"
        val written = bytesOf(body)
        val prefix = expected.toByteArray()
        assertEquals(expected, String(written.copyOfRange(0, prefix.size)))
        assertTrue(written.copyOfRange(prefix.size, prefix.size + 4).contentEquals(png))
        assertEquals("\r\n--B--\r\n", String(written.copyOfRange(prefix.size + 4, written.size)))
        assertEquals(written.size.toLong(), body.contentLength)
        assertEquals("multipart/form-data; boundary=B", body.contentType)
        // Writable twice (transport retries reopen the stream).
        assertTrue(bytesOf(body).contentEquals(written))
    }

    @Test
    fun multipartUnknownLengthAndChangedSource() {
        val unknown = MultipartFormBody(emptyList(), listOf(MultipartFormBody.FilePart("media", "a", "image/png", null) { ByteArrayInputStream(png) }))
        assertEquals(-1L, unknown.contentLength)
        assertTrue(unknown.boundary.startsWith("fst-"))
        val changed = MultipartFormBody(emptyList(), listOf(MultipartFormBody.FilePart("media", "a", "image/png", 10) { ByteArrayInputStream(png) }))
        assertThrows(IOException::class.java) { bytesOf(changed) }
    }

    @Test
    fun filenamesAndTypesAreHeaderSafe() {
        assertEquals("evil.png", MultipartFormBody.sanitizeFilename("../../dir\\evil.png"))
        assertEquals("ab.png", MultipartFormBody.sanitizeFilename("a\"\r\nb.png"))
        assertEquals("attachment", MultipartFormBody.sanitizeFilename("  "))
        assertEquals(120, MultipartFormBody.sanitizeFilename("x".repeat(300)).length)
        val body = MultipartFormBody(emptyList(), listOf(MultipartFormBody.FilePart("media", "a.png", "image/png\r\nX: y", 0) { ByteArrayInputStream(ByteArray(0)) }), "B")
        assertTrue(String(bytesOf(body)).contains("Content-Type: image/pngX:y\r\n"))
    }

    // endregion

    // region Gate

    private val anyBody = object : HttpBody {
        override val contentType = "multipart/form-data; boundary=x"
        override val contentLength = 0L
        override fun writeTo(sink: OutputStream) = Unit
    }

    @Test
    fun gateAllowsOnlyTheFeedbackPost() {
        RequestGate.validateFeedback(RequestGate.makeFeedbackRequest("https://x.test/api/feedback", anyBody))
        val rejected = listOf(
            RequestGate.makeFeedbackRequest("https://x.test/api/feedback?x=1", anyBody),
            RequestGate.makeFeedbackRequest("https://x.test/api/feedback/extra", anyBody),
            RequestGate.makeFeedbackRequest("https://x.test/api/songs", anyBody),
            HttpRequest("https://x.test/api/feedback", "POST"),
            HttpRequest("https://x.test/api/feedback", "PUT", body = anyBody),
            HttpRequest("https://x.test/api/feedback", "POST", mapOf("X-API-Key" to "k"), anyBody),
            HttpRequest("https://x.test/api/feedback", "POST", mapOf("x-fst-selected-profile" to "p"), anyBody),
            HttpRequest("not a url", "POST", body = anyBody),
        )
        rejected.forEach { request -> assertThrows(FestivalApiException.ForbiddenRequest::class.java) { RequestGate.validateFeedback(request) } }
        // Reads stay GET-only and body-less; the feedback POST cannot go through the read path.
        assertThrows(FestivalApiException.ForbiddenRequest::class.java) { RequestGate.validateKeyless(HttpRequest("https://x.test/api/songs", body = anyBody)) }
        assertThrows(FestivalApiException.ForbiddenRequest::class.java) {
            RequestGate.validateKeyless(RequestGate.makeFeedbackRequest("https://x.test/api/feedback", anyBody))
        }
        val request = RequestGate.makeFeedbackRequest("https://x.test/api/feedback", anyBody)
        assertEquals(RequestGate.FEEDBACK_READ_TIMEOUT_SECONDS, request.readTimeoutSeconds)
        assertEquals("application/json", request.headers["Accept"])
    }

    // endregion

    // region Submit

    @Test
    fun submitPostsMultipartAndDecodesReceipt() = runTest {
        val transport = FakeTransport().apply {
            on("/api/feedback", status = 201) { """{"issueNumber":42,"issueUrl":"https://github.com/o/r/issues/42","extra":1}""" }
        }
        val api = FestivalApi("https://fixture.test", transport)
        val attachment = FeedbackAttachment("content://a", "shot.png", "image/png", png.size.toLong())
        var opens = 0
        val receipt = api.submitFeedback(submission(listOf(attachment))) {
            opens++
            ByteArrayInputStream(png)
        }
        assertEquals(FeedbackReceipt(42, "https://github.com/o/r/issues/42"), receipt)
        val request = transport.requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://fixture.test/api/feedback", request.url)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected-") })
        val text = String(bytesOf(request.body!!))
        listOf(
            "name=\"kind\"\r\n\r\nbug\r\n", "name=\"platform\"\r\n\r\nandroid\r\n", "name=\"title\"\r\n\r\n[Bug] Crash\r\n",
            "name=\"reproSteps\"\r\n\r\nTap\r\n", "name=\"expectedBehavior\"\r\n\r\nNo crash\r\n",
            "name=\"media\"; filename=\"shot.png\"\r\nContent-Type: image/png",
        ).forEach { assertTrue(it, text.contains(it)) }
        assertEquals(2, opens) // preflight + the write above
    }

    @Test
    fun submitAcceptsBareOrUnsafeReceipts() = runTest {
        val transport = FakeTransport().apply { on("/api/feedback", status = 202) { "" } }
        val api = FestivalApi("https://fixture.test", transport)
        assertEquals(FeedbackReceipt(null, null), api.submitFeedback(submission()) { fail(); ByteArrayInputStream(png) })
        transport.on("/api/feedback", status = 200) { """{"issueNumber":0,"issueUrl":"javascript:alert(1)"}""" }
        assertEquals(FeedbackReceipt(null, null), api.submitFeedback(submission()) { ByteArrayInputStream(png) })
    }

    @Test
    fun submitMapsStatusesAndFailures() = runTest {
        val transport = FakeTransport()
        val api = FestivalApi("https://fixture.test", transport)
        // No route: 404 means the endpoint is not live yet.
        assertEquals(FeedbackException.forStatus(404).message, expectFailure { api.submitFeedback(submission()) { ByteArrayInputStream(png) } }.message)
        transport.on("/api/feedback", status = 413) { "{}" }
        assertEquals(413, expectFailure { api.submitFeedback(submission()) { ByteArrayInputStream(png) } }.status)

        val offline = FestivalApi("https://fixture.test", HttpTransport { throw IOException("down") })
        assertEquals(FeedbackException.offline().message, expectFailure { offline.submitFeedback(submission()) { ByteArrayInputStream(png) } }.message)

        val attachment = FeedbackAttachment("content://gone", "gone.png", "image/png", null)
        val unreadable = expectFailure { api.submitFeedback(submission(listOf(attachment))) { throw SecurityException("revoked") } }
        assertEquals(FeedbackException.unreadable("gone.png").message, unreadable.message)

        // A source that fails mid-upload (after preflight) still names the attachment.
        var calls = 0
        val writing = FestivalApi("https://fixture.test", HttpTransport { request ->
            request.body!!.writeTo(ByteArrayOutputStream())
            HttpResult(200, ByteArray(0))
        })
        val midway = expectFailure {
            writing.submitFeedback(submission(listOf(attachment))) {
                if (calls++ == 0) ByteArrayInputStream(png) else throw IOException("gone")
            }
        }
        assertEquals(FeedbackException.unreadable("gone.png").message, midway.message)
    }

    // endregion
}
