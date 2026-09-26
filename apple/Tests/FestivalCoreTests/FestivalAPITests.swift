import Foundation
import Testing
@testable import FestivalCore

actor FixtureTransport: HTTPTransport {
    private var replies: [Result<HTTPResult, URLError>]
    private var requests: [URLRequest] = []

    /// Create a deterministic ordered transport.
    ///
    /// - Parameter replies: Responses to consume in HTTP order.
    init(_ replies: [HTTPResult]) {
        self.replies = replies.map(Result.success)
    }

    /// Create a transport with both response and network-failure fixtures.
    ///
    /// - Parameter results: Network outcomes in request order.
    init(results: [Result<HTTPResult, URLError>]) {
        replies = results
    }

    /// Return the next fixture and retain the request for assertions.
    ///
    /// - Parameter request: Sent URLRequest.
    /// - Returns: Next mock response.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !replies.isEmpty else {
            throw FestivalAPIError.invalidResponse
        }
        return try replies.removeFirst().get()
    }

    /// Return requests observed to date.
    ///
    /// - Returns: HTTP requests in send order.
    func recorded() -> [URLRequest] {
        requests
    }
}

private actor ReorderedPublicationTransport: HTTPTransport {
    private var publicationReads = 0
    private var oldResponse: CheckedContinuation<HTTPResult, Error>?
    private var oldRequestQueued: CheckedContinuation<Void, Never>?

    /// Suspend generation seven's song response while a newer publication arrives.
    ///
    /// - Parameter request: Pending publication or song request.
    /// - Returns: Controlled HTTP result after any required release.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if request.url?.path == "/api/publication" {
            publicationReads += 1
            if publicationReads == 1 {
                return HTTPResult(status: 200, data: publicationJSON)
            }
            return reply(200, """
            {"contractVersion":1,"publicationId":8,"publishedScrapeId":43,
            "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """)
        }
        if request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "7" {
            return try await withCheckedThrowingContinuation { continuation in
                oldResponse = continuation
                oldRequestQueued?.resume()
                oldRequestQueued = nil
            }
        }
        if request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "8" {
            return reply(200, "new", headers: ["X-FST-Publication-Id": "8"])
        }
        throw FestivalAPIError.invalidResource
    }

    /// Wait until the stale request is suspended without relying on sleeps.
    func waitForOldRequest() async {
        if oldResponse != nil { return }
        await withCheckedContinuation { continuation in oldRequestQueued = continuation }
    }

    /// Complete the old request after the client has observed generation eight.
    func releaseOldRequest() {
        oldResponse?.resume(returning: reply(
            200, "old", headers: ["X-FST-Publication-Id": "7"]
        ))
        oldResponse = nil
    }
}

/// Ignore task cancellation until an explicitly released connectivity failure arrives.
private actor HeldOfflineFailureTransport: HTTPTransport {
    let pinned: Bool
    private var songReads = 0
    private var suspended: CheckedContinuation<HTTPResult, Error>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Choose verified or headerless bytes for both cached-reader paths.
    ///
    /// - Parameter pinned: True for a response-proven publication header.
    init(pinned: Bool) { self.pinned = pinned }

    /// Hold the second public read so the caller can cancel it before the error.
    ///
    /// - Parameter request: Publication or catalogue fixture request.
    /// - Returns: Valid first bytes or a later controlled transport error.
    /// - Throws: Unknown endpoint or the deliberately late network error.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        switch request.url?.path {
        case "/api/publication":
            return HTTPResult(
                status: 200,
                data: pinned ? publicationJSON : unpinnedPublicationJSON
            )
        case "/api/songs":
            songReads += 1
            if songReads == 1 {
                return HTTPResult(
                    status: 200, data: unpinnedSongsJSON,
                    headers: pinned ? ["X-FST-Publication-Id": "7"] : [:]
                )
            }
            return try await withCheckedThrowingContinuation { continuation in
                suspended = continuation
                waiting?.resume()
                waiting = nil
            }
        default:
            throw FestivalAPIError.invalidResource
        }
    }

    /// Wait for the ignored-cancellation transport to reach its second request.
    func waitForPending() async {
        if suspended != nil { return }
        await withCheckedContinuation { continuation in waiting = continuation }
    }

    /// Complete the held request with an otherwise offline-cache-eligible error.
    func releaseAsConnectivityLoss() {
        suspended?.resume(throwing: URLError(.notConnectedToInternet))
        suspended = nil
    }
}

private final class FixtureURLProtocol: URLProtocol {
    /// Intercept requests only for this test-only domain.
    ///
    /// - Parameter request: Candidate network request.
    /// - Returns: True for an intentionally mocked host.
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fixture.test"
    }

    /// Preserve the fixture URL without rewriting it.
    ///
    /// - Parameter request: Candidate network request.
    /// - Returns: Canonical request for the fixture host.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// Synchronously supply bytes or a deliberately non-HTTP response.
    override func startLoading() {
        guard let url = request.url, let client else {
            fatalError("Fixture protocol requires a request and URL loading client")
        }
        let response: URLResponse
        if url.path == "/not-http" {
            response = URLResponse(
                url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            )
        } else {
            response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["X-FST-Publication-Id": "7"]
            )!
        }
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Data("fixture".utf8))
        client.urlProtocolDidFinishLoading(self)
    }

    /// Nothing runs after the synchronous fixture response has completed.
    override func stopLoading() {}
}

private let publicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private let unpinnedPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
""".utf8)

private let unpinnedSongsJSON = Data("""
{"count":1,"songs":[{"songId":"fixture-one","title":"One","artist":"Fixture"}]}
""".utf8)

private func reply(_ status: Int, _ text: String = "", headers: [String: String] = [:]) -> HTTPResult {
    HTTPResult(status: status, data: Data(text.utf8), headers: headers)
}

@Test func pinnedRequestAndMatching304ReusesMemory() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "{\"songs\":[]}", headers: ["ETag": "\"first\"", "X-FST-Publication-Id": "7"]),
        reply(304, headers: ["x-fst-publication-id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)

    let first = try await client.read(.songs)
    let second = try await client.read(.songs)

    #expect(first.data == second.data)
    #expect(!second.isStale)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[1].value(forHTTPHeaderField: "X-FST-Publication-Id") == "7")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"first\"")
    #expect(requests.allSatisfy {
        $0.value(forHTTPHeaderField: "X-API-Key") == nil
    })
}

@Test func mismatched304RefetchesWithoutETag() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "fresh", headers: ["ETag": "v1", "X-FST-Publication-Id": "7"]),
        reply(304, headers: ["X-FST-Publication-Id": "6"]),
        reply(200, "new", headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    _ = try await client.read(.songs)
    let latest = try await client.read(.songs)
    let requests = await transport.recorded()
    #expect(String(decoding: latest.data, as: UTF8.self) == "new")
    #expect(requests[3].value(forHTTPHeaderField: "If-None-Match") == nil)
}

@Test func publicationConflictRetriesOnlyOnce() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(409, "{\"status\":\"publication_changed\"}"),
        HTTPResult(status: 200, data: Data("""
        {"contractVersion":1,"publicationId":8,"publishedScrapeId":43,
        "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
        """.utf8)),
        reply(200, "new", headers: ["X-FST-Publication-Id": "8"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let result = try await client.read(.songs)
    #expect(result.publicationId == 8)
    let requests = await transport.recorded()
    #expect(requests.count == 4)
    #expect(requests[3].value(forHTTPHeaderField: "X-FST-Publication-Id") == "8")
}

@Test func unrelatedConflictIsAnError() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(409, "{\"status\":\"other\"}"),
    ]))
    await #expect(throws: FestivalAPIError.httpStatus(409)) {
        try await client.read(.songs)
    }
}

@Test func invalidPublicationAndInsecureOriginFail() async throws {
    #expect(throws: FestivalAPIError.insecureBaseURL) {
        try FestivalAPI(baseURL: URL(string: "http://example.com")!)
    }
    let client = try FestivalAPI(transport: FixtureTransport([
        reply(200, """
        {"contractVersion":1,"publicationId":0,"publishedScrapeId":1,
        "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
        """),
    ]))
    await #expect(throws: FestivalAPIError.invalidPublication) {
        try await client.read(.songs)
    }
}

@Test func warmSessionOfflineResponseIsExplicitlyStale() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: publicationJSON)),
        .success(reply(200, "remembered", headers: ["X-FST-Publication-Id": "7"])),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    _ = try await client.read(.songs)
    let offline = try await client.read(.songs)
    #expect(offline.isStale)
    #expect(String(decoding: offline.data, as: UTF8.self) == "remembered")
    let coldClient = try FestivalAPI(transport: FixtureTransport(results: [
        .failure(URLError(.notConnectedToInternet))
    ]))
    await #expect(throws: URLError.self) {
        try await coldClient.read(.songs)
    }
}

@Test func unavailableAndMismatchedPublicationSurfaceErrors() async throws {
    let unavailable = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(503, headers: ["Retry-After": "30"]),
    ]))
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: "30")) {
        try await unavailable.read(.songs)
    }
    let mismatch = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "wrong", headers: ["X-FST-Publication-Id": "6"]),
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "wrong", headers: ["X-FST-Publication-Id": "6"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidPublication) {
        try await mismatch.read(.songs)
    }
}

@Test func missingPublicationHeaderDoesNotCreateOfflineCache() async throws {
    let transport = FixtureTransport(results: [
        .success(reply(200, "unversioned")),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    _ = try await client.readOperational(.features)
    await #expect(throws: URLError.self) {
        try await client.readOperational(.features)
    }
    let requests = await transport.recorded()
    #expect(requests.count == 2)
    #expect(requests.allSatisfy {
        $0.url?.path == "/api/features"
            && $0.value(forHTTPHeaderField: "X-FST-Publication-Id") == nil
    })
}

@Test func publicEndpointsAreConstrainedAndEncoded() throws {
    let base = URL(string: "https://example.com")!
    #expect(try OperationalEndpoint.features.url(relativeTo: base).path == "/api/features")
    #expect(
        try PublicEndpoint.leaderboard(songId: "track 1", instrument: "pro-lead")
            .url(relativeTo: base).absoluteString
        == "https://example.com/api/leaderboard/track%201/pro-lead?top=25&offset=0"
    )
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.leaderboard(songId: "a/b", instrument: "lead")
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.leaderboard(songId: "song", instrument: "lead", top: 0)
            .url(relativeTo: base)
    }
    #expect(
        try PublicEndpoint.leaderboard(
            songId: "song", instrument: "Solo_Guitar", offset: 25, leeway: 1.5
        ).url(relativeTo: base).query == "top=25&offset=25&leeway=1.5"
    )
}

@Test func ephemeralURLSessionTransportUsesHTTPFixtures() async throws {
    let transport = URLSessionHTTPTransport(protocolClasses: [FixtureURLProtocol.self])
    let result = try await transport.send(URLRequest(url: URL(string: "https://fixture.test/ok")!))
    #expect(result.status == 200)
    #expect(result.header("x-fst-publication-id") == "7")
    #expect(String(decoding: result.data, as: UTF8.self) == "fixture")
    await #expect(throws: FestivalAPIError.invalidResponse) {
        try await transport.send(URLRequest(url: URL(string: "https://fixture.test/not-http")!))
    }
}

@Test func missingSecondETagResponseFailsRatherThanAcceptingStaleBytes() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(304),
        reply(304),
    ]))
    await #expect(throws: FestivalAPIError.unexpectedNotModified) {
        try await client.read(.songs)
    }
}

@Test func publicationHTTPFailureAndInvalidFieldsAreErrors() async throws {
    let badStatus = try FestivalAPI(transport: FixtureTransport([reply(503)]))
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: nil)) {
        try await badStatus.publication()
    }
    let refreshing = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(503, headers: ["Retry-After": "30"]),
    ]))
    _ = try await refreshing.publication()
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: "30")) {
        try await refreshing.publication(force: true)
    }
    #expect((try await refreshing.publication()).publicationId == 7)
    let invalid = try FestivalAPI(transport: FixtureTransport([reply(200, "{}")]))
    await #expect(throws: DecodingError.self) {
        try await invalid.publication()
    }
}

@Test func publicationDecodesStructuredUnreadySurfaces() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        reply(200, """
        {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
        "readyForPinning":false,"pinningEnabled":false,
        "unreadySurfaces":[{"surface":"songs","reasons":["awaiting publication"]}]}
        """),
        reply(200, "pending"),
    ]))
    let publication = try await client.publication()
    #expect(publication.unreadySurfaces.first?.surface == "songs")
    #expect(publication.unreadySurfaces.first?.reasons == ["awaiting publication"])
    _ = try await client.read(.songs)
}

@Test func typedCatalogueSurfacesDecodedSongsAndInvalidCounts() async throws {
    let valid = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, """
        {"count":1,"songs":[{"songId":"fixture-one","title":"One","artist":"Fixture"}]}
        """, headers: ["X-FST-Publication-Id": "7"]),
    ]))
    let catalog = try await valid.catalog()
    #expect(catalog.catalog.songs.first?.title == "One")
    #expect(!catalog.isStale)
    let invalid = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, #"{"count":2,"songs":[]}"#, headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidCatalogue) {
        try await invalid.catalog()
    }
}

@Test func leaderboardPagesUseDistinctCacheKeysAndETags() async throws {
    let pageOne = """
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":1,
    "totalEntries":26,"localEntries":26,
    "entries":[{"accountId":"player-1","rank":1,"score":100000}]}
    """
    let pageTwo = """
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":1,
    "totalEntries":26,"localEntries":26,
    "entries":[{"accountId":"player-26","rank":26,"score":90000}]}
    """
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, pageOne, headers: ["X-FST-Publication-Id": "7", "ETag": "p1"]),
        reply(200, pageTwo, headers: ["X-FST-Publication-Id": "7", "ETag": "p2"]),
        reply(304, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.leaderboard(songId: "fixture-pulse", instrument: .lead, page: 1)
    let second = try await client.leaderboard(songId: "fixture-pulse", instrument: .lead, page: 2)
    let again = try await client.leaderboard(songId: "fixture-pulse", instrument: .lead, page: 1)
    #expect(first.leaderboard.entries[0].rank == 1)
    #expect(second.leaderboard.entries[0].rank == 26)
    #expect(again.leaderboard.entries[0].rank == 1)
    let requests = await transport.recorded()
    #expect(requests[1].url?.query == "top=25&offset=0")
    #expect(requests[2].url?.query == "top=25&offset=25")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requests[3].value(forHTTPHeaderField: "If-None-Match") == "p1")
}

/// A ten-row preview cannot reuse the full-page ETag or overfill its visible card.
@Test func songDetailPreviewUsesBoundedIndependentChartQuery() async throws {
    let previewRows = (1...10).map { rank in
        """
        {"accountId":"fixture-\(rank)","displayName":"Fixture \(rank)",
        "rank":\(rank),"score":\(100_000 - rank)}
        """
    }.joined(separator: ",")
    let preview = """
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":10,
    "totalEntries":26,"localEntries":26,"entries":[\(previewRows)]}
    """
    let full = """
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":1,
    "totalEntries":26,"localEntries":26,
    "entries":[{"accountId":"fixture-1","rank":1,"score":99999}]}
    """
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, preview, headers: ["X-FST-Publication-Id": "7", "ETag": "preview"]),
        reply(200, full, headers: ["X-FST-Publication-Id": "7", "ETag": "full"]),
        reply(304, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.leaderboard(
        songId: "fixture-pulse", instrument: .lead, page: 1, top: 10
    )
    let fullPage = try await client.leaderboard(
        songId: "fixture-pulse", instrument: .lead, page: 1
    )
    let cached = try await client.leaderboard(
        songId: "fixture-pulse", instrument: .lead, page: 1, top: 10
    )
    #expect(first.leaderboard.entries.count == 10)
    #expect(fullPage.leaderboard.entries.count == 1)
    #expect(cached.leaderboard.entries == first.leaderboard.entries)
    let requests = await transport.recorded()
    #expect(requests.count == 4)
    #expect(requests[1].url?.query == "top=10&offset=0")
    #expect(requests[2].url?.query == "top=25&offset=0")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requests[3].value(forHTTPHeaderField: "If-None-Match") == "preview")
    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.leaderboard(
            songId: "fixture-pulse", instrument: .lead, page: 1, top: 26
        )
    }
}

/// Fail closed if a server ignores the requested preview size.
@Test func songDetailPreviewRejectsOverfilledScores() async throws {
    let rows = (1...11).map { rank in
        "{\"accountId\":\"fixture-\(rank)\",\"rank\":\(rank),\"score\":90000}"
    }.joined(separator: ",")
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, """
        {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":11,
        "totalEntries":11,"entries":[\(rows)]}
        """, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try await client.leaderboard(
            songId: "fixture-pulse", instrument: .lead, page: 1, top: 10
        )
    }
}

@Test func artworkCacheSurvivesWarmOfflineButRejectsInvalidImages() async throws {
    let url = URL(string: "https://cdn2.unrealengine.com/fixture.png")!
    let bytes = Data([137, 80, 78, 71])
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: bytes, headers: ["Content-Type": "image/png"])),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let cache = ArtworkCache(transport: transport)
    let first = try await cache.load(url)
    let offline = try await cache.load(url)
    #expect(first.data == bytes && !first.fromMemory)
    #expect(offline.data == bytes && offline.fromMemory)
    #expect((await transport.recorded()).count == 1)
    let bad = ArtworkCache(transport: FixtureTransport([reply(200, "html")]))
    await #expect(throws: FestivalAPIError.invalidArtwork) {
        try await bad.load(url)
    }
}

@Test func artworkURLAllowsOnlyCDNHTTPSOrLoopbackFixture() async throws {
    let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8765")!)
    #expect(try await client.artworkURL(nil) == nil)
    #expect(
        try await client.artworkURL("/__fixture__/art/pulse.png")?.absoluteString
        == "http://127.0.0.1:8765/__fixture__/art/pulse.png"
    )
    #expect(
        try await client.artworkURL("covers/pulse.png")?.absoluteString
        == "https://cdn2.unrealengine.com/covers/pulse.png"
    )
    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.artworkURL("http://example.com/unsafe.png")
    }
    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.artworkURL("../private.png")
    }
}

@Test func cancelledReadNeverBecomesOfflineSuccess() async throws {
    let client = try FestivalAPI(transport: FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: publicationJSON)),
        .success(reply(200, "cached", headers: ["X-FST-Publication-Id": "7"])),
        .failure(URLError(.cancelled)),
    ]))
    _ = try await client.read(.songs)
    await #expect(throws: URLError.self) {
        try await client.read(.songs)
    }
}

@Test func cancelledArtworkNeverBecomesOfflineSuccess() async throws {
    let cache = ArtworkCache(transport: FixtureTransport(results: [
        .failure(URLError(.cancelled)),
    ]))
    let url = URL(string: "https://cdn2.unrealengine.com/fixture.png")!
    await #expect(throws: URLError.self) {
        try await cache.load(url)
    }
}

@Test func boundResponsesWithoutProvenanceAreNotLabeledPinned() async throws {
    let pinned = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "unverified"),
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, "unverified"),
    ]))
    await #expect(throws: FestivalAPIError.invalidPublication) {
        try await pinned.read(.songs)
    }
    let unpinned = try FestivalAPI(transport: FixtureTransport([
        reply(200, """
        {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
        "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
        """),
        reply(200, "live unpinned"),
    ]))
    let result = try await unpinned.read(.songs)
    #expect(result.publicationId == nil)
    #expect(result.observedPublicationId == 7)
}

@Test func headerlessBytesAreNotMisrepresentedAsOfflineVerifiedData() async throws {
    let transport = FixtureTransport(results: [
        .success(reply(200, """
        {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
        "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
        """)),
        .success(reply(200, "live unpinned", headers: ["ETag": "unverified"])),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    let live = try await client.read(.songs)
    #expect(live.publicationId == nil && live.observedPublicationId == 7)
    await #expect(throws: URLError.self) {
        try await client.read(.songs)
    }
    let requests = await transport.recorded()
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
}

/// Only decoded, validated headerless songs may survive a warm connectivity outage.
@Test func validatedHeaderlessCatalogIsWarmOfflineButNeverGenerationVerified() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(HTTPResult(
            status: 200, data: unpinnedSongsJSON, headers: ["ETag": "unsafe"]
        )),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    let live = try await client.catalog()
    let offline = try await client.catalog()
    #expect(!live.isStale && live.publicationId == nil)
    #expect(offline.isStale && offline.publicationId == nil)
    #expect(offline.observedPublicationId == 7)
    #expect(offline.catalog == live.catalog)
    #expect((await transport.recorded())[2].value(forHTTPHeaderField: "If-None-Match") == nil)

    let cold = try FestivalAPI(transport: FixtureTransport(results: [
        .failure(URLError(.notConnectedToInternet)),
    ]))
    await #expect(throws: URLError.self) {
        try await cold.catalog()
    }
}

/// Enabling pinning within generation seven must revoke unverified offline reuse.
@Test func samePublicationPinningTransitionRejectsUnverifiedOfflineSnapshot() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(HTTPResult(status: 200, data: unpinnedSongsJSON)),
        .success(HTTPResult(status: 200, data: publicationJSON)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    #expect((try await client.catalog()).publicationId == nil)
    let promoted = try await client.publication(force: true)
    #expect(promoted.publicationId == 7 && promoted.readyForPinning && promoted.pinningEnabled)
    await #expect(throws: URLError.self) {
        try await client.catalog()
    }
    let requests = await transport.recorded()
    #expect(requests.count == 4)
    #expect(requests[3].value(forHTTPHeaderField: "X-FST-Publication-Id") == "7")
}

/// A bad first catalogue cannot seed an offline snapshot.
@Test func malformedHeaderlessSongsCannotCreateWarmSnapshot() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(reply(200, #"{"count":2,"songs":[]}"#)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidCatalogue) {
        try await client.catalog()
    }
    await #expect(throws: URLError.self) {
        try await client.catalog()
    }
}

/// An invalid refresh must not overwrite the last successfully validated JSON.
@Test func malformedHeaderlessSongsDoNotReplaceTheLastValidSnapshot() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(HTTPResult(status: 200, data: unpinnedSongsJSON)),
        .success(reply(200, #"{"count":2,"songs":[]}"#)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    let valid = try await client.catalog()
    await #expect(throws: FestivalAPIError.invalidCatalogue) {
        try await client.catalog()
    }
    let offline = try await client.catalog()
    #expect(offline.isStale && offline.publicationId == nil)
    #expect(offline.catalog == valid.catalog)
}

/// Different page keys, known publication changes and cancellation never reuse old scores.
@Test func headerlessLeaderboardSnapshotIsScopedToPageAndObservedGeneration() async throws {
    let leaderboard = """
    {"songId":"fixture-one","instrument":"Solo_Guitar","count":1,
     "totalEntries":1,"entries":[{"accountId":"fixture-player","rank":1,"score":1000}]}
    """
    let newPublication = """
    {"contractVersion":1,"publicationId":8,"publishedScrapeId":43,
     "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
    """
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(reply(200, leaderboard)),
        .failure(URLError(.notConnectedToInternet)),
        .failure(URLError(.notConnectedToInternet)),
        .success(reply(200, newPublication)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    let live = try await client.leaderboard(
        songId: "fixture-one", instrument: .lead, page: 1
    )
    let offline = try await client.leaderboard(
        songId: "fixture-one", instrument: .lead, page: 1
    )
    #expect(!live.isStale && live.publicationId == nil)
    #expect(offline.isStale && offline.publicationId == nil)
    #expect(offline.leaderboard == live.leaderboard)
    await #expect(throws: URLError.self) {
        try await client.leaderboard(songId: "fixture-one", instrument: .lead, page: 2)
    }
    #expect((try await client.publication(force: true)).publicationId == 8)
    await #expect(throws: URLError.self) {
        try await client.leaderboard(songId: "fixture-one", instrument: .lead, page: 1)
    }
    let requests = await transport.recorded()
    #expect(requests[3].url?.query == "top=25&offset=25")
    #expect(requests[5].value(forHTTPHeaderField: "If-None-Match") == nil)
}

/// Canceling a request must still fail even if a validated unverified snapshot exists.
@Test func cancelledHeaderlessReadNeverUsesWarmSnapshot() async throws {
    let client = try FestivalAPI(transport: FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedPublicationJSON)),
        .success(HTTPResult(status: 200, data: unpinnedSongsJSON)),
        .failure(URLError(.cancelled)),
    ]))
    _ = try await client.catalog()
    await #expect(throws: URLError.self) {
        try await client.catalog()
    }
}

/// A late eligible network error cannot transform a canceled read into cached success.
@Test(arguments: [true, false])
func cancelledLateNetworkErrorNeverReturnsVerifiedOrUnverifiedCache(
    pinned: Bool
) async throws {
    let transport = HeldOfflineFailureTransport(pinned: pinned)
    let client = try FestivalAPI(transport: transport)
    _ = try await client.catalog()
    let pending = Task { try await client.catalog() }
    await transport.waitForPending()
    pending.cancel()
    await transport.releaseAsConnectivityLoss()
    await #expect(throws: CancellationError.self) {
        try await pending.value
    }
}

@Test func delayedOldReadCannotReplaceFreshPublication() async throws {
    let transport = ReorderedPublicationTransport()
    let client = try FestivalAPI(transport: transport)
    let delayed = Task { try await client.read(.songs) }
    await transport.waitForOldRequest()
    let newest = try await client.publication(force: true)
    #expect(newest.publicationId == 8)
    await transport.releaseOldRequest()
    let fresh = try await delayed.value
    #expect(fresh.publicationId == 8)
    #expect(String(decoding: fresh.data, as: UTF8.self) == "new")
}

@Test func unpinnedRolloverRefreshesAndLabelsCurrentGeneration() async throws {
    let transport = FixtureTransport([
        reply(200, """
        {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
        "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
        """),
        reply(200, "newer songs", headers: ["X-FST-Publication-Id": "8"]),
        reply(200, """
        {"contractVersion":1,"publicationId":8,"publishedScrapeId":43,
        "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
        """),
    ])
    let client = try FestivalAPI(transport: transport)
    let result = try await client.read(.songs)
    #expect(result.publicationId == 8)
    #expect((try await client.publication()).publicationId == 8)
    #expect(String(decoding: result.data, as: UTF8.self) == "newer songs")
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[1].value(forHTTPHeaderField: "X-FST-Publication-Id") == nil)
}

@Test func fixtureScenariosNeverAttachToTheProductionOrigin() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: publicationJSON),
        reply(200, #"{"count":0,"songs":[]}"#, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(
        baseURL: URL(string: "http://127.0.0.1:8765")!,
        fixtureScenario: .empty,
        transport: transport
    )
    #expect((try await client.catalog()).catalog.count == 0)
    let requests = await transport.recorded()
    #expect(requests[1].url?.query == "scenario=empty")
    #expect(throws: FestivalAPIError.invalidResource) {
        try FestivalAPI(
            baseURL: URL(string: "https://festivalscoretracker.com")!,
            fixtureScenario: .error
        )
    }
    for scenario in [FixtureScenario.artError, .artSkip, .artWhite] {
        let scenarioTransport = FixtureTransport([
            HTTPResult(status: 200, data: publicationJSON),
            reply(200, #"{"count":0,"songs":[]}"#, headers: ["X-FST-Publication-Id": "7"]),
        ])
        let local = try FestivalAPI(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            fixtureScenario: scenario, transport: scenarioTransport
        )
        _ = try await local.catalog()
        #expect((await scenarioTransport.recorded())[1].url?.query
                == "scenario=\(scenario.rawValue)")
        #expect(throws: FestivalAPIError.invalidResource) {
            try FestivalAPI(
                baseURL: URL(string: "https://festivalscoretracker.com")!,
                fixtureScenario: scenario
            )
        }
    }
}
