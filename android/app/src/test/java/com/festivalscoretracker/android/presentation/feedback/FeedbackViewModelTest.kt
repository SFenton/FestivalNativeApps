package com.festivalscoretracker.android.presentation.feedback

import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackProblem
import com.festivalscoretracker.android.core.feedback.FeedbackReceipt
import com.festivalscoretracker.android.core.feedback.FeedbackSubmission
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedbackViewModelTest {
    private val sent = mutableListOf<FeedbackSubmission>()

    private fun TestScope.model(send: suspend (FeedbackSubmission) -> FeedbackReceipt = { sent += it; FeedbackReceipt(7, null) }): FeedbackViewModel {
        val dispatcher = StandardTestDispatcher(testScheduler)
        return FeedbackViewModel(send, appVersion = "1.0", osVersion = "Android 15", io = dispatcher, scope = this)
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
        assertTrue(vm.form.value!!.editable && vm.form.value!!.canSubmit)
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
    fun submitValidatesFirst() = runTest {
        val vm = model()
        vm.open(FeedbackKind.Bug)
        vm.submit()
        assertEquals(FeedbackProblem.MissingTitle.message, vm.form.value!!.error)
        vm.edit { it.copy(title = "[Bug] Crash") }
        assertNull(vm.form.value!!.error)
        vm.submit()
        assertEquals(FeedbackProblem.MissingDescription.message, vm.form.value!!.error)
        advanceUntilIdle()
        assertTrue(sent.isEmpty())
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
        advanceUntilIdle()
        assertEquals(FeedbackPhase.Sent(FeedbackReceipt(7, null)), vm.form.value!!.phase)
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
        val vm = model { if (attempt++ == 0) throw FeedbackException.forStatus(429) else throw IllegalStateException("boom") }
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
        val gate = CompletableDeferred<FeedbackReceipt>()
        val vm = model { gate.await() }
        vm.open(FeedbackKind.Bug)
        vm.fill()
        vm.submit()
        advanceUntilIdle()
        vm.requestClose()
        assertTrue(vm.form.value!!.confirmingDiscard)
        vm.confirmDiscard()
        gate.complete(FeedbackReceipt(1, null))
        advanceUntilIdle()
        assertNull(vm.form.value)
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
