package com.festivalscoretracker.android.presentation.bands

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.bands.BandDetail
import com.festivalscoretracker.android.core.bands.BandDetailProjection
import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandRankHistoryResponse
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandSongExtremesResponse
import com.festivalscoretracker.android.core.bands.BandText
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.RetryingLoader
import com.festivalscoretracker.android.presentation.SongResolver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// region Paging helper

/**
 * Load a page, reloading the last page once when the list shrank below the requested one.
 *
 * @param T Page type.
 * @param requested Requested one-based page.
 * @param load Page read.
 * @param pageCount Page count of a loaded page.
 * @param onCorrected Called with the corrected page before it is reloaded.
 * @return The requested page, or the last page.
 */
internal suspend fun <T> loadClampedPage(requested: Int, load: suspend (Int) -> T, pageCount: (T) -> Int, onCorrected: (Int) -> Unit): T {
    val first = load(requested)
    val last = pageCount(first)
    if (requested <= last) return first
    onCorrected(last)
    return load(last)
}

// endregion

// region Player bands

/**
 * `/bands/player/:accountId` (and the Bands landing preview): one group-filtered,
 * paged list of a player's bands. Changing the group returns to page one; a newer
 * load cancels an older one so a late response never replaces a newer group/page.
 *
 * @property accountId Player whose bands are listed.
 * @property pageSize Rows per page (25 for the page, 6 for the landing preview).
 * @param load Page read `(accountId, group, page, pageSize)`.
 * @param backoff Shared retry backoff.
 * @param initialGroup Group selected on open (web `?group=`; the player page's per-size "View all").
 */
class PlayerBandsViewModel(
    val accountId: String,
    val pageSize: Int,
    private val load: suspend (String, PlayerBandGroup, Int, Int) -> PlayerBandListResponse,
    backoff: ServiceRetryBackoff,
    initialGroup: PlayerBandGroup = PlayerBandGroup.All,
) : ViewModel() {
    private val groupFlow = MutableStateFlow(initialGroup)
    private val pageFlow = MutableStateFlow(1)
    private val loader = RetryingLoader(viewModelScope, "player-bands:$accountId:$pageSize", backoff) {
        val group = groupFlow.value
        loadClampedPage(pageFlow.value, { load(accountId, group, it, pageSize) }, { it.pageCount(pageSize) }) { pageFlow.value = it }
    }

    /** Selected group. */
    val group: StateFlow<PlayerBandGroup> = groupFlow.asStateFlow()

    /** Current one-based page. */
    val page: StateFlow<Int> = pageFlow.asStateFlow()

    /** Current page state. */
    val bands: StateFlow<LoadState<PlayerBandListResponse>> = loader.state

    init {
        if (BandText.isValidMemberId(accountId)) loader.ensureStarted()
    }

    /** Whether the route's account ID can be requested at all. */
    val isValidAccount: Boolean get() = BandText.isValidMemberId(accountId)

    /**
     * Switch the group filter, returning to page one.
     *
     * @param group New group.
     */
    fun selectGroup(group: PlayerBandGroup) {
        if (group == groupFlow.value) return
        groupFlow.value = group
        pageFlow.value = 1
        loader.retry()
    }

    /**
     * Go to a page (clamped to ≥ 1; past-the-end pages fall back to the last page).
     *
     * @param page One-based page.
     */
    fun goTo(page: Int) {
        pageFlow.value = page.coerceAtLeast(1)
        loader.retry()
    }

    /** Retry the current page. */
    fun retry() = loader.retry()
}

// endregion

// region Band detail

/**
 * Best/worst songs with their catalogue matches.
 *
 * @property response Wire lists.
 * @property songsById Catalogue songs by ID (empty when the catalogue failed; rows fall back to "Unknown Song").
 */
data class BandSongsState(val response: BandSongExtremesResponse, val songsById: Map<String, Song>)

/**
 * `/bands/:bandId`: the band row resolved only through the pure rankings board
 * filtered by `teamKey`, then rank history and best/worst songs as independent
 * sections (each with its own inline status). A route without a valid
 * `bandType`/`teamKey` is [isResolvable] = false and makes no request, because
 * the only `bandId` lookup (`/api/bands/{bandId}`) writes on a GET.
 *
 * @param bandTypeWire Route band type.
 * @param teamKey Route team key.
 * @param loadProfile Band row read.
 * @param loadHistory Rank-history read `(type, teamKey, days)`.
 * @param loadSongs Best/worst read `(type, teamKey, limit)`.
 * @param loadCatalog Catalogue read (best effort, for song titles and links).
 * @param backoff Shared retry backoff.
 * @param experimentalRanksSetting Settings → Experimental Ranks: Rank By is offered only when on, and
 *   turning it off returns the page to Total Score (experimental-ranks R1, R3).
 */
class BandDetailViewModel(
    bandTypeWire: String?,
    teamKey: String?,
    loadProfile: suspend (BandType, String) -> BandDetail,
    loadHistory: suspend (BandType, String, Int) -> BandRankHistoryResponse,
    loadSongs: suspend (BandType, String, Int) -> BandSongExtremesResponse,
    loadCatalog: suspend () -> CatalogPayload,
    backoff: ServiceRetryBackoff,
    experimentalRanksSetting: Flow<Boolean>,
) : ViewModel() {
    /** Parsed band size, or null for an unresolvable route. */
    val bandType: BandType? = BandType.fromWireId(bandTypeWire).takeIf { BandText.isValidTeamKey(teamKey) }

    /** Whether the route carries a valid band type and team key. */
    val isResolvable: Boolean = bandType != null

    private val key = teamKey.orEmpty()
    private val metricFlow = MutableStateFlow(BandRankingMetric.DEFAULT)
    private val experimentalFlow = MutableStateFlow(false)
    private val detailLoader = RetryingLoader(viewModelScope, "band:$bandTypeWire:$key", backoff) { loadProfile(bandType!!, key) }
    private val historyLoader = RetryingLoader(viewModelScope, "band-history:$bandTypeWire:$key", backoff) {
        loadHistory(bandType!!, key, BandDetailProjection.HISTORY_DAYS)
    }
    private val songsLoader = RetryingLoader(viewModelScope, "band-songs:$bandTypeWire:$key", backoff) {
        val response = loadSongs(bandType!!, key, BandDetailProjection.SONG_LIMIT)
        val songs = try {
            loadCatalog().catalog.songs.associateBy { it.songId }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            emptyMap()
        }
        BandSongsState(response, songs)
    }

    /** Band row. */
    val detail: StateFlow<LoadState<BandDetail>> = detailLoader.state

    /** Rank history (starts once the band row loads). */
    val history: StateFlow<LoadState<BandRankHistoryResponse>> = historyLoader.state

    /** Best/worst songs (starts once the band row loads). */
    val songs: StateFlow<LoadState<BandSongsState>> = songsLoader.state

    /** Rank-by metric for Statistics and Rank History (no new request). */
    val metric: StateFlow<BandRankingMetric> = metricFlow.asStateFlow()

    /** Settings → Experimental Ranks: the Rank By menu shows only when on. */
    val experimentalRanks: StateFlow<Boolean> = experimentalFlow.asStateFlow()

    init {
        viewModelScope.launch {
            experimentalRanksSetting.collect { enabled ->
                experimentalFlow.value = enabled
                metricFlow.value = BandRankingMetric.coerce(metricFlow.value, enabled)
            }
        }
        if (isResolvable) {
            detailLoader.ensureStarted()
            viewModelScope.launch {
                detailLoader.state.first { it is LoadState.Loaded }
                historyLoader.ensureStarted()
                songsLoader.ensureStarted()
            }
        }
    }

    /**
     * Select the rank-by metric; metrics Experimental Ranks doesn't offer are ignored.
     *
     * @param metric Metric.
     */
    fun selectMetric(metric: BandRankingMetric) {
        if (metric !in BandRankingMetric.enabled(experimentalFlow.value)) return
        metricFlow.value = metric
    }

    /** Retry the band row. */
    fun retry() = detailLoader.retry()

    /** Retry rank history. */
    fun retryHistory() = historyLoader.retry()

    /** Retry best/worst songs. */
    fun retrySongs() = songsLoader.retry()
}

// endregion

// region Song band leaderboard

/**
 * `/songs/:songId/bands/:bandType`: 25-row pages of one song's band scores with an
 * in-place band-size switcher (returns to page one).
 *
 * @param songId Song.
 * @param initialBandType Starting size.
 * @param loadCatalog Catalogue read (header).
 * @param loadBoard Page read `(songId, bandType, page, top)`.
 * @param backoff Shared retry backoff.
 * @param initialPage Starting one-based page (route `?page=`; Song Detail's band row jumps here, issue #307).
 */
class SongBandLeaderboardViewModel(
    songId: String,
    initialBandType: BandType,
    loadCatalog: suspend (refresh: Boolean) -> CatalogPayload,
    loadBoard: suspend (String, BandType, Int, Int) -> SongBandLeaderboardResponse,
    backoff: ServiceRetryBackoff,
    initialPage: Int = 1,
) : ViewModel() {
    private val typeFlow = MutableStateFlow(initialBandType)
    private val pageFlow = MutableStateFlow(initialPage.coerceAtLeast(1))
    private val songLoader = RetryingLoader(viewModelScope, "song:$songId", backoff) { refresh ->
        SongResolver.resolve(loadCatalog(refresh).catalog.songs, songId)
    }
    private val boardLoader = RetryingLoader(viewModelScope, "song-bands:$songId", backoff) {
        val type = typeFlow.value
        loadClampedPage(pageFlow.value, { loadBoard(songId, type, it, BandPaging.PAGE_SIZE) }, { it.pageCount(BandPaging.PAGE_SIZE) }) {
            pageFlow.value = it
        }
    }

    /** Song header. */
    val song: StateFlow<LoadState<Song>> = songLoader.state

    /** Selected band size. */
    val bandType: StateFlow<BandType> = typeFlow.asStateFlow()

    /** Current one-based page. */
    val page: StateFlow<Int> = pageFlow.asStateFlow()

    /** Current page rows. */
    val board: StateFlow<LoadState<SongBandLeaderboardResponse>> = boardLoader.state

    init {
        songLoader.ensureStarted()
        boardLoader.ensureStarted()
    }

    /**
     * Switch band size in place, returning to page one.
     *
     * @param type New size.
     */
    fun selectBandType(type: BandType) {
        if (type == typeFlow.value) return
        typeFlow.value = type
        pageFlow.value = 1
        boardLoader.retry()
    }

    /**
     * Go to a page.
     *
     * @param page One-based page.
     */
    fun goTo(page: Int) {
        pageFlow.value = page.coerceAtLeast(1)
        boardLoader.retry()
    }

    /** Retry the current page. */
    fun retry() = boardLoader.retry()

    /** Retry the song header. */
    fun retrySong() = songLoader.retry()
}

// endregion
