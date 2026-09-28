package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.LeaderboardResponse
import com.festivalscoretracker.android.core.model.PlayerSearchResponse
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.model.Publication
import com.festivalscoretracker.android.core.model.SongsResponse
import java.io.ByteArrayInputStream
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// region Endpoints

/**
 * Allowlisted keyless GETs (`.agents/platforms/service-safety.md`). Add a read by
 * adding a case here after proving it side-effect free; blocked routes (band
 * search, band detail, player stats, band sync-status) must never appear.
 */
sealed interface ServiceEndpoint {
    /** Whether the read is publication-bound and may be pinned/ETag-cached. */
    val pinned: Boolean

    /** Whether HTTP 202 is a documented syncing envelope. */
    val acceptsSyncing: Boolean get() = false

    /** `GET /api/publication`. */
    data object PublicationRead : ServiceEndpoint {
        override val pinned = false
    }

    /** `GET /api/songs`. */
    data object Songs : ServiceEndpoint {
        override val pinned = true
    }

    /** `GET /api/leaderboard/{songId}/{instrument}?top=&offset=`. */
    data class Leaderboard(val songId: String, val instrument: Instrument, val top: Int, val offset: Int) : ServiceEndpoint {
        override val pinned = true
    }

    /** `GET /api/account/search?q=&limit=` (publication-bound on the service, read unpinned like Apple). */
    data class AccountSearch(val query: String, val limit: Int) : ServiceEndpoint {
        override val pinned = false
        override val acceptsSyncing = true
    }

    /**
     * A feature-owned allowlisted read declared in its own
     * `data/<feature>/FestivalApi<Feature>.kt` file, so feature lanes add reads
     * without editing this `when`. Every segment must pass [isSafeSegment]; the
     * owning file documents the endpoint's purity (service-safety.md).
     *
     * @property segments Path segments after `/api/`.
     * @property query Query parameters in order.
     */
    data class Feature(
        val segments: List<String>,
        val query: List<Pair<String, String>> = emptyList(),
        override val pinned: Boolean = true,
        override val acceptsSyncing: Boolean = false,
    ) : ServiceEndpoint

    /**
     * Build the URL from individually validated, percent-encoded segments.
     *
     * @param base Validated origin.
     * @return Endpoint URL.
     * @throws FestivalApiException for invalid segments or bounds.
     */
    fun url(base: HttpUrl): String {
        val builder = base.newBuilder().encodedPath("/").addPathSegment("api")
        when (this) {
            PublicationRead -> builder.addPathSegment("publication")
            Songs -> builder.addPathSegment("songs")
            is Leaderboard -> {
                if (!isSafeSegment(songId) || top !in 1..LeaderboardPaging.PAGE_SIZE || offset < 0) {
                    throw FestivalApiException.InvalidResource()
                }
                builder.addPathSegment("leaderboard").addPathSegment(songId).addPathSegment(instrument.wireId)
                    .addQueryParameter("top", top.toString())
                    .addQueryParameter("offset", offset.toString())
            }
            is AccountSearch -> {
                if (!ProfileSearchText.isValidQuery(query)) throw FestivalApiException.InvalidSearchQuery()
                if (limit !in 1..10) throw FestivalApiException.InvalidResource()
                builder.addPathSegment("account").addPathSegment("search")
                    .addQueryParameter("q", query)
                    .addQueryParameter("limit", limit.toString())
            }
            is Feature -> {
                if (segments.isEmpty() || !segments.all(::isSafeSegment)) throw FestivalApiException.InvalidResource()
                segments.forEach(builder::addPathSegment)
                query.forEach { (name, value) -> builder.addQueryParameter(name, value) }
            }
        }
        return builder.build().toString()
    }

    companion object {
        /**
         * Whether a value is a nonempty single path segment.
         *
         * @param segment Candidate.
         * @return False for empty, `/`-containing or `..` values.
         */
        fun isSafeSegment(segment: String): Boolean =
            segment.isNotEmpty() && '/' !in segment && '\\' !in segment && segment != "." && segment != ".."
    }
}

// endregion

// region Payloads

/**
 * A decoded catalogue plus the generation observed while reading it.
 *
 * @property catalog Validated songs envelope.
 * @property publicationId Observed publication.
 */
data class CatalogPayload(val catalog: SongsResponse, val publicationId: Int)

/**
 * One leaderboard page.
 *
 * @property page One-based page.
 * @property leaderboard Validated rows.
 * @property publicationId Observed publication.
 */
data class LeaderboardPayload(val page: Int, val leaderboard: LeaderboardResponse, val publicationId: Int)

@Serializable
private data class Conflict(val status: String? = null)

// endregion

// region API client

/**
 * Publication-aware, read-only API client (Apple `FestivalAPI`). Every read goes
 * through [RequestGate]; no privileged key is ever obtained or sent.
 *
 * In-process caches only (online-only): the publication, an ETag/body cache for
 * pinned reads within one publication, and the decoded catalogue. A newer
 * publication clears them and is announced on [publicationChanges].
 *
 * @param origin HTTPS origin, or a loopback/emulator-host HTTP fixture origin.
 * @param transport Injected transport.
 */
class FestivalApi(origin: String, transport: HttpTransport) {
    private val base: HttpUrl
    private val gate = RequestGate(transport)
    private val mutex = Mutex()
    private var current: Publication? = null
    private val etagCache = mutableMapOf<String, CachedBody>()
    private var catalogMemo: CatalogPayload? = null
    private val publicationFlow = MutableStateFlow<Int?>(null)

    private data class CachedBody(val publicationId: Int, val etag: String, val body: ByteArray)

    init {
        val parsed = origin.toHttpUrlOrNull() ?: throw FestivalApiException.InsecureBaseUrl()
        val loopback = parsed.host in LOOPBACK_HOSTS
        if (!(parsed.scheme == "https" || (loopback && parsed.scheme == "http"))) {
            throw FestivalApiException.InsecureBaseUrl()
        }
        base = parsed
    }

    /** Latest observed publication ID; changes clear every in-process cache. */
    val publicationChanges: StateFlow<Int?> = publicationFlow.asStateFlow()

    /** Validated service origin. */
    val origin: String get() = base.toString()

    // region Publication

    /**
     * Bootstrap or refresh the published generation.
     *
     * @param force Ignore the cached generation.
     * @return Validated publication.
     * @throws FestivalApiException for status, decoding or a generation moving backwards.
     */
    suspend fun publication(force: Boolean = false): Publication {
        if (!force) mutex.withLock { current }?.let { return it }
        val response = gate.send(RequestGate.makeRequest(ServiceEndpoint.PublicationRead.url(base)))
        RequestGate.mapStatus(response, acceptsSyncing = false)
        if (response.status != 200) throw FestivalApiException.HttpStatus(response.status)
        val new = decode(Publication.serializer(), response.body)
        new.validate()
        adopt(new)
        return new
    }

    private suspend fun adopt(new: Publication) {
        mutex.withLock {
            val previous = current
            if (previous != null && new.publicationId < previous.publicationId) {
                throw FestivalApiException.InvalidPublication()
            }
            if (previous?.publicationId != new.publicationId) {
                etagCache.clear()
                catalogMemo = null
            }
            current = new
        }
        publicationFlow.value = new.publicationId
    }

    // endregion

    // region Pinned reads

    /**
     * Read a publication-bound endpoint, retrying one `publication_changed` 409 and
     * adopting a newer response publication while pinning is disabled.
     *
     * @param endpoint Pinned endpoint.
     * @return Body bytes and the generation they belong to.
     */
    internal suspend fun readPinned(endpoint: ServiceEndpoint): Pair<ByteArray, Int> {
        val url = endpoint.url(base)
        var publication = publication()
        var response = gate.send(pinnedRequest(url, publication))
        if (response.status == 409 && runCatching { decode(Conflict.serializer(), response.body).status }.getOrNull() == "publication_changed") {
            publication = publication(force = true)
            response = gate.send(pinnedRequest(url, publication))
        }
        if (response.status == 304) {
            val cached = mutex.withLock { etagCache[url] }
            val responseId = response.header(RequestGate.PUBLICATION_HEADER)?.toIntOrNull()
            if (cached != null && cached.publicationId == publication.publicationId &&
                (responseId == null || responseId == publication.publicationId)
            ) {
                return cached.body to publication.publicationId
            }
            response = gate.send(RequestGate.makeRequest(url, pinHeaders(publication)))
        }
        RequestGate.mapStatus(response, endpoint.acceptsSyncing)
        val responseId = response.header(RequestGate.PUBLICATION_HEADER)?.toIntOrNull()
        if (responseId != null && responseId != publication.publicationId) {
            if (publication.pins || responseId < publication.publicationId) throw FestivalApiException.InvalidPublication()
            publication = publication(force = true)
            if (publication.publicationId != responseId) throw FestivalApiException.InvalidPublication()
        }
        val etag = response.header("ETag")
        if (etag != null && responseId == publication.publicationId) {
            mutex.withLock {
                if (current?.publicationId == publication.publicationId) {
                    etagCache[url] = CachedBody(publication.publicationId, etag, response.body)
                }
            }
        }
        return response.body to publication.publicationId
    }

    private suspend fun pinnedRequest(url: String, publication: Publication): HttpRequest {
        val cached = mutex.withLock { etagCache[url] }?.takeIf { it.publicationId == publication.publicationId }
        val headers = pinHeaders(publication) + (cached?.let { mapOf("If-None-Match" to it.etag) } ?: emptyMap())
        return RequestGate.makeRequest(url, headers)
    }

    private fun pinHeaders(publication: Publication): Map<String, String> =
        if (publication.pins) mapOf(RequestGate.PUBLICATION_HEADER to publication.publicationId.toString()) else emptyMap()

    // endregion

    // region Typed reads

    /**
     * Fetch and validate the song catalogue, memoized for the current publication.
     *
     * @param refresh Re-check the publication and bypass the decoded memo.
     * @return Catalogue and observed publication.
     */
    suspend fun catalog(refresh: Boolean = false): CatalogPayload {
        if (refresh) {
            publication(force = true)
        } else {
            val memo = mutex.withLock { catalogMemo?.takeIf { it.publicationId == current?.publicationId } }
            if (memo != null) return memo
        }
        val (body, publicationId) = readPinned(ServiceEndpoint.Songs)
        val catalog = decode(SongsResponse.serializer(), body)
        catalog.validate()
        val payload = CatalogPayload(catalog, publicationId)
        mutex.withLock { if (current?.publicationId == publicationId) catalogMemo = payload }
        return payload
    }

    /**
     * Read one leaderboard page (ten rows for a Detail preview, 25 for a page).
     *
     * @param songId Catalogue song ID.
     * @param instrument Chart.
     * @param page One-based page.
     * @param top Rows per request.
     * @return Validated page.
     */
    suspend fun leaderboard(songId: String, instrument: Instrument, page: Int, top: Int = LeaderboardPaging.PAGE_SIZE): LeaderboardPayload {
        if (page < 1 || top !in 1..LeaderboardPaging.PAGE_SIZE || page - 1 > Int.MAX_VALUE / top) {
            throw FestivalApiException.InvalidResource()
        }
        val (body, publicationId) = readPinned(ServiceEndpoint.Leaderboard(songId, instrument, top, (page - 1) * top))
        val response = decode(LeaderboardResponse.serializer(), body)
        response.validate(songId, instrument, top)
        return LeaderboardPayload(page, response, publicationId)
    }

    /**
     * Search players by display name (allowlisted pure read). An empty result is
     * never proof of no match (the service also returns empty after a DB timeout).
     *
     * @param query Trimmed 2–200 character query.
     * @param limit Up to ten results.
     * @return Results, empty for a 202 envelope.
     */
    suspend fun searchPlayers(query: String, limit: Int = 10): List<PlayerSearchResult> {
        val url = ServiceEndpoint.AccountSearch(query, limit).url(base)
        val response = gate.send(RequestGate.makeRequest(url))
        if (RequestGate.mapStatus(response, acceptsSyncing = true) == ServiceStatus.Syncing) return emptyList()
        return decode(PlayerSearchResponse.serializer(), response.body).results
            .filter { ProfileSearchText.isValidAccountId(it.accountId) && it.displayName.isNotBlank() }
    }

    /**
     * Resolve a song's artwork reference (Apple `artworkURL`).
     *
     * @param raw Absolute HTTPS URL, CDN-relative file name, or loopback fixture path.
     * @return URL, or null for no/invalid artwork.
     */
    fun artworkUrl(raw: String?): String? {
        if (raw.isNullOrEmpty()) return null
        val url = when {
            raw.startsWith("/__fixture__/") -> if (base.host in LOOPBACK_HOSTS) base.resolve(raw) else null
            "://" in raw -> raw.toHttpUrlOrNull()
            raw.startsWith("/") || ".." in raw -> null
            else -> CDN.resolve(raw)
        } ?: return null
        val allowed = url.scheme == "https" || (url.scheme == "http" && url.host in LOOPBACK_HOSTS)
        return if (allowed) url.toString() else null
    }

    // endregion

    /**
     * Decode a body with the tolerant decoder, mapping malformed JSON to
     * [FestivalApiException.InvalidResponse] (feature reads use this too).
     *
     * @param strategy Serializer.
     * @param body Body bytes.
     * @return Decoded value.
     */
    @OptIn(ExperimentalSerializationApi::class)
    internal fun <T> decode(strategy: DeserializationStrategy<T>, body: ByteArray): T =
        try {
            JSON.decodeFromStream(strategy, ByteArrayInputStream(body))
        } catch (error: IllegalArgumentException) {
            throw FestivalApiException.InvalidResponse()
        }

    companion object {
        /** Hosts treated as loopback fixture origins (`10.0.2.2` is the emulator's host alias). */
        val LOOPBACK_HOSTS = setOf("localhost", "127.0.0.1", "::1", "10.0.2.2")

        /** Public HTTPS origin used by default in every build type. */
        const val PUBLIC_ORIGIN = "https://festivalscoretracker.com"

        private val CDN = "https://cdn2.unrealengine.com/".toHttpUrlOrNull()!!

        /** Tolerant decoder: unknown wire keys (population tiers, provenance…) are skipped. */
        val JSON = Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
            explicitNulls = false
        }
    }
}

// endregion
