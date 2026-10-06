package com.festivalscoretracker.android.testing

import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.rules.TestWatcher
import org.junit.runner.Description

// region Synthetic data

/** Synthetic, captured-shape fixtures. Never production titles, payloads or account IDs. */
object Fixtures {
    /** Synthetic 32-hex account ID. */
    const val ACCOUNT_A = "0123456789abcdef0123456789abcdef"

    /** Second synthetic account ID. */
    const val ACCOUNT_B = "fedcba9876543210fedcba9876543210"

    /**
     * Build a synthetic song.
     *
     * @param id Song ID.
     * @param title Title.
     * @param artist Artist.
     * @param year Year.
     * @param duration Seconds.
     * @param lead Raw Lead difficulty (null = uncharted).
     * @return Song.
     */
    fun song(id: String, title: String, artist: String = "Synthetic Artist", year: Int? = 2020, duration: Int? = 200, lead: Double? = 3.0) = Song(
        songId = id,
        title = title,
        artist = artist,
        year = year,
        durationSeconds = duration,
        albumArt = null,
        difficulty = SongDifficulty(guitar = lead, bass = 2.0, drums = 1.0, vocals = 99.0, proGuitar = 4.0, proBass = 0.0, proDrums = 5.0, proCymbals = 5.9, proVocals = null),
    )

    /** Publication JSON. */
    fun publication(id: Int = 7, pinning: Boolean = false) =
        """{"contractVersion":1,"publicationId":$id,"publishedScrapeId":11,"readyForPinning":$pinning,"pinningEnabled":$pinning,"unreadySurfaces":[{"surface":"song_catalog","reasons":["x"]}],"previousPublicationId":6}"""

    /** Songs JSON with extra unknown keys the decoder must skip. */
    val songsJson = """
        {"count":3,"currentSeason":15,"songs":[
          {"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","year":2021,"durationSeconds":185,"albumArt":"alpha-512.jpg","sig":"Guitar",
           "difficulty":{"guitar":3,"bass":0,"vocals":2,"drums":1,"proGuitar":3,"proBass":0,"proDrums":1,"proCymbals":1,"proVocals":3},
           "maxScores":{"Solo_Guitar":90000},"populationTiers":{"Solo_Guitar":{"tiers":[1,2,3]}},"genres":["x"]},
          {"songId":"s-beta","title":"Beta Song","artist":"Band Two","year":2019,"durationSeconds":240,"albumArt":null,"sig":"Keyboard",
           "difficulty":{"guitar":5,"bass":4}},
          {"songId":"s-gamma","title":"Échos","artist":"Band Three","year":2023,"durationSeconds":95,
           "difficulty":{"drums":6}}
        ]}
    """.trimIndent()

    /**
     * Leaderboard JSON.
     *
     * @param songId Song.
     * @param instrument Wire instrument.
     * @param rows Row count.
     * @param total Total entries.
     * @param startRank First rank.
     * @return JSON.
     */
    fun leaderboard(songId: String, instrument: String = "Solo_Guitar", rows: Int = 2, total: Int = 60, startRank: Int = 1): String {
        val entries = (0 until rows).joinToString(",") { i ->
            val rank = startRank + i
            """{"accountId":"${ACCOUNT_A.dropLast(2)}${(10 + i % 80)}","displayName":"Synthetic Player $rank","score":${100000 - rank},"rank":$rank,"accuracy":${if (i == 0) 1000000 else 987654},"isFullCombo":${i == 0},"stars":6,"season":15,"difficulty":3,"percentile":0.1,"source":"scrape"}"""
        }
        return """{"songId":"$songId","instrument":"$instrument","showLeaderboardEntryTotals":false,"count":$rows,"totalEntries":$total,"localEntries":$total,"entries":[$entries]}"""
    }
}

// endregion

// region Fake transport

/**
 * Routes requests by path (without query) to canned responses and records them.
 *
 * @property routes Path → response factory.
 */
class FakeTransport(private val routes: MutableMap<String, (HttpRequest) -> HttpResult> = mutableMapOf()) : HttpTransport {
    /** Every request sent, in order. */
    val requests = mutableListOf<HttpRequest>()

    /** Runs before each request is answered; a test can suspend here to hold reads open (loading states). */
    var beforeRespond: suspend (HttpRequest) -> Unit = {}

    /**
     * Register a JSON response.
     *
     * @param path URL path such as `/api/songs`.
     * @param status Status.
     * @param headers Response headers.
     * @param body Body factory.
     */
    fun on(path: String, status: Int = 200, headers: Map<String, String> = emptyMap(), body: (HttpRequest) -> String) {
        routes[path] = { request -> HttpResult(status, body(request).toByteArray(), headers) }
    }

    /**
     * Register a raw response factory.
     *
     * @param path URL path.
     * @param respond Factory.
     */
    fun onRaw(path: String, respond: (HttpRequest) -> HttpResult) {
        routes[path] = respond
    }

    override suspend fun send(request: HttpRequest): HttpResult {
        requests += request
        beforeRespond(request)
        val path = request.url.substringAfter("://").substringAfter('/').substringBefore('?').let { "/$it" }
        val route = routes[path] ?: return HttpResult(404, "{}".toByteArray())
        return route(request)
    }

    /**
     * Requests whose URL path matches.
     *
     * @param path Path.
     * @return Matching requests.
     */
    fun sent(path: String) = requests.filter { it.url.substringAfter("://").substringAfter('/').substringBefore('?').let { p -> "/$p" } == path }

    companion object {
        /**
         * Transport serving a publication, the synthetic songs and generic leaderboards.
         *
         * @return Configured transport.
         */
        fun standard(): FakeTransport = FakeTransport().apply {
            on("/api/publication") { Fixtures.publication() }
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7", "ETag" to "W/\"songs\"")) { Fixtures.songsJson }
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson }
            listOf("s-alpha", "s-beta", "s-gamma").forEach { id ->
                listOf("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums").forEach { instrument ->
                    on("/api/leaderboard/$id/$instrument", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
                        val top = Regex("top=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 25
                        val offset = Regex("offset=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 0
                        Fixtures.leaderboard(id, instrument, rows = minOf(top, 60 - offset).coerceAtLeast(0), total = 60, startRank = offset + 1)
                    }
                }
                // Song Detail band previews: empty boards unless a test installs rows.
                listOf("Band_Duets", "Band_Trios", "Band_Quad").forEach { type ->
                    on("/api/leaderboard/$id/bands/$type", headers = mapOf("X-FST-Publication-Id" to "7")) {
                        """{"songId":"$id","bandType":"$type","count":0,"totalEntries":0,"localEntries":0,"entries":[]}"""
                    }
                }
            }
            on("/api/account/search") { """{"results":[{"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player"},{"accountId":"bad/id","displayName":"Invalid"}]}""" }
        }
    }
}

// endregion

// region Main dispatcher rule

/**
 * Installs a [StandardTestDispatcher] as `Dispatchers.Main` for view model tests.
 *
 * @property dispatcher The test dispatcher (share it with `runTest`).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(val dispatcher: TestDispatcher = StandardTestDispatcher()) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(dispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}

// endregion
