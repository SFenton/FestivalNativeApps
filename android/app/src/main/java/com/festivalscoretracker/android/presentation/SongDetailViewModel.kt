package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.profile.PlayerHistoryPayload
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.data.LeaderboardPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// region Song resolution

/** Resolve debug/deep-link song keys against the current catalogue. */
object SongResolver {
    /**
     * Find a song by exact ID, then by case-insensitive exact title.
     *
     * @param songs Current catalogue.
     * @param key Song ID or title.
     * @return The song.
     * @throws FestivalApiException.HttpStatus 404 when absent, so the screen shows "not found".
     */
    fun resolve(songs: List<Song>, key: String): Song =
        songs.firstOrNull { it.songId == key }
            ?: songs.firstOrNull { it.title.equals(key.trim(), ignoreCase = true) }
            ?: throw FestivalApiException.HttpStatus(404)
}

// endregion

// region Song detail

/**
 * Song Detail logic: the song resolved by ID against the current catalogue, a
 * ten-row preview per visible chart (started together by [startPreviews] so the page
 * can wait for all of them, web `allReady`) and the selected player's score history
 * for this song (web `ScoreHistoryChart` on the song page).
 *
 * @param songKey Route song ID (or debug title).
 * @param loadCatalog Catalogue read.
 * @param loadLeaderboard Leaderboard page read `(songId, instrument, page, top, leeway)`.
 * @property backoff Shared retry backoff.
 * @param leeway Invalid-score leeway while Filter Invalid Scores is on, else null;
 *   previews are keyed by it so a change re-reads.
 * @param loadHistory Song score-history read `(accountId, songId)`, or null when unavailable.
 */
class SongDetailViewModel(
    songKey: String,
    loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    private val loadLeaderboard: suspend (String, Instrument, Int, Int, Double?) -> LeaderboardPayload,
    private val backoff: ServiceRetryBackoff,
    private val leeway: () -> Double? = { null },
    private val loadHistory: (suspend (String, String) -> PlayerHistoryPayload)? = null,
) : ViewModel() {
    private val catalogPublicationFlow = MutableStateFlow<Int?>(null)
    private val songLoader = RetryingLoader(viewModelScope, "song:$songKey", backoff) { refresh ->
        val payload = loadCatalog(refresh)
        catalogPublicationFlow.value = payload.publicationId
        SongResolver.resolve(payload.catalog.songs, songKey)
    }
    private val previews = mutableMapOf<Pair<Instrument, Double?>, RetryingLoader<LeaderboardPayload>>()
    private val histories = mutableMapOf<String, RetryingLoader<PlayerHistoryPayload>>()

    /** The resolved song. */
    val song: StateFlow<LoadState<Song>> = songLoader.state

    /** Generation observed for the catalogue the song was resolved from. */
    val catalogPublication: StateFlow<Int?> = catalogPublicationFlow.asStateFlow()

    init {
        songLoader.ensureStarted()
    }

    /**
     * The ten-row preview for one chart, started on first access.
     *
     * @param song Resolved song.
     * @param instrument Chart.
     * @return Preview state.
     */
    fun preview(song: Song, instrument: Instrument): StateFlow<LoadState<LeaderboardPayload>> {
        val current = leeway()
        val loader = previews.getOrPut(instrument to current) {
            RetryingLoader(viewModelScope, "preview:${song.songId}:${instrument.wireId}", backoff) {
                loadLeaderboard(song.songId, instrument, 1, LeaderboardPaging.PREVIEW_SIZE, current)
            }
        }
        loader.ensureStarted()
        return loader.state
    }

    /**
     * Start every chart's preview at once (the page reveals when all have settled).
     *
     * @param song Resolved song.
     * @param charts Visible charted instruments.
     * @return Each chart's preview state, in [charts] order.
     */
    fun startPreviews(song: Song, charts: List<Instrument>): List<StateFlow<LoadState<LeaderboardPayload>>> = charts.map { preview(song, it) }

    /**
     * The selected player's score history for this song (every chart), started on first access.
     *
     * @param song Resolved song.
     * @param accountId Selected player.
     * @return History state, or null when no history reader is configured.
     */
    fun history(song: Song, accountId: String): StateFlow<LoadState<PlayerHistoryPayload>>? {
        val read = loadHistory ?: return null
        val loader = histories.getOrPut(accountId) {
            RetryingLoader(viewModelScope, "song-history:${song.songId}:$accountId", backoff) { read(accountId, song.songId) }
        }
        loader.ensureStarted()
        return loader.state
    }

    /**
     * Retry one chart preview.
     *
     * @param instrument Chart.
     */
    fun retryPreview(instrument: Instrument) {
        previews[instrument to leeway()]?.retry()
    }

    /** Retry resolving the song. */
    fun retry() = songLoader.retry()
}

// endregion

// region Song leaderboard

/**
 * Full 25-row song leaderboard with page navigation.
 *
 * @param songId Song ID.
 * @property instrument Chart.
 * @param initialPage One-based starting page.
 * @param loadCatalog Catalogue read (for the header).
 * @param loadLeaderboard Leaderboard page read.
 * @param backoff Shared retry backoff.
 */
class SongLeaderboardViewModel(
    songId: String,
    val instrument: Instrument,
    initialPage: Int,
    loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    loadLeaderboard: suspend (String, Instrument, Int, Int) -> LeaderboardPayload,
    backoff: ServiceRetryBackoff,
) : ViewModel() {
    private val pageFlow = MutableStateFlow(initialPage.coerceAtLeast(1))
    private val songLoader = RetryingLoader(viewModelScope, "song:$songId", backoff) { refresh ->
        SongResolver.resolve(loadCatalog(refresh).catalog.songs, songId)
    }
    private val pageLoader = RetryingLoader(viewModelScope, "board:$songId:${instrument.wireId}", backoff) {
        val requested = pageFlow.value
        val payload = loadLeaderboard(songId, instrument, requested, LeaderboardPaging.PAGE_SIZE)
        val corrected = LeaderboardPaging.corrected(requested, payload.leaderboard.pageCount())
        if (corrected != requested) {
            pageFlow.value = corrected
            loadLeaderboard(songId, instrument, corrected, LeaderboardPaging.PAGE_SIZE)
        } else {
            payload
        }
    }

    /** Song header. */
    val song: StateFlow<LoadState<Song>> = songLoader.state

    /** Current page rows. */
    val board: StateFlow<LoadState<LeaderboardPayload>> = pageLoader.state

    /** Current one-based page. */
    val page: StateFlow<Int> = pageFlow.asStateFlow()

    init {
        songLoader.ensureStarted()
        pageLoader.ensureStarted()
    }

    /**
     * Go to a page (clamped to ≥ 1; the loader corrects past-the-end pages).
     *
     * @param page One-based page.
     */
    fun goTo(page: Int) {
        pageFlow.value = page.coerceAtLeast(1)
        pageLoader.retry()
    }

    /** Retry the current page. */
    fun retry() = pageLoader.retry()
}

// endregion
