package com.festivalscoretracker.android.presentation.whatsnew

import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.InstallChannel
import com.festivalscoretracker.android.core.whatsnew.WhatsNewGate
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// region Controller

/**
 * One "What's New" presentation.
 *
 * @property isReplay Opened from Settings rather than owed at launch.
 */
data class WhatsNewPresentation(val isReplay: Boolean)

/**
 * Process-wide "What's New" state (Apple `WhatsNewLauncher`, Windows `MainWindow.WhatsNew`):
 * resolves the launch gate once per process, presents the owed sheet only when the shared
 * first-run slot is free (so a launch carousel shows first, like the web), replays from
 * Settings, and records the dismissal either way.
 *
 * @property store Dismissal persistence.
 * @property center Shared first-run slot arbiter.
 * @property mode Launch mode (debug defaults to [WhatsNewMode.Off]).
 * @property version App version shown in the title and stored on dismissal.
 * @property channel How the app was installed: tester installs see the tester notes (resolved
 *   synchronously at startup, so the sheet never shows the store view while detection is pending).
 */
class WhatsNewController(
    private val store: ChangelogSeenStore,
    private val center: FirstRunCenter,
    val mode: WhatsNewMode,
    val version: String,
    val channel: InstallChannel = InstallChannel.Store,
) {
    private val mutex = Mutex()
    private val shownFlow = MutableStateFlow<WhatsNewPresentation?>(null)
    private var resolved = false
    private var pending = false

    /** The sheet currently shown, if any. */
    val shown: StateFlow<WhatsNewPresentation?> = shownFlow.asStateFlow()

    /**
     * Resolve the launch gate the first time only (a `fresh` reset happens once per process).
     *
     * @return Whether the launch sheet is still owed.
     */
    suspend fun resolveIfNeeded(): Boolean = mutex.withLock { resolveLocked() }

    private suspend fun resolveLocked(): Boolean {
        if (!resolved) {
            resolved = true
            if (mode == WhatsNewMode.Fresh) store.reset()
            pending = WhatsNewGate.isPending(mode, store.shouldShow())
        }
        return pending
    }

    /**
     * Present the owed launch sheet if the slot is free.
     *
     * @return True when the sheet is now shown.
     */
    suspend fun presentIfOwed(): Boolean = mutex.withLock {
        if (!resolveLocked() || shownFlow.value != null || !center.claim(WhatsNewGate.SLOT_KEY)) return false
        pending = false
        shownFlow.value = WhatsNewPresentation(isReplay = false)
        true
    }

    /**
     * Settings "Show": present regardless of the stored dismissal.
     *
     * @return True when shown; false while it or a carousel is already showing.
     */
    suspend fun replay(): Boolean = mutex.withLock {
        if (shownFlow.value != null || !center.claim(WhatsNewGate.SLOT_KEY)) return false
        shownFlow.value = WhatsNewPresentation(isReplay = true)
        true
    }

    /** Close (Dismiss, Close, back, swipe or outside tap alike): record the dismissal and free the slot. */
    suspend fun dismiss() = mutex.withLock {
        if (shownFlow.value == null) return
        store.markSeen(version)
        shownFlow.value = null
        center.release(WhatsNewGate.SLOT_KEY)
    }
}

// endregion
