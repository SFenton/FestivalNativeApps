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
        val many = (1..6).map { image("i$it") }
        val counted = FeedbackDraft(FeedbackKind.Feature).adding(many)
        assertEquals(4, counted.attachments.size)
        assertEquals("You can attach up to 4 files.", counted.notice)

        val big = FeedbackAttachment("v", "v.mp4", "video/mp4", FeedbackLimits.MAX_ATTACHMENT_BYTES + 1)
        val sized = FeedbackDraft(FeedbackKind.Feature).adding(listOf(big))
        assertTrue(sized.attachments.isEmpty())
        assertEquals("Attachments must add up to less than 90 MB.", sized.notice)

        // The budget leaves 512 KiB of the 90 MiB request for fields and framing.
        assertEquals(94_371_840L - 524_288L, FeedbackLimits.MAX_TOTAL_BYTES)
        val half = FeedbackLimits.MAX_TOTAL_BYTES / 2
        val total = FeedbackDraft(FeedbackKind.Feature).adding(listOf(image("x", half), image("y", half), image("z", 1)))
        assertEquals(listOf("x", "y"), total.attachments.map { it.id })
        assertEquals("Attachments must add up to less than 90 MB.", total.notice)

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
                "repro" to "1. Open\n2. Tap", "expected" to "No crash", "appVersion" to "2610.02.1", "clientInfo" to "Android 15",
            ),
            submission.formFields,
        )
        assertEquals(1, submission.attachments.size)
    }

    @Test
    fun diagnosticsAreTrimmedAndClipped() {
        val draft = FeedbackDraft(FeedbackKind.Feature, "[Feature] Dark", "Please")
        val fields = draft.submission("android", " " + "v".repeat(70) + " ", "c".repeat(300)).formFields.toMap()
        assertEquals("v".repeat(FeedbackLimits.MAX_APP_VERSION_LENGTH), fields["appVersion"])
        assertEquals("c".repeat(FeedbackLimits.MAX_CLIENT_INFO_LENGTH), fields["clientInfo"])
        assertEquals("ab", draft.submission("android", "1", "ab" + " ".repeat(254) + "x").formFields.toMap()["clientInfo"])
    }

    @Test
    fun featureSubmissionOmitsBugFields() {
        val draft = FeedbackDraft(FeedbackKind.Feature, "[Feature] Dark", "Please", reproSteps = "ignored", expectedBehavior = "ignored")
        val fields = draft.submission("android", "", "").formFields
        assertEquals(listOf("kind" to "feature", "platform" to "android", "title" to "[Feature] Dark", "description" to "Please"), fields)
    }

    @Test
    fun jobMessagesAndParsing() {
        val id = "0123456789abcdef0123456789abcdef"
        assertEquals("Thanks! Your report was filed as issue #12.", FeedbackJob(id, FeedbackJobState.Submitted, 12).message(FeedbackKind.Bug))
        assertEquals("Thanks! Your request was filed on GitHub.", FeedbackJob(id, FeedbackJobState.Submitted).message(FeedbackKind.Feature))
        assertEquals(
            "Thanks! Your request was received and will be filed on GitHub shortly.",
            FeedbackJob(id, FeedbackJobState.Processing, 12).message(FeedbackKind.Feature),
        )
        assertEquals(
            "Thanks! Your report was filed as issue #3. 1 attachment couldn't be attached.",
            FeedbackJob(id, FeedbackJobState.Submitted, 3, skippedAttachments = 1).message(FeedbackKind.Bug),
        )
        assertTrue(FeedbackJob(id, FeedbackJobState.Submitted, 3, 2).message(FeedbackKind.Bug).endsWith(" 2 attachments couldn't be attached."))
        assertTrue(FeedbackJob(null, FeedbackJobState.Failed).isTerminal)
        assertFalse(FeedbackJob(null, FeedbackJobState.Queued).isTerminal)

        assertTrue(FeedbackJob.isValidId(id))
        listOf(null, "", id.uppercase(), id.dropLast(1), id.dropLast(1) + "g", "../$id".take(32)).forEach { assertFalse(FeedbackJob.isValidId(it)) }
        assertEquals(FeedbackJobState.Submitted, FeedbackJob.parseState(" SUBMITTED "))
        assertEquals(FeedbackJobState.Queued, FeedbackJob.parseState("queued"))
        assertEquals(FeedbackJobState.Processing, FeedbackJob.parseState("processing"))
        assertEquals(FeedbackJobState.Failed, FeedbackJob.parseState("failed"))
        assertNull(FeedbackJob.parseState("later"))
        assertNull(FeedbackJob.parseState(null))
    }

    @Test
    fun errorsUseFixedCopy() {
        val statuses = listOf(400, 404, 413, 415, 429, 503, 500, 418)
        val messages = statuses.map { FeedbackException.forStatus(it).message!! }
        assertEquals(statuses.size, messages.toSet().size)
        assertEquals(FeedbackException.forStatus(400).message, FeedbackException.forStatus(422).message)
        assertEquals(FeedbackException.forStatus(404).message, FeedbackException.forStatus(405).message)
        assertEquals(FeedbackException.forStatus(500).message, FeedbackException.forStatus(502).message)
        assertTrue(FeedbackException.forStatus(418).message!!.contains("HTTP 418"))
        assertEquals(413, FeedbackException.forStatus(413).status)
        assertEquals("The attachments are too large. Keep them under 90 MB in total.", FeedbackException.forStatus(413).message)
        assertEquals("Feedback is busy right now. Try again in a minute.", FeedbackException.forStatus(503).message)

        // Service codes win over the status.
        assertEquals(FeedbackException.forStatus(413).message, FeedbackException.forStatus(400, "payload_too_large").message)
        assertEquals("Attach up to 4 files.", FeedbackException.forStatus(400, "too_many_attachments").message)
        assertEquals(FeedbackException.forStatus(415).message, FeedbackException.forStatus(400, "unsupported_media").message)
        assertEquals(FeedbackException.forStatus(404).message, FeedbackException.forStatus(404, "feedback_disabled").message)
        assertEquals(FeedbackException.forStatus(503).message, FeedbackException.forStatus(503, "feedback_busy").message)
        assertEquals(FeedbackProblem.MissingTitle.message, FeedbackException.forStatus(400, "title_required").message)
        assertEquals(FeedbackProblem.MissingDescription.message, FeedbackException.forStatus(400, "description_required").message)
        assertTrue(FeedbackException.forStatus(400, "field_too_long").message!!.contains("too long"))
        assertEquals(FeedbackException.forStatus(400).message, FeedbackException.forStatus(400, "something_new").message)

        assertEquals("Too many submissions from this network. Try again in 45 seconds.", FeedbackException.forStatus(429, null, 45).message)
        assertEquals("Too many submissions from this network. Try again in 10 minutes.", FeedbackException.forStatus(429, null, 541).message)
        assertEquals("Too many submissions from this network. Try again later.", FeedbackException.forStatus(429, null, 0).message)

        assertTrue(FeedbackException.filingFailed(FeedbackKind.Bug).message!!.startsWith("Your report couldn't be filed"))
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
        assertEquals("90 MB", FeedbackFormat.bytes(FeedbackLimits.MAX_REQUEST_BYTES))
        assertEquals("1 second", FeedbackFormat.wait(1))
        assertEquals("59 seconds", FeedbackFormat.wait(59))
        assertEquals("1 minute", FeedbackFormat.wait(60))
        assertEquals("2 minutes", FeedbackFormat.wait(61))
        assertEquals("Add up to 4 screenshots or screen recordings, 90 MB in total. Tap one to open it.", FeedbackCopy.ATTACH_HELP)
    }

    // endregion
}
