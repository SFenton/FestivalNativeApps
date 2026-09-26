import Foundation
import Testing
@testable import FestivalCore

/// Build one wire reply without storing real account identifiers in fixtures.
///
/// - Parameters:
///   - status: HTTP status to exercise.
///   - body: Synthetic JSON or invalid response bytes.
/// - Returns: Raw response consumed by the injected transport.
private func accountReply(_ status: Int, _ body: String) -> HTTPResult {
    HTTPResult(status: status, data: Data(body.utf8))
}

private actor HeldAccountSearchAbort: HTTPTransport {
    private var held: CheckedContinuation<HTTPResult, Error>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Hold the search until its task has been cancelled by the caller.
    ///
    /// - Parameter request: One keyless account lookup.
    /// - Returns: Never successfully; the test later releases a transport abort.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try await withCheckedThrowingContinuation { continuation in
            held = continuation
            waiting?.resume()
            waiting = nil
        }
    }

    /// Wait for the actual GET rather than racing a task scheduler.
    func waitForRequest() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }

    /// Simulate URLSession's cancellation-shaped URL error.
    func releaseAsCancelled() {
        held?.resume(throwing: URLError(.cancelled))
        held = nil
    }
}

@Test func accountSearchUsesOnlyOneBoundedKeylessGET() async throws {
    let transport = FixtureTransport([
        accountReply(200, """
        {"results":[{"accountId":"fixture-player-1","displayName":"Fixture Player"}]}
        """),
    ])
    let client = try FestivalAPI(transport: transport)
    let found = try await client.searchPlayers(query: "  Fiçture + one?  ", limit: 1)
    #expect(found.results.map(\.accountId) == ["fixture-player-1"])
    let requests = await transport.recorded()
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/account/search")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.queryItems == [
        URLQueryItem(name: "q", value: "Fiçture + one?"),
        URLQueryItem(name: "limit", value: "1"),
    ])
    for forbidden in [
        "X-API-Key", "X-FST-Selected-Player", "X-FST-Selected-Profile-Type",
        "X-FST-Selected-Profile-Id", "X-FST-Selected-Band-Id",
    ] {
        #expect(request.value(forHTTPHeaderField: forbidden) == nil)
    }
    #expect(request.allHTTPHeaderFields?.isEmpty ?? true)
    #expect(request.value(forHTTPHeaderField: "X-FST-Publication-Id") == nil)
}

@Test func plusSignsArePercentEncodedBeforeAccountSearchReachesTheServer() throws {
    let base = URL(string: "https://example.test")!
    let url = try OperationalEndpoint.accountSearch(query: "C++", limit: 10)
        .url(relativeTo: base)
    #expect(url.absoluteString
        == "https://example.test/api/account/search?q=C%2B%2B&limit=10")
}

@Test func invalidAccountQueriesNeverReachTheTransport() async throws {
    let transport = FixtureTransport([])
    let client = try FestivalAPI(transport: transport)
    for text in ["a", "   ", "foo\nbar", String(repeating: "x", count: 201)] {
        await #expect(throws: FestivalAPIError.invalidProfileSearchQuery) {
            try await client.searchPlayers(query: text)
        }
    }
    for limit in [0, 11] {
        await #expect(throws: FestivalAPIError.invalidProfileSearchLimit) {
            try await client.searchPlayers(query: "Fixture", limit: limit)
        }
    }
    #expect(await transport.recorded().isEmpty)
}

@Test func accountSearchKeepsEmptyDeniedAndOfflineDistinct() async throws {
    let transport = FixtureTransport(results: [
        .success(accountReply(200, #"{"results":[]}"#)),
        .success(accountReply(403, #"{"status":"account_search_denied"}"#)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    #expect(try await client.searchPlayers(query: "missing").results.isEmpty)
    await #expect(throws: FestivalAPIError.httpStatus(403)) {
        try await client.searchPlayers(query: "blocked")
    }
    await #expect(throws: URLError.self) {
        try await client.searchPlayers(query: "offline")
    }
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
}

@Test func accountSearchPreservesService503And429() async throws {
    let transport = FixtureTransport([
        HTTPResult(
            status: 503, data: Data(), headers: ["Retry-After": "2"]
        ),
        accountReply(429, #"{"status":"rate_limited"}"#),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: "2")) {
        try await client.searchPlayers(query: "busy")
    }
    await #expect(throws: FestivalAPIError.httpStatus(429)) {
        try await client.searchPlayers(query: "rate")
    }
}

@Test func cancelledAccountSearchIsNotShownAsANetworkFailure() async throws {
    let transport = HeldAccountSearchAbort()
    let client = try FestivalAPI(transport: transport)
    let pending = Task {
        try await client.searchPlayers(query: "cancel")
    }
    await transport.waitForRequest()
    pending.cancel()
    await transport.releaseAsCancelled()
    await #expect(throws: CancellationError.self) {
        try await pending.value
    }
}

@Test(arguments: [
    "{}",
    #"{"results":[{"accountId":"","displayName":"Missing ID"}]}"#,
    #"{"results":[{"accountId":"fixture/player","displayName":"Bad ID"}]}"#,
    #"{"results":[{"accountId":"fixture-player-1\n","displayName":"Bad ID"}]}"#,
    #"{"results":[{"accountId":"fixture-player-1","displayName":" "}]}"#,
    #"{"results":[{"accountId":"fixture-player-1","displayName":"Control\nCharacter"}]}"#,
    #"{"results":[{"accountId":"fixture-player-1","displayName":"Bidi\u202EOverride"}]}"#,
    #"{"results":[{"accountId":"fixture-player-1","displayName":"One"},{"accountId":"fixture-player-2","displayName":"Two"}]}"#,
])
func invalidAccountSearchWireCannotBecomeAnIdentity(_ body: String) async throws {
    let client = try FestivalAPI(transport: FixtureTransport([accountReply(200, body)]))
    await #expect(throws: FestivalAPIError.invalidProfileSearch) {
        try await client.searchPlayers(query: "Fixture", limit: 1)
    }
}

@Test func duplicateAccountIdsAreRejectedCaseInsensitively() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([accountReply(200, """
    {"results":[{"accountId":"fixture-player-1","displayName":"One"},
                {"accountId":"FIXTURE-PLAYER-1","displayName":"Two"}]}
    """)]))
    await #expect(throws: FestivalAPIError.invalidProfileSearch) {
        try await client.searchPlayers(query: "Fixture", limit: 2)
    }
}

@Test func accountNamesNormalizeOuterSpaceButKeepInternalUnicodeFormat() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([accountReply(200, """
    {"results":[{"accountId":"fixture-player-1","displayName":"  Mehr\\u200Cdad  "}]}
    """)]))
    let found = try await client.searchPlayers(query: "Mehr\u{200C}dad")
    #expect(found.results.first?.displayName == "Mehr\u{200C}dad")
}

@Test func oversizedAccountSearchIsRejectedBeforeDecoding() async throws {
    let padded = "{\"results\":[],\"pad\":\""
    let client = try FestivalAPI(transport: FixtureTransport([
        accountReply(200, padded + String(repeating: "x", count: 64_000) + "\"}"),
    ]))
    await #expect(throws: FestivalAPIError.invalidProfileSearch) {
        try await client.searchPlayers(query: "Fixture")
    }
    let small = try FestivalAPI(transport: FixtureTransport([
        accountReply(200, padded + String(repeating: "x", count: 16) + "\"}"),
    ]))
    #expect(try await small.searchPlayers(query: "Fixture").results.isEmpty)
}
