package com.festivalscoretracker.android.core.feedback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedbackTest {
    private fun image(id: String, size: Long? = 1_000) = FeedbackAttachment(id, "$id.png", "image/png", size)

    // region Draft

    @Test
    fun draftStartsWithPrefixAndIsClean() {
        val bug = FeedbackDraft(FeedbackKind.Bug)
        assertEquals("[Bug] ", bug.title)
        assertFalse(bug.isDirty)
        assertEquals(FeedbackProblem.MissingTitle, bug.problem)
        assertEquals("[Feature] ", FeedbackDraft(FeedbackKind.Feature).title)
        assertTrue(FeedbackKind.Bug.hasBugFields)
        assertFalse(FeedbackKind.Feature.hasBugFields)
    }

    @Test
    fun dirtyTracksEveryInput() {
        val base = FeedbackDraft(FeedbackKind.Bug)
        assertFalse(base.copy(title = "  [Bug]   ").isDirty)
        assertTrue(base.copy(title = "[Bug] Crash").isDirty)
        assertTrue(base.copy(description = "x").isDirty)
        assertTrue(base.copy(reproSteps = "x").isDirty)
        assertTrue(base.copy(expectedBehavior = "x").isDirty)
        assertTrue(base.copy(attachments = listOf(image("a"))).isDirty)
        assertFalse(base.copy(description = "   ").isDirty)
        // Bug-only boxes do not exist on the Feature form.
        assertFalse(FeedbackDraft(FeedbackKind.Feature, reproSteps = "x").isDirty)
    }

    @Test
    fun titleIsNormalizedToThePrefix() {
        val draft = FeedbackDraft(FeedbackKind.Bug)
        assertEquals("[Bug] Crash", draft.copy(title = "[Bug] Crash ").normalizedTitle)
        assertEquals("[Bug] Crash", draft.copy(title = "Crash").normalizedTitle)
        assertEquals("[Bug] Crash", draft.copy(title = "[bug]Crash").normalizedTitle)
        assertEquals("[Feature] Dark mode", FeedbackDraft(FeedbackKind.Feature, title = "  [Feature]   Dark mode").normalizedTitle)
    }

    @Test
    fun problemsInOrder() {
        val draft = FeedbackDraft(FeedbackKind.Bug, title = "[Bug] Crash")
        assertEquals(FeedbackProblem.MissingDescription, draft.problem)
        assertNull(draft.copy(description = "It crashes").problem)
        assertEquals(FeedbackProblem.TooLong, draft.copy(title = "[Bug] " + "x".repeat(FeedbackLimits.MAX_TITLE_LENGTH), description = "d").problem)
        assertEquals(FeedbackProblem.TooLong, draft.copy(description = "d", reproSteps = "x".repeat(FeedbackLimits.MAX_TEXT_LENGTH + 1)).problem)
        assertNull(draft.copy(description = "d", reproSteps = "x".repeat(FeedbackLimits.MAX_TEXT_LENGTH)).problem)
        FeedbackProblem.entries.forEach { assertTrue(it.message.isNotBlank()) }
    }

    // endregion

    // region Attachments

    @Test
    fun addingSkipsDuplicatesAndNonMedia() {
        val draft = FeedbackDraft(FeedbackKind.Bug, attachments = listOf(image("a")))
        val result = draft.adding(listOf(image("a"), image("b"), FeedbackAttachment("c", "c.pdf", "application/pdf", 5)))
        assertEquals(listOf("a", "b"), result.attachments.map { it.id })
        assertEquals("Only images and videos can be attached.", result.notice)
        assertNull(draft.adding(listOf(image("d"))).notice)
    }

    @Test
    fun addingEnforcesCountAndSize() {
        val many = (1..12).map { image("i$it") }
        val counted = FeedbackDraft(FeedbackKind.Feature).adding(many)
        assertEquals(FeedbackLimits.MAX_ATTACHMENTS, counted.attachments.size)
        assertEquals("You can attach up to 10 files.", counted.notice)

        val big = FeedbackAttachment("v", "v.mp4", "video/mp4", FeedbackLimits.MAX_ATTACHMENT_BYTES + 1)
        val sized = FeedbackDraft(FeedbackKind.Feature).adding(listOf(big))
        assertTrue(sized.attachments.isEmpty())
        assertEquals("Files must be under 250 MB each and 500 MB in total.", sized.notice)

        val half = FeedbackLimits.MAX_ATTACHMENT_BYTES
        val total = FeedbackDraft(FeedbackKind.Feature).adding(listOf(image("x", half), image("y", half), image("z", 1)))
        assertEquals(listOf("x", "y"), total.attachments.map { it.id })
        assertTrue(total.notice!!.startsWith("Files must be under"))

        // Unknown sizes are accepted (the service enforces its own limit).
        assertEquals(1, FeedbackDraft(FeedbackKind.Feature).adding(listOf(image("u", null))).attachments.size)
    }

    @Test
    fun attachmentDescriptions() {
        val video = FeedbackAttachment("v", "clip.mp4", "VIDEO/MP4", 3L * 1024 * 1024)
        assertTrue(video.isVideo && video.isMedia)
        assertEquals("Video, clip.mp4, 3 MB", video.accessibilityLabel)
        assertEquals("Image, a.png", image("a", null).accessibilityLabel)
        assertFalse(FeedbackAttachment("d", "d", "text/plain", 1).isMedia)
    }

    // endregion

    // region Submission

    @Test
    fun bugSubmissionFields() {
        val draft = FeedbackDraft(FeedbackKind.Bug, "Crash", " It crashes ", " 1. Open\n2. Tap ", " No crash ", listOf(image("a")))
        val submission = draft.submission("android", "2610.02.1", "Android 15")
        assertEquals(
            listOf(
                "kind" to "bug", "platform" to "android", "title" to "[Bug] Crash", "description" to "It crashes",
                "reproSteps" to "1. Open\n2. Tap", "expectedBehavior" to "No crash", "appVersion" to "2610.02.1", "osVersion" to "Android 15",
            ),
            submission.formFields,
        )
        assertEquals(1, submission.attachments.size)
    }

    @Test
    fun featureSubmissionOmitsBugFields() {
        val draft = FeedbackDraft(FeedbackKind.Feature, "[Feature] Dark", "Please", reproSteps = "ignored", expectedBehavior = "ignored")
        val fields = draft.submission("android", "", "").formFields
        assertEquals(listOf("kind" to "feature", "platform" to "android", "title" to "[Feature] Dark", "description" to "Please"), fields)
    }

    @Test
    fun receiptAndErrors() {
        assertEquals("Report sent as issue #12. Thank you!", FeedbackReceipt(12, null).message(FeedbackKind.Bug))
        assertEquals("Request sent. Thank you!", FeedbackReceipt(null, null).message(FeedbackKind.Feature))
        assertEquals("https://github.com/o/r/issues/1", FeedbackReceipt.safeUrl("https://github.com/o/r/issues/1"))
        assertNull(FeedbackReceipt.safeUrl("http://github.com/o/r/issues/1"))
        assertNull(FeedbackReceipt.safeUrl("https://evil.test/x"))
        assertNull(FeedbackReceipt.safeUrl("https://github.com/a b"))
        assertNull(FeedbackReceipt.safeUrl(null))

        val statuses = listOf(400, 404, 413, 415, 429, 503, 418)
        val messages = statuses.map { FeedbackException.forStatus(it).message!! }
        assertEquals(statuses.size, messages.toSet().size)
        assertEquals(FeedbackException.forStatus(400).message, FeedbackException.forStatus(422).message)
        assertEquals(FeedbackException.forStatus(404).message, FeedbackException.forStatus(405).message)
        assertEquals(FeedbackException.forStatus(500).message, FeedbackException.forStatus(503).message)
        assertTrue(FeedbackException.forStatus(418).message!!.contains("HTTP 418"))
        assertEquals(413, FeedbackException.forStatus(413).status)
        assertNull(FeedbackException.offline().status)
        assertTrue(FeedbackException.unreadable("a.png").message!!.contains("\"a.png\""))
    }

    @Test
    fun copyAndFormatting() {
        FeedbackKind.entries.forEach { kind ->
            assertTrue(FeedbackCopy.titleHelp(kind).contains(kind.titlePrefix.trim()))
            assertTrue(FeedbackCopy.descriptionHelp(kind).isNotBlank())
        }
        assertEquals("512 B", FeedbackFormat.bytes(512))
        assertEquals("2 KB", FeedbackFormat.bytes(2048))
        assertEquals("1.5 MB", FeedbackFormat.bytes(1536L * 1024))
        assertEquals("2 GB", FeedbackFormat.bytes(2L * 1024 * 1024 * 1024))
        assertEquals("1.5 GB", FeedbackFormat.bytes(1536L * 1024 * 1024))
    }

    // endregion
}
