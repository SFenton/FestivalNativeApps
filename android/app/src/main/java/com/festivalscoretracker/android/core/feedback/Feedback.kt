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

/** Client-side bounds; the service transcodes oversized media itself, these only stop absurd uploads. */
object FeedbackLimits {
    /** Most attachments one submission carries. */
    const val MAX_ATTACHMENTS = 10

    /** Largest single attachment (250 MB). */
    const val MAX_ATTACHMENT_BYTES = 250L * 1024 * 1024

    /** Largest combined upload (500 MB). */
    const val MAX_TOTAL_BYTES = 500L * 1024 * 1024

    /** Longest title, prefix included. */
    const val MAX_TITLE_LENGTH = 200

    /** Longest description, steps or expected-behavior text. */
    const val MAX_TEXT_LENGTH = 10_000

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

    /** Helper above the attach button. */
    const val ATTACH_HELP = "Screenshots or screen recordings help a lot. Tap an attachment to open it."
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
            if (skippedSize > 0) {
                add(
                    "Files must be under ${FeedbackFormat.bytes(FeedbackLimits.MAX_ATTACHMENT_BYTES)} each and " +
                        "${FeedbackFormat.bytes(FeedbackLimits.MAX_TOTAL_BYTES)} in total.",
                )
            }
        }
        return AttachmentAddResult(result, notices.joinToString(" ").ifEmpty { null })
    }

    /**
     * Build the wire submission.
     *
     * @param platform Platform label (`android`, `windows`).
     * @param appVersion App version string.
     * @param osVersion OS description.
     * @return Submission with trimmed text; bug-only fields are empty for features.
     */
    fun submission(platform: String, appVersion: String, osVersion: String): FeedbackSubmission = FeedbackSubmission(
        kind = kind,
        platform = platform,
        title = normalizedTitle,
        description = description.trim(),
        reproSteps = if (kind.hasBugFields) reproSteps.trim() else "",
        expectedBehavior = if (kind.hasBugFields) expectedBehavior.trim() else "",
        appVersion = appVersion,
        osVersion = osVersion,
        attachments = attachments,
    )
}

// endregion

// region Submission

/**
 * What `POST /api/feedback` carries (`.agents/controls/feedback-form/spec.md`).
 *
 * @property kind Form.
 * @property platform Platform label the service turns into the issue's platform label.
 * @property title Prefixed title.
 * @property description Description.
 * @property reproSteps Steps (empty for features: omitted on the wire).
 * @property expectedBehavior Expected behavior (empty for features: omitted on the wire).
 * @property appVersion App version.
 * @property osVersion OS description.
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
    val osVersion: String,
    val attachments: List<FeedbackAttachment>,
) {
    /** Text form fields in wire order; empty optional fields are omitted. */
    val formFields: List<Pair<String, String>>
        get() = buildList {
            add("kind" to kind.wire)
            add("platform" to platform)
            add("title" to title)
            add("description" to description)
            if (reproSteps.isNotEmpty()) add("reproSteps" to reproSteps)
            if (expectedBehavior.isNotEmpty()) add("expectedBehavior" to expectedBehavior)
            if (appVersion.isNotEmpty()) add("appVersion" to appVersion)
            if (osVersion.isNotEmpty()) add("osVersion" to osVersion)
        }

    companion object {
        /** Multipart name of every file part. */
        const val MEDIA_PART = "media"

        /** Platform label Android submits. */
        const val PLATFORM_ANDROID = "android"
    }
}

/**
 * The service's answer to a successful submission. Both fields are optional so a bare 2xx is still success.
 *
 * @property issueNumber Created issue number.
 * @property issueUrl Created issue URL (only `https://github.com/…` URLs are kept).
 */
data class FeedbackReceipt(val issueNumber: Int?, val issueUrl: String?) {
    /**
     * Success text shown in the form.
     *
     * @param kind Form.
     * @return Readable confirmation.
     */
    fun message(kind: FeedbackKind): String {
        val noun = kind.noun.replaceFirstChar { it.titlecase(Locale.ROOT) }
        return if (issueNumber != null) "$noun sent as issue #$issueNumber. Thank you!" else "$noun sent. Thank you!"
    }

    companion object {
        /**
         * Keep only a GitHub HTTPS URL (never open an arbitrary server-provided link).
         *
         * @param raw Wire value.
         * @return The URL, or null.
         */
        fun safeUrl(raw: String?): String? =
            raw?.takeIf { it.startsWith("https://github.com/") && it.none(Char::isWhitespace) }
    }
}

/**
 * A failed submission with text safe to show (never server text).
 *
 * @property status HTTP status, when one arrived.
 */
class FeedbackException(message: String, val status: Int? = null) : Exception(message) {
    companion object {
        /**
         * Map an HTTP status to readable text.
         *
         * @param status Non-2xx status.
         * @return Exception to surface.
         */
        fun forStatus(status: Int): FeedbackException = FeedbackException(
            when (status) {
                400, 422 -> "The service couldn't accept this form. Check the fields and try again."
                404, 405, 501 -> "Sending feedback isn't available yet. Try again after the next update."
                413 -> "The attachments are too large to send. Remove some and try again."
                415 -> "One of the attachments isn't a supported image or video."
                429 -> "Too many submissions right now. Try again in a few minutes."
                in 500..599 -> "The service is temporarily unavailable. Try again."
                else -> "Your feedback couldn't be sent (HTTP $status). Try again."
            },
            status,
        )

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
}

// endregion
