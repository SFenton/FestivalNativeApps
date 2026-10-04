package com.festivalscoretracker.android.presentation.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.format.StarRatingSpec
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.profile.PlayerHistoryState
import com.festivalscoretracker.android.core.profile.PlayerScoreHistorySort
import com.festivalscoretracker.android.core.profile.PlayerScoreSortMode
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.ScoreHistoryChartModel
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// region UI state

/** What the score-history page shows. */
sealed interface HistoryPhase {
    /** No player selected: no request is made. */
    data object NoPlayer : HistoryPhase

    /** Loading. */
    data object Loading : HistoryPhase

    /** HTTP 404: registered users only (never "no history"). */
    data object Unregistered : HistoryPhase

    /** HTTP 202: still syncing. */
    data object Syncing : HistoryPhase

    /** No rows for this chart. */
    data object Empty : HistoryPhase

    /**
     * Failed.
     *
     * @property issue Classified failure.
     * @property countdown Seconds to the automatic retry (scrape freeze), else null.
     */
    data class Failed(val issue: ServiceIssue, val countdown: Int?) : HistoryPhase

    /** Rows shown. */
    data object Loaded : HistoryPhase
}

/**
 * One history row with display text.
 *
 * @property entry Wire row.
 * @property isHighScore Highest score in the displayed rows (follows the sort).
 * @property date Localized date.
 */
data class ScoreHistoryRow(val entry: ScoreHistoryEntry, val isHighScore: Boolean, val date: String) {
    /** Grouped score. */
    val score: String get() = ProfileFormatting.count(entry.newScore)

    /** "Season 9", or null. */
    val season: String? get() = entry.season?.let { "Season $it" }

    /** "99.1%", or null. */
    val accuracy: String? get() = entry.accuracy?.takeIf { it.isFinite() && it >= 0 }?.let { ScoreFormatting.accuracy(it) + "%" }

    /** Full combo. */
    val isFullCombo: Boolean get() = entry.isFullCombo == true

    /** Stars 0–6 (6 = gold). */
    val stars: Int get() = (entry.stars ?: 0).coerceIn(0, 6)

    /** Screen-reader text. */
    val announcement: String
        get() = listOfNotNull(
            date,
            "score $score",
            accuracy?.let { "accuracy $it" },
            "full combo".takeIf { isFullCombo },
            entry.stars?.takeIf { it > 0 }?.let { StarRatingSpec.display(it).label },
            season,
            "personal best".takeIf { isHighScore },
        ).joinToString(", ")
}

/**
 * Everything the score-history page renders.
 *
 * @property phase Phase.
 * @property rows Sorted rows.
 * @property chart Score-over-time chart (2+ dated rows).
 * @property sortMode Sort key.
 * @property ascending Sort direction.
 * @property songTitle Resolved song title, or null until the catalogue loads.
 * @property keyboard Whether the song uses the keyboard icon.
 */
data class PlayerHistoryUiState(
    val phase: HistoryPhase = HistoryPhase.Loading,
    val rows: List<ScoreHistoryRow> = emptyList(),
    val chart: ScoreHistoryChartModel? = null,
    val sortMode: PlayerScoreSortMode = PlayerScoreSortMode.Score,
    val ascending: Boolean = false,
    val songTitle: String? = null,
    val keyboard: Boolean = false,
)

// endregion

// region View model

/**
 * The selected player's score changes for one song and chart
 * (`/songs/:songId/:instrument/history`, web `PlayerHistoryPage`), with the web's
 * sort modes and a native score-over-time chart. Re-reads when the selected
 * player changes (per-entity reset). Sort is in memory only, like the web.
 *
 * @property songId Song.
 * @property instrument Chart.
 * @param read `FestivalApi.playerHistory`.
 * @param findSong Resolve the song from the current catalogue.
 * @param settings Effective settings (selected player).
 * @param backoff Shared scrape-freeze backoff.
 * @param zone Display time zone.
 * @param locale Display locale.
 */
class PlayerHistoryViewModel(
    val songId: String,
    val instrument: Instrument,
    private val read: suspend (String, String, Instrument) -> PlayerHistoryPayload,
    private val findSong: suspend (String) -> Song?,
    settings: StateFlow<AppSettings?>,
    private val backoff: ServiceRetryBackoff,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val locale: Locale = Locale.getDefault(),
) : ViewModel() {
    private val mutableState = MutableStateFlow(PlayerHistoryUiState())
    private var entries: List<ScoreHistoryEntry> = emptyList()
    private var job: Job? = null
    private var account: String? = null
    private val dateFormat = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(zone)

    /** Page state. */
    val state: StateFlow<PlayerHistoryUiState> = mutableState.asStateFlow()

    init {
        viewModelScope.launch {
            settings.map { it?.let { s -> s.selectedPlayer?.accountId ?: "" } }.distinctUntilChanged().collect { selected ->
                if (selected == null) return@collect
                account = selected.ifEmpty { null }
                load()
            }
        }
        viewModelScope.launch {
            val song = try {
                findSong(songId)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                null
            }
            if (song != null) mutableState.value = mutableState.value.copy(songTitle = song.title, keyboard = song.usesKeyboardIcon)
        }
    }

    /** Re-read (Retry). */
    fun retry() {
        load()
    }

    /**
     * Choose a sort key (keeps the direction).
     *
     * @param mode Key.
     */
    fun sortBy(mode: PlayerScoreSortMode) {
        mutableState.value = resorted(mutableState.value.copy(sortMode = mode))
    }

    /**
     * Set the direction.
     *
     * @param ascending Direction.
     */
    fun setAscending(ascending: Boolean) {
        mutableState.value = resorted(mutableState.value.copy(ascending = ascending))
    }

    /** Restore Score, descending. */
    fun resetSort() {
        mutableState.value = resorted(mutableState.value.copy(sortMode = PlayerScoreSortMode.Score, ascending = false))
    }

    private fun load() {
        job?.cancel()
        val player = account
        if (player == null) {
            show(HistoryPhase.NoPlayer, emptyList())
            return
        }
        job = viewModelScope.launch {
            val key = "player-history:$player"
            while (true) {
                show(HistoryPhase.Loading, emptyList())
                try {
                    val payload = read(player, songId, instrument)
                    backoff.reset(key)
                    val rows = payload.entries(songId, instrument)
                    when (payload.state) {
                        PlayerHistoryState.Unregistered -> show(HistoryPhase.Unregistered, emptyList())
                        PlayerHistoryState.Syncing -> show(HistoryPhase.Syncing, emptyList())
                        PlayerHistoryState.Available -> show(if (rows.isEmpty()) HistoryPhase.Empty else HistoryPhase.Loaded, rows)
                    }
                    return@launch
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    val issue = ServiceIssue.from(error)
                    if (!issue.retriesAutomatically) {
                        show(HistoryPhase.Failed(issue, null), emptyList())
                        return@launch
                    }
                    var remaining = backoff.nextDelay(key, issue.retryAfterSeconds)
                    while (remaining > 0) {
                        show(HistoryPhase.Failed(issue, remaining), emptyList())
                        delay(1_000)
                        remaining--
                    }
                }
            }
        }
    }

    private fun show(phase: HistoryPhase, rows: List<ScoreHistoryEntry>) {
        entries = rows
        mutableState.value = resorted(mutableState.value.copy(phase = phase, chart = ScoreHistoryChartModel.build(rows, zone, locale)))
    }

    private fun resorted(state: PlayerHistoryUiState): PlayerHistoryUiState {
        val sorted = PlayerScoreHistorySort.sorted(entries, state.sortMode, state.ascending)
        val best = PlayerScoreHistorySort.highScoreIndex(sorted)
        return state.copy(
            rows = sorted.mapIndexed { i, entry ->
                ScoreHistoryRow(entry, i == best, entry.displayDate?.let(dateFormat::format) ?: entry.dateKey)
            },
        )
    }
}

// endregion
