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
        start(refresh = false)
    }

    /** Reload while keeping current content visible (pull to refresh). */
    fun refresh() {
        start(refresh = true)
    }

    private fun start(refresh: Boolean) {
        job?.cancel()
        job = scope.launch { run(refresh) }
    }

    private suspend fun run(refresh: Boolean) {
        var isRefresh = refresh
        while (true) {
            val previous = mutableState.value
            mutableState.value = if (isRefresh && previous is LoadState.Loaded) previous.copy(refreshing = true) else LoadState.Loading
            try {
                val value = loader(isRefresh)
                backoff.reset(key)
                mutableState.value = LoadState.Loaded(value)
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
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
            }
        }
    }
}

// endregion
