package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.presentation.LoadState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region State

/** Lifecycle of the selected player's process-only scores. */
enum class SelectedProfileStatus {
    /** No player selected. */
    None,

    /** Read in flight (earlier scores already cleared). */
    Loading,

    /** Scores available for [SelectedProfileState.observedPublicationId]. */
    Available,

    /** HTTP 202: registered, not yet published. Never an empty success. */
    Syncing,

    /** The read failed; see [SelectedProfileState.issue]. */
    Failed,
}

/**
 * The selected player's identity and scores. Only the identity persists (DataStore);
 * scores are process-only and cleared on switch, deselect, retry, failure and
 * publication change.
 *
 * @property player Selected identity, or null.
 * @property status Scores lifecycle.
 * @property payload Validated read while [status] is Available or Syncing.
 * @property issue Failure while [status] is Failed.
 * @property countdown Seconds until an automatic retry (scrape freeze), else null.
 * @property scoreIndex Song ID → chart → score, only while Available (built once per read).
 */
data class SelectedProfileState(
    val player: SelectedPlayer? = null,
    val status: SelectedProfileStatus = SelectedProfileStatus.None,
    val payload: PlayerProfilePayload? = null,
    val issue: ServiceIssue? = null,
    val countdown: Int? = null,
    val scoreIndex: Map<String, Map<Instrument, PlayerScore>>? = null,
) {
    /** Generation the scores were observed under; compare with the Songs catalogue before projecting. */
    val observedPublicationId: Int? get() = payload?.observedPublicationId

    /** The same read as a [LoadState] for screens that render the shared status views. */
    val load: LoadState<PlayerProfilePayload>
        get() = when (status) {
            SelectedProfileStatus.Available, SelectedProfileStatus.Syncing -> payload?.let { LoadState.Loaded(it) } ?: LoadState.Loading
            SelectedProfileStatus.Failed -> LoadState.Failed(issue ?: ServiceIssue.Other("Profile unavailable"), countdown)
            else -> LoadState.Loading
        }
}

// endregion

// region Store

/**
 * Process-wide selected-player scores (Windows `FestivalSession.Profile`). The shell
 * feeds it the effective selected identity; Songs, Statistics and the player page
 * read [state] instead of reading `/api/player/{id}` again.
 *
 * @param read `FestivalApi.playerProfile`.
 * @param publications Latest observed publication (`FestivalApi.publicationChanges`).
 * @param backoff Shared scrape-freeze backoff.
 */
class SelectedProfileStore(
    private val read: suspend (String) -> PlayerProfilePayload,
    private val publications: StateFlow<Int?>,
    private val backoff: ServiceRetryBackoff,
) {
    private val mutableState = MutableStateFlow(SelectedProfileState())
    private var scope: CoroutineScope? = null
    private var job: Job? = null

    /** Current state. */
    val state: StateFlow<SelectedProfileState> = mutableState.asStateFlow()

    /**
     * Follow the effective selected identity and reload when the publication advances.
     *
     * @param scope Owner scope (the app root composition).
     * @param players Effective selected player (settings plus debug override).
     */
    fun start(scope: CoroutineScope, players: Flow<SelectedPlayer?>) {
        this.scope = scope
        scope.launch { players.collect(::onPlayer) }
        scope.launch {
            publications.collect { id ->
                val current = mutableState.value
                val held = current.payload
                if (id != null && held != null && held.observedPublicationId != id &&
                    current.status in setOf(SelectedProfileStatus.Available, SelectedProfileStatus.Syncing)
                ) {
                    reload()
                }
            }
        }
    }

    /**
     * Apply a new effective identity: a switch or deselect drops the previous scores.
     *
     * @param player Selected identity.
     */
    fun onPlayer(player: SelectedPlayer?) {
        val current = mutableState.value
        if (player == null) {
            job?.cancel()
            mutableState.value = SelectedProfileState()
            return
        }
        if (current.player?.accountId.equals(player.accountId, ignoreCase = true)) {
            if (current.player != player) mutableState.value = current.copy(player = player)
            if (current.status != SelectedProfileStatus.None && !wasInterrupted(current)) return
        }
        val held = current.payload
        if (held != null && held.belongsTo(player.accountId)) {
            mutableState.value = current.copy(player = player)
            return
        }
        mutableState.value = SelectedProfileState(player = player, status = SelectedProfileStatus.Loading)
        reload()
    }

    /**
     * Seed the scores from the read that backed an explicit Select (no second read).
     *
     * @param player Identity being selected.
     * @param payload Selectable read for the same account.
     */
    fun seed(player: SelectedPlayer, payload: PlayerProfilePayload) {
        if (!payload.belongsTo(player.accountId)) return
        job?.cancel()
        apply(player, payload)
    }

    /** Clear and re-read the selected player's scores (Retry). */
    fun retry() {
        reload()
    }

    /**
     * Whether a read or retry countdown for [current] stopped without settling because its
     * owner scope ended (an activity recreated mid-read, e.g. after a font-size change).
     *
     * @param current Current state for the same account.
     * @return True when the read must be resumed rather than kept as is.
     */
    private fun wasInterrupted(current: SelectedProfileState): Boolean {
        if (job?.isActive == true) return false
        return current.status == SelectedProfileStatus.Loading ||
            (current.status == SelectedProfileStatus.Failed && (current.countdown ?: 0) > 0)
    }

    private fun reload() {
        val player = mutableState.value.player ?: return
        val owner = scope ?: return
        job?.cancel()
        job = owner.launch { run(player) }
    }

    private suspend fun run(player: SelectedPlayer) {
        val key = "selected-profile:${player.accountId}"
        while (true) {
            mutableState.value = SelectedProfileState(player = player, status = SelectedProfileStatus.Loading)
            try {
                val payload = read(player.accountId)
                if (!mutableState.value.player?.accountId.equals(player.accountId, ignoreCase = true)) return
                backoff.reset(key)
                apply(mutableState.value.player ?: player, payload)
                return
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                val issue = ServiceIssue.from(error)
                if (!issue.retriesAutomatically) {
                    mutableState.value = SelectedProfileState(player = player, status = SelectedProfileStatus.Failed, issue = issue)
                    return
                }
                var remaining = backoff.nextDelay(key, issue.retryAfterSeconds)
                while (remaining > 0) {
                    mutableState.value = SelectedProfileState(player, SelectedProfileStatus.Failed, issue = issue, countdown = remaining)
                    delay(1_000)
                    remaining--
                }
            }
        }
    }

    private fun apply(player: SelectedPlayer, payload: PlayerProfilePayload) {
        val available = payload.state == PlayerProfileState.Available
        mutableState.value = SelectedProfileState(
            player = player,
            status = if (available) SelectedProfileStatus.Available else SelectedProfileStatus.Syncing,
            payload = payload,
            scoreIndex = if (available) payload.profile.scoreIndex() else null,
        )
    }
}

// endregion
