import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// A locally authored `/api/rankings/{instrument}/{accountId}` envelope, never a
/// captured production payload (`.agents/platforms/service-safety.md`).
private let singleAccountRankingWire = """
{"accountId":"fixture-player-1","displayName":"Fixture Player 1","instrument":"Solo_Guitar",
 "songsPlayed":40,"totalChartedSongs":40,"coverage":1.0,"rawSkillRating":0.0041,
 "adjustedSkillRating":0.0041,"adjustedSkillRank":3,"weightedRating":0.9,
 "weightedRank":4,"fcRate":0.975,"fcRateRank":2,"totalScore":123456789,
 "totalScoreRank":5,"maxScorePercent":0.998,"maxScorePercentRank":1,
 "avgAccuracy":97.5,"fullComboCount":39,"avgStars":5.9,"bestRank":1,"avgRank":3.2,
 "rawMaxScorePercent":0.998,"rawWeightedRating":0.9,"computedAt":"2026-09-27T00:00:00Z",
 "totalRankedAccounts":500}
"""

private let rankingsPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private func rankingReply(
    _ status: Int, _ wire: String, headers: [String: String] = [:]
) -> HTTPResult {
    HTTPResult(status: status, data: Data(wire.utf8), headers: headers)
}

// MARK: - Decoding and validation

@Test func singleAccountRankingDecodesEveryFieldAndValidates() throws {
    let ranking = try JSONDecoder().decode(
        PlayerInstrumentRanking.self, from: Data(singleAccountRankingWire.utf8)
    )
    try ranking.validate(instrument: .lead, accountId: "fixture-player-1")
    #expect(ranking.entry.accountId == "fixture-player-1")
    #expect(ranking.entry.displayName == "Fixture Player 1")
    #expect(ranking.entry.totalScore == 123_456_789)
    #expect(ranking.entry.totalScoreRank == 5)
    #expect(ranking.totalRankedAccounts == 500)
    #expect(ranking.instrument == "Solo_Guitar")
}

@Test func singleAccountRankingRejectsMismatchedInstrumentOrAccount() throws {
    let ranking = try JSONDecoder().decode(
        PlayerInstrumentRanking.self, from: Data(singleAccountRankingWire.utf8)
    )
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try ranking.validate(instrument: .bass, accountId: "fixture-player-1")
    }
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try ranking.validate(instrument: .lead, accountId: "fixture-player-2")
    }
    // Account IDs compare case-insensitively, like the profile-selection contract.
    try ranking.validate(instrument: .lead, accountId: "FIXTURE-PLAYER-1")
}

/// Live-probed 2026-09-28: this route's own response never backfills a blank
/// `instrument` field from the request the way the list endpoint's
/// `MapAccountRanking` helper does, so a live payload is accepted with it empty;
/// only a populated-but-different value is treated as a real mismatch.
@Test func emptyInstrumentFieldIsAcceptedButAMismatchedOneIsNot() throws {
    let liveShaped = try JSONDecoder().decode(PlayerInstrumentRanking.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1","instrument":"",
     "songsPlayed":728,"totalChartedSongs":729,"coverage":0.998,"rawSkillRating":0.0013,
     "adjustedSkillRating":0.0333,"adjustedSkillRank":1,"weightedRating":0.0333,
     "weightedRank":1,"fcRate":0.994,"fcRateRank":2,"totalScore":107582999,
     "totalScoreRank":1,"maxScorePercent":0.962,"maxScorePercentRank":1,
     "avgAccuracy":999972.5,"fullComboCount":725,"avgStars":6,"bestRank":1,
     "avgRank":55.07,"rawMaxScorePercent":0.9938,"rawWeightedRating":0.00128,
     "computedAt":"2026-09-28T06:00:11Z","totalRankedAccounts":869250}
    """.utf8))
    try liveShaped.validate(instrument: .lead, accountId: "fixture-player-1")
    try liveShaped.validate(instrument: .bass, accountId: "fixture-player-1")
    #expect(liveShaped.entry.totalScoreRank == 1)
}

@Test func percentileFallsBackToRankOverFieldSizeExceptForBayesianMetrics() throws {
    let ranking = try JSONDecoder().decode(
        PlayerInstrumentRanking.self, from: Data(singleAccountRankingWire.utf8)
    )
    // Adjusted/weighted already carry a native Bayesian percentile fraction.
    #expect(ranking.percentile(for: .adjusted) == 0.0041)
    #expect(ranking.percentile(for: .weighted) == 0.9)
    // Total Score has none on the wire, so it falls back to rank / totalRankedAccounts.
    let totalScoreFraction = try #require(ranking.percentile(for: .totalscore))
    #expect(abs(totalScoreFraction - Double(5) / Double(500)) < 0.0001)

    let unranked = try JSONDecoder().decode(
        PlayerInstrumentRanking.self, from: Data("""
        {"accountId":"fixture-player-1","instrument":"Solo_Guitar","songsPlayed":0,
         "totalChartedSongs":40,"coverage":0,"rawSkillRating":0,"adjustedSkillRating":0,
         "adjustedSkillRank":0,"weightedRating":0,"weightedRank":0,"fcRate":0,
         "fcRateRank":0,"totalScore":0,"totalScoreRank":0,"maxScorePercent":0,
         "maxScorePercentRank":0,"avgAccuracy":0,"fullComboCount":0,"avgStars":0,
         "bestRank":0,"avgRank":0,"totalRankedAccounts":500}
        """.utf8)
    )
    #expect(unranked.percentile(for: .totalscore) == nil)
}

// MARK: - Client read

@Test func playerInstrumentRankingReadIsPinnedKeylessAndNeverRegistersActivity() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: rankingsPublicationJSON),
        rankingReply(200, singleAccountRankingWire, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerInstrumentRanking(
        instrument: .lead, accountId: "fixture-player-1"
    )
    #expect(payload.state == .available)
    #expect(payload.publicationId == 7)
    #expect(payload.ranking?.entry.totalScoreRank == 5)

    let requests = await transport.recorded()
    #expect(requests.count == 2)
    let request = try #require(requests.last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/rankings/Solo_Guitar/fixture-player-1")
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Player") == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains {
        $0.lowercased().hasPrefix("x-fst-selected-")
    } != true)
}

/// HTTP 404 ("Account not found in rankings for this instrument") is an honest
/// "not ranked yet" state, never surfaced as an error.
@Test func fourOhFourBecomesAnHonestUnrankedStateNotAnError() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: rankingsPublicationJSON),
        rankingReply(404, #"{"error":"Account not found in rankings for this instrument."}"#),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerInstrumentRanking(
        instrument: .lead, accountId: "fixture-player-1"
    )
    #expect(payload.state == .unranked)
    #expect(payload.ranking == nil)
    #expect(payload.publicationId == nil)
    #expect(payload.observedPublicationId == 7)
}

@Test func otherHTTPFailuresAndMismatchedResponsesStillThrow() async throws {
    let denied = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: rankingsPublicationJSON),
        rankingReply(403, #"{"status":"denied"}"#),
    ]))
    await #expect(throws: FestivalAPIError.httpStatus(403)) {
        try await denied.playerInstrumentRanking(instrument: .lead, accountId: "fixture-player-1")
    }

    // A response for a different account than requested must not be accepted.
    let mismatched = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: rankingsPublicationJSON),
        rankingReply(200, singleAccountRankingWire, headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try await mismatched.playerInstrumentRanking(
            instrument: .lead, accountId: "fixture-player-2"
        )
    }
}
