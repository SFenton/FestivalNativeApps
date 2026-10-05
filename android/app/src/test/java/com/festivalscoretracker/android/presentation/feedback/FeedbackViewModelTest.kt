package com.festivalscoretracker.android.presentation.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackLimits
import com.festivalscoretracker.android.core.feedback.FeedbackProblem
import com.festivalscoretracker.android.core.feedback.FeedbackJob
import com.festivalscoretracker.android.core.feedback.FeedbackJobState
import com.festivalscoretracker.android.core.feedback.FeedbackSubmission
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedbackViewModelTest {
    private val sent = mutableListOf<FeedbackSubmission>()
    private val polled = mutableListOf<String>()
    private val id = "0123456789abcdef0123456789abcdef"
    private val queued = FeedbackJob(id, FeedbackJobState.Queued)
    private val filed = FeedbackJob(id, FeedbackJobState.Submitted, 7)

    private fun TestScope.model(
        status: suspend (String) -> FeedbackJob = { polled += it; filed },
        features: suspend () -> Boolean = { true },
        send: suspend (FeedbackSubmission) -> FeedbackJob = { sent += it; queued },
    ): FeedbackViewModel {
        val dispatcher = StandardTestDispatcher(testScheduler)
        return FeedbackViewModel(
            send, status, features, appVersion = "1.0", clientInfo = "Android 15", io = dispatcher, scope = this,
            now = { testScheduler.currentTime },
        )
    }

    private fun FeedbackViewModel.fill() = edit { it.copy(title = "[Bug] Crash", description = "It crashes") }

    @Test
    fun openShowsOneFormAtATime() = runTest {
        val vm = model()
        assertNull(vm.form.value)
        vm.open(FeedbackKind.Bug)
        vm.open(FeedbackKind.Feature)
        assertEquals(FeedbackKind.Bug, vm.form.value!!.draft.kind)
        assertEquals("[Bug] ", vm.form.value!!.draft.title)
        assertTrue(vm.form.value!!.editable)
        // Only the prefix: Submit stays disabled and says why.
        assertFalse(vm.form.value!!.canSubmit)
        assertEquals(FeedbackProblem.MissingTitle.message, vm.form.value!!.validationMessage)
    }

    @Test
    fun cleanFormClosesAtOnceDirtyFormAsks() = runTest {
        val vm = model()
        vm.open(FeedbackKind.Feature)
        vm.requestClose()
        assertNull(vm.form.value)

        vm.open(FeedbackKind.Feature)
        vm.edit { it.copy(description = "idea") }
        vm.requestClose()
        assertTrue(vm.form.value!!.confirmingDiscard)
        vm.keepEditing()
        assertFalse(vm.form.value!!.confirmingDiscard)
        assertEquals("idea", vm.form.value!!.draft.description)
        vm.requestClose()
        vm.confirmDiscard()
        assertNull(vm.form.value)
        // Actions with no open form are no-ops.
        vm.requestClose()
        vm.submit()
        vm.edit { it.copy(description = "x") }
        vm.keepEditing()
        assertNull(vm.form.value)
    }

    @Test
    fun invalidFormKeepsSubmitDisabledWithAReason() = runTest {
        val vm = model()
        vm.open(FeedbackKind.Bug)
        vm.submit() // disabled: a no-op, not an error
        assertNull(vm.form.value!!.error)
        assertEquals(FeedbackPhase.Editing, vm.form.value!!.phase)
        vm.edit { it.copy(title = "[Bug] Crash") }
        assertFalse(vm.form.value!!.canSubmit)
        assertEquals(FeedbackProblem.MissingDescription.message, vm.form.value!!.validationMessage)
        vm.submit()
        assertNull(vm.form.value!!.error)
        vm.edit { it.copy(title = "[Bug] Crash", description = "x".repeat(FeedbackLimits.MAX_TEXT_LENGTH + 1)) }
        assertEquals(FeedbackProblem.TooLong.message, vm.form.value!!.validationMessage)
        vm.edit { it.copy(title = "[Bug] Crash", description = "d") }
        assertTrue(vm.form.value!!.canSubmit)
        assertNull(vm.form.value!!.validationMessage)
        advanceUntilIdle()
        assertTrue(sent.isEmpty())
        vm.submit()
        // While sending the reason is hidden and Submit stays off.
        assertFalse(vm.form.value!!.canSubmit)
        assertNull(vm.form.value!!.validationMessage)
        advanceUntilIdle()
        assertEquals(1, sent.size)
    }

    @Test
    fun submitSucceeds() = runTest {
        val vm = model()
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        assertEquals(FeedbackPhase.Submitting, vm.form.value!!.phase)
        assertFalse(vm.form.value!!.editable)
        vm.edit { it.copy(description = "ignored while sending") }
        vm.submit() // no double send
        assertEquals("Sending your report…", vm.form.value!!.progressText)
        runCurrent()
        assertEquals(FeedbackPhase.Filing(queued), vm.form.value!!.phase)
        assertTrue(vm.form.value!!.busy)
        assertEquals("Filing your report on GitHub…", vm.form.value!!.progressText)
        advanceUntilIdle()
        assertEquals(FeedbackPhase.Sent(filed), vm.form.value!!.phase)
        assertFalse(vm.form.value!!.busy)
        assertEquals(listOf(id), polled)
        assertEquals(1, sent.size)
        assertEquals("[Bug] Crash", sent.single().title)
        assertEquals("It crashes", sent.single().description)
        assertEquals("android", sent.single().platform)
        assertEquals("1.0", sent.single().appVersion)
        // After success Close needs no confirmation.
        vm.requestClose()
        assertNull(vm.form.value)
    }

    @Test
    fun failureKeepsInputAndShowsReadableError() = runTest {
        var attempt = 0
        val vm = model(send = { if (attempt++ == 0) throw FeedbackException.forStatus(429) else throw IllegalStateException("boom") })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        val failed = vm.form.value!!
        assertEquals(FeedbackPhase.Editing, failed.phase)
        assertEquals(FeedbackException.forStatus(429).message, failed.error)
        assertEquals("It crashes", failed.draft.description)
        vm.submit()
        advanceUntilIdle()
        assertEquals(FeedbackException.offline().message, vm.form.value!!.error)
    }

    @Test
    fun discardWhileSendingCancels() = runTest {
        val gate = CompletableDeferred<FeedbackJob>()
        val vm = model(send = { gate.await() })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        vm.requestClose()
        assertTrue(vm.form.value!!.confirmingDiscard)
        vm.confirmDiscard()
        gate.complete(queued)
        advanceUntilIdle()
        assertNull(vm.form.value)
    }

    @Test
    fun pollingFollowsUntilFiled() = runTest {
        val states = ArrayDeque(listOf(FeedbackJob(id, FeedbackJobState.Processing), FeedbackJob(id, FeedbackJobState.Submitted, 9, 1)))
        val vm = model(status = { polled += it; states.removeFirst() })
        vm.open(FeedbackKind.Feature)
        vm.edit { it.copy(title = "[Feature] Dark", description = "Please") }
        vm.submit()
        runCurrent()
        assertTrue(polled.isEmpty())
        advanceTimeBy(FeedbackViewModel.POLL_INTERVAL_MS + 1)
        assertEquals(FeedbackPhase.Filing(FeedbackJob(id, FeedbackJobState.Processing)), vm.form.value!!.phase)
        advanceUntilIdle()
        val phase = vm.form.value!!.phase as FeedbackPhase.Sent
        assertEquals("Thanks! Your request was filed as issue #9. 1 attachment couldn't be attached.", phase.job.message(FeedbackKind.Feature))
        assertEquals(2, polled.size)
    }

    @Test
    fun failedFilingKeepsInputForRetry() = runTest {
        val vm = model(status = { FeedbackJob(id, FeedbackJobState.Failed) })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        val state = vm.form.value!!
        assertEquals(FeedbackPhase.Editing, state.phase)
        assertEquals(FeedbackException.filingFailed(FeedbackKind.Bug).message, state.error)
        assertEquals("It crashes", state.draft.description)
    }

    @Test
    fun unknownOutcomeReportsReceived() = runTest {
        // A status read failure (expired, offline) reports the accepted form as received, not as an error.
        val vm = model(status = { throw IllegalStateException("gone") })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        assertEquals(FeedbackPhase.Sent(queued), vm.form.value!!.phase)
        assertTrue((vm.form.value!!.phase as FeedbackPhase.Sent).job.message(FeedbackKind.Bug).contains("received"))

        // No ID means nothing to poll.
        val bare = model(send = { FeedbackJob(null, FeedbackJobState.Queued) })
        bare.open(FeedbackKind.Bug)
        bare.fill()
        bare.submit()
        advanceUntilIdle()
        assertEquals(FeedbackPhase.Sent(FeedbackJob(null, FeedbackJobState.Queued)), bare.form.value!!.phase)
        assertTrue(polled.isEmpty())
    }

    @Test
    fun pollingStopsAtTheDeadline() = runTest {
        val vm = model(status = { polled += it; FeedbackJob(id, FeedbackJobState.Processing) })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        assertEquals(FeedbackPhase.Sent(FeedbackJob(id, FeedbackJobState.Processing)), vm.form.value!!.phase)
        assertEquals((FeedbackViewModel.POLL_TIMEOUT_MS / FeedbackViewModel.POLL_INTERVAL_MS).toInt(), polled.size)
    }

    @Test
    fun closingWhileFilingStopsPollingWithoutAsking() = runTest {
        val vm = model(status = { polled += it; FeedbackJob(id, FeedbackJobState.Processing) })
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        runCurrent()
        assertTrue(vm.form.value!!.phase is FeedbackPhase.Filing)
        vm.requestClose()
        assertNull(vm.form.value)
        advanceUntilIdle()
        assertTrue(polled.isEmpty())
    }

    @Test
    fun availabilityFollowsTheServiceFlag() = runTest {
        var calls = 0
        var answer: suspend () -> Boolean = { throw IllegalStateException("offline") }
        val vm = model(features = { calls++; answer() })
        assertFalse(vm.available.value)
        vm.loadAvailability()
        vm.loadAvailability() // in flight: one read
        advanceUntilIdle()
        assertFalse(vm.available.value)
        assertEquals(1, calls)
        answer = { false }
        vm.loadAvailability()
        advanceUntilIdle()
        assertFalse(vm.available.value)
        answer = { true }
        vm.loadAvailability()
        advanceUntilIdle()
        assertTrue(vm.available.value)
        vm.loadAvailability() // already on: no more reads
        advanceUntilIdle()
        assertEquals(3, calls)
    }

    @Test
    fun attachmentsAddAndRemove() = runTest {
        val vm = model()
        vm.addAttachments(listOf(FeedbackAttachment("a", "a.png", "image/png", 1))) // no form: ignored
        vm.open(FeedbackKind.Feature)
        vm.addAttachments(emptyList())
        vm.addAttachments(listOf(FeedbackAttachment("a", "a.png", "image/png", 1), FeedbackAttachment("d", "d.txt", "text/plain", 1)))
        assertEquals(listOf("a"), vm.form.value!!.draft.attachments.map { it.id })
        assertEquals("Only images and videos can be attached.", vm.form.value!!.notice)
        assertTrue(vm.form.value!!.draft.isDirty)
        vm.removeAttachment("a")
        assertTrue(vm.form.value!!.draft.attachments.isEmpty())
        assertNull(vm.form.value!!.notice)
        vm.requestClose()
        assertNull(vm.form.value)
    }
}
