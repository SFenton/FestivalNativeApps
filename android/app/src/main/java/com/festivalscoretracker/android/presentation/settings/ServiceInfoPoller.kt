package com.festivalscoretracker.android.presentation.settings

import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoPhase
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoSnapshot
import com.festivalscoretracker.android.core.serviceinfo.ServiceProgressMemory
import com.festivalscoretracker.android.core.serviceinfo.ServiceProgressReducer
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// region Poller

/**
 * Polls `GET /api/service-info` while Settings is visible and reduces each read through the
 * web's monotonic progress rules (web `useServiceInfo('settings')` + `SettingsServiceProgressCard`,
 * Apple `SettingsServiceInfoModel`). The caller runs [poll] inside a lifecycle-bound coroutine
 * (`repeatOnLifecycle(STARTED)` on the Settings screen), so polling stops when Settings leaves
 * composition or the app goes to the background; the progress memory survives in between.
 *
 * @param read One service-info read.
 * @param interval Web cadence (`SERVICE_INFO_SETTINGS_POLL_MS` / `…_UNAVAILABLE_RETRY_MS`): 5 s either way.
 */
class ServiceInfoPoller(
    private val read: suspend () -> ServiceInfoSnapshot,
    private val interval: Duration = 5.seconds,
) {
    private val phaseFlow = MutableStateFlow<ServiceInfoPhase>(ServiceInfoPhase.Loading)
    private var memory: ServiceProgressMemory? = null

    /** Latest poll phase. */
    val phase: StateFlow<ServiceInfoPhase> = phaseFlow.asStateFlow()

    /**
     * Fold one read (or failure) into the displayed state. A failure after a success shows the
     * failure rather than silently keeping old progress.
     *
     * @param result Latest read.
     */
    fun apply(result: Result<ServiceInfoSnapshot>) {
        phaseFlow.value = result.fold(
            onSuccess = { snapshot ->
                val (display, next) = ServiceProgressReducer.reduce(memory, snapshot.info)
                memory = next
                ServiceInfoPhase.Loaded(snapshot, display)
            },
            onFailure = { ServiceInfoPhase.Failed },
        )
    }

    /** Read, then wait [interval], until the calling coroutine is cancelled. */
    suspend fun poll() {
        while (true) {
            val result = try {
                Result.success(read())
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                Result.failure(error)
            }
            apply(result)
            delay(interval)
        }
    }
}

// endregion
