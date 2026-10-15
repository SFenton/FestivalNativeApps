package com.festivalscoretracker.android.presentation.feedback

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackCopy
import com.festivalscoretracker.android.core.feedback.FeedbackDraft
import com.festivalscoretracker.android.core.feedback.FeedbackException
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.core.feedback.FeedbackJob
import com.festivalscoretracker.android.core.feedback.FeedbackJobState
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
import kotlinx.coroutines.delay as sleep

// region State

/** Where an open feedback form is. */
sealed interface FeedbackPhase {
    /** The user is editing (also after a failure, keeping every field). */
    data object Editing : FeedbackPhase

    /** The POST is in flight; fields are read-only and a progress indicator shows. */
    data object Submitting : FeedbackPhase

    /**
     * The service accepted the form (202) and is filing it; the app polls its status.
     *
     * @property job Latest known job.
     */
    data class Filing(val job: FeedbackJob) : FeedbackPhase

}

/**
 * A filed (or received) form's result, shown as an alert over Settings after the form has
 * closed (issue #565): the form never stays open behind its own success message.
 *
 * @property kind Bug or Feature, for the alert's title and copy.
 * @property job Final known job: filed, or accepted with an unknown outcome (reported as
 * received, never as an error).
 */
data class FeedbackSent(val kind: FeedbackKind, val job: FeedbackJob) {
    /** Alert title: "Report Sent" or "Request Sent" (the Apple wording). */
    val title: String get() = if (kind == FeedbackKind.Bug) "Report Sent" else "Request Sent"

    /** Alert body: the spec's fixed outcome copy. */
    val message: String get() = job.message(kind)
}

/**
 * The busy view that replaces the form's fields while it is sent and filed (owner, issue #634):
 * one spinner that stays put, and a title with either a progress bar or a subtitle under it.
 *
 * @property step Which step it is; the title, subtitle and bar cross-fade only when this changes.
 * @property title "Uploading Media", "Filing Issue" or "Filing Request".
 * @property subtitle Text under the title, or null when the progress bar is the subtitle.
 * @property showsBar Whether the upload bar is the subtitle.
 * @property progress Upload fraction 0…1 for the bar, or null when the body's length is unknown.
 */
data class FeedbackBusyStatus(
    val step: Step,
    val title: String,
    val subtitle: String?,
    val showsBar: Boolean,
    val progress: Float?,
) {
    /** The two busy steps, in order. */
    enum class Step { Uploading, Filing }

    companion object {
        /**
         * The upload step: "Uploading Media" over a determinate bar.
         *
         * @param progress Fraction sent, or null when unknown.
         * @return Status.
         */
        fun uploading(progress: Float?): FeedbackBusyStatus =
            FeedbackBusyStatus(Step.Uploading, FeedbackCopy.UPLOADING_TITLE, null, showsBar = true, progress = progress)

        /**
         * The filing step: "Filing Issue/Request" over the owner's sentence.
         *
         * @param kind Form.
         * @return Status.
         */
        fun filing(kind: FeedbackKind): FeedbackBusyStatus =
            FeedbackBusyStatus(Step.Filing, FeedbackCopy.filingTitle(kind), FeedbackCopy.filingSubtitle(kind), showsBar = false, progress = null)
    }
}

/**
 * One open feedback form.
 *
 * @property draft Field values and attachments.
 * @property phase Editing, sending or filing.
 * @property error Readable send or filing failure, shown above the fields.
 * @property notice Readable note about skipped attachments.
 * @property confirmingDiscard Whether the discard confirmation is showing.
 * @property uploadProgress Fraction of the request sent while [FeedbackPhase.Submitting], or null when unknown.
 */
data class FeedbackFormState(
    val draft: FeedbackDraft,
    val phase: FeedbackPhase = FeedbackPhase.Editing,
    val error: String? = null,
    val notice: String? = null,
    val confirmingDiscard: Boolean = false,
    val uploadProgress: Float? = null,
) {
    /** Whether the fields and Attach Media accept input. */
    val editable: Boolean get() = phase == FeedbackPhase.Editing

    /** Whether Submit is enabled: editing and valid (the spec's `invalid` state disables it). */
    val canSubmit: Boolean get() = phase == FeedbackPhase.Editing && draft.problem == null

    /** Inline reason Submit is disabled while editing an invalid draft, or null. */
    val validationMessage: String? get() = if (phase == FeedbackPhase.Editing) draft.problem?.message else null

    /** Whether the send or filing progress shows. */
    val busy: Boolean get() = phase == FeedbackPhase.Submitting || phase is FeedbackPhase.Filing

    /**
     * The busy view's content, or null while editing. A form without attachments has no media
     * to upload, so its short text-only send already reads as filing (agent decision, issue #634):
     * "Uploading Media" would be inaccurate and would flash for a fraction of a second.
     */
    val busyStatus: FeedbackBusyStatus?
        get() = when (phase) {
            FeedbackPhase.Editing -> null
            FeedbackPhase.Submitting ->
                if (draft.attachments.isEmpty()) FeedbackBusyStatus.filing(draft.kind) else FeedbackBusyStatus.uploading(uploadProgress)
            is FeedbackPhase.Filing -> FeedbackBusyStatus.filing(draft.kind)
        }
}

// endregion

// region View model

/**
 * Settings → Report an Issue / Request a Feature (issue #78). Holds at most one open form so
 * it survives configuration changes; closing with unsent input asks first. After the service
 * accepts a form it polls the job until it is filed, fails or [POLL_TIMEOUT_MS] passes. A filed
 * or received form closes and its result moves to [sent] (one presentation at a time, #565).
 *
 * @param send Sends one submission (`FestivalApi.submitFeedback` with the content resolver),
 * reporting upload progress (0…1, or null when unknown) through its second argument.
 * @param status Reads an accepted job (`FestivalApi.feedbackStatus`).
 * @param features Reads whether the service accepts feedback (`FestivalApi.feedbackEnabled`).
 * @param appVersion App version reported with the form.
 * @param clientInfo OS and device description reported with the form.
 * @param platform Platform label (`android`).
 * @param io Dispatcher for attachment reads, the upload and status reads.
 * @param scope Scope for the work (the view model scope by default).
 * @param now Monotonic clock in milliseconds for the polling deadline.
 */
class FeedbackViewModel(
    private val send: suspend (FeedbackSubmission, (Float?) -> Unit) -> FeedbackJob,
    private val status: suspend (String) -> FeedbackJob,
    private val features: suspend () -> Boolean,
    private val appVersion: String,
    private val clientInfo: String,
    private val platform: String = FeedbackSubmission.PLATFORM_ANDROID,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    scope: CoroutineScope? = null,
    private val now: () -> Long = { System.nanoTime() / 1_000_000 },
) : ViewModel() {
    private val work: CoroutineScope = scope ?: viewModelScope
    private val formFlow = MutableStateFlow<FeedbackFormState?>(null)
    private val availableFlow = MutableStateFlow(false)
    private val sentFlow = MutableStateFlow<FeedbackSent?>(null)
    private var job: Job? = null
    private var featuresJob: Job? = null

    /** The open form, or null when closed. */
    val form: StateFlow<FeedbackFormState?> = formFlow.asStateFlow()

    /** Whether the Settings rows show: only after `/api/features` reports `feedback: true`. */
    val available: StateFlow<Boolean> = availableFlow.asStateFlow()

    /** The result alert to show over Settings once a form has closed after filing, or null. */
    val sent: StateFlow<FeedbackSent?> = sentFlow.asStateFlow()

    /** Done (or Back) on the result alert. */
    fun dismissSent() {
        sentFlow.value = null
    }

    /**
     * Read the service flag once per Settings visit until it succeeds; a failure keeps the rows
     * hidden and the next visit retries. No-op while a read is in flight or after it reported true.
     */
    fun loadAvailability() {
        if (availableFlow.value || featuresJob?.isActive == true) return
        featuresJob = work.launch {
            availableFlow.value = try {
                withContext(io) { features() }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                false
            }
        }
    }

    /**
     * Open a fresh form (no-op while another form is open: one modal at a time).
     *
     * @param kind Bug or Feature.
     */
    fun open(kind: FeedbackKind) {
        if (formFlow.value != null || sentFlow.value != null) return
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
        // While filing the service already holds the form: stop waiting without asking.
        if (state.phase is FeedbackPhase.Filing ||
            (state.phase == FeedbackPhase.Editing && !state.draft.isDirty)
        ) {
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

    /** Send a valid draft, then follow filing; failure keeps every field and shows a readable error. No-op while invalid. */
    fun submit() {
        val state = formFlow.value ?: return
        if (!state.canSubmit) return
        val submission = state.draft.submission(platform, appVersion, clientInfo)
        formFlow.value = state.copy(phase = FeedbackPhase.Submitting, error = null, uploadProgress = 0f)
        job = work.launch {
            val accepted = try {
                withContext(io) { send(submission, ::reportUpload) }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: FeedbackException) {
                fail(error.message)
                return@launch
            } catch (error: Exception) {
                fail(FeedbackException.offline().message)
                return@launch
            }
            formFlow.update { it?.copy(phase = FeedbackPhase.Filing(accepted), error = null, confirmingDiscard = false) }
            val final = follow(accepted)
            val current = formFlow.value ?: return@launch
            if (final.state == FeedbackJobState.Failed) {
                formFlow.value = current.copy(phase = FeedbackPhase.Editing, error = FeedbackException.filingFailed(current.draft.kind).message)
            } else {
                // Close the form first, then show the result over Settings: never both at once (modal-shell R7).
                formFlow.value = null
                job = null
                sentFlow.value = FeedbackSent(current.draft.kind, final)
            }
        }
    }

    private fun fail(message: String?) {
        formFlow.update { it?.copy(phase = FeedbackPhase.Editing, error = message ?: FeedbackException.offline().message) }
    }

    /**
     * Record upload progress from the writing thread, in whole-percent steps so a large video
     * doesn't recompose the bar for every buffer. Ignored once the form has left sending.
     *
     * @param fraction Fraction sent, or null when the length is unknown.
     */
    internal fun reportUpload(fraction: Float?) {
        val stepped = fraction?.let { (it.coerceIn(0f, 1f) * 100).toInt() / 100f }
        formFlow.update { state ->
            if (state == null || state.phase != FeedbackPhase.Submitting || state.uploadProgress == stepped) state
            else state.copy(uploadProgress = stepped)
        }
    }

    /**
     * Poll an accepted job until it is filed or fails. Without an ID, after [POLL_TIMEOUT_MS], or when
     * a status read fails (expired, unknown, offline), return the last known state so the form reports
     * it as received rather than inviting a duplicate.
     */
    private suspend fun follow(accepted: FeedbackJob): FeedbackJob {
        val id = accepted.id
        if (accepted.isTerminal || id == null) return accepted
        var latest = accepted
        val deadline = now() + POLL_TIMEOUT_MS
        while (now() < deadline) {
            sleep(POLL_INTERVAL_MS)
            latest = try {
                withContext(io) { status(id) }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                return latest
            }
            val seen = latest
            formFlow.update { current -> if (current?.phase is FeedbackPhase.Filing) current.copy(phase = FeedbackPhase.Filing(seen)) else current }
            if (latest.isTerminal) return latest
        }
        return latest
    }

    private fun close() {
        job?.cancel()
        job = null
        formFlow.value = null
    }

    companion object {
        /** Time between status reads (the web polls every 1.5 s; the service rate-limits it as a public read). */
        const val POLL_INTERVAL_MS = 2_000L

        /** How long the form follows filing before reporting the form as received. */
        const val POLL_TIMEOUT_MS = 5 * 60_000L
    }
}

// endregion
