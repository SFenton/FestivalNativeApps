package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encoding.Decoder
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FestivalApiTest {
    private fun api(transport: HttpTransport = FakeTransport.standard(), origin: String = "https://fixture.test") = FestivalApi(origin, transport)

    private inline fun <reified T : Throwable> assertFails(noinline block: suspend () -> Unit) = runTest {
        try {
            block()
            fail("expected ${T::class.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) throw error
        }
    }

    private inline fun <reified T : Throwable> failsWith(block: () -> Unit) {
        try {
            block()
        } catch (error: Throwable) {
            if (error !is T) throw error
            return
        }
        fail("expected ${T::class.simpleName}")
    }

    // region Gate

    @Test
    fun gateRejectsKeysSelectedProfileHeadersAndNonGet() {
        RequestGate.validateKeyless(RequestGate.makeRequest("https://x/api/songs", mapOf("X-FST-Publication-Id" to "3")))
        listOf("X-API-Key", "x-api-key", "X-FST-Selected-Profile", "x-fst-selected-band").forEach { name ->
            assertThrows(FestivalApiException.ForbiddenRequest::class.java) {
                RequestGate.validateKeyless(HttpRequest("https://x", headers = mapOf(name to "v")))
            }
        }
        assertThrows(FestivalApiException.ForbiddenRequest::class.java) { RequestGate.validateKeyless(HttpRequest("https://x", method = "POST")) }
        val gate = RequestGate(FakeTransport.standard())
        assertFails<FestivalApiException.ForbiddenRequest> { gate.send(HttpRequest("https://x/api/songs", method = "DELETE")) }
        assertEquals("no-cache", RequestGate.makeRequest("https://x").headers["Cache-Control"])
    }

    @Test
    fun statusMapping() {
        fun result(status: Int, headers: Map<String, String> = emptyMap()) = HttpResult(status, ByteArray(0), headers)
        assertEquals(ServiceStatus.Success, RequestGate.mapStatus(result(200), false))
        assertEquals(ServiceStatus.Success, RequestGate.mapStatus(result(204), false))
        assertEquals(ServiceStatus.Syncing, RequestGate.mapStatus(result(202), true))
        assertThrows(FestivalApiException.Syncing::class.java) { RequestGate.mapStatus(result(202), false) }
        assertThrows(FestivalApiException.UnexpectedNotModified::class.java) { RequestGate.mapStatus(result(304), false) }
        val frozen = assertThrows(FestivalApiException.PublicReadFrozen::class.java) {
            RequestGate.mapStatus(result(503, mapOf("retry-after" to "30", "x-fst-public-read-freeze-reason" to "scrape")), false)
        }
        assertEquals("scrape", frozen.reason)
        assertEquals("30", frozen.retryAfter)
        val outage = assertThrows(FestivalApiException.Unavailable::class.java) {
            RequestGate.mapStatus(result(503, mapOf("Retry-After" to "12", ServiceFreezeReason.HEADER to "")), false)
        }
        assertEquals("12", outage.retryAfter)
        assertEquals(404, assertThrows(FestivalApiException.HttpStatus::class.java) { RequestGate.mapStatus(result(404), false) }.status)
    }

    @Test
    fun gateHonoursCancellation() = runTest {
        val gate = RequestGate { _ ->
            yield()
            HttpResult(200, ByteArray(0))
        }
        val job = async { gate.send(RequestGate.makeRequest("https://x")) }
        job.cancelAndJoin()
        assertTrue(job.isCancelled)
    }

    // endregion

    // region Origin and URLs

    @Test
    fun originMustBeHttpsOrLoopback() {
        api(origin = "https://festivalscoretracker.com")
        api(origin = "http://10.0.2.2:8080")
        api(origin = "http://localhost:8080")
        assertThrows(FestivalApiException.InsecureBaseUrl::class.java) { api(origin = "http://festivalscoretracker.com") }
        assertThrows(FestivalApiException.InsecureBaseUrl::class.java) { api(origin = "ftp://x") }
        assertEquals("https://fixture.test/", api().origin)
    }

    @Test
    fun endpointUrlsAreValidatedAndEncoded() {
        val base = "https://fixture.test".toHttpUrl()
        assertEquals("https://fixture.test/api/publication", ServiceEndpoint.PublicationRead.url(base))
        assertEquals("https://fixture.test/api/songs", ServiceEndpoint.Songs.url(base))
        assertEquals(
            "https://fixture.test/api/leaderboard/a%20b/Solo_Bass?top=10&offset=20",
            ServiceEndpoint.Leaderboard("a b", Instrument.Bass, 10, 20).url(base),
        )
        assertEquals("https://fixture.test/api/account/search?q=a%2Bb&limit=5", ServiceEndpoint.AccountSearch("a+b", 5).url(base))
        listOf("", "a/b", "..", ".", "a\\b").forEach { id ->
            assertThrows(FestivalApiException.InvalidResource::class.java) { ServiceEndpoint.Leaderboard(id, Instrument.Lead, 10, 0).url(base) }
        }
        assertThrows(FestivalApiException.InvalidResource::class.java) { ServiceEndpoint.Leaderboard("s", Instrument.Lead, 26, 0).url(base) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { ServiceEndpoint.Leaderboard("s", Instrument.Lead, 10, -1).url(base) }
        assertThrows(FestivalApiException.InvalidSearchQuery::class.java) { ServiceEndpoint.AccountSearch("a", 5).url(base) }
        assertThrows(FestivalApiException.InvalidResource::class.java) { ServiceEndpoint.AccountSearch("ab", 11).url(base) }
        assertTrue(ServiceEndpoint.Songs.pinned)
        assertFalse(ServiceEndpoint.AccountSearch("ab", 1).pinned)
        assertTrue(ServiceEndpoint.AccountSearch("ab", 1).acceptsSyncing)
        assertFalse(ServiceEndpoint.Songs.acceptsSyncing)
    }

    @Test
    fun artworkUrls() {
        val public = api()
        assertEquals("https://cdn2.unrealengine.com/a-512.jpg", public.artworkUrl("a-512.jpg"))
        assertEquals("https://img.test/x.png", public.artworkUrl("https://img.test/x.png"))
        assertNull(public.artworkUrl("http://img.test/x.png"))
        assertNull(public.artworkUrl("/abs.png"))
        assertNull(public.artworkUrl("../x.png"))
        assertNull(public.artworkUrl(null))
        assertNull(public.artworkUrl(""))
        assertNull(public.artworkUrl("/__fixture__/art.png"))
        val fixture = api(origin = "http://10.0.2.2:8080")
        assertEquals("http://10.0.2.2:8080/__fixture__/art.png", fixture.artworkUrl("/__fixture__/art.png"))
        assertEquals("http://localhost/x.png", fixture.artworkUrl("http://localhost/x.png"))
    }

    // endregion

    // region Publication

    @Test
    fun publicationIsCachedAndCannotMoveBackwards() = runTest {
        var id = 7
        val transport = FakeTransport().apply { on("/api/publication") { Fixtures.publication(id) } }
        val api = api(transport)
        assertEquals(7, api.publication().publicationId)
        assertEquals(7, api.publication().publicationId)
        assertEquals(1, transport.sent("/api/publication").size)
        assertEquals(7, api.publicationChanges.value)
        id = 8
        assertEquals(8, api.publication(force = true).publicationId)
        assertEquals(8, api.publicationChanges.value)
        id = 6
        try {
            api.publication(force = true)
            fail("expected InvalidPublication")
        } catch (_: FestivalApiException.InvalidPublication) {
        }
    }

    @Test
    fun publicationErrors() {
        val invalid = FakeTransport().apply { on("/api/publication") { """{"contractVersion":0,"publicationId":1,"publishedScrapeId":1}""" } }
        assertFails<FestivalApiException.InvalidPublication> { api(invalid).publication() }
        val garbage = FakeTransport().apply { on("/api/publication") { "not json" } }
        assertFails<FestivalApiException.InvalidResponse> { api(garbage).publication() }
        val noContent = FakeTransport().apply { on("/api/publication", status = 204) { "" } }
        assertFails<FestivalApiException.HttpStatus> { api(noContent).publication() }
        val frozen = FakeTransport().apply { on("/api/publication", status = 503, headers = mapOf(ServiceFreezeReason.HEADER to "publish")) { "{}" } }
        assertFails<FestivalApiException.PublicReadFrozen> { api(frozen).publication() }
    }

    // endregion

    // region Catalogue

    @Test
    fun catalogDecodesSkipsUnknownKeysAndMemoizes() = runTest {
        val transport = FakeTransport.standard()
        val api = api(transport)
        val payload = api.catalog()
        assertEquals(7, payload.publicationId)
        assertEquals(3, payload.catalog.count)
        assertEquals(15, payload.catalog.currentSeason)
        val alpha = payload.catalog.songs.first()
        assertEquals("alpha-512.jpg", alpha.albumArt)
        assertEquals(90000, alpha.maxScore(Instrument.Lead))
        assertTrue(payload.catalog.songs[1].usesKeyboardIcon)
        assertSame(payload, api.catalog())
        assertEquals(1, transport.sent("/api/songs").size)
        assertNull(transport.sent("/api/songs").single().headers["X-FST-Publication-Id"])
        transport.requests.forEach { request ->
            assertEquals("GET", request.method)
            assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected-") })
        }
    }

    @Test
    fun refreshRevalidatesWithEtagAndServesCachedBodyOn304() = runTest {
        val transport = FakeTransport.standard()
        transport.onRaw("/api/songs") { request ->
            if (request.headers["If-None-Match"] == "W/\"songs\"") {
                HttpResult(304, ByteArray(0), mapOf("X-FST-Publication-Id" to "7"))
            } else {
                HttpResult(200, Fixtures.songsJson.toByteArray(), mapOf("X-FST-Publication-Id" to "7", "ETag" to "W/\"songs\""))
            }
        }
        val api = api(transport)
        api.catalog()
        val refreshed = api.catalog(refresh = true)
        assertEquals(3, refreshed.catalog.songs.size)
        assertEquals("W/\"songs\"", transport.sent("/api/songs").last().headers["If-None-Match"])
    }

    @Test
    fun refreshOfUnchangedBodyReusesDecodedCatalogButRedecodesChangedBody() = runTest {
        var mode = "etag"
        val transport = FakeTransport.standard()
        transport.onRaw("/api/songs") { request ->
            when {
                mode == "changed" -> HttpResult(200, Fixtures.songsJson.replace("\"Alpha Tune\"", "\"Alpha Tune 2\"").toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
                mode == "same200" -> HttpResult(200, Fixtures.songsJson.toByteArray(), mapOf("X-FST-Publication-Id" to "7", "ETag" to "W/\"songs\""))
                request.headers["If-None-Match"] == "W/\"songs\"" -> HttpResult(304, ByteArray(0), mapOf("X-FST-Publication-Id" to "7"))
                else -> HttpResult(200, Fixtures.songsJson.toByteArray(), mapOf("X-FST-Publication-Id" to "7", "ETag" to "W/\"songs\""))
            }
        }
        val decoding = CountingDispatcher()
        val api = FestivalApi("https://fixture.test", transport, decoding, offloadBytes = 0)
        val first = api.catalog()
        val decodes = decoding.dispatches.get()
        assertSame(first, api.catalog(refresh = true))
        mode = "same200"
        assertSame(first, api.catalog(refresh = true))
        assertEquals("only the forced /api/publication re-check decodes on an unchanged refresh", decodes + 2, decoding.dispatches.get())
        assertEquals(3, transport.sent("/api/songs").size)
        mode = "changed"
        val updated = api.catalog(refresh = true)
        assertNotSame(first, updated)
        assertEquals("Alpha Tune 2", updated.catalog.songs.first().title)
        assertTrue(decoding.dispatches.get() > decodes)
        decoding.close()
    }

    @Test
    fun largeBodiesDecodeAndValidateOnDecodeDispatcherNotCaller() = runTest {
        val decoding = CountingDispatcher()
        val api = FestivalApi("https://fixture.test", FakeTransport.standard(), decoding, offloadBytes = 4)
        val caller = Thread.currentThread()
        val threads = mutableListOf<Thread>()
        val recording = object : DeserializationStrategy<String> by String.serializer() {
            override fun deserialize(decoder: Decoder): String = String.serializer().deserialize(decoder).also { threads += Thread.currentThread() }
        }
        assertEquals("ok", api.decode(recording, "\"ok\"".toByteArray()))
        var validatedOn: Thread? = null
        assertEquals(2, api.decode(recording, "\"ok\"".toByteArray()) { validatedOn = Thread.currentThread(); it.length })
        assertEquals("", api.decode(recording, "\"\"".toByteArray()))
        assertEquals(listOf(decoding.thread, decoding.thread, caller), threads)
        assertSame(decoding.thread, validatedOn)
        assertNotSame(caller, decoding.thread)
        assertEquals(2, decoding.dispatches.get())
        assertEquals(3, api.catalog().catalog.songs.size)
        assertTrue(decoding.dispatches.get() >= 4)
        val malformed = runCatching { api.decode(recording, "not json".toByteArray()) }.exceptionOrNull()
        assertTrue(malformed is FestivalApiException.InvalidResponse)
        assertEquals(64 * 1024, FestivalApi.OFFLOAD_BYTES)
        decoding.close()
    }

    /** Single named thread that counts dispatches, standing in for `Dispatchers.Default`. */
    private class CountingDispatcher : CoroutineDispatcher() {
        private val executor = Executors.newSingleThreadExecutor { Thread(it, "fst-decode-test") }
        val thread: Thread = executor.submit<Thread> { Thread.currentThread() }.get()
        val dispatches = AtomicInteger()

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            dispatches.incrementAndGet()
            executor.execute(block)
        }

        fun close() = executor.shutdown()
    }

    @Test
    fun stray304WithoutCacheRetriesWithoutEtag() = runTest {
        val calls = AtomicInteger()
        val transport = FakeTransport.standard()
        transport.onRaw("/api/songs") {
            if (calls.getAndIncrement() == 0) HttpResult(304, ByteArray(0)) else HttpResult(200, Fixtures.songsJson.toByteArray())
        }
        assertEquals(3, api(transport).catalog().catalog.songs.size)
        assertEquals(2, calls.get())
        val always304 = FakeTransport.standard().apply { onRaw("/api/songs") { HttpResult(304, ByteArray(0)) } }
        assertFails<FestivalApiException.UnexpectedNotModified> { api(always304).catalog() }
    }

    @Test
    fun publicationConflictRetriesOnce() = runTest {
        var publication = 7
        val transport = FakeTransport().apply {
            on("/api/publication") { Fixtures.publication(publication, pinning = true) }
            onRaw("/api/songs") { request ->
                if (request.headers["X-FST-Publication-Id"] == "7") {
                    publication = 8
                    HttpResult(409, """{"status":"publication_changed"}""".toByteArray())
                } else {
                    HttpResult(200, Fixtures.songsJson.toByteArray(), mapOf("X-FST-Publication-Id" to "8"))
                }
            }
        }
        val payload = api(transport).catalog()
        assertEquals(8, payload.publicationId)
        assertEquals(listOf("7", "8"), transport.sent("/api/songs").map { it.headers["X-FST-Publication-Id"] })
    }

    @Test
    fun otherConflictIsAnError() {
        val transport = FakeTransport.standard().apply { on("/api/songs", status = 409) { """{"status":"other"}""" } }
        assertFails<FestivalApiException.HttpStatus> { api(transport).catalog() }
        val garbage = FakeTransport.standard().apply { on("/api/songs", status = 409) { "nope" } }
        assertFails<FestivalApiException.HttpStatus> { api(garbage).catalog() }
    }

    @Test
    fun newerResponsePublicationIsAdoptedWhenNotPinning() = runTest {
        var publication = 7
        val transport = FakeTransport().apply {
            on("/api/publication") { Fixtures.publication(publication) }
            onRaw("/api/songs") {
                publication = 9
                HttpResult(200, Fixtures.songsJson.toByteArray(), mapOf("X-FST-Publication-Id" to "9"))
            }
        }
        val api = api(transport)
        assertEquals(9, api.catalog().publicationId)
        assertEquals(9, api.publicationChanges.value)
    }

    @Test
    fun inconsistentResponsePublicationsFail() {
        val older = FakeTransport.standard().apply { on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "3")) { Fixtures.songsJson } }
        assertFails<FestivalApiException.InvalidPublication> { api(older).catalog() }
        val pinnedMismatch = FakeTransport().apply {
            on("/api/publication") { Fixtures.publication(7, pinning = true) }
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "9")) { Fixtures.songsJson }
        }
        assertFails<FestivalApiException.InvalidPublication> { api(pinnedMismatch).catalog() }
        val stuck = FakeTransport().apply {
            on("/api/publication") { Fixtures.publication(7) }
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "9")) { Fixtures.songsJson }
        }
        assertFails<FestivalApiException.InvalidPublication> { api(stuck).catalog() }
    }

    @Test
    fun catalogueValidationAndFreeze() {
        val inconsistent = FakeTransport.standard().apply { on("/api/songs") { """{"count":5,"songs":[]}""" } }
        assertFails<FestivalApiException.InvalidCatalogue> { api(inconsistent).catalog() }
        val frozen = FakeTransport.standard().apply {
            on("/api/songs", status = 503, headers = mapOf("Retry-After" to "30", ServiceFreezeReason.HEADER to "scrape")) { "{}" }
        }
        assertFails<FestivalApiException.PublicReadFrozen> { api(frozen).catalog() }
        val forced = ForcedFreezeTransport(FakeTransport.standard())
        assertFails<FestivalApiException.PublicReadFrozen> { api(forced).catalog() }
    }

    /** A 503 for `/api/<path>` with the given freeze reason and publication header (either may be absent). */
    private fun freeze503(reason: String?, publicationId: String? = "7") = HttpResult(
        503,
        ByteArray(0),
        listOfNotNull("Retry-After" to "30", reason?.let { ServiceFreezeReason.HEADER to it }, publicationId?.let { "X-FST-Publication-Id" to it }).toMap(),
    )

    @Test
    fun scoreUpdateFreezeServesTheBodyAlreadyReadThisPublication() = runTest {
        var frozen: HttpResult? = null
        val transport = FakeTransport.standard().apply {
            // Like live band /songs and /history: publication-stamped, no ETag.
            onRaw("/api/x") { frozen ?: HttpResult(200, "published".toByteArray(), mapOf("X-FST-Publication-Id" to "7")) }
            onRaw("/api/never") { freeze503("scrape") }
        }
        val api = api(transport)
        val x = ServiceEndpoint.Feature(listOf("x"))
        assertEquals("published", String(api.readPinnedResponse(x).body))
        assertNull("an ETag-less body is kept without a conditional request", transport.sent("/api/x").single().headers["If-None-Match"])
        for (reason in listOf("scrape", "post-process", "publish", "publication-commit", "publication-commit-deferred")) {
            frozen = freeze503(reason)
            val read = api.readPinnedResponse(x)
            assertEquals(reason, "published", String(read.body))
            assertEquals(200, read.status)
            assertEquals(7, read.responsePublicationId)
            assertEquals(7, read.observedPublicationId)
        }
        frozen = freeze503("scrape", publicationId = null)
        assertEquals("a headerless freeze is still this publication", "published", String(api.readPinnedResponse(x).body))
        // Never read this publication: the freeze stays a freeze.
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(ServiceEndpoint.Feature(listOf("never"))) }
        // A generic outage, a non-score freeze or a different publication still fail.
        frozen = freeze503(reason = null)
        failsWith<FestivalApiException.Unavailable> { api.readPinnedResponse(x) }
        frozen = freeze503("max-score-maintenance:v1:x")
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(x) }
        frozen = freeze503("scrape", publicationId = "8")
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(x) }
        frozen = HttpResult(500, ByteArray(0), mapOf(ServiceFreezeReason.HEADER to "scrape"))
        failsWith<FestivalApiException.HttpStatus> { api.readPinnedResponse(x) }
    }

    @Test
    fun aNewerPublicationDropsTheKeptBodies() = runTest {
        var frozen = false
        val transport = FakeTransport.standard().apply {
            onRaw("/api/x") { if (frozen) freeze503("scrape", publicationId = null) else HttpResult(200, "p7".toByteArray(), mapOf("X-FST-Publication-Id" to "7")) }
        }
        val api = api(transport)
        val x = ServiceEndpoint.Feature(listOf("x"))
        api.readPinnedResponse(x)
        transport.on("/api/publication") { Fixtures.publication(8) }
        api.publication(force = true)
        frozen = true
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(x) }
    }

    @Test
    fun keptBodiesStayWithinTheirByteBudget() = runTest {
        var frozen = false
        val transport = FakeTransport.standard().apply {
            listOf("a" to 4, "b" to 4, "c" to 4, "big" to 11).forEach { (path, size) ->
                onRaw("/api/$path") { if (frozen) freeze503("scrape") else HttpResult(200, ByteArray(size) { 1 }, mapOf("X-FST-Publication-Id" to "7")) }
            }
        }
        val api = FestivalApi("https://fixture.test", transport, retainedBytes = 10)
        fun endpoint(path: String) = ServiceEndpoint.Feature(listOf(path))
        api.readPinnedResponse(endpoint("a"))
        api.readPinnedResponse(endpoint("b"))
        api.readPinnedResponse(endpoint("big"))
        frozen = true
        api.readPinnedResponse(endpoint("a"))
        frozen = false
        api.readPinnedResponse(endpoint("c"))
        frozen = true
        // `big` never fitted; `c` evicted the least recently used `b`, not the just-served `a`.
        assertEquals(4, api.readPinnedResponse(endpoint("a")).body.size)
        assertEquals(4, api.readPinnedResponse(endpoint("c")).body.size)
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(endpoint("b")) }
        failsWith<FestivalApiException.PublicReadFrozen> { api.readPinnedResponse(endpoint("big")) }
        assertEquals(32L * 1024 * 1024, FestivalApi.RETAINED_BYTES)
    }

    // endregion

    // region Leaderboard and search

    @Test
    fun leaderboardPagesAndValidates() = runTest {
        val transport = FakeTransport.standard()
        val api = api(transport)
        val page = api.leaderboard("s-alpha", Instrument.Lead, 2, 25)
        assertEquals(2, page.page)
        assertEquals(26, page.leaderboard.entries.first().rank)
        assertTrue(transport.sent("/api/leaderboard/s-alpha/Solo_Guitar").single().url.endsWith("top=25&offset=25"))
        assertTrue(page.leaderboard.entries.first().isFullCombo == true)
        assertEquals(1_000_000.0, page.leaderboard.entries.first().accuracy!!, 0.0)
    }

    @Test
    fun leaderboardRejectsBadArguments() {
        assertFails<FestivalApiException.InvalidResource> { api().leaderboard("s-alpha", Instrument.Lead, 0) }
        assertFails<FestivalApiException.InvalidResource> { api().leaderboard("s-alpha", Instrument.Lead, 1, 30) }
        assertFails<FestivalApiException.InvalidResource> { api().leaderboard("s-alpha", Instrument.Lead, Int.MAX_VALUE, 25) }
        val mismatched = FakeTransport.standard().apply { on("/api/leaderboard/s-alpha/Solo_Guitar") { Fixtures.leaderboard("other") } }
        assertFails<FestivalApiException.InvalidLeaderboard> { api(mismatched).leaderboard("s-alpha", Instrument.Lead, 1, 10) }
    }

    @Test
    fun searchFiltersInvalidRowsAndAcceptsSyncing() = runTest {
        val results = api().searchPlayers("syn")
        assertEquals(listOf(Fixtures.ACCOUNT_A), results.map { it.accountId })
        val syncing = FakeTransport.standard().apply { on("/api/account/search", status = 202) { "{}" } }
        assertTrue(api(syncing).searchPlayers("syn").isEmpty())
        try {
            api().searchPlayers(" x")
            fail("expected InvalidSearchQuery")
        } catch (_: FestivalApiException.InvalidSearchQuery) {
        }
    }

    @Test
    fun forcedFreezeFreezesEachPathOnceButNeverPublication() = runTest {
        val inner = FakeTransport.standard()
        val forced = ForcedFreezeTransport(inner, retryAfter = "5")
        val first = forced.send(RequestGate.makeRequest("https://fixture.test/api/songs"))
        assertEquals(503, first.status)
        assertEquals("5", first.header("retry-after"))
        assertEquals("scrape", first.header(ServiceFreezeReason.HEADER))
        assertEquals(200, forced.send(RequestGate.makeRequest("https://fixture.test/api/songs")).status)
        assertEquals(200, forced.send(RequestGate.makeRequest("https://fixture.test/api/publication")).status)
        assertEquals(404, forced.send(RequestGate.makeRequest("https://fixture.test/other")).status)
    }

    @Test
    fun cancellationPropagatesThroughReads() = runTest {
        val transport = FakeTransport.standard().apply {
            onRaw("/api/songs") { throw CancellationException("cancelled") }
        }
        try {
            api(transport).catalog()
            fail("expected cancellation")
        } catch (_: CancellationException) {
        }
    }

    // endregion
}
