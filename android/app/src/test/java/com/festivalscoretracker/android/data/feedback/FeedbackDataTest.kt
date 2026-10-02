package com.festivalscoretracker.android.data.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackDraft
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackJob
import com.festivalscoretracker.android.core.feedback.FeedbackJobState
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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FeedbackDataTest {
    private val png = byteArrayOf(1, 2, 3, 4)
    private val jobId = "0123456789abcdef0123456789abcdef"

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
    fun submitPostsMultipartAndDecodesTheAcceptedJob() = runTest {
        val transport = FakeTransport().apply {
            on("/api/feedback", status = 202) { """{"id":"$jobId","status":"queued","extra":1}""" }
        }
        val api = FestivalApi("https://fixture.test", transport)
        val attachment = FeedbackAttachment("content://a", "shot.png", "image/png", png.size.toLong())
        var opens = 0
        val job = api.submitFeedback(submission(listOf(attachment))) {
            opens++
            ByteArrayInputStream(png)
        }
        assertEquals(FeedbackJob(jobId, FeedbackJobState.Queued), job)
        val request = transport.requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://fixture.test/api/feedback", request.url)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected-") })
        val text = String(bytesOf(request.body!!))
        listOf(
            "name=\"kind\"\r\n\r\nbug\r\n", "name=\"platform\"\r\n\r\nandroid\r\n", "name=\"title\"\r\n\r\n[Bug] Crash\r\n",
            "name=\"repro\"\r\n\r\nTap\r\n", "name=\"expected\"\r\n\r\nNo crash\r\n", "name=\"clientInfo\"\r\n\r\nAndroid 15\r\n",
            "name=\"media\"; filename=\"shot.png\"\r\nContent-Type: image/png",
        ).forEach { assertTrue(it, text.contains(it)) }
        assertEquals(2, opens) // preflight + the write above
    }

    @Test
    fun submitAcceptsBareOrOddBodies() = runTest {
        val transport = FakeTransport().apply { on("/api/feedback", status = 202) { "" } }
        val api = FestivalApi("https://fixture.test", transport)
        assertEquals(FeedbackJob(null, FeedbackJobState.Queued), api.submitFeedback(submission()) { fail(); ByteArrayInputStream(png) })
        transport.on("/api/feedback", status = 200) { """{"id":"BAD","status":"submitted","issueNumber":9}""" }
        assertEquals(FeedbackJob(null, FeedbackJobState.Submitted, 9), api.submitFeedback(submission()) { ByteArrayInputStream(png) })
        transport.on("/api/feedback", status = 202) { "[1]" }
        assertEquals(FeedbackJob(null, FeedbackJobState.Queued), api.submitFeedback(submission()) { ByteArrayInputStream(png) })
    }

    @Test
    fun submitMapsServiceCodesAndRetryAfter() = runTest {
        val transport = FakeTransport()
        val api = FestivalApi("https://fixture.test", transport)
        transport.on("/api/feedback", status = 400) { """{"error":"server words","code":"too_many_attachments"}""" }
        val coded = expectFailure { api.submitFeedback(submission()) { ByteArrayInputStream(png) } }
        assertEquals("Attach up to 4 files.", coded.message)
        assertEquals(400, coded.status)
        transport.on("/api/feedback", status = 429, headers = mapOf("retry-after" to "120")) { """{"error":"slow down"}""" }
        assertEquals(
            "Too many submissions from this network. Try again in 2 minutes.",
            expectFailure { api.submitFeedback(submission()) { ByteArrayInputStream(png) } }.message,
        )
        transport.on("/api/feedback", status = 429, headers = mapOf("Retry-After" to "Wed, 21 Oct 2015 07:28:00 GMT")) { "x" }
        assertEquals(
            FeedbackException.forStatus(429).message,
            expectFailure { api.submitFeedback(submission()) { ByteArrayInputStream(png) } }.message,
        )
    }

    @Test
    fun statusReadsTheJobAndRejectsBadIds() = runTest {
        val transport = FakeTransport().apply {
            on("/api/feedback/$jobId") {
                """{"id":"$jobId","status":"submitted","issueNumber":42,"attachments":[
                    {"name":"a.png","kind":"image","outcome":"attached"},{"name":"b.mp4","kind":"video","outcome":"SKIPPED"},
                    {"name":"c","outcome":7},"junk"]}"""
            }
        }
        val api = FestivalApi("https://fixture.test", transport)
        assertEquals(FeedbackJob(jobId, FeedbackJobState.Submitted, 42, 1), api.feedbackStatus(jobId))
        val request = transport.requests.single()
        assertEquals("GET", request.method)
        assertNull(request.body)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-") })

        assertThrows(IllegalArgumentException::class.java) { kotlinx.coroutines.runBlocking { api.feedbackStatus("../songs") } }
        assertEquals(1, transport.requests.size)

        // Unknown status keeps polling; a missing body is unreadable; an expired job is a 404.
        transport.on("/api/feedback/$jobId") { """{"status":"later","issueNumber":"7"}""" }
        assertEquals(FeedbackJob(jobId, FeedbackJobState.Processing), api.feedbackStatus(jobId))
        transport.on("/api/feedback/$jobId") { "" }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { kotlinx.coroutines.runBlocking { api.feedbackStatus(jobId) } }
        transport.on("/api/feedback/$jobId", status = 404) { """{"code":"not_found"}""" }
        assertThrows(FestivalApiException::class.java) { kotlinx.coroutines.runBlocking { api.feedbackStatus(jobId) } }
    }

    @Test
    fun featuresFlagIsOnOnlyForJsonTrue() = runTest {
        val transport = FakeTransport()
        val api = FestivalApi("https://fixture.test", transport)
        mapOf(
            """{"appManual":false,"feedback":true}""" to true,
            """{"appManual":false}""" to false,
            """{"feedback":"true"}""" to false,
            """{"feedback":1}""" to false,
            """{"feedback":false}""" to false,
            "[true]" to false,
            "not json" to false,
        ).forEach { (body, expected) ->
            transport.on("/api/features") { body }
            assertEquals(body, expected, api.feedbackEnabled())
        }
        assertTrue(transport.requests.all { it.method == "GET" && it.url == "https://fixture.test/api/features" })
        transport.on("/api/features", status = 500) { "{}" }
        assertThrows(FestivalApiException::class.java) { kotlinx.coroutines.runBlocking { api.feedbackEnabled() } }
        assertFalse(FeedbackWire.enabled(ByteArray(0)))
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
