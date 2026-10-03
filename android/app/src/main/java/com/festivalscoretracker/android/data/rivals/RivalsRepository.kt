package com.festivalscoretracker.android.data.rivals

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalDetailRequest
import com.festivalscoretracker.android.core.rivals.RivalDetailResponse
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalsAllDetail
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import com.festivalscoretracker.android.data.FestivalApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// region Reads

/**
 * The Rivals reads screens use, over an in-process cache (online-only speed cache,
 * not offline storage): successful reads live [TTL_MILLIS] (the service's `max-age`),
 * failures are never cached, and at most [MAX_ENTRIES] results are kept. Hub → All
 * Rivals and Rival Detail → Rivalry therefore reuse one read. When a newer read is
 * refused by a public-read freeze or a 503, a result read within [STALE_MILLIS] keeps
 * showing, as the web keeps a rival it already loaded (operator 7.13).
 *
 * @param lists Song-scope list read `(accountId, scope)`.
 * @param leaderboardLists Leaderboard list read.
 * @param details Song-scope detail read `(accountId, scope, rivalId, allowLiveFallback)`.
 * @param leaderboardDetails Leaderboard detail read.
 * @param clock Milliseconds source.
 * @param all `rivals/all` read `(accountId)` for the detail freeze fallback, or null for none.
 */
class RivalsRepository(
    private val lists: suspend (String, String) -> RivalsListResponse,
    private val leaderboardLists: suspend (String, Instrument, RivalRankMetric) -> LeaderboardRivalsListResponse,
    private val details: suspend (String, String, String, Boolean) -> RivalDetailResponse,
    private val leaderboardDetails: suspend (String, Instrument, String, RivalRankMetric) -> RivalDetailResponse,
    private val clock: () -> Long = System::currentTimeMillis,
    private val all: (suspend (String) -> RivalsAllResponse)? = null,
) {
    /**
     * Build over the shared API client.
     *
     * @param api Keyless client.
     */
    constructor(api: FestivalApi) : this(
        lists = api::rivalsList,
        leaderboardLists = api::leaderboardRivals,
        details = { account, scope, rival, live -> api.rivalDetail(account, scope, rival, allowLiveFallback = live) },
        leaderboardDetails = { account, instrument, rival, rankBy -> api.leaderboardRivalDetail(account, instrument, rival, rankBy) },
        all = api::rivalsAll,
    )

    private data class Entry(val value: Any, val atMillis: Long)

    private val mutex = Mutex()
    private val cache = LinkedHashMap<String, Entry>()

    /**
     * One song-scope rivals list.
     *
     * @param accountId Selected player.
     * @param scope Chart wire ID or combo token.
     * @param refresh Bypass the cache.
     * @return List.
     */
    suspend fun list(accountId: String, scope: String, refresh: Boolean = false): RivalsListResponse =
        cached("list:$accountId:$scope", refresh) { lists(accountId, scope) }

    /**
     * One chart's leaderboard neighbours.
     *
     * @param accountId Selected player.
     * @param instrument Chart.
     * @param rankBy Metric.
     * @param refresh Bypass the cache.
     * @return List.
     */
    suspend fun leaderboardList(accountId: String, instrument: Instrument, rankBy: RivalRankMetric, refresh: Boolean = false) =
        cached("lb:$accountId:${instrument.wireId}:${rankBy.wireId}", refresh) { leaderboardLists(accountId, instrument, rankBy) }

    /**
     * A rival comparison for a resolved request. Several scopes are read concurrently
     * and merged; one failing scope still shows the rest, and only an all-failed read
     * throws (web `fetchCombinedRivalDetail`). Chart/combo scopes refused by a freeze
     * or 503 are rebuilt from `rivals/all` ([RivalsAllDetail], issue #95); when that
     * cannot supply them the original failure stands, so the page keeps its retry state.
     *
     * @param accountId Selected player.
     * @param rivalId Rival.
     * @param request Resolved request.
     * @param allowLiveFallback Find Rival's live computation flag.
     * @param refresh Bypass the cache.
     * @return Detail.
     */
    suspend fun detail(
        accountId: String,
        rivalId: String,
        request: RivalDetailRequest,
        allowLiveFallback: Boolean = false,
        refresh: Boolean = false,
    ): RivalDetailResponse = when (request) {
        is RivalDetailRequest.Leaderboard -> cached("lbd:$accountId:$rivalId:${request.instrument.wireId}:${request.rankBy.wireId}", refresh) {
            leaderboardDetails(accountId, request.instrument, rivalId, request.rankBy)
        }
        is RivalDetailRequest.Scopes -> {
            val results = coroutineScope {
                request.scopes.map { scope ->
                    async {
                        try {
                            Result.success(cached("detail:$accountId:$rivalId:$scope:$allowLiveFallback", refresh) { details(accountId, scope, rivalId, allowLiveFallback) })
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            Result.failure<RivalDetailResponse>(error)
                        }
                    }
                }.awaitAll()
            }
            val succeeded = results.mapNotNull { it.getOrNull() }.toMutableList()
            val frozen = request.scopes.filterIndexed { index, _ -> results[index].exceptionOrNull()?.let(::isFreeze) == true }
            if (frozen.isNotEmpty()) rebuiltFromAll(accountId, rivalId, frozen, refresh)?.let(succeeded::add)
            if (succeeded.isEmpty()) throw results.first().exceptionOrNull()!!
            if (succeeded.size == 1 && request.scopes.size == 1) succeeded.single() else RivalDetailResponse.merge(succeeded, request.scopes)
        }
    }

    /**
     * Rebuild frozen chart/combo scopes from the cached `rivals/all` read.
     *
     * @param accountId Selected player.
     * @param rivalId Rival.
     * @param scopes Scopes the service refused.
     * @param refresh Bypass the cache.
     * @return Rebuilt detail, or null when unavailable.
     */
    private suspend fun rebuiltFromAll(accountId: String, rivalId: String, scopes: List<String>, refresh: Boolean): RivalDetailResponse? {
        val read = all ?: return null
        val instruments = scopes.mapNotNull(RivalsAllDetail::instrumentsFor).flatten().toSet()
        if (instruments.isEmpty()) return null
        val response = try {
            cached("all:$accountId", refresh) { read(accountId) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            return null
        }
        return RivalsAllDetail.build(response, rivalId, instruments, scopes.joinToString(","))
    }

    /** Forget every cached read (pull to refresh everywhere). */
    suspend fun clear() {
        mutex.withLock { cache.clear() }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun <T : Any> cached(key: String, refresh: Boolean, load: suspend () -> T): T {
        if (!refresh) {
            mutex.withLock {
                val hit = cache[key]
                if (hit != null && clock() - hit.atMillis < TTL_MILLIS) return hit.value as T
            }
        }
        val value = try {
            load()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            if (!isFreeze(error)) throw error
            // Serve the last good read as is: re-caching it would restart its age.
            return mutex.withLock { cache[key]?.takeIf { clock() - it.atMillis < STALE_MILLIS }?.value as T? } ?: throw error
        }
        mutex.withLock {
            cache.remove(key)
            cache[key] = Entry(value, clock())
            while (cache.size > MAX_ENTRIES) cache.remove(cache.keys.first())
        }
        return value
    }

    companion object {
        /** Cache lifetime, matching the service's `Cache-Control: max-age=120`. */
        const val TTL_MILLIS = 120_000L

        /** Most results kept. */
        const val MAX_ENTRIES = 64

        /** How long a result may stand in for a read refused by a freeze or 503. */
        const val STALE_MILLIS = 600_000L

        /**
         * Whether a failure is a temporary public-read refusal (freeze or 503), not bad data.
         *
         * @param error Failure.
         * @return True for a freeze or unavailable response.
         */
        fun isFreeze(error: Throwable): Boolean =
            error is FestivalApiException.PublicReadFrozen || error is FestivalApiException.Unavailable ||
                (error is FestivalApiException.HttpStatus && error.status == 503)
    }
}

// endregion
