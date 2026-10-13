package com.festivalscoretracker.android.presentation

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

// region Publication catch-up

/**
 * Keeps a publication-bound [RetryingLoader] value caught up with the newest observed
 * publication (issue #616; web `PublicationBoundary`, Apple `PublicationRefreshBoundary`,
 * load-transition R9).
 *
 * When [publications] reports a generation newer than the loaded value's, the loader re-reads
 * once for that generation through [RetryingLoader.catchUp], whether the newer generation came
 * from the live socket or from another read (the notifications bell, a player page). Pages
 * show [pending] as an in-place refresh rather than pausing their rows; a catch-up that fails
 * or comes back still behind settles, so the page falls back to its own paused state instead
 * of spinning, and a later generation tries again.
 *
 * @param T Loaded value.
 * @param scope Owner scope (a `viewModelScope`).
 * @param loader The page's publication-bound read.
 * @param publications Newest observed generation (usually `FestivalApi.publicationChanges`).
 * @param publicationOf Generation a loaded value was read at.
 */
class PublicationCatchUp<T>(
    private val scope: CoroutineScope,
    private val loader: RetryingLoader<T>,
    publications: Flow<Int?>,
    private val publicationOf: (T) -> Int,
) {
    private val settledFlow = MutableStateFlow<Int?>(null)
    private var attempted: Int? = null

    /** Newest generation whose catch-up finished without reaching it (see [pending]). */
    val settled: StateFlow<Int?> = settledFlow.asStateFlow()

    init {
        scope.launch {
            combine(loader.state, publications) { state, observed -> state to observed }.collect { (state, observed) -> check(state, observed) }
        }
    }

    private fun check(state: LoadState<T>, observed: Int?) {
        val loaded = state as? LoadState.Loaded ?: return
        if (observed == null || publicationOf(loaded.value) >= observed || loaded.refreshing) return
        if (attempted == observed) {
            settle(observed)
            return
        }
        attempted = observed
        val job = loader.catchUp()
        scope.launch {
            job.join()
            val after = loader.state.value
            if (after is LoadState.Loaded && !after.refreshing && publicationOf(after.value) < observed) settle(observed)
        }
    }

    private fun settle(observed: Int) {
        if ((settledFlow.value ?: 0) < observed) settledFlow.value = observed
    }

    companion object {
        /**
         * Whether a page should show its in-place publication refresh instead of its content.
         *
         * @param loaded Generation of the loaded value, or null when nothing is loaded.
         * @param observed Newest observed generation.
         * @param settled [settled].
         * @return True while the loaded value is behind and its catch-up has not settled.
         */
        fun pending(loaded: Int?, observed: Int?, settled: Int?): Boolean =
            loaded != null && observed != null && loaded < observed && (settled ?: 0) < observed
    }
}

// endregion
