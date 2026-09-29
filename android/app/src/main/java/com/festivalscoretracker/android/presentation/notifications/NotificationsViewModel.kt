package com.festivalscoretracker.android.presentation.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.notifications.ImprovementNotification
import com.festivalscoretracker.android.core.notifications.NotificationDestination
import com.festivalscoretracker.android.core.notifications.NotificationPresentation
import com.festivalscoretracker.android.core.notifications.NotificationSeenStore
import com.festivalscoretracker.android.core.notifications.NotificationText
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.core.service.ServiceIssue
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// region State

/**
 * One notification row.
 *
 * @property presentation Formatted text and destination.
 * @property unread Whether it is unread.
 * @property timeText Relative time.
 */
data class NotificationRow(val presentation: NotificationPresentation, val unread: Boolean, val timeText: String) {
    /** GUID. */
    val id: String get() = presentation.id

    /** TalkBack text: unread state, title, message and time. */
    val accessibleText: String get() = (if (unread) "Unread. " else "") + "${presentation.title}. ${presentation.message} $timeText"
}

/** Notifications sheet states (control spec). */
sealed interface NotificationsState {
    /** No profile selected: prompt, no request. */
    data object NoPlayer : NotificationsState

    /** First read in flight. */
    data object Loading : NotificationsState

    /**
     * Read failed; Retry.
     *
     * @property issue Shared service issue.
     */
    data class Failed(val issue: ServiceIssue) : NotificationsState

    /**
     * No rows.
     *
     * @property generated Whether a detection run produced the (empty) feed.
     */
    data class Empty(val generated: Boolean) : NotificationsState {
        /** Body copy: "generated but empty" differs from "never generated" (web `notifications.empty.*`). */
        val body: String
            get() = if (generated) {
                "Notifications will appear here when new high scores are set or global ranks improve. Set new high scores and compete with friends to see them!"
            } else {
                "Notifications may appear here after the next leaderboard update. Set new high scores and compete with friends to see them!"
            }
    }

    /**
     * Rows loaded.
     *
     * @property newRows Unread rows ("New").
     * @property olderRows Read rows ("Older").
     */
    data class Loaded(val newRows: List<NotificationRow>, val olderRows: List<NotificationRow>) : NotificationsState
}

// endregion

// region View model

/**
 * Top-bar bell and sheet (Apple `NotificationsCenter`, Windows `NotificationsViewModel`):
 * loads the selected player's feed on selection, launch and each open (no
 * polling), derives unread rows from per-account seen state, and marks rows
 * seen on activation and when the sheet closes. A failed refresh keeps the
 * previous feed.
 *
 * @param player Selected player stream.
 * @param load Feed read for an account.
 * @param seenStore Seen-state persistence.
 * @param songTitle Catalogue title lookup (null until the catalogue loads).
 * @param artwork Absolute album-art URL for a row (catalogue art, else the shop payload's), if any.
 * @param clock Current time for relative labels.
 * @param scope Scope for loads (the view model scope by default).
 */
class NotificationsViewModel(
    player: Flow<SelectedPlayer?>,
    private val load: suspend (String) -> NotificationsEnvelope,
    private val seenStore: NotificationSeenStore,
    private val songTitle: suspend (String) -> String? = { null },
    private val artwork: suspend (ImprovementNotification) -> String? = { null },
    private val clock: () -> Instant = Instant::now,
    scope: CoroutineScope? = null,
) : ViewModel() {
    private val work: CoroutineScope = scope ?: viewModelScope
    private val stateFlow = MutableStateFlow<NotificationsState>(NotificationsState.NoPlayer)
    private val unreadFlow = MutableStateFlow(0)
    private var account: String? = null
    private var envelope: NotificationsEnvelope? = null
    private var loadedAccount: String? = null
    private var job: Job? = null

    /** Current sheet state. */
    val state: StateFlow<NotificationsState> = stateFlow.asStateFlow()

    /** Unread count shown on the bell. */
    val unreadCount: StateFlow<Int> = unreadFlow.asStateFlow()

    init {
        work.launch {
            player.map { it?.accountId }.distinctUntilChanged().collect { id ->
                account = id
                refresh()
            }
        }
    }

    /** Load (or reload) the feed for the selected player; cancels an older read. */
    fun refresh() {
        job?.cancel()
        val id = account
        if (id == null) {
            envelope = null
            loadedAccount = null
            unreadFlow.value = 0
            stateFlow.value = NotificationsState.NoPlayer
            return
        }
        if (loadedAccount != id) {
            envelope = null
            loadedAccount = null
            unreadFlow.value = 0
            stateFlow.value = NotificationsState.Loading
        }
        job = work.launch {
            try {
                val feed = load(id)
                envelope = feed
                loadedAccount = id
                apply()
            } catch (error: Throwable) {
                val issue = ServiceIssue.from(error)
                if (loadedAccount != id) stateFlow.value = NotificationsState.Failed(issue)
            }
        }
    }

    /**
     * Mark one row seen; the caller navigates to the returned destination.
     *
     * @param row Activated row.
     * @return The destination, if any.
     */
    fun activate(row: NotificationRow): NotificationDestination? {
        val id = loadedAccount
        if (id != null && row.unread) {
            work.launch {
                seenStore.markSeen(id, listOf(row.id), feedIds())
                apply()
            }
        }
        return row.presentation.destination
    }

    /** Sheet closed: every loaded row becomes seen and moves to Older. */
    fun markAllSeen() {
        val id = loadedAccount ?: return
        val items = envelope?.items.orEmpty()
        if (items.isEmpty()) return
        work.launch {
            seenStore.markSeen(id, items.map { it.notificationGuid }, feedIds())
            apply()
        }
    }

    private fun feedIds(): List<String> = envelope?.items.orEmpty().map { it.notificationGuid }

    private suspend fun apply() {
        val id = loadedAccount ?: return
        val feed = envelope ?: return
        val seen = seenStore.seen(id)
        val now = clock()
        val rows = feed.items.orEmpty().sortedByDescending { it.detectedInstant }.map { item ->
            val title = item.songId?.let { songTitle(it) }
            NotificationRow(NotificationText.format(item, title, artwork(item)), item.notificationGuid !in seen, NotificationText.relativeTime(item.detectedInstant, now))
        }
        val (fresh, older) = rows.partition { it.unread }
        unreadFlow.value = fresh.size
        stateFlow.value = if (rows.isEmpty()) NotificationsState.Empty(feed.isGenerated) else NotificationsState.Loaded(fresh, older)
    }

    companion object {
        /**
         * Badge text (capped at 99+).
         *
         * @param count Unread count.
         * @return Text.
         */
        fun badgeText(count: Int): String = if (count > 99) "99+" else count.toString()

        /**
         * TalkBack name for the bell.
         *
         * @param count Unread count.
         * @return Label.
         */
        fun bellLabel(count: Int): String = when (count) {
            0 -> "Notifications"
            1 -> "Notifications, 1 unread"
            else -> "Notifications, $count unread"
        }
    }
}

// endregion
