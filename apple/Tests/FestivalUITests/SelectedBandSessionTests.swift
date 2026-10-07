import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Band song-rows fixture transport

/// Serves the publication and the keyless band song-rows read for three synthetic
/// teams: one that scored Pulse (`band-song-rows-demo.json`), one with no rows and one
/// whose projection is unpublished (503). Rejects writes, the privileged key and
/// selected-profile headers, and records each request path.
actor HostedBandSongRowsTransport: HTTPTransport {
    static let scoredTeam = "fixture-rank-1:fixture-rank-2"
    static let emptyTeam = "fixture-empty-1:fixture-empty-2"
    static let unpublishedTeam = "fixture-down-1:fixture-down-2"

    private var paths: [String] = []

    /// Answer one native public GET.
    ///
    /// - Parameter request: The request.
    /// - Returns: The publication, the team's rows or a 503.
    /// - Throws: A write, privileged header or unexpected path.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        paths.append(url.path)
        let prefix = "/api/rankings/bands/Band_Duets/"
        guard url.path.hasPrefix(prefix), url.path.hasSuffix("/song-rows") else {
            throw FestivalAPIError.invalidResource
        }
        let team = String(url.path.dropFirst(prefix.count).dropLast("/song-rows".count))
        let headers = ["X-FST-Publication-Id": "7"]
        switch team {
        case Self.scoredTeam:
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let data = try Data(contentsOf: root.appendingPathComponent(
                "contracts/fixtures/band-song-rows-demo.json"
            ))
            return HTTPResult(status: 200, data: data, headers: headers)
        case Self.emptyTeam:
            return HTTPResult(status: 200, data: Data("""
            {"bandType":"Band_Duets","teamKey":"\(team)","comboId":null,"count":0,"entries":[]}
            """.utf8), headers: headers)
        default:
            return HTTPResult(status: 503, data: Data(), headers: ["Retry-After": "30"])
        }
    }

    /// Paths requested besides the publication.
    ///
    /// - Returns: Request paths in order.
    func recordedPaths() -> [String] { paths }
}

/// Build a session with one in-memory selected band over the fixture transport.
///
/// - Parameters:
///   - teamKey: One of the transport's teams.
///   - transport: The fixture transport.
/// - Returns: A session whose band is selected but not yet loaded.
/// - Throws: Client construction failures.
@MainActor
func selectedBandSession(
    teamKey: String, transport: HostedBandSongRowsTransport
) throws -> FestivalSession {
    let client = try FestivalAPI(transport: transport)
    return FestivalSession(
        factory: { client },
        debugSelectedBand: SelectedBandIdentity(
            bandType: .duets, teamKey: teamKey, displayName: "Fixture Duo"
        )
    )
}

// MARK: - Band score index

/// The band index loads from `/song-rows` only, applies to Songs from the same
/// publication, and is cleared (back to loading) by a new publication (#340).
@MainActor
@Test func selectedBandIndexLoadsAndGatesOnPublication() async throws {
    let transport = HostedBandSongRowsTransport()
    let session = try selectedBandSession(
        teamKey: HostedBandSongRowsTransport.scoredTeam, transport: transport
    )
    #expect(session.bandLoadState == .loading)
    #expect(!session.hasCurrentBandScores(forCatalogue: 7))

    await session.refreshSelectedBand()
    #expect(session.bandLoadState == .available)
    #expect(session.selectedBandScores["fixture-pulse"]?.score == 1_234_567)
    #expect(session.hasCurrentBandScores(forCatalogue: 7))
    // Songs from another publication pause instead of borrowing these scores.
    #expect(!session.hasCurrentBandScores(forCatalogue: 6))
    #expect(!session.hasCurrentBandScores(forCatalogue: nil))
    #expect(await transport.recordedPaths()
        == ["/api/rankings/bands/Band_Duets/\(HostedBandSongRowsTransport.scoredTeam)/song-rows"])

    try await session.observe(publicationId: 8)
    #expect(session.bandLoadState == .loading)
    #expect(session.selectedBandScores.isEmpty)
    #expect(!session.hasCurrentBandScores(forCatalogue: 8))
}

/// An unpublished projection (503) fails the band index rather than reading as "no
/// scores"; a band with no rows is available and empty.
@MainActor
@Test func selectedBandIndexFailsOnUnpublishedProjection() async throws {
    let transport = HostedBandSongRowsTransport()
    let down = try selectedBandSession(
        teamKey: HostedBandSongRowsTransport.unpublishedTeam, transport: transport
    )
    await down.refreshSelectedBand()
    guard case .failed = down.bandLoadState else {
        Issue.record("Expected a failed band index, got \(down.bandLoadState)")
        return
    }
    #expect(down.selectedBandScores.isEmpty)
    #expect(!down.hasCurrentBandScores(forCatalogue: 7))

    let empty = try selectedBandSession(
        teamKey: HostedBandSongRowsTransport.emptyTeam, transport: transport
    )
    await empty.refreshSelectedBand()
    #expect(empty.bandLoadState == .available)
    #expect(empty.selectedBandScores.isEmpty)
}

/// Band fields follow the player projection: score, accuracy, percentile bucket, gold
/// stars, season and last played; no chart Intensity or game difficulty.
@Test func bandFieldsProjectLikeAPlayerScore() throws {
    let entry = try JSONDecoder().decode(BandSongPerformanceEntry.self, from: Data("""
    {"songId":"s","rank":1,"totalEntries":26,"percentile":0.04,"score":1234567,
     "accuracy":992000,"isFullCombo":false,"stars":6,"season":9,"endTime":"2026-09-27T00:00:00Z"}
    """.utf8))
    let fields = try SongProfileCardPolicy.bandFields(
        for: entry, currentSeason: 9, visibility: SongMetadataVisibility()
    )
    #expect(fields.map(\.id) == [.score, .accuracy, .percentile, .stars, .season, .lastPlayed])
    #expect(fields.first == .score(1_234_567))
    #expect(fields.contains(.stars(count: 5, gold: true)))
    #expect(fields.contains(.season(9, current: true)))
    var hidden = SongMetadataVisibility()
    hidden.percentage = false
    hidden.lastPlayed = false
    #expect(try SongProfileCardPolicy.bandFields(for: entry, currentSeason: 9, visibility: hidden)
        .map(\.id) == [.score, .percentile, .stars, .season])
}
