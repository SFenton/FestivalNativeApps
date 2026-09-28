import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// A locally authored `/api/rankings/{instrument}/{accountId}/history` envelope
/// (`contracts/fixtures/player-rank-history-demo.json` shape), never a captured
/// production payload.
private let rankHistoryWire = """
{"instrument":"Solo_Guitar","accountId":"fixture-player-1","history":[
 {"snapshotDate":"2026-09-25","snapshotTakenAt":"2026-09-25T06:00:00Z",
  "adjustedSkillRank":4,"weightedRank":5,"fcRateRank":3,"totalScoreRank":9,
  "maxScorePercentRank":2,"adjustedSkillRating":0.01,"weightedRating":0.02,
  "fcRate":0.5,"totalScore":88000000,"maxScorePercent":0.97,"songsPlayed":38,
  "coverage":0.76,"fullComboCount":18,"totalChartedSongs":50,"rankedAccountCount":500,
  "rawMaxScorePercent":0.97,"rawWeightedRating":0.02,"rawSkillRating":0.01},
 {"snapshotDate":"2026-09-26","snapshotTakenAt":null,"adjustedSkillRank":0,
  "weightedRank":0,"fcRateRank":0,"totalScoreRank":0,"maxScorePercentRank":0,
  "totalScore":null,"songsPlayed":null,"totalChartedSongs":null,"rankedAccountCount":null},
 {"snapshotDate":"2026-09-27","adjustedSkillRank":3,"weightedRank":4,"fcRateRank":2,
  "totalScoreRank":6,"maxScorePercentRank":1,"totalScore":89500000,"songsPlayed":39,
  "fullComboCount":19,"totalChartedSongs":50,"rankedAccountCount":502}
]}
"""

private let historyPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

// MARK: - Decoding and validation

@Test func rankHistoryDecodesValidatesAndChartsOnlyRankedSnapshotsOldestFirst() throws {
    let history = try JSONDecoder().decode(PlayerRankHistory.self, from: Data(rankHistoryWire.utf8))
    try history.validate(instrument: .lead, accountId: "FIXTURE-PLAYER-1")
    #expect(history.history.count == 3)
    let charted = history.rankedChronological
    #expect(charted.map(\.snapshotDate) == ["2026-09-25", "2026-09-27"])
    #expect(charted.last?.totalScore == 89_500_000)
    #expect(charted.last?.rankedAccountCount == 502)
    // The wire day is a calendar label: it must read back as the same local day
    // (anchoring at UTC midnight showed one day early west of UTC).
    let day = try #require(charted.first?.date)
    #expect(Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        == DateComponents(year: 2026, month: 9, day: 25))
}

@Test func rankHistoryRejectsAnotherInstrumentAccountOrMalformedRows() throws {
    let history = try JSONDecoder().decode(PlayerRankHistory.self, from: Data(rankHistoryWire.utf8))
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try history.validate(instrument: .bass, accountId: "fixture-player-1")
    }
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try history.validate(instrument: .lead, accountId: "fixture-player-2")
    }
    let badDate = try JSONDecoder().decode(PlayerRankHistory.self, from: Data("""
    {"instrument":"Solo_Guitar","accountId":"fixture-player-1","history":[
     {"snapshotDate":"2026-02-30","adjustedSkillRank":1,"weightedRank":1,"fcRateRank":1,
      "totalScoreRank":1,"maxScorePercentRank":1}]}
    """.utf8))
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try badDate.validate(instrument: .lead, accountId: "fixture-player-1")
    }
}

// MARK: - Client read

@Test func rankHistoryReadIsKeylessBoundedAndValidated() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: historyPublicationJSON),
        HTTPResult(
            status: 200, data: Data(rankHistoryWire.utf8),
            headers: ["X-FST-Publication-Id": "7"]
        ),
    ])
    let client = try FestivalAPI(transport: transport)
    let history = try await client.playerRankHistory(instrument: .lead, accountId: "fixture-player-1")
    #expect(history.rankedChronological.count == 2)

    let request = try #require(await transport.recorded().last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/rankings/Solo_Guitar/fixture-player-1/history")
    #expect(request.url?.query == "days=30")
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains {
        $0.lowercased().hasPrefix("x-fst-selected-")
    } != true)

    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.playerRankHistory(instrument: .lead, accountId: "fixture-player-1", days: 0)
    }
    await #expect(throws: FestivalAPIError.invalidResource) {
        try await client.playerRankHistory(instrument: .lead, accountId: "bad/id")
    }
}

@Test func rankHistoryForAnotherAccountOrUndecodableBodyThrows() async throws {
    let mismatched = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: historyPublicationJSON),
        HTTPResult(status: 200, data: Data(rankHistoryWire.utf8), headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try await mismatched.playerRankHistory(instrument: .lead, accountId: "fixture-player-2")
    }
    let garbage = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: historyPublicationJSON),
        HTTPResult(status: 200, data: Data(#"{"history":"nope"}"#.utf8), headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try await garbage.playerRankHistory(instrument: .lead, accountId: "fixture-player-1")
    }
}

// MARK: - Percentile distribution

@Test func percentileBucketsMatchTheWebThresholdsAndSkipUnplacedScores() throws {
    // rank/te × 100: 0.5 → Top 1%; 1.0 → Top 1% (inclusive upper bound);
    // 1.5 → Top 2%; 7 → Top 10%; 100 → Top 100%; bass and unranked rows excluded.
    let profile = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1","totalScores":7,"scores":[
     {"si":"a","ins":"01","sc":1,"rk":1,"te":200},
     {"si":"b","ins":"01","sc":1,"rk":1,"te":100},
     {"si":"c","ins":"01","sc":1,"rk":3,"te":200},
     {"si":"d","ins":"01","sc":1,"rk":7,"te":100},
     {"si":"e","ins":"01","sc":1,"rk":50,"te":50},
     {"si":"f","ins":"01","sc":1,"rk":0,"te":50},
     {"si":"g","ins":"02","sc":1,"rk":1,"te":100}]}
    """.utf8))
    let buckets = profile.percentileBuckets(.lead)
    #expect(buckets == [
        PlayerPercentileBucket(topPercent: 1, count: 2),
        PlayerPercentileBucket(topPercent: 2, count: 1),
        PlayerPercentileBucket(topPercent: 10, count: 1),
        PlayerPercentileBucket(topPercent: 100, count: 1),
    ])
    #expect(profile.percentileBuckets(.drums).isEmpty)
    #expect(PlayerProfileResponse.percentileThresholds.first == 1)
    #expect(PlayerProfileResponse.percentileThresholds.last == 100)
}

// MARK: - Committed fixture

/// The committed fixture the loopback mock serves decodes and validates.
@Test func committedPlayerRankHistoryFixtureDecodesAndValidates() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/player-rank-history-demo.json")
    let history = try JSONDecoder().decode(PlayerRankHistory.self, from: Data(contentsOf: url))
    try history.validate(instrument: .lead, accountId: "fixture-player-1")
    #expect(history.rankedChronological.count == 7)
    #expect(history.rankedChronological.last?.totalScoreRank == 4)
}
