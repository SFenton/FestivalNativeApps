package com.festivalscoretracker.android.presentation.feedback

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackDraft
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackReceipt
import com.festivalscoretracker.android.core.feedback.FeedbackSubmission
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// region State

/** Where an open feedback form is. */
sealed interface FeedbackPhase {
    /** The user is editing (also after a failure, keeping every field). */
    data object Editing : FeedbackPhase

    /** The POST is in flight; fields are read-only and a progress indicator shows. */
    data object Submitting : FeedbackPhase

    /**
     * The service accepted the form.
     *
     * @property receipt Issue number/URL when reported.
     */
    data class Sent(val receipt: FeedbackReceipt) : FeedbackPhase
}

/**
 * One open feedback form.
 *
 * @property draft Field values and attachments.
 * @property phase Editing, sending or sent.
 * @property error Readable failure (validation or send), shown above the actions.
 * @property notice Readable note about skipped attachments.
 * @property confirmingDiscard Whether the discard confirmation is showing.
 */
data class FeedbackFormState(
    val draft: FeedbackDraft,
    val phase: FeedbackPhase = FeedbackPhase.Editing,
    val error: String? = null,
    val notice: String? = null,
    val confirmingDiscard: Boolean = false,
) {
    /** Whether the fields and Attach Media accept input. */
    val editable: Boolean get() = phase == FeedbackPhase.Editing

    /** Whether Submit is enabled (validation failures are reported on tap, not by disabling). */
    val canSubmit: Boolean get() = phase == FeedbackPhase.Editing
}

// endregion

// region View model

/**
 * Settings → Report an Issue / Request a Feature (issue #78). Holds at most one open form so
 * it survives configuration changes; closing with unsent input asks first.
 *
 * @param send Sends one submission (`FestivalApi.submitFeedback` with the content resolver).
 * @param appVersion App version reported with the form.
 * @param osVersion OS description reported with the form.
 * @param platform Platform label (`android`).
 * @param io Dispatcher for attachment reads and the upload.
 * @param scope Scope for the upload (the view model scope by default).
 */
class FeedbackViewModel(
    private val send: suspend (FeedbackSubmission) -> FeedbackReceipt,
    private val appVersion: String,
    private val osVersion: String,
    private val platform: String = FeedbackSubmission.PLATFORM_ANDROID,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    scope: CoroutineScope? = null,
) : ViewModel() {
    private val work: CoroutineScope = scope ?: viewModelScope
    private val formFlow = MutableStateFlow<FeedbackFormState?>(null)
    private var job: Job? = null

    /** The open form, or null when closed. */
    val form: StateFlow<FeedbackFormState?> = formFlow.asStateFlow()

    /**
     * Open a fresh form (no-op while another form is open: one modal at a time).
     *
     * @param kind Bug or Feature.
     */
    fun open(kind: FeedbackKind) {
        if (formFlow.value != null) return
        formFlow.value = FeedbackFormState(FeedbackDraft(kind))
    }

    /**
     * Edit the draft while editing; clears a stale error.
     *
     * @param transform Draft change.
     */
    fun edit(transform: (FeedbackDraft) -> FeedbackDraft) {
        formFlow.update { state ->
            if (state == null || !state.editable) state else state.copy(draft = transform(state.draft), error = null)
        }
    }

    /**
     * Add picked media (duplicates, non-media and over-limit picks are skipped with a notice).
     *
     * @param picked Picked attachments.
     */
    fun addAttachments(picked: List<FeedbackAttachment>) {
        if (picked.isEmpty()) return
        formFlow.update { state ->
            if (state == null || !state.editable) return@update state
            val result = state.draft.adding(picked)
            state.copy(draft = state.draft.copy(attachments = result.attachments), notice = result.notice)
        }
    }

    /**
     * Remove one attachment.
     *
     * @param id Attachment ID.
     */
    fun removeAttachment(id: String) {
        edit { draft -> draft.copy(attachments = draft.attachments.filterNot { it.id == id }) }
        formFlow.update { it?.copy(notice = null) }
    }

    /** Close, Back or Cancel: closes at once unless unsent input would be lost. */
    fun requestClose() {
        val state = formFlow.value ?: return
        if (state.phase is FeedbackPhase.Sent || (state.phase == FeedbackPhase.Editing && !state.draft.isDirty)) {
            close()
        } else {
            formFlow.value = state.copy(confirmingDiscard = true)
        }
    }

    /** Discard confirmed: cancel any upload and close. */
    fun confirmDiscard() = close()

    /** Keep Editing: dismiss the confirmation. */
    fun keepEditing() {
        formFlow.update { it?.copy(confirmingDiscard = false) }
    }

    /** Validate, then send; failure keeps every field and shows a readable error. */
    fun submit() {
        val state = formFlow.value ?: return
        if (!state.canSubmit) return
        state.draft.problem?.let { problem ->
            formFlow.value = state.copy(error = problem.message)
            return
        }
        val submission = state.draft.submission(platform, appVersion, osVersion)
        formFlow.value = state.copy(phase = FeedbackPhase.Submitting, error = null)
        job = work.launch {
            val outcome = try {
                Result.success(withContext(io) { send(submission) })
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: FeedbackException) {
                Result.failure(error)
            } catch (error: Exception) {
                Result.failure(FeedbackException.offline())
            }
            formFlow.update { current ->
                if (current == null) return@update null
                outcome.fold(
                    onSuccess = { current.copy(phase = FeedbackPhase.Sent(it), error = null, confirmingDiscard = false) },
                    onFailure = { current.copy(phase = FeedbackPhase.Editing, error = it.message) },
                )
            }
        }
    }

    private fun close() {
        job?.cancel()
        job = null
        formFlow.value = null
    }
}

// endregion
