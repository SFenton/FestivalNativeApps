import Foundation
import Testing
@testable import FestivalCore

/// Build one synthetic band-search reply.
///
/// - Parameters:
///   - status: HTTP status to exercise.
///   - body: Synthetic JSON or invalid response bytes.
/// - Returns: Raw response consumed by the injected transport.
private func bandReply(_ status: Int, _ body: String) -> HTTPResult {
    HTTPResult(status: status, data: Data(body.utf8))
}

/// One synthetic `BandSearchResultDto`, with the ranking/provenance fields global
/// search ignores.
private func bandJSON(
    _ id: String, type: String = "Band_Duets", members: String = """
    [{"accountId":"fixture-a","displayName":"Fixture A","instruments":["Solo_Guitar"]},\
    {"accountId":"fixture-b","displayName":"Fixture B","instruments":["Solo_Bass"]}]
    """
) -> String {
    """
    {"bandId":"\(id)","teamKey":"fixture-a:fixture-b-\(id)","bandType":"\(type)",\
    "appearanceCount":12,"members":\(members),"ranking":{"rank":3},\
    "matchedInterpretationIds":[0],"matchedAccountIds":["fixture-a"]}
    """
}

/// A full `BandSearchResponseDto` envelope around `results`.
private func envelope(_ results: [String]) -> String {
    """
    {"query":"fixture","normalizedQuery":"fixture","rankBy":"adjusted","page":1,\
    "pageSize":10,"totalCount":\(results.count),"isAmbiguous":false,\
    "needsDisambiguation":false,"interpretations":[],"results":[\(results.joined(separator: ","))]}
    """
}

@Test func bandSearchUsesOneKeylessFirstPageGET() async throws {
    let transport = FixtureTransport([bandReply(200, envelope([bandJSON("band-1")]))])
    let client = try FestivalAPI(transport: transport)
    let found = try await client.searchBands(query: "  Fixture + one?  ")
    #expect(found.results.map(\.bandId) == ["band-1"])
    #expect(found.results.first?.membersLabel == "Fixture A + Fixture B")
    #expect(found.results.first?.appearanceCount == 12)
    let request = try #require(await transport.recorded().first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/bands/search")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.queryItems == [
        URLQueryItem(name: "q", value: "Fixture + one?"),
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "pageSize", value: "10"),
    ])
    // No key, no selected-profile headers: only the helper's no-cache directive.
    #expect(Array((request.allHTTPHeaderFields ?? [:]).keys) == ["Cache-Control"])
}

@Test func plusSignsArePercentEncodedBeforeBandSearchReachesTheServer() throws {
    let url = try OperationalEndpoint.bandSearch(query: "C++", pageSize: 10)
        .url(relativeTo: URL(string: "https://example.test")!)
    #expect(url.absoluteString == "https://example.test/api/bands/search?q=C%2B%2B&page=1&pageSize=10")
}

@Test func invalidBandQueriesNeverReachTheTransport() async throws {
    let transport = FixtureTransport([])
    let client = try FestivalAPI(transport: transport)
    for text in ["a", "   ", "foo\nbar", String(repeating: "x", count: 201)] {
        await #expect(throws: FestivalAPIError.invalidBandSearchQuery) {
            try await client.searchBands(query: text)
        }
    }
    for size in [0, 101] {
        await #expect(throws: FestivalAPIError.invalidBandSearch) {
            try await client.searchBands(query: "Fixture", pageSize: size)
        }
    }
    #expect(await transport.recorded().isEmpty)
}

@Test func bandSearchKeepsEmptyFailedAndMalformedDistinct() async throws {
    let transport = FixtureTransport([
        bandReply(200, envelope([])),
        bandReply(503, #"{"error":"busy"}"#),
        bandReply(200, "not json"),
    ])
    let client = try FestivalAPI(transport: transport)
    #expect(try await client.searchBands(query: "missing").results.isEmpty)
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: nil)) {
        try await client.searchBands(query: "busy")
    }
    await #expect(throws: FestivalAPIError.invalidBandSearch) {
        try await client.searchBands(query: "broken")
    }
}

/// Bad rows fail the whole result rather than being dropped or shown.
@Test(arguments: [
    envelope([bandJSON("band-1", type: "Band_Unknown")]),
    envelope([bandJSON("band-1", members: "[]")]),
    envelope([bandJSON("band-1", members: #"[{"accountId":"bad id","instruments":[]}]"#)]),
    envelope([bandJSON("band-1", members: #"[{"accountId":"ok","displayName":"A\u202eB","instruments":[]}]"#)]),
    envelope([bandJSON("band/1")]),
    envelope([bandJSON("band-1"), bandJSON("band-1")]),
])
func bandSearchRejectsUnusableResults(_ body: String) async throws {
    let client = try FestivalAPI(transport: FixtureTransport([bandReply(200, body)]))
    await #expect(throws: FestivalAPIError.invalidBandSearch) {
        try await client.searchBands(query: "fixture")
    }
}

@Test func bandSearchRejectsMoreRowsThanRequested() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        bandReply(200, envelope([bandJSON("band-1"), bandJSON("band-2")])),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandSearch) {
        try await client.searchBands(query: "fixture", pageSize: 1)
    }
}
