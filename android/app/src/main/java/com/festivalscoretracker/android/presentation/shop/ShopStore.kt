package com.festivalscoretracker.android.presentation.shop

import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// region Shop store

/**
 * Process-wide Item Shop data shared by the Shop page, Songs and Song Detail
 * (web `ShopContext`). Loaded lazily on first use and reloaded when a newer
 * publication is observed, so a Shop feed is never paired with a different
 * catalogue generation for long. In-process only (online-only).
 *
 * @param load Shop read (`FestivalApi.shop`).
 * @param publications Observed publication stream (`FestivalApi.publicationChanges`).
 * @param backoff Shared retry backoff.
 * @param scope Owner scope (process lifetime on the main thread by default, so [state] is
 *   published on the main thread like a `viewModelScope` loader; issue #707).
 * @param loadDispatcher Dispatcher the read runs on (off the main thread).
 */
class ShopStore(
    load: suspend () -> ShopPayload,
    private val publications: Flow<Int?>,
    backoff: ServiceRetryBackoff,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    loadDispatcher: CoroutineDispatcher = Dispatchers.Default,
) {
    private val loader = RetryingLoader(scope, "shop", backoff) { withContext(loadDispatcher) { load() } }
    private var watching = false

    /** Current Shop state. */
    val state: StateFlow<LoadState<ShopPayload>> = loader.state

    /** Start loading if nothing has started, and follow publication changes afterwards. */
    fun ensureStarted() {
        loader.ensureStarted()
        if (watching) return
        watching = true
        scope.launch {
            publications.filterNotNull().distinctUntilChanged().drop(1).collect { loader.refresh() }
        }
    }

    /** Retry after a failure. */
    fun retry() = loader.retry()

    /** Reload keeping current offers visible. */
    fun refresh() = loader.refresh()
}

// endregion
