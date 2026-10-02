package com.festivalscoretracker.android.core.feedback

import java.util.Locale

// region Kind

/**
 * The two in-app feedback forms (Settings → App Settings, issue #78).
 *
 * @property wire `kind` form field sent to `POST /api/feedback`.
 * @property titlePrefix Text the title starts with (and is restored to on submit).
 * @property formTitle Modal title and Settings row label.
 * @property rowDescription Settings row supporting text.
 * @property noun Lower-case noun used in prompts ("report", "request").
 */
enum class FeedbackKind(
    val wire: String,
    val titlePrefix: String,
    val formTitle: String,
    val rowDescription: String,
    val noun: String,
) {
    /** Report an Issue: title, description, steps to reproduce, expected behavior. */
    Bug("bug", "[Bug] ", "Report an Issue", "Tell us about something that isn't working right.", "report"),

    /** Request a Feature: title and description. */
    Feature("feature", "[Feature] ", "Request a Feature", "Suggest something new for Festival Score Tracker.", "request"),
    ;

    /** Whether the form shows the Steps to Reproduce and Expected Behavior boxes. */
    val hasBugFields: Boolean get() = this == Bug
}

// endregion

// region Limits and copy

/**
 * Client-side bounds matching the service (`docs/components/in-app-feedback.md` on the service repo).
 * The service fits each accepted file under GitHub's limits itself; these only stop uploads it would reject.
 */
object FeedbackLimits {
    /** Most attachments one submission carries (service `MaxAttachments`). */
    const val MAX_ATTACHMENTS = 4

    /** Largest whole request the service accepts (90 MiB; larger answers 413 `payload_too_large`). */
    const val MAX_REQUEST_BYTES = 94_371_840L

    /** Combined attachment budget: the request cap less 512 KiB for text fields and multipart framing. */
    const val MAX_TOTAL_BYTES = MAX_REQUEST_BYTES - 512L * 1024

    /** Largest single attachment (the whole budget; there is no separate per-file cap). */
    const val MAX_ATTACHMENT_BYTES = MAX_TOTAL_BYTES

    /** Longest title, prefix included. */
    const val MAX_TITLE_LENGTH = 200

    /** Longest description, steps or expected-behavior text. */
    const val MAX_TEXT_LENGTH = 10_000

    /** Longest `appVersion` field. */
    const val MAX_APP_VERSION_LENGTH = 64

    /** Longest `clientInfo` field (OS and device). */
    const val MAX_CLIENT_INFO_LENGTH = 256

    /** MIME filters handed to the system document picker. */
    val PICKER_MIME_TYPES = arrayOf("image/*", "video/*")
}

/** Field labels and the always-visible helper lines under them (they never disappear while typing). */
object FeedbackCopy {
    /** Title label. */
    const val TITLE = "Title"

    /** Description label. */
    const val DESCRIPTION = "Description"

    /** Steps label. */
    const val REPRO = "Steps to Reproduce"

    /** Expected label. */
    const val EXPECTED = "Expected Behavior"

    /**
     * Helper under the title.
     *
     * @param kind Form.
     * @return Guidance text.
     */
    fun titleHelp(kind: FeedbackKind): String = when (kind) {
        FeedbackKind.Bug -> "A short summary of the problem, after ${kind.titlePrefix.trim()}."
        FeedbackKind.Feature -> "A short name for your idea, after ${kind.titlePrefix.trim()}."
    }

    /**
     * Helper under the description.
     *
     * @param kind Form.
     * @return Guidance text.
     */
    fun descriptionHelp(kind: FeedbackKind): String = when (kind) {
        FeedbackKind.Bug -> "What went wrong? Include the page, song, instrument or player involved."
        FeedbackKind.Feature -> "What would you like, and how would it help you? Mention the pages it affects."
    }

    /** Helper under Steps to Reproduce. */
    const val REPRO_HELP = "List the steps that make the problem happen, one per line."

    /** Helper under Expected Behavior. */
    const val EXPECTED_HELP = "What did you expect to happen instead?"

    /** Attach button label. */
    const val ATTACH = "Attach Media"

    /** Helper above the attach button (count and size budget, then how to open one). */
    val ATTACH_HELP: String =
        "Add up to ${FeedbackLimits.MAX_ATTACHMENTS} screenshots or screen recordings, " +
            "${FeedbackFormat.bytes(FeedbackLimits.MAX_REQUEST_BYTES)} in total. Tap one to open it."
}

// endregion

// region Attachment

/**
 * One picked image or video. The app never decodes video or plays media; tapping hands it to the system.
 *
 * @property id Stable platform handle (an Android `content://` URI string).
 * @property name Display name sent as the multipart filename.
 * @property mimeType Reported MIME type (`image/…` or `video/…`).
 * @property sizeBytes Size when the provider reports it.
 */
data class FeedbackAttachment(
    val id: String,
    val name: String,
    val mimeType: String,
    val sizeBytes: Long?,
) {
    /** Whether this is a video (shown with a video glyph instead of a thumbnail). */
    val isVideo: Boolean get() = mimeType.lowercase(Locale.ROOT).startsWith("video/")

    /** Whether the type is an image or a video. */
    val isMedia: Boolean
        get() = mimeType.lowercase(Locale.ROOT).let { it.startsWith("image/") || it.startsWith("video/") }

    /** TalkBack/Narrator label: kind, name and size. */
    val accessibilityLabel: String
        get() = buildString {
            append(if (isVideo) "Video" else "Image")
            append(", ").append(name)
            sizeBytes?.let { append(", ").append(FeedbackFormat.bytes(it)) }
        }
}

/**
 * Outcome of adding picked attachments.
 *
 * @property attachments Resulting list.
 * @property notice Readable reason some picks were skipped, or null.
 */
data class AttachmentAddResult(val attachments: List<FeedbackAttachment>, val notice: String?)

// endregion

// region Draft

/** Why a draft cannot be submitted yet. */
enum class FeedbackProblem(val message: String) {
    /** Nothing but the prefix in the title. */
    MissingTitle("Add a title after the prefix."),

    /** Empty description. */
    MissingDescription("Add a description."),

    /** A field is over its limit. */
    TooLong("Shorten the text and try again."),
}

/**
 * The editable form. Pure value; [isDirty] drives the discard confirmation.
 *
 * @property kind Form.
 * @property title Title text (pre-filled with the prefix).
 * @property description Description.
 * @property reproSteps Steps to reproduce (bugs only).
 * @property expectedBehavior Expected behavior (bugs only).
 * @property attachments Picked media in pick order.
 */
data class FeedbackDraft(
    val kind: FeedbackKind,
    val title: String = kind.titlePrefix,
    val description: String = "",
    val reproSteps: String = "",
    val expectedBehavior: String = "",
    val attachments: List<FeedbackAttachment> = emptyList(),
) {
    /** Title text after the kind prefix (the user's own words). */
    val titleBody: String
        get() {
            val trimmed = title.trim()
            val tag = kind.titlePrefix.trim()
            return if (trimmed.startsWith(tag, ignoreCase = true)) trimmed.substring(tag.length).trim() else trimmed
        }

    /** Whether closing would lose anything the user entered. */
    val isDirty: Boolean
        get() = titleBody.isNotEmpty() || description.isNotBlank() ||
            (kind.hasBugFields && (reproSteps.isNotBlank() || expectedBehavior.isNotBlank())) ||
            attachments.isNotEmpty()

    /** The first problem blocking submission, or null when ready. */
    val problem: FeedbackProblem?
        get() = when {
            titleBody.isEmpty() -> FeedbackProblem.MissingTitle
            description.isBlank() -> FeedbackProblem.MissingDescription
            normalizedTitle.length > FeedbackLimits.MAX_TITLE_LENGTH -> FeedbackProblem.TooLong
            listOf(description, reproSteps, expectedBehavior).any { it.trim().length > FeedbackLimits.MAX_TEXT_LENGTH } ->
                FeedbackProblem.TooLong
            else -> null
        }

    /** Title sent to the service: trimmed and always starting with the kind prefix, even if the user deleted it. */
    val normalizedTitle: String get() = kind.titlePrefix + titleBody

    /**
     * Add picked media: skip duplicates and non-media, then enforce count and size bounds.
     *
     * @param picked Newly picked items.
     * @return New list plus a notice naming anything skipped.
     */
    fun adding(picked: List<FeedbackAttachment>): AttachmentAddResult {
        val result = attachments.toMutableList()
        var total = attachments.sumOf { it.sizeBytes ?: 0L }
        var skippedType = 0
        var skippedSize = 0
        var skippedCount = 0
        for (item in picked) {
            val size = item.sizeBytes ?: 0L
            when {
                result.any { it.id == item.id } -> Unit
                !item.isMedia -> skippedType++
                result.size >= FeedbackLimits.MAX_ATTACHMENTS -> skippedCount++
                size > FeedbackLimits.MAX_ATTACHMENT_BYTES || total + size > FeedbackLimits.MAX_TOTAL_BYTES -> skippedSize++
                else -> {
                    result += item
                    total += size
                }
            }
        }
        val notices = buildList {
            if (skippedType > 0) add("Only images and videos can be attached.")
            if (skippedCount > 0) add("You can attach up to ${FeedbackLimits.MAX_ATTACHMENTS} files.")
            if (skippedSize > 0) add("Attachments must add up to less than ${FeedbackFormat.bytes(FeedbackLimits.MAX_REQUEST_BYTES)}.")
        }
        return AttachmentAddResult(result, notices.joinToString(" ").ifEmpty { null })
    }

    /**
     * Build the wire submission.
     *
     * @param platform Platform label (`android`, `windows`).
     * @param appVersion App version string.
     * @param clientInfo OS and device description.
     * @return Submission with trimmed text; bug-only fields are empty for features.
     */
    fun submission(platform: String, appVersion: String, clientInfo: String): FeedbackSubmission = FeedbackSubmission(
        kind = kind,
        platform = platform,
        title = normalizedTitle,
        description = description.trim(),
        reproSteps = if (kind.hasBugFields) reproSteps.trim() else "",
        expectedBehavior = if (kind.hasBugFields) expectedBehavior.trim() else "",
        appVersion = appVersion,
        clientInfo = clientInfo,
        attachments = attachments,
    )
}

// endregion

// region Submission

/**
 * What `POST /api/feedback` carries (`.agents/controls/feedback-form/spec.md`).
 *
 * @property kind Form.
 * @property platform Platform label the service turns into the issue's `surface:` label.
 * @property title Prefixed title.
 * @property description Description.
 * @property reproSteps Steps (empty for features: omitted on the wire).
 * @property expectedBehavior Expected behavior (empty for features: omitted on the wire).
 * @property appVersion App version (clipped to [FeedbackLimits.MAX_APP_VERSION_LENGTH] on the wire).
 * @property clientInfo OS and device (clipped to [FeedbackLimits.MAX_CLIENT_INFO_LENGTH] on the wire).
 * @property attachments Media parts, each sent as a `media` file part.
 */
data class FeedbackSubmission(
    val kind: FeedbackKind,
    val platform: String,
    val title: String,
    val description: String,
    val reproSteps: String,
    val expectedBehavior: String,
    val appVersion: String,
    val clientInfo: String,
    val attachments: List<FeedbackAttachment>,
) {
    /** Text form fields in wire order; empty optional fields are omitted. */
    val formFields: List<Pair<String, String>>
        get() = buildList {
            add("kind" to kind.wire)
            add("platform" to platform)
            add("title" to title)
            add("description" to description)
            if (reproSteps.isNotEmpty()) add("repro" to reproSteps)
            if (expectedBehavior.isNotEmpty()) add("expected" to expectedBehavior)
            clip(appVersion, FeedbackLimits.MAX_APP_VERSION_LENGTH).takeIf { it.isNotEmpty() }?.let { add("appVersion" to it) }
            clip(clientInfo, FeedbackLimits.MAX_CLIENT_INFO_LENGTH).takeIf { it.isNotEmpty() }?.let { add("clientInfo" to it) }
        }

    companion object {
        /** Multipart name of every file part. */
        const val MEDIA_PART = "media"

        /** Platform label Android submits. */
        const val PLATFORM_ANDROID = "android"

        private fun clip(value: String, max: Int): String {
            val trimmed = value.trim()
            return if (trimmed.length > max) trimmed.take(max).trimEnd() else trimmed
        }
    }
}

// endregion

// region Job status

/** Service processing state of an accepted submission (`GET /api/feedback/{id}`). */
enum class FeedbackJobState {
    /** Accepted (the 202 answer), waiting for a worker. */
    Queued,

    /** Media being prepared or the issue being filed. */
    Processing,

    /** Filed on GitHub. */
    Submitted,

    /** Filing failed; nothing was created. */
    Failed,
}

/**
 * An accepted submission as last seen. The 202 answer is `{id, status:"queued"}`; polling adds the
 * issue number and per-attachment outcomes. The service never returns an issue URL (the tracker may
 * be private), so the app shows the number only and opens no link.
 *
 * @property id 32 lowercase hex characters, or null when the 2xx body carried none (no polling).
 * @property state Processing state.
 * @property issueNumber Created issue number once submitted, when reported.
 * @property skippedAttachments Attachments the service could not fit and left out.
 */
data class FeedbackJob(
    val id: String?,
    val state: FeedbackJobState,
    val issueNumber: Int? = null,
    val skippedAttachments: Int = 0,
) {
    /** Whether polling can stop. */
    val isTerminal: Boolean get() = state == FeedbackJobState.Submitted || state == FeedbackJobState.Failed

    /**
     * Success text. A submitted job names its issue; an accepted job whose outcome is unknown (still
     * processing when polling stopped, status expired or unreadable) says it will be filed shortly
     * rather than inviting a duplicate.
     *
     * @param kind Form.
     * @return Readable confirmation.
     */
    fun message(kind: FeedbackKind): String {
        val noun = kind.noun
        val text = when {
            state != FeedbackJobState.Submitted -> "Thanks! Your $noun was received and will be filed on GitHub shortly."
            issueNumber != null -> "Thanks! Your $noun was filed as issue #$issueNumber."
            else -> "Thanks! Your $noun was filed on GitHub."
        }
        return when {
            skippedAttachments <= 0 -> text
            skippedAttachments == 1 -> "$text 1 attachment couldn't be attached."
            else -> "$text $skippedAttachments attachments couldn't be attached."
        }
    }

    companion object {
        /**
         * Whether a value is a well-formed job ID (the only shape the status route answers).
         *
         * @param id Candidate.
         * @return True for exactly 32 lowercase hex characters.
         */
        fun isValidId(id: String?): Boolean = id != null && id.length == 32 && id.all { it in '0'..'9' || it in 'a'..'f' }

        /**
         * Wire `status` value, case-insensitively.
         *
         * @param wire Value.
         * @return State, or null for anything unknown.
         */
        fun parseState(wire: String?): FeedbackJobState? = when (wire?.trim()?.lowercase(Locale.ROOT)) {
            "queued" -> FeedbackJobState.Queued
            "processing" -> FeedbackJobState.Processing
            "submitted" -> FeedbackJobState.Submitted
            "failed" -> FeedbackJobState.Failed
            else -> null
        }
    }
}

/**
 * A failed submission with fixed, readable text (server `error` strings are never shown).
 *
 * @property status HTTP status, when one arrived.
 */
class FeedbackException(message: String, val status: Int? = null) : Exception(message) {
    companion object {
        /**
         * Map a service error `code` (preferred) or HTTP status to readable text.
         *
         * @param status Non-2xx status.
         * @param code `code` from the `{error, code}` body, when present.
         * @param retryAfterSeconds Positive `Retry-After` delta, when present.
         * @return Exception to surface.
         */
        fun forStatus(status: Int, code: String? = null, retryAfterSeconds: Int? = null): FeedbackException {
            val budget = FeedbackFormat.bytes(FeedbackLimits.MAX_REQUEST_BYTES)
            val busy = "Feedback is busy right now. Try again in a minute."
            val unavailable = "Sending feedback isn't available right now."
            val message = when (code) {
                "payload_too_large" -> "The attachments are too large. Keep them under $budget in total."
                "too_many_attachments" -> "Attach up to ${FeedbackLimits.MAX_ATTACHMENTS} files."
                "unsupported_media" -> "Only image and video attachments are supported."
                "feedback_disabled" -> unavailable
                "feedback_busy" -> busy
                "title_required" -> FeedbackProblem.MissingTitle.message
                "description_required" -> FeedbackProblem.MissingDescription.message
                "field_too_long" -> "One of the fields is too long. Shorten it and try again."
                else -> when (status) {
                    429 -> if (retryAfterSeconds != null && retryAfterSeconds > 0) {
                        "Too many submissions from this network. Try again in ${FeedbackFormat.wait(retryAfterSeconds)}."
                    } else {
                        "Too many submissions from this network. Try again later."
                    }
                    400, 422 -> "The service couldn't accept this form. Check the fields and try again."
                    404, 405, 501 -> unavailable
                    413 -> "The attachments are too large. Keep them under $budget in total."
                    415 -> "Only image and video attachments are supported."
                    503 -> busy
                    in 500..599 -> "The service is temporarily unavailable. Try again."
                    else -> "Your feedback couldn't be sent (HTTP $status). Try again."
                }
            }
            return FeedbackException(message, status)
        }

        /**
         * The service accepted the form but could not file it.
         *
         * @param kind Form.
         * @return Exception to surface (the form keeps every field for a retry).
         */
        fun filingFailed(kind: FeedbackKind): FeedbackException =
            FeedbackException("Your ${kind.noun} couldn't be filed on GitHub. Try again in a few minutes.")

        /**
         * Connectivity failure.
         *
         * @return Exception to surface.
         */
        fun offline(): FeedbackException = FeedbackException("Check your connection and try again.")

        /**
         * An attachment could not be read.
         *
         * @param name Attachment name.
         * @return Exception to surface.
         */
        fun unreadable(name: String): FeedbackException =
            FeedbackException("\"$name\" couldn't be read. Remove it and try again.")
    }
}

// endregion

// region Formatting

/** Small formatting helpers shared by the form. */
object FeedbackFormat {
    /**
     * Human file size (1 decimal for MB/GB, trailing `.0` dropped).
     *
     * @param bytes Size.
     * @return E.g. `512 KB`, `3.4 MB`.
     */
    fun bytes(bytes: Long): String {
        val kb = 1024.0
        val mb = kb * 1024
        val gb = mb * 1024
        return when {
            bytes < kb -> "$bytes B"
            bytes < mb -> "${(bytes / kb).toLong()} KB"
            bytes < gb -> String.format(Locale.US, "%.1f MB", bytes / mb).replace(".0 MB", " MB")
            else -> String.format(Locale.US, "%.1f GB", bytes / gb).replace(".0 GB", " GB")
        }
    }

    /**
     * A short wait for retry messages.
     *
     * @param seconds Seconds (positive).
     * @return E.g. `45 seconds`, `1 minute`, `10 minutes` (rounded up).
     */
    fun wait(seconds: Int): String {
        if (seconds < 60) return if (seconds == 1) "1 second" else "$seconds seconds"
        val minutes = (seconds + 59) / 60
        return if (minutes == 1) "1 minute" else "$minutes minutes"
    }
}

// endregion
