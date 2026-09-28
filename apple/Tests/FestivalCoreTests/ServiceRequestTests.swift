import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fake transport

/// Path-routed fake transport: each path answers from its own queue.
private actor RoutedTransport: HTTPTransport {
    private var routes: [String: [Result<HTTPResult, URLError>]]
    private(set) var requests: [URLRequest] = []

    /// Create a transport with ordered replies per URL path.
    ///
    /// - Parameter routes: URL path → replies consumed in order.
    init(_ routes: [String: [Result<HTTPResult, URLError>]]) {
        self.routes = routes
    }

    /// Return the next reply for the request's path.
    ///
    /// - Parameter request: Sent request, recorded for assertions.
    /// - Returns: Next queued reply.
    /// - Throws: The queued `URLError`, or `invalidResource` for an unrouted path.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard var queue = routes[path], !queue.isEmpty else {
            throw FestivalAPIError.invalidResource
        }
        let next = queue.removeFirst()
        routes[path] = queue
        return try next.get()
    }
}

private let publication7 = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
""".utf8)

private let accountA = "0000000000000000000000000000a001"
private let rivalB = "0000000000000000000000000000b001"

private func ok(_ text: String, headers: [String: String] = [:]) -> Result<HTTPResult, URLError> {
    .success(HTTPResult(status: 200, data: Data(text.utf8), headers: headers))
}

private func status(_ code: Int, headers: [String: String] = [:]) -> Result<HTTPResult, URLError> {
    .success(HTTPResult(status: code, data: Data(), headers: headers))
}

private let frozen: [String: String] = ["Retry-After": "30", ServiceFreezeReason.header: "scrape"]

private func repoFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/\(name).json"))
}

// MARK: - Header guard and request shape

@Test func keylessGuardRejectsPrivilegedAndSelectedProfileHeaders() throws {
    let url = URL(string: "https://festivalscoretracker.com/api/songs")!
    for name in ["X-API-Key", "x-api-key", "X-FST-Selected-Profile", "x-fst-selected-account-id"] {
        var request = FestivalAPI.makeRequest(url)
        request.setValue("secret", forHTTPHeaderField: name)
        #expect(throws: FestivalAPIError.forbiddenRequestHeader) {
            try FestivalAPI.validateKeyless(request)
        }
    }
    var post = FestivalAPI.makeRequest(url)
    post.httpMethod = "POST"
    #expect(throws: FestivalAPIError.forbiddenRequestHeader) { try FestivalAPI.validateKeyless(post) }

    var allowed = FestivalAPI.makeRequest(url)
    allowed.setValue("7", forHTTPHeaderField: "X-FST-Publication-Id")
    allowed.setValue("\"e\"", forHTTPHeaderField: "If-None-Match")
    try FestivalAPI.validateKeyless(allowed)
    #expect(allowed.httpMethod == "GET")
    #expect(allowed.timeoutInterval == FestivalAPI.requestTimeout)
    #expect(allowed.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
    #expect(allowed.cachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func sendRefusesForbiddenHeaderWithoutTouchingTransport() async throws {
    let transport = RoutedTransport([:])
    let client = try FestivalAPI(transport: transport)
    var request = FestivalAPI.makeRequest(URL(string: "https://festivalscoretracker.com/api/songs")!)
    request.setValue("k", forHTTPHeaderField: "X-API-Key")
    await #expect(throws: FestivalAPIError.forbiddenRequestHeader) {
        _ = try await client.send(request)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func sendChecksCancellationBeforeTheWire() async throws {
    let transport = RoutedTransport(["/api/songs": [ok("{}")]])
    let client = try FestivalAPI(transport: transport)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await client.fetch(RivalsEndpoint.all(accountId: accountA))
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await transport.requests.isEmpty)
}

// MARK: - Status mapping

@Test func statusMappingCoversEveryServiceOutcome() throws {
    func map(_ code: Int, _ headers: [String: String] = [:], syncing: Bool = false) throws -> ServiceStatus {
        try FestivalAPI.mapStatus(HTTPResult(status: code, data: Data(), headers: headers), acceptsSyncing: syncing)
    }
    #expect(try map(200) == .success)
    #expect(try map(204) == .success)
    #expect(try map(202, syncing: true) == .syncing)
    #expect(throws: FestivalAPIError.syncing) { try map(202) }
    #expect(throws: FestivalAPIError.unexpectedNotModified) { try map(304) }
    #expect(throws: FestivalAPIError.httpStatus(404)) { try map(404) }
    #expect(throws: FestivalAPIError.httpStatus(429)) { try map(429) }
    #expect(throws: FestivalAPIError.httpStatus(500)) { try map(500) }
    #expect(throws: FestivalAPIError.unavailable(retryAfter: "30")) { try map(503, ["Retry-After": "30"]) }
    #expect(throws: FestivalAPIError.unavailable(retryAfter: nil)) {
        try map(503, [ServiceFreezeReason.header: ""])
    }
    #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        try map(503, ["retry-after": "30", "x-fst-public-read-freeze-reason": "scrape"])
    }
}

// MARK: - Unpinned helper

@Test func fetchReportsProvenanceAndFreezeHeadersOnSuccess() async throws {
    let transport = RoutedTransport([
        "/api/publication": [.success(HTTPResult(status: 200, data: publication7))],
        "/api/player/\(accountA)/rivals/all": [
            ok("{}", headers: ["X-FST-Publication-Id": "365", ServiceFreezeReason.header: "scrape"]),
        ],
    ])
    let client = try FestivalAPI(transport: transport)
    let response = try await client.fetch(
        RivalsEndpoint.all(accountId: accountA), observesPublication: true
    )
    #expect(response.httpStatus == 200)
    #expect(response.publicationId == 365)
    #expect(response.observedPublicationId == 7)
    #expect(response.freezeReason == "scrape")
    let sent = await transport.requests
    #expect(sent.map { $0.url?.path } == ["/api/publication", "/api/player/\(accountA)/rivals/all"])
    for request in sent {
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
        #expect(request.timeoutInterval == FestivalAPI.requestTimeout)
    }
}

@Test func fetchJSONMapsUndecodableBodiesToTheCallersError() async throws {
    let path = "/api/player/\(accountA)/rivals/all"
    let transport = RoutedTransport([path: [ok("not json"), ok("not json")]])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidResponse) {
        _ = try await client.fetchJSON(RivalsEndpoint.all(accountId: accountA), as: RivalsAllResponse.self)
    }
    await #expect(throws: RivalsAPIError.invalidResponse) {
        _ = try await client.rivalsAll(accountId: accountA)
    }
}

@Test func operationalReadsShareTheFreezeMapping() async throws {
    let transport = RoutedTransport(["/api/account/search": [status(503, headers: frozen)]])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        _ = try await client.readOperational(.accountSearch(query: "demo", limit: 5))
    }
}

// MARK: - Pinned pipeline shares the mapping

@Test func pinnedReadsSurfaceScrapeFreezeAndUnexpectedSyncing() async throws {
    let transport = RoutedTransport([
        "/api/publication": [.success(HTTPResult(status: 200, data: publication7))],
        "/api/songs": [status(503, headers: frozen)],
        "/api/shop": [status(202)],
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        _ = try await client.read(.songs)
    }
    await #expect(throws: FestivalAPIError.syncing) { _ = try await client.read(.shop) }
    #expect(PublicEndpoint.player(accountId: accountA).acceptsSyncing)
    #expect(PublicEndpoint.playerHistory(accountId: accountA).acceptsSyncing)
    #expect(!PublicEndpoint.songs.acceptsSyncing)
}

@Test func publicationBootstrapSurfacesFreezeAndRejectsOtherSuccessCodes() async throws {
    let transport = RoutedTransport(["/api/publication": [status(503, headers: frozen), status(204)]])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        _ = try await client.publication()
    }
    await #expect(throws: FestivalAPIError.httpStatus(204)) { _ = try await client.publication() }
}

// MARK: - Rivals through the shared helper

@Test func rivalsReadsUseTheSharedTransportAndNormalize404() async throws {
    let listPath = "/api/player/\(accountA)/rivals/Solo_Guitar"
    let lbPath = "/api/player/\(accountA)/leaderboard-rivals/Solo_Guitar"
    let transport = RoutedTransport([
        listPath: [ok(#"{"combo":"01","above":[],"below":[]}"#), status(404), status(503, headers: frozen)],
        lbPath: [status(404)],
    ])
    let client = try FestivalAPI(transport: transport)
    #expect(try await client.rivalsList(accountId: accountA, instrument: .lead).combo == "01")
    #expect(try await client.rivalsList(accountId: accountA, instrument: .lead).isEmpty)
    let error = await #expect(throws: FestivalAPIError.self) {
        _ = try await client.rivalsList(accountId: accountA, instrument: .lead)
    }
    #expect(error.map(ServiceIssue.init) == .scrapeInProgress(retryAfter: 30))
    await #expect(throws: FestivalAPIError.httpStatus(404)) {
        _ = try await client.leaderboardRivals(accountId: accountA, instrument: .lead)
    }
    let sent = await transport.requests
    #expect(sent.count == 4)
    #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })
}

// MARK: - rivals/all

@Test func rivalsAllDecodesThePrecomputedShape() async throws {
    let transport = RoutedTransport([
        "/api/player/\(accountA)/rivals/all": [.success(HTTPResult(status: 200, data: try repoFixture("rivals-all-demo")))],
    ])
    let client = try FestivalAPI(transport: transport)
    let response = try await client.rivalsAll(accountId: accountA)
    #expect(response.accountId == accountA)
    #expect(response.songs.count == 3)
    #expect(response.combos.map(\.id) == ["01", "03"])
    #expect(!response.isEmpty)
    let rival = try #require(response.combos.first?.above.first)
    #expect(rival.id == rivalB)
    #expect(rival.direction == "above")
    #expect(rival.rivalScore == 863.541259765625)
    #expect(rival.avgSignedDelta == nil)
    let sample = try #require(rival.samples.last)
    #expect(sample.instrument == "Solo_Guitar")
    #expect(sample.userRank == 12 && sample.rivalRank == 9)
    #expect(sample.userScore == 98001 && sample.rivalScore == 98410)
    #expect(response.songId(for: sample) == "demo-song-charlie")
    let below = try #require(response.combos.first?.below.first)
    #expect(below.displayName == nil)
    #expect(below.samples.first?.userScore == nil)
}

@Test func rivalsAllDecodesTheLiveFallbackShapeAndEmpty404() async throws {
    let fallback = """
    {"accountId":"\(accountA)","combos":[{"combo":"01","above":[{"accountId":"\(rivalB)",
    "displayName":"Demo","rivalScore":1.5,"sharedSongCount":3,"aheadCount":1,"behindCount":2,
    "avgSignedDelta":-0.5}],"below":[]}]}
    """
    let transport = RoutedTransport(["/api/player/\(accountA)/rivals/all": [ok(fallback), status(404)]])
    let client = try FestivalAPI(transport: transport)
    let response = try await client.rivalsAll(accountId: accountA)
    #expect(response.songs.isEmpty)
    let rival = try #require(response.combos.first?.above.first)
    #expect(rival.samples.isEmpty && rival.direction == nil && rival.avgSignedDelta == -0.5)
    let outOfRange = try JSONDecoder().decode(
        RivalsAllSample.self, from: Data(#"{"s":9,"i":"Solo_Bass","ur":1,"rr":2,"us":null,"rs":null}"#.utf8)
    )
    #expect(response.songId(for: outOfRange) == nil)

    let empty = try await client.rivalsAll(accountId: accountA)
    #expect(empty == .empty(accountId: accountA))
    #expect(empty.isEmpty)
    await #expect(throws: RivalsAPIError.invalidResource) { _ = try await client.rivalsAll(accountId: "../x") }
}

// MARK: - ServiceIssue

@Test func serviceIssueClassifiesEveryErrorFamily() {
    #expect(ServiceIssue(FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30"))
        == .scrapeInProgress(retryAfter: 30))
    #expect(ServiceIssue(FestivalAPIError.publicReadFrozen(reason: "Publish", retryAfter: nil))
        == .scrapeInProgress(retryAfter: nil))
    #expect(ServiceIssue(FestivalAPIError.publicReadFrozen(reason: "max-score-maintenance:v1:x", retryAfter: "15"))
        == .unavailable(retryAfter: 15))
    #expect(ServiceIssue(FestivalAPIError.unavailable(retryAfter: "abc")) == .unavailable(retryAfter: nil))
    #expect(ServiceIssue(FestivalAPIError.syncing) == .syncing)
    #expect(ServiceIssue(FestivalAPIError.httpStatus(404)) == .notFound)
    #expect(ServiceIssue(FestivalAPIError.httpStatus(500))
        == .other(message: "The service is temporarily unavailable. Try again."))
    #expect(ServiceIssue(URLError(.notConnectedToInternet)) == .offline)
    #expect(ServiceIssue(URLError(.timedOut)) == .offline)
    if case .other = ServiceIssue(URLError(.badServerResponse)) {} else { Issue.record("expected other") }
    #expect(ServiceIssue(RivalsAPIError.invalidResponse)
        == .other(message: "The service returned data we could not read. Try again."))
}

@Test func serviceIssuePresentationIsStable() {
    let scrape = ServiceIssue.scrapeInProgress(retryAfter: 30)
    #expect(scrape.title == "Scores are updating")
    #expect(scrape.retriesAutomatically && scrape.retryAfter == 30)
    #expect(scrape.message.contains("automatically"))
    #expect(ServiceIssue.unavailable(retryAfter: 12).message.contains("12 seconds"))
    #expect(ServiceIssue.unavailable(retryAfter: nil).message == "The service is temporarily unavailable. Try again.")
    #expect(ServiceIssue.unavailable(retryAfter: 12).retryAfter == 12)
    #expect(!ServiceIssue.unavailable(retryAfter: 12).retriesAutomatically)
    #expect(ServiceIssue.unavailable(retryAfter: 12).title == nil)
    #expect(ServiceIssue.offline.title == "You're offline")
    #expect(ServiceIssue.offline.message == "Check your connection and try again.")
    #expect(ServiceIssue.syncing.title == "Still syncing")
    #expect(!ServiceIssue.syncing.message.isEmpty)
    #expect(ServiceIssue.notFound.title == nil && ServiceIssue.notFound.retryAfter == nil)
    #expect(ServiceIssue.notFound.message == "This content is no longer available.")
    #expect(ServiceIssue.other(message: "x").message == "x")
    #expect(ServiceIssue.retryAfterSeconds(" 45 ") == 45)
    #expect(ServiceIssue.retryAfterSeconds("0") == nil)
    #expect(ServiceIssue.retryAfterSeconds("Wed, 21 Oct 2026 07:28:00 GMT") == nil)
    #expect(ServiceFreezeReason.isScoreUpdate(" SCRAPE "))
    #expect(!ServiceFreezeReason.isScoreUpdate("publication-isolation-pending"))
}

@Test func newErrorCasesHaveReadableDescriptions() {
    #expect(FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30").localizedDescription
        == "Scores are updating. Try again shortly.")
    #expect(FestivalAPIError.publicReadFrozen(reason: "other", retryAfter: nil).localizedDescription
        == "The service is temporarily unavailable. Try again.")
    #expect(FestivalAPIError.syncing.localizedDescription == "This data is still syncing. Try again shortly.")
    #expect(FestivalAPIError.forbiddenRequestHeader.localizedDescription == "The app blocked an unsafe request.")
}

// MARK: - Retry backoff

@Test func retryBackoffHonoursRetryAfterThenDoublesToTheCap() {
    var backoff = ServiceRetryBackoff()
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start) == 30)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(31)) == 60)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(92)) == 120)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(213)) == 240)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(454)) == 300)
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(755)) == 300)
    // Another scope is independent; nil Retry-After uses the default.
    #expect(backoff.nextDelay(scope: "b", retryAfter: nil, now: start) == ServiceRetryBackoff.defaultDelay)
    // A failure long after the last countdown starts over.
    #expect(backoff.nextDelay(scope: "a", retryAfter: 30, now: start.addingTimeInterval(5_000)) == 30)
    backoff.reset(scope: "a")
    #expect(backoff.nextDelay(scope: "a", retryAfter: 5, now: start.addingTimeInterval(5_001)) == 5)
    #expect(backoff.nextDelay(scope: "c", retryAfter: 9_999, now: start) == ServiceRetryBackoff.cap)
}

// MARK: - Debug forced freeze

@Test func forcedFreezeAnswersEachApiPathOnceThenPassesThrough() async throws {
    let inner = RoutedTransport([
        "/api/publication": [.success(HTTPResult(status: 200, data: publication7))],
        "/api/songs": [ok("{}"), ok("{}")],
        "/art/cover.png": [ok("png")],
    ])
    let transport = ForcedFreezeTransport(wrapping: inner)
    func get(_ path: String, _ query: String = "") async throws -> HTTPResult {
        try await transport.send(URLRequest(url: URL(string: "https://example.com\(path)\(query)")!))
    }
    #expect(try await get("/api/publication").status == 200)
    let first = try await get("/api/songs", "?page=1")
    #expect(first.status == 503)
    #expect(first.header(ServiceFreezeReason.header) == "scrape")
    #expect(first.header("Retry-After") == "30")
    #expect(throws: FestivalAPIError.publicReadFrozen(reason: "scrape", retryAfter: "30")) {
        try FestivalAPI.mapStatus(first, acceptsSyncing: false)
    }
    #expect(try await get("/api/songs", "?page=2").status == 200)
    #expect(try await get("/api/songs").status == 200)
    #expect(try await get("/art/cover.png").status == 200)
}
