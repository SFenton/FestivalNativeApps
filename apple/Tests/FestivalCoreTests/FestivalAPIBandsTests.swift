import Foundation
import Testing
@testable import FestivalCore

/// Locate a fixture committed under `contracts/fixtures/`.
///
/// - Parameter name: Fixture file name, including its extension.
/// - Returns: Raw wire bytes.
private func bandsFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/\(name).json"))
}

private let bandsPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

/// `FestivalAPI+Bands.swift`'s five reads only ever run in production through
/// `FestivalSession+Bands.swift`; nothing in `FestivalCoreTests` previously drove
/// the actual network round trip (decode, validation guard, payload wrapping),
/// so the file measured 0% line coverage despite `Bands.swift`'s models and
/// `PublicEndpoint` URL construction being well tested elsewhere.

// MARK: - Player bands

@Test func playerBandsReadIsKeylessAndReturnsValidatedPage() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("player-bands-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerBands(
        accountId: "fixture-player-1", group: .all, page: 1
    )
    #expect(payload.page == 1)
    #expect(payload.list.entries.count == 2)
    #expect(payload.publicationId == 7)
    #expect(payload.isStale == false)

    let request = try #require(await transport.recorded().last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/player/fixture-player-1/bands")
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains {
        $0.lowercased().hasPrefix("x-fst-selected-")
    } != true)
}

@Test func playerBandsRejectsAMismatchedAccountId() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("player-bands-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.playerBands(accountId: "fixture-player-2", group: .all, page: 1)
    }
}

// MARK: - Band profile

@Test func bandProfileReadReturnsTheSelectedTeamFromTheRankingsBoard() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-detail-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.bandProfile(bandType: .duets, teamKey: "fixture-rank-1:fixture-rank-2")
    #expect(payload.detail.teamKey == "fixture-rank-1:fixture-rank-2")
    #expect(payload.detail.rank(for: .totalscore) == 1)
    #expect(payload.publicationId == 7)

    let request = try #require(await transport.recorded().last)
    #expect(request.url?.path == "/api/rankings/bands/Band_Duets")
}

@Test func bandProfileRejectsAnEmptyTeamKeyWithoutAnyNetworkCall() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.bandProfile(bandType: .duets, teamKey: "")
    }
}

@Test func bandProfileRejectsAMismatchedBandTypeOrAnUnknownTeam() async throws {
    let wrongType = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-detail-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await wrongType.bandProfile(bandType: .trios, teamKey: "fixture-rank-1:fixture-rank-2")
    }
    let unknownTeam = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(status: 200, data: Data("""
        {"bandType":"Band_Duets","selectedBandEntry":null}
        """.utf8), headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await unknownTeam.bandProfile(bandType: .duets, teamKey: "no-such-team")
    }
}

// MARK: - Band rank history

@Test func bandRankHistoryReadReturnsValidatedDailySnapshots() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-rank-history-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.bandRankHistory(
        bandType: .duets, teamKey: "fixture-rank-1:fixture-rank-2"
    )
    #expect(payload.response.history.count == 2)
    #expect(payload.response.history.first?.rank(for: .adjusted) == 1)
    #expect(payload.publicationId == 7)

    let request = try #require(await transport.recorded().last)
    #expect(request.url?.path == "/api/rankings/bands/Band_Duets/fixture-rank-1:fixture-rank-2/history")
}

@Test func bandRankHistoryRejectsAMismatchedBandOrTeam() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-rank-history-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.bandRankHistory(bandType: .duets, teamKey: "someone-else")
    }
}

// MARK: - Band song extremes

@Test func bandSongExtremesReadReturnsValidatedBestAndWorstSongs() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-song-extremes-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.bandSongExtremes(
        bandType: .duets, teamKey: "fixture-rank-1:fixture-rank-2", limit: 2
    )
    #expect(payload.response.best.first?.songId == "fixture-pulse")
    #expect(payload.response.worst.first?.rank == 20)
    #expect(payload.publicationId == 7)

    let request = try #require(await transport.recorded().last)
    #expect(request.url?.path == "/api/rankings/bands/Band_Duets/fixture-rank-1:fixture-rank-2/songs")
}

@Test func bandSongExtremesRejectsAMismatchedBandOrTeam() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("band-song-extremes-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.bandSongExtremes(bandType: .duets, teamKey: "someone-else")
    }
}

// MARK: - Song band leaderboard

@Test func songBandLeaderboardReadReturnsAValidatedPage() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("song-band-leaderboard-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.songBandLeaderboard(
        songId: "fixture-pulse", bandType: .duets, page: 1
    )
    #expect(payload.page == 1)
    #expect(payload.leaderboard.entries.count == 2)
    #expect(payload.publicationId == 7)

    let request = try #require(await transport.recorded().last)
    #expect(request.url?.path == "/api/leaderboard/fixture-pulse/bands/Band_Duets")
    #expect(request.url?.query == "top=25&offset=0")
}

@Test func songBandLeaderboardSendsTheSelectedPlayerOnlyAsAQueryParameter() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("song-band-leaderboard-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    _ = try await client.songBandLeaderboard(
        songId: "fixture-pulse", bandType: .duets, page: 2, accountId: "fixture-player-1"
    )
    let request = try #require(await transport.recorded().last)
    #expect(request.url?.query == "top=25&offset=25&accountId=fixture-player-1")
    // Never a selected-profile header: those register activity on the service.
    let headers = (request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }
    #expect(!headers.contains { $0.contains("account") || $0.contains("profile") || $0 == "x-api-key" })
}

@Test func songBandLeaderboardRejectsAnInvalidPageWithoutAnyNetworkCall() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([]))
    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.songBandLeaderboard(songId: "fixture-pulse", bandType: .duets, page: 0)
    }
}

@Test func songBandLeaderboardRejectsAMismatchedSongOrBandTypeFromTheWire() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("song-band-leaderboard-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.songBandLeaderboard(songId: "other-song", bandType: .duets, page: 1)
    }
}

// MARK: - Song Detail band previews

@Test func songBandPreviewsReadIsOneKeylessQueryOnlyRequest() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("song-band-leaderboards-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.songBandLeaderboards(
        songId: "fixture-pulse", accountId: "fixture-player-1"
    )
    #expect(payload.publicationId == 7)
    #expect(payload.response.bands.map(\.bandType) == BandType.allCases.map(\.rawValue))
    #expect(payload.response.preview(for: .duets).entries.count == 2)

    let request = try #require(await transport.recorded().last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/leaderboard/fixture-pulse/bands/all")
    let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(items == [
        URLQueryItem(name: "top", value: "10"),
        URLQueryItem(name: "accountId", value: "fixture-player-1"),
    ])
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains {
        $0.lowercased().hasPrefix("x-fst-selected-")
    } != true)
}

@Test func songBandPreviewsWithoutAPlayerSendOnlyTop() throws {
    let base = try #require(URL(string: "https://example.test"))
    let url = try PublicEndpoint.songBandLeaderboards(songId: "s1", top: 10, accountId: nil)
        .url(relativeTo: base)
    #expect(url.absoluteString == "https://example.test/api/leaderboard/s1/bands/all?top=10")
    #expect(PublicEndpoint.songBandLeaderboards(songId: "s1", top: 10, accountId: nil).allowsSnapshotCache)
    #expect(!PublicEndpoint.songBandLeaderboards(songId: "s1", top: 10, accountId: "a1").allowsSnapshotCache)
}

@Test func songBandPreviewsRejectInvalidInput() throws {
    let base = try #require(URL(string: "https://example.test"))
    for endpoint in [
        PublicEndpoint.songBandLeaderboards(songId: "", top: 10, accountId: nil),
        .songBandLeaderboards(songId: "a/b", top: 10, accountId: nil),
        .songBandLeaderboards(songId: "s1", top: 0, accountId: nil),
        .songBandLeaderboards(songId: "s1", top: 51, accountId: nil),
        .songBandLeaderboards(songId: "s1", top: 10, accountId: "bad id/"),
    ] {
        #expect(throws: FestivalAPIError.invalidResource) { try endpoint.url(relativeTo: base) }
    }
}

@Test func songBandPreviewsRejectAnotherSongsResponse() async throws {
    let client = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: bandsPublicationJSON),
        HTTPResult(
            status: 200, data: try bandsFixture("song-band-leaderboards-demo"),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ]))
    await #expect(throws: FestivalAPIError.invalidBandProfile) {
        try await client.songBandLeaderboards(songId: "fixture-orbit", accountId: nil)
    }
}

@Test func songBandPreviewsValidationRejectsCorruptSizes() throws {
    func response(_ json: String) throws -> SongBandLeaderboardsResponse {
        try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: Data(json.utf8))
    }
    let empty = #"{"bandType":"%@","count":0,"totalEntries":0,"entries":[]}"#
    let unknown = try response(#"{"songId":"s","bands":[\#(empty.replacingOccurrences(of: "%@", with: "Band_Solo"))]}"#)
    #expect(throws: FestivalAPIError.invalidBandProfile) { try unknown.validate(songId: "s") }
    let duet = empty.replacingOccurrences(of: "%@", with: "Band_Duets")
    let repeated = try response(#"{"songId":"s","bands":[\#(duet),\#(duet)]}"#)
    #expect(throws: FestivalAPIError.invalidBandProfile) { try repeated.validate(songId: "s") }
    let miscounted = try response(
        #"{"songId":"s","bands":[{"bandType":"Band_Duets","count":3,"totalEntries":0,"entries":[]}]}"#
    )
    #expect(throws: FestivalAPIError.invalidBandProfile) { try miscounted.validate(songId: "s") }
    let partial = try response(#"{"songId":"s","bands":[\#(duet)]}"#)
    try partial.validate(songId: "s")
    #expect(partial.preview(for: .quad).entries.isEmpty)
    #expect(partial.preview(for: .quad).bandType == "Band_Quad")
}

@Test func songBandPreviewsRejectARowFiledUnderTheWrongSize() throws {
    var object = try #require(
        JSONSerialization.jsonObject(with: bandsFixture("song-band-leaderboards-demo")) as? [String: Any]
    )
    var bands = try #require(object["bands"] as? [[String: Any]])
    bands[2]["selectedPlayerEntry"] = (bands[0]["entries"] as? [Any])?.first
    object["bands"] = bands
    let data = try JSONSerialization.data(withJSONObject: object)
    let response = try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: data)
    #expect(throws: FestivalAPIError.invalidBandProfile) { try response.validate(songId: "fixture-pulse") }
}

@Test func songBandPreviewSelectionHighlightsInPlaceOrAppends() throws {
    let response = try JSONDecoder().decode(
        SongBandLeaderboardsResponse.self, from: bandsFixture("song-band-leaderboards-demo")
    )
    // Duos: the selected player's band is rank 14, outside the top rows: append it.
    let duos = response.preview(for: .duets)
    #expect(duos.entries.allSatisfy { !duos.isSelected($0) })
    #expect(duos.footerEntry?.rank == 14)
    // Trios: the selected band is already the top row: highlight it, append nothing.
    let trios = response.preview(for: .trios)
    #expect(trios.isSelected(try #require(trios.entries.first)))
    #expect(trios.footerEntry == nil)
    // Quads: nothing selected and no rows.
    let quads = response.preview(for: .quad)
    #expect(quads.selectedEntry == nil)
    #expect(quads.footerEntry == nil)
}

@Test func songBandPreviewSelectedBandWinsAndMatchesByRoster() throws {
    let response = try JSONDecoder().decode(
        SongBandLeaderboardsResponse.self, from: bandsFixture("song-band-leaderboards-demo")
    )
    let duos = response.preview(for: .duets)
    let top = try #require(duos.entries.first)
    let player = try #require(duos.selectedPlayerEntry)
    let preview = SongBandLeaderboardPreview(
        bandType: "Band_Duets", totalEntries: 26, entries: duos.entries,
        selectedPlayerEntry: player, selectedBandEntry: top
    )
    #expect(preview.selectedEntry == top)
    #expect(preview.isSelected(top))
    #expect(preview.footerEntry == nil)
    #expect(preview.count == 2)
    #expect(SongBandLeaderboardPreview.isSameBand(top, top))
    #expect(!SongBandLeaderboardPreview.isSameBand(top, player))
}
