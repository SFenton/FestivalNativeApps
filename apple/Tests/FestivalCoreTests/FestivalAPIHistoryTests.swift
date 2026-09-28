import Foundation
import Testing
@testable import FestivalCore

/// `FestivalAPI+History.swift`'s `playerHistory(accountId:songId:instrument:)` only
/// ran in production through `FestivalSession+History.swift`; nothing in
/// `FestivalCoreTests` previously drove the network round trip (available, 202
/// syncing and 404 unregistered states), so the file was 61.5% covered even though
/// `PlayerHistoryTests.swift` covers `PlayerHistoryResponse`/`PlayerHistoryPayload`
/// model logic thoroughly.

private let historyApiPublicationJSON = Data("""
{"contractVersion":1,"publicationId":9,"publishedScrapeId":44,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private let readyHistoryWire = Data("""
{"accountId":"fixture-player-1","count":1,"history":[
 {"songId":"fixture-song","instrument":"Solo_Lead","oldScore":900,"newScore":1000,
  "oldRank":5,"newRank":3,"accuracy":0.98,"isFullCombo":true,"stars":5,"percentile":0.02,
  "season":9,"scoreAchievedAt":"2026-09-27T00:00:00Z","seasonRank":3,"allTimeRank":100,
  "difficulty":3,"changedAt":"2026-09-27T00:00:00Z"}
],"status":null,"notYetPublished":null}
""".utf8)

@Test func playerHistoryReadReturnsAvailableRowsWithOfflineFreshness() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: historyApiPublicationJSON),
        HTTPResult(
            status: 200, data: readyHistoryWire, headers: ["X-FST-Publication-Id": "9"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerHistory(
        accountId: "fixture-player-1", songId: "fixture-song", instrument: .lead
    )
    #expect(payload.state == .available)
    #expect(payload.response.history.count == 1)
    #expect(payload.publicationId == 9)
    #expect(payload.isStale == false)

    let request = try #require(await transport.recorded().last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/player/fixture-player-1/history")
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
}

@Test func playerHistoryReadReportsSyncingOnAnAccepted202() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: historyApiPublicationJSON),
        HTTPResult(
            status: 202,
            data: Data("""
            {"accountId":"fixture-player-1","count":0,"history":[],"status":"syncing",
             "notYetPublished":true}
            """.utf8),
            headers: ["X-FST-Publication-Id": "9"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerHistory(
        accountId: "fixture-player-1", songId: "fixture-song", instrument: .lead
    )
    #expect(payload.state == .syncing)
    #expect(payload.response.history.isEmpty)
}

@Test func playerHistoryReadReportsUnregisteredOnA404WithoutThrowing() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: historyApiPublicationJSON),
        HTTPResult(status: 404, data: Data()),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerHistory(
        accountId: "fixture-player-2", songId: "fixture-song", instrument: .lead
    )
    #expect(payload.state == .unregistered)
    #expect(payload.response.accountId == "fixture-player-2")
    #expect(payload.response.count == 0)
    #expect(payload.response.history.isEmpty)
    #expect(payload.publicationId == nil)
    #expect(payload.observedPublicationId == 9)
    #expect(payload.isStale == false)
}

@Test func playerHistoryReadRejectsAMismatchedAccountOrMalformedBody() async throws {
    let mismatched = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: historyApiPublicationJSON),
        HTTPResult(status: 200, data: readyHistoryWire, headers: ["X-FST-Publication-Id": "9"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try await mismatched.playerHistory(
            accountId: "fixture-player-2", songId: "fixture-song", instrument: .lead
        )
    }
    let garbage = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: historyApiPublicationJSON),
        HTTPResult(
            status: 200, data: Data(#"{"history":"nope"}"#.utf8),
            headers: ["X-FST-Publication-Id": "9"]
        ),
    ]))
    await #expect(throws: (any Error).self) {
        try await garbage.playerHistory(
            accountId: "fixture-player-1", songId: "fixture-song", instrument: .lead
        )
    }
}
