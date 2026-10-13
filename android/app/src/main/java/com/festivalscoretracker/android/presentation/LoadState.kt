package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
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
    private val mutableFollowFailed = MutableStateFlow<Int?>(null)
    private var job: Job? = null
    private var followObserved: ((T) -> Int?)? = null
    private var followCurrent: Int? = null

    /** Current state. */
    val state: StateFlow<LoadState<T>> = mutableState.asStateFlow()

    /**
     * The newer publication a [followPublications] refresh could not reach (the read failed or
     * still answered from an older generation), or null. The page keeps its older content and
     * shows its explicit paused state for that generation instead of refreshing again.
     */
    val followFailedFor: StateFlow<Int?> = mutableFollowFailed.asStateFlow()

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

    /**
     * Keep the loaded value on the newest publication (load-transition R9, #616): when the app
     * observes a newer generation than [observed] reports for the loaded value (the live
     * `/api/ws` socket, or any other pinned read such as the notification bell), re-read once
     * in place. Content stays visible as `Loaded(refreshing)` while the read runs; a failed
     * read keeps the older content and records [followFailedFor] so the page shows its
     * paused state rather than an error or a loop. A failure without an automatic retry is
     * retried once on the next new generation. Call once, from the owner's init.
     *
     * @param publications Latest observed publication (`FestivalApi.publicationChanges`).
     * @param observed The generation a loaded value was read in, or null when it carries none.
     */
    fun followPublications(publications: Flow<Int?>, observed: (T) -> Int?) {
        if (followObserved != null) return
        followObserved = observed
        scope.launch {
            var refreshedFor: Int? = null
            var lastSeen: Int? = null
            combine(mutableState, publications.filterNotNull().distinctUntilChanged()) { state, current -> state to current }.collect { (state, current) ->
                val changed = lastSeen != null && lastSeen != current
                lastSeen = current
                followCurrent = current
                when (state) {
                    is LoadState.Loaded -> {
                        if (state.refreshing) return@collect
                        val seen = observed(state.value) ?: return@collect
                        if (seen >= current) {
                            if (mutableFollowFailed.value != null) mutableFollowFailed.value = null
                        } else if (refreshedFor != current) {
                            refreshedFor = current
                            mutableFollowFailed.value = null
                            start(refresh = true, followFor = current)
                        }
                    }
                    is LoadState.Failed -> if (changed && state.countdown == null && refreshedFor != current) {
                        refreshedFor = current
                        retry()
                    }
                    LoadState.Loading -> Unit
                }
            }
        }
    }

    private fun start(refresh: Boolean, followFor: Int? = null) {
        job?.cancel()
        job = scope.launch { run(refresh, followFor) }
    }

    /**
     * Load until success or a non-retrying failure.
     *
     * @param refresh Keep loaded content visible while reading.
     * @param followFor The newer publication a [followPublications] refresh is for: a failure
     *   keeps the previous content, and a failed or still-older read records [followFailedFor].
     */
    private suspend fun run(refresh: Boolean, followFor: Int? = null) {
        var isRefresh = refresh
        while (true) {
            val previous = mutableState.value
            mutableState.value = if (isRefresh && previous is LoadState.Loaded) previous.copy(refreshing = true) else LoadState.Loading
            try {
                val value = loader(isRefresh)
                backoff.reset(key)
                mutableState.value = LoadState.Loaded(value)
                if (followObserved != null) {
                    // Any read that lands behind the newest observed generation ends a follow.
                    val target = followFor ?: followCurrent
                    val seen = followObserved?.invoke(value)
                    if (target != null && seen != null && seen < target) mutableFollowFailed.value = target
                }
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val issue = ServiceIssue.from(error)
                if (followFor != null && previous is LoadState.Loaded) {
                    // A publication follow never swaps shown content for an error (R9).
                    mutableState.value = previous.copy(refreshing = false)
                    mutableFollowFailed.value = followFor
                    return
                }
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
