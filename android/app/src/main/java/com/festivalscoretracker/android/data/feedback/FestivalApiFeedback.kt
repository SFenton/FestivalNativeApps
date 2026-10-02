package com.festivalscoretracker.android.data.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackReceipt
import com.festivalscoretracker.android.core.feedback.FeedbackSubmission
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.data.FestivalApi
import java.io.IOException
import java.io.InputStream
import kotlinx.serialization.Serializable

// region Feedback submission

/**
 * `POST /api/feedback` (issue #78): the app's only write. User-initiated from the
 * Settings feedback form; never automated against production
 * (`.agents/platforms/service-safety.md`). Wire contract:
 * `.agents/controls/feedback-form/spec.md`.
 */
@Serializable
private data class FeedbackReceiptBody(val issueNumber: Int? = null, val issueUrl: String? = null)

/**
 * An attachment whose source could not be opened or read mid-upload.
 *
 * @property name Display name.
 */
class UnreadableAttachmentException(val name: String, cause: Throwable? = null) : IOException(name, cause)

/**
 * Submit a feedback form with its media.
 *
 * @param submission Validated form contents.
 * @param openAttachment Opens a fresh stream for an attachment (called once in preflight and once per write).
 * @return Receipt (issue number/URL when the service reports them).
 * @throws FeedbackException with readable text for every failure.
 */
suspend fun FestivalApi.submitFeedback(
    submission: FeedbackSubmission,
    openAttachment: (FeedbackAttachment) -> InputStream,
): FeedbackReceipt {
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
    if (response.status !in 200..299) throw FeedbackException.forStatus(response.status)
    val body = runCatching { FestivalApi.JSON.decodeFromString(FeedbackReceiptBody.serializer(), response.body.decodeToString()) }
        .getOrNull()
    return FeedbackReceipt(body?.issueNumber?.takeIf { it > 0 }, FeedbackReceipt.safeUrl(body?.issueUrl))
}

// endregion
