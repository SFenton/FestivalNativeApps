package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region Load state

/** A screen or section's load state, rendered by the shared service-status views. */
sealed interface LoadState<out T> {
    /** First load in flight. */
    data object Loading : LoadState<Nothing>

    /**
     * Content available.
     *
     * @property value Loaded value.
     * @property refreshing Whether a user refresh is in flight over it.
     */
    data class Loaded<T>(val value: T, val refreshing: Boolean = false) : LoadState<T>

    /**
     * Load failed.
     *
     * @property issue Classified failure.
     * @property countdown Seconds until an automatic retry (scrape freeze only), else null.
     */
    data class Failed(val issue: ServiceIssue, val countdown: Int? = null) : LoadState<Nothing>
}

/** The loaded value, or null. */
val <T> LoadState<T>.valueOrNull: T? get() = (this as? LoadState.Loaded<T>)?.value

// endregion

// region Retrying loader

/**
 * Runs one read with the shared service-status semantics: a scrape freeze counts
 * down (honouring `Retry-After` with capped backoff) and retries automatically;
 * every other issue waits for [retry]. A newer load cancels an older one so a late
 * error never overwrites a newer success.
 *
 * @property scope Owner scope (a `viewModelScope`).
 * @property key Backoff scope identifier.
 * @property backoff Shared backoff history.
 * @property loader The read.
 */
class RetryingLoader<T>(
    private val scope: CoroutineScope,
    private val key: String,
    private val backoff: ServiceRetryBackoff,
    private val loader: suspend (refresh: Boolean) -> T,
) {
    private val mutableState = MutableStateFlow<LoadState<T>>(LoadState.Loading)
    private var job: Job? = null

    /** Current state. */
    val state: StateFlow<LoadState<T>> = mutableState.asStateFlow()

    /** Start the first load if nothing has started yet. */
    fun ensureStarted() {
        if (job == null) retry()
    }

    /** Load now, showing the loading state (used by Retry / Retry Now). */
    fun retry() {
        start(keepContent = false, reread = false, keepOnFailure = false)
    }

    /** Reload while keeping current content visible (pull to refresh). */
    fun refresh() {
        start(keepContent = true, reread = true, keepOnFailure = false)
    }

    /**
     * Reload in the background for a newer publication ([PublicationCatchUp], issue #616): like
     * [refresh], but the read is a plain load (`refresh = false`: the publication was already
     * observed, so it is not re-read) and a failure keeps the current content (no error page, no
     * countdown), so the page shows its own paused state instead of losing its rows.
     *
     * @return The load, finished once the value is replaced or kept.
     */
    fun catchUp(): Job = start(keepContent = true, reread = false, keepOnFailure = true)

    private fun start(keepContent: Boolean, reread: Boolean, keepOnFailure: Boolean): Job {
        job?.cancel()
        // Mark the refresh at once, so observers never see the old value as settled in between.
        val previous = mutableState.value
        if (keepContent && previous is LoadState.Loaded) mutableState.value = previous.copy(refreshing = true)
        return scope.launch { run(keepContent, reread, keepOnFailure) }.also { job = it }
    }

    private suspend fun run(keepContent: Boolean, reread: Boolean, keepOnFailure: Boolean) {
        var isRefresh = keepContent
        var isReread = reread
        while (true) {
            val previous = mutableState.value
            mutableState.value = if (isRefresh && previous is LoadState.Loaded) previous.copy(refreshing = true) else LoadState.Loading
            try {
                val value = loader(isReread)
                backoff.reset(key)
                mutableState.value = LoadState.Loaded(value)
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (keepOnFailure && previous is LoadState.Loaded) {
                    mutableState.value = previous.copy(refreshing = false)
                    return
                }
                val issue = ServiceIssue.from(error)
                if (!issue.retriesAutomatically) {
                    mutableState.value = LoadState.Failed(issue)
                    return
                }
                var remaining = backoff.nextDelay(key, issue.retryAfterSeconds)
                while (remaining > 0) {
                    mutableState.value = LoadState.Failed(issue, remaining)
                    delay(1_000)
                    remaining--
                }
                isRefresh = false
                isReread = false
            }
        }
    }
}

// endregion
