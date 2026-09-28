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
