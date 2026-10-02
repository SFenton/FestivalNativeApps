package com.festivalscoretracker.android.data.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackJob
import com.festivalscoretracker.android.core.feedback.FeedbackJobState
import com.festivalscoretracker.android.core.feedback.FeedbackSubmission
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.ServiceEndpoint
import java.io.IOException
import java.io.InputStream
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

// region Feedback

/*
 * In-app feedback (issue #78). `GET /api/features` decides whether Settings shows the two rows;
 * one user-initiated multipart `POST /api/feedback` per Submit answers 202 `{id, status}`; then
 * `GET /api/feedback/{id}` reports filing progress from service memory. None carries a key,
 * profile or publication header, and automation never POSTs to production
 * (`.agents/platforms/service-safety.md`, `.agents/controls/feedback-form/spec.md`).
 */

/**
 * An attachment whose source could not be opened or read mid-upload.
 *
 * @property name Display name.
 */
class UnreadableAttachmentException(val name: String, cause: Throwable? = null) : IOException(name, cause)

/**
 * Read whether the service accepts feedback; a pure, unpinned read.
 *
 * @return True only when the body's `feedback` is JSON `true` (missing on older services).
 * @throws FestivalApiException for transport or status failures (callers keep the rows hidden).
 */
suspend fun FestivalApi.feedbackEnabled(): Boolean =
    FeedbackWire.enabled(readUnpinned(ServiceEndpoint.Feature(listOf("features"), pinned = false)))

/**
 * Submit a feedback form with its media.
 *
 * @param submission Validated form contents.
 * @param openAttachment Opens a fresh stream for an attachment (called once in preflight and once per write).
 * @return The accepted job (normally [FeedbackJobState.Queued] with an ID to poll).
 * @throws FeedbackException with readable text for every failure.
 */
suspend fun FestivalApi.submitFeedback(
    submission: FeedbackSubmission,
    openAttachment: (FeedbackAttachment) -> InputStream,
): FeedbackJob {
    val parts = submission.attachments.map { attachment ->
        MultipartFormBody.FilePart(
            name = FeedbackSubmission.MEDIA_PART,
            filename = attachment.name,
            contentType = attachment.mimeType,
            length = attachment.sizeBytes,
        ) {
            try {
                openAttachment(attachment)
            } catch (error: Exception) {
                throw UnreadableAttachmentException(attachment.name, error)
            }
        }
    }
    parts.forEach { part -> runCatching { part.open().close() }.onFailure { throw FeedbackException.unreadable(part.filename) } }
    val response = try {
        postFeedback(MultipartFormBody(submission.formFields, parts))
    } catch (error: FestivalApiException) {
        throw FeedbackException(error.message ?: "The app blocked an unsafe request.")
    } catch (error: IOException) {
        val unreadable = generateSequence<Throwable>(error) { it.cause }.filterIsInstance<UnreadableAttachmentException>().firstOrNull()
        throw if (unreadable != null) FeedbackException.unreadable(unreadable.name) else FeedbackException.offline()
    }
    if (response.status !in 200..299) {
        throw FeedbackException.forStatus(response.status, FeedbackWire.errorCode(response.body), FeedbackWire.retryAfterSeconds(response))
    }
    return FeedbackWire.job(response.body, null) ?: FeedbackJob(null, FeedbackJobState.Queued)
}

/**
 * Read an accepted job's progress (in-memory on the service; lost after 60 minutes or a restart).
 *
 * @param id Job ID from [submitFeedback].
 * @return Latest state.
 * @throws IllegalArgumentException when the ID is not 32 lowercase hex characters.
 * @throws FestivalApiException for transport, status (404 = unknown or expired) or an unreadable body.
 */
suspend fun FestivalApi.feedbackStatus(id: String): FeedbackJob {
    require(FeedbackJob.isValidId(id)) { "Not a feedback job ID." }
    val body = readUnpinned(ServiceEndpoint.Feature(listOf("feedback", id), pinned = false))
    return FeedbackWire.job(body, id) ?: throw FestivalApiException.InvalidResponse()
}

/** Tolerant parsers for the feedback wire bodies (unknown fields ignored, nothing throws). */
internal object FeedbackWire {
    private fun objectOf(body: ByteArray): JsonObject? = try {
        if (body.isEmpty()) null else FestivalApi.JSON.parseToJsonElement(body.decodeToString()) as? JsonObject
    } catch (error: SerializationException) {
        null
    } catch (error: IllegalArgumentException) {
        null
    }

    private fun JsonElement?.string(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

    /**
     * Read the `feedback` flag; anything but JSON `true` is off.
     *
     * @param body `/api/features` bytes.
     * @return Whether the rows show.
     */
    fun enabled(body: ByteArray): Boolean =
        (objectOf(body)?.get("feedback") as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull == true

    /**
     * Read a job body (`{id, status, issueNumber?, attachments[{outcome}]}`). A malformed ID falls back to
     * [knownId]; an unknown status reads as [FeedbackJobState.Processing] so polling continues.
     *
     * @param body Response bytes.
     * @param knownId ID already held (status reads), or null (the 202 answer).
     * @return Job, or null when the body is not a JSON object.
     */
    fun job(body: ByteArray, knownId: String?): FeedbackJob? {
        val root = objectOf(body) ?: return null
        val wireId = root["id"].string()
        val id = if (FeedbackJob.isValidId(wireId)) wireId else knownId
        val state = FeedbackJob.parseState(root["status"].string()) ?: FeedbackJobState.Processing
        val number = (root["issueNumber"] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull?.takeIf { it > 0 }
        val skipped = (root["attachments"] as? JsonArray)?.count { item ->
            (item as? JsonObject)?.get("outcome").string()?.equals("skipped", ignoreCase = true) == true
        } ?: 0
        return FeedbackJob(id, state, number, skipped)
    }

    /**
     * Read the `code` of an `{error, code}` body.
     *
     * @param body Response bytes.
     * @return Code, or null.
     */
    fun errorCode(body: ByteArray): String? = objectOf(body)?.get("code").string()

    /**
     * Parse a delta-seconds `Retry-After`.
     *
     * @param response Response.
     * @return Positive seconds, or null.
     */
    fun retryAfterSeconds(response: HttpResult): Int? =
        response.header("Retry-After")?.trim()?.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.toIntOrNull()?.takeIf { it > 0 }
}

// endregion
