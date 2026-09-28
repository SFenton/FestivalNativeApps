import Foundation
import Testing
@testable import FestivalCore

private let availablePlayerWire = """
{"accountId":"fixture-player-1","displayName":"  Fixture Player 1  ",
 "totalScores":2,"scores":[
   {"si":"fixture-pulse","ins":"01","sc":99900,"acc":979,"fc":false,
    "st":5,"dif":3,"sn":9,"pct":0.038461538461538464,"rk":1,"te":26},
   {"si":"fixture-orbit","ins":"01","sc":99900,"acc":979,"fc":false,
    "st":5,"dif":3,"sn":9,"pct":0.038461538461538464,"rk":1,"te":26}
 ]}
"""

/// Decode synthetic compact wire using the same model intended for native cards.
///
/// - Parameter json: Locally authored player JSON, never a live account payload.
/// - Returns: Decoded, not yet validated profile envelope.
/// - Throws: Incorrect wire types or missing required fields.
private func player(_ json: String) throws -> PlayerProfileResponse {
    try JSONDecoder().decode(PlayerProfileResponse.self, from: Data(json.utf8))
}

private struct LocalPlayerFixtures: Decodable {
    let profiles: [String: PlayerProfileResponse]
}

@Test func allNinePlayerInstrumentCodesMatchTheServiceBitOrder() throws {
    let codes: [(String, Instrument)] = [
        ("01", .lead), ("02", .bass), ("04", .drums), ("08", .vocals),
        ("10", .proLead), ("20", .proBass), ("40", .karaoke),
        ("80", .proCymbals), ("100", .proDrums),
    ]
    for (code, expected) in codes {
        #expect(try PlayerInstrumentCode.instrument(for: code) == expected)
    }
    for invalid in ["", "1", "00", "03", "200", "001", "gg", "0f"] {
        #expect(throws: FestivalAPIError.invalidPlayerProfile) {
            try PlayerInstrumentCode.instrument(for: invalid)
        }
    }
}

@Test func compactPlayerWirePreservesCoherentInstrumentAccuracyAndScore() throws {
    let response = try player(availablePlayerWire)
    #expect(try response.validate(requestedAccountId: "fixture-player-1") == .available)
    #expect(response.displayName == "Fixture Player 1")
    #expect(response.scores[0].accuracy == 979_000)
    #expect(response.scores[0].isFullCombo == false)
    #expect(response.scores[0].stars == 5)
    #expect(response.scores[0].percentile == 1.0 / 26)
    let indexed = try response.scoreIndex(requestedAccountId: "fixture-player-1")
    #expect(indexed.count == 2)
    #expect(indexed["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(indexed["fixture-orbit"]?[.lead]?.score == 99_900)
    #expect(indexed["fixture-pulse"]?[.bass] == nil)
}

@Test func legacyFallbackAndKnownUnknownPercentileRemainSeparate() throws {
    let response = try player("""
    {"accountId":"fixture-legacy","totalScores":1,
     "scores":[{"si":"fixture-orbit","ins":"100","sc":91000,"acc":920,
      "fc":false,"st":5,"pct":-1,"rk":3,"te":26,"isValid":false,
      "validScore":90000,"validAccuracy":905,"validIsFullCombo":true}]}
    """)
    #expect(try response.validate(requestedAccountId: "fixture-legacy") == .available)
    let score = try #require(
        response.scoreIndex(requestedAccountId: "fixture-legacy")["fixture-orbit"]?[.proDrums]
    )
    #expect(score.percentile == nil)
    #expect(score.score == 91_000)
    #expect(score.isFullCombo == false)
    #expect(score.validScore == 90_000)
    #expect(score.validAccuracy == 905_000)
    #expect(score.validIsFullCombo == true)
}

@Test func precomputedProfileRetainsFallbackVariantsAndRankTiers() throws {
    let response = try player("""
    {"accountId":"fixture-precomputed","totalScores":1,"scores":[{
      "si":"fixture-pulse","ins":"01","sc":99900,"acc":979,"fc":false,
      "st":5,"dif":3,"sn":9,"pct":-1,"rk":1,"te":26,
      "et":"2026-09-26T00:00:00Z","lp":"2026-09-27T00:00:00Z",
      "ml":0.5,"vs":[{"sc":90000,"acc":900,"fc":true,"st":5,
         "ml":1.5,"rt":[{"l":0.5,"r":8},{"l":1.5,"r":4}]}]}]}
    """)
    #expect(try response.validate(requestedAccountId: "fixture-precomputed") == .available)
    let score = try #require(response.scores.first)
    #expect(score.percentile == nil)
    #expect(score.endTime == "2026-09-26T00:00:00Z")
    #expect(score.lastPlayedAt == "2026-09-27T00:00:00Z")
    #expect(score.minLeeway == 0.5)
    let variant = try #require(score.validScores?.first)
    #expect(variant.score == 90_000)
    #expect(variant.accuracy == 900_000)
    #expect(variant.isFullCombo == true)
    #expect(variant.minLeeway == 1.5)
    #expect(variant.rankTiers?.map(\.rank) == [8, 4])

    let invalid = try player("""
    {"accountId":"fixture-precomputed","totalScores":1,"scores":[{
      "si":"fixture-pulse","ins":"01","sc":100,"vs":[{"sc":90,"ml":1,
        "rt":[{"l":0,"r":-1}]}]}]}
    """)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try invalid.validate(requestedAccountId: "fixture-precomputed")
    }
    for variant in [
        #"{"sc":90,"ml":1,"st":7}"#,
        #"{"sc":90,"ml":1,"acc":1001}"#,
    ] {
        let corrupt = try player("""
        {"accountId":"fixture-precomputed","totalScores":1,"scores":[{
          "si":"fixture-pulse","ins":"01","sc":100,"vs":[\(variant)]}]}
        """)
        #expect(throws: FestivalAPIError.invalidPlayerProfile) {
            try corrupt.validate(requestedAccountId: "fixture-precomputed")
        }
    }
}

@Test func committedPlayerFixturesDecodeAsDistinctAvailableProfiles() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/player-demo.json")
    let demo = try JSONDecoder().decode(
        LocalPlayerFixtures.self, from: Data(contentsOf: fixtureURL)
    )
    #expect(demo.profiles.count == 2)
    for (accountId, profile) in demo.profiles {
        #expect(try profile.validate(requestedAccountId: accountId) == .available)
    }
    let first = try #require(demo.profiles["fixture-player-1"]?.scores.first)
    let second = try #require(demo.profiles["fixture-player-2"]?.scores.first)
    #expect(first.isFullCombo == false)
    #expect(second.isFullCombo == true)
}

private struct MetadataEdgeFixture: Decodable {
    let songs: SongsResponse
    let player: PlayerProfileResponse
    let shop: ShopResponse
    let leaderboard: LeaderboardResponse
}

/// One isolated edge must decode coherently across all four real native clients.
@Test func metadataEdgeFixtureKeepsSevenDigitPlayerShopAndChartConsistent() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/metadata-edge.json")
    let edge = try JSONDecoder().decode(
        MetadataEdgeFixture.self, from: Data(contentsOf: fixtureURL)
    )
    try edge.songs.validate()
    try edge.shop.validate()
    #expect(try edge.player.validate(requestedAccountId: "fixture-edge") == .available)
    try edge.leaderboard.validate(songId: "fixture-marathon", instrument: .lead)
    let song = try #require(edge.songs.songs.first)
    let score = try #require(
        edge.player.scoreIndex(requestedAccountId: "fixture-edge")[song.songId]?[.lead]
    )
    let entry = try #require(edge.leaderboard.entries.first)
    let offer = try #require(edge.shop.songs.first)
    #expect(song.title.count > 40)
    #expect(song.durationSeconds == 366)
    #expect(score.score == 1_234_567)
    #expect(score.score == entry.score)
    #expect(score.rank == entry.rank)
    #expect(score.totalEntries == edge.leaderboard.totalEntries)
    #expect(score.accuracy == entry.accuracy)
    #expect(score.isFullCombo == entry.isFullCombo)
    #expect(score.validLastPlayedAt == "2026-09-20T12:34:56.1234567Z")
    #expect(score.stars == entry.stars)
    #expect(score.season == entry.season)
    #expect(edge.shop.newSongs == [song.songId])
    #expect(offer.songId == song.songId)
    #expect(ShopPresentationPolicy.highlight(
        for: offer, hidden: false, highlightingDisabled: false
    ) == .new)
}

@Test func syncingProfileCannotMasqueradeAsAnAvailableEmptyOne() throws {
    let syncing = try player("""
    {"accountId":"fixture-player-1","displayName":null,"status":"syncing",
     "notYetPublished":true,"totalScores":0,"scores":[]}
    """)
    #expect(try syncing.validate(requestedAccountId: "fixture-player-1") == .syncing)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try syncing.scoreIndex(requestedAccountId: "fixture-player-1")
    }
    let populatedSyncing = try player("""
    {"accountId":"fixture-player-1","status":"syncing",
     "notYetPublished":true,"totalScores":1,
     "scores":[{"si":"fixture-pulse","ins":"01","sc":99900}]}
    """)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try populatedSyncing.validate(requestedAccountId: "fixture-player-1")
    }
    let empty = try player("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1",
     "totalScores":0,"scores":[]}
    """)
    #expect(try empty.validate(requestedAccountId: "fixture-player-1") == .available)
    #expect(try empty.scoreIndex(requestedAccountId: "fixture-player-1").isEmpty)
}

@Test func identityCountAndDuplicateScoresFailBeforeIndexing() throws {
    let profile = try player(availablePlayerWire)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try profile.validate(requestedAccountId: "fixture-player-2")
    }
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try profile.scoreIndex(requestedAccountId: "fixture-player-2")
    }
    let row = #"{"si":"fixture-pulse","ins":"01","sc":99000}"#
    let duplicates = try player("""
    {"accountId":"fixture-player-1","totalScores":2,"scores":[\(row),\(row)]}
    """)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try duplicates.validate(requestedAccountId: "fixture-player-1")
    }
    let badCount = try player("""
    {"accountId":"fixture-player-1","totalScores":3,"scores":[\(row)]}
    """)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try badCount.validate(requestedAccountId: "fixture-player-1")
    }
    let unknownStatus = try player("""
    {"accountId":"fixture-player-1","status":"ready","totalScores":0,"scores":[]}
    """)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try unknownStatus.validate(requestedAccountId: "fixture-player-1")
    }
}

@Test func badNumbersAndSyntheticUnknownFullComboDoNotBecomeFC() throws {
    let unknown = try player("""
    {"accountId":"fixture-player-1","totalScores":1,
     "scores":[{"si":"fixture-pulse","ins":"01","sc":99000,"acc":1000}]}
    """)
    #expect(try unknown.validate(requestedAccountId: "fixture-player-1") == .available)
    #expect(unknown.scores[0].isFullCombo == nil)
    #expect(unknown.scores[0].accuracy == 1_000_000)

    for row in [
        #"{"si":"fixture-pulse","ins":"01","sc":-1}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":2147483648}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":100,"acc":1001}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":100,"pct":101}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":100,"te":-1}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":100,"validScore":-1}"#,
        #"{"si":"fixture-pulse","ins":"01","sc":100,"st":7}"#,
    ] {
        let response = try player("""
        {"accountId":"fixture-player-1","totalScores":1,"scores":[\(row)]}
        """)
        #expect(throws: FestivalAPIError.invalidPlayerProfile) {
            try response.validate(requestedAccountId: "fixture-player-1")
        }
    }
}

@Test func malformedAndUnsafeNamesCannotBecomeProfileIdentity() throws {
    let row = #"{"si":"fixture-pulse","ins":"01","sc":100}"#
    let unsafe = """
    {"accountId":"fixture-player-1","displayName":"Bi\\u202Edi",
     "totalScores":1,"scores":[\(row)]}
    """
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try player(unsafe)
    }
    let missing = try player("""
    {"accountId":"fixture-player-1","totalScores":1,"scores":[\(row)]}
    """)
    #expect(try missing.validate(requestedAccountId: "fixture-player-1") == .available)
    #expect(missing.displayName == nil)
    let blank = try player("""
    {"accountId":"fixture-player-1","displayName":"  ","totalScores":0,"scores":[]}
    """)
    #expect(try blank.validate(requestedAccountId: "fixture-player-1") == .available)
    #expect(blank.displayName == nil)
}

private let playerPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

/// Build an injected response without contacting a player or profile service.
///
/// - Parameters:
///   - status: Synthetic HTTP status.
///   - wire: Original local fixture JSON, or an explicitly invalid body.
///   - headers: Publication and retry metadata for the test.
/// - Returns: Raw fake transport result.
private func profileReply(
    _ status: Int, _ wire: String, headers: [String: String] = [:]
) -> HTTPResult {
    HTTPResult(status: status, data: Data(wire.utf8), headers: headers)
}

@Test func availablePlayerReadIsPinnedKeylessAndNotRawCached() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: playerPublicationJSON),
        profileReply(200, availablePlayerWire, headers: [
            "X-FST-Publication-Id": "7", "ETag": "\"profile-v1\"",
        ]),
        profileReply(200, availablePlayerWire, headers: [
            "X-FST-Publication-Id": "7",
        ]),
    ])
    let client = try FestivalAPI(transport: transport)
    for _ in 0..<2 {
        let loaded = try await client.playerProfile(accountId: "fixture-player-1")
        #expect(loaded.state == .available)
        #expect(loaded.publicationId == 7)
        #expect(loaded.observedPublicationId == 7)
        #expect(loaded.profile.scores.count == 2)
    }
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    for request in requests.suffix(2) {
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/player/fixture-player-1")
        #expect(request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "7")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Player") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Profile-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Profile-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Band-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Band-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "X-FST-Selected-Band-Team-Key") == nil)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }
}

@Test func syncingPlayer202WaitsForAvailable200() async throws {
    let syncing = """
    {"accountId":"fixture-player-1","displayName":null,"status":"syncing",
     "notYetPublished":true,"totalScores":0,"scores":[]}
    """
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: playerPublicationJSON),
        profileReply(202, syncing),
        profileReply(200, availablePlayerWire, headers: [
            "X-FST-Publication-Id": "7",
        ]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.playerProfile(accountId: "fixture-player-1")
    #expect(first.state == .syncing)
    #expect(first.publicationId == nil)
    #expect(first.observedPublicationId == 7)
    let next = try await client.playerProfile(accountId: "fixture-player-1")
    #expect(next.state == .available)
    #expect(next.profile.scores.count == 2)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
}

@Test func playerProfile403AndWarmOfflineCannotInventCachedScores() async throws {
    let denied = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: playerPublicationJSON),
        profileReply(403, #"{"status":"denied"}"#),
    ]))
    await #expect(throws: FestivalAPIError.httpStatus(403)) {
        try await denied.playerProfile(accountId: "fixture-player-1")
    }
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: playerPublicationJSON)),
        .success(profileReply(200, availablePlayerWire, headers: [
            "X-FST-Publication-Id": "7",
        ])),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    _ = try await client.playerProfile(accountId: "fixture-player-1")
    await #expect(throws: URLError.self) {
        try await client.playerProfile(accountId: "fixture-player-1")
    }
}

@Test func playerProfileRequiresMatchingGenerationIdentityAndHTTPState() async throws {
    let syncing = """
    {"accountId":"fixture-player-1","status":"syncing",
     "notYetPublished":true,"totalScores":0,"scores":[]}
    """
    for (status, body, header, expected) in [
        (200, syncing, "7", FestivalAPIError.invalidPlayerProfile),
        (202, availablePlayerWire, "7", FestivalAPIError.invalidPlayerProfile),
        (203, availablePlayerWire, "7", FestivalAPIError.invalidPlayerProfile),
        (200, availablePlayerWire, "6", FestivalAPIError.invalidPublication),
        (200, availablePlayerWire, "", FestivalAPIError.invalidPublication),
    ] {
        let responseHeaders = header.isEmpty ? [:] : ["X-FST-Publication-Id": header]
        var replies: [HTTPResult] = [
            HTTPResult(status: 200, data: playerPublicationJSON),
            profileReply(status, body, headers: responseHeaders),
        ]
        if expected == .invalidPublication {
            replies += [
                HTTPResult(status: 200, data: playerPublicationJSON),
                profileReply(status, body, headers: responseHeaders),
            ]
        }
        let client = try FestivalAPI(transport: FixtureTransport(replies))
        await #expect(throws: expected) {
            try await client.playerProfile(accountId: "fixture-player-1")
        }
    }
    let malformed = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: playerPublicationJSON),
        profileReply(200, """
        {"accountId":"fixture-player-1","totalScores":1,
         "scores":[{"si":"fixture-pulse","ins":"01","sc":"99,900"}]}
        """, headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try await malformed.playerProfile(accountId: "fixture-player-1")
    }
    let unsent = FixtureTransport([])
    let invalid = try FestivalAPI(transport: unsent)
    await #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try await invalid.playerProfile(accountId: "../other")
    }
    #expect(await unsent.recorded().isEmpty)
}

@Test func oversizedButValidPlayerJSONNeverBecomesAnOfflineSnapshot() async throws {
    let oversized = "{\"accountId\":\"fixture-player-1\",\"totalScores\":0,"
        + "\"scores\":[],\"pad\":\""
        + String(repeating: "x", count: PlayerProfileResponse.wireByteLimit) + "\"}"
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: playerPublicationJSON),
        profileReply(200, oversized, headers: [
            "X-FST-Publication-Id": "7",
        ]),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try await client.playerProfile(accountId: "fixture-player-1")
    }
}

// MARK: - Client-side player-page aggregation

private let statsPlayerWire = """
{"accountId":"fixture-player-1","displayName":"Fixture Player 1","totalScores":5,
 "scores":[
   {"si":"song-a","ins":"01","sc":99900,"acc":979,"fc":true,"st":6,"rk":1,"te":26},
   {"si":"song-b","ins":"01","sc":95000,"acc":900,"fc":false,"st":5,"rk":5,"te":26},
   {"si":"song-c","ins":"01","sc":80000,"acc":700,"fc":false,"st":3,"rk":20,"te":26},
   {"si":"song-a","ins":"02","sc":91000,"acc":905,"fc":true,"st":6,"rk":2,"te":26},
   {"si":"song-d","ins":"04","sc":50000}
 ]}
"""

/// Overall totals count unique songs across instruments and pick the single best rank.
@Test func overallStatsAggregatesAcrossVisibleInstrumentsOnly() throws {
    let response = try player(statsPlayerWire)
    #expect(try response.validate(requestedAccountId: "fixture-player-1") == .available)
    let stats = response.overallStats(visibleInstruments: [.lead, .bass])
    // song-a is charted on both Lead and Bass, so it counts once.
    #expect(stats.songsPlayed == 3)
    #expect(stats.fullComboCount == 2)
    #expect(stats.fullComboPercent == 50.0)
    #expect(stats.goldStarCount == 2)
    #expect(stats.bestRank == 1)
    #expect(stats.bestRankSongId == "song-a")
    #expect(stats.bestRankInstrument == .lead)
    let avg = try #require(stats.averageAccuracy)
    #expect(abs(avg - (979 + 900 + 700 + 905) * 1_000 / 4) < 0.01)

    // Drums is not in the visible set, so its unrated, unranked row never counts.
    let leadOnly = response.overallStats(visibleInstruments: [.lead])
    #expect(leadOnly.songsPlayed == 3)
    #expect(leadOnly.fullComboCount == 1)
    #expect(leadOnly.bestRank == 1)

    // An empty visible set (all Settings instruments hidden) zeroes every total.
    let none = response.overallStats(visibleInstruments: [])
    #expect(none.songsPlayed == 0)
    #expect(none.fullComboCount == 0)
    #expect(none.fullComboPercent == 0)
    #expect(none.goldStarCount == 0)
    #expect(none.averageAccuracy == nil)
    #expect(none.bestRank == nil)
    #expect(none.bestRankSongId == nil)
    #expect(none.bestRankInstrument == nil)
}

/// Per-instrument totals only ever look at that one instrument's rows.
@Test func instrumentStatsIsolatesOneChartAndReportsAnEmptyState() throws {
    let response = try player(statsPlayerWire)
    let lead = response.instrumentStats(.lead)
    #expect(lead.songsPlayed == 3)
    #expect(lead.fullComboCount == 1)
    // floor(1/3 * 1000) / 10 == 33.3, not a rounded 33.3333...
    #expect(lead.fullComboPercent == 33.3)
    #expect(lead.goldStarCount == 1)
    #expect(lead.fiveStarCount == 1)
    #expect(lead.bestRank == 1)
    #expect(lead.bestRankSongId == "song-a")

    let drums = response.instrumentStats(.drums)
    #expect(drums.songsPlayed == 1)
    #expect(drums.fullComboCount == 0)
    #expect(drums.fullComboPercent == 0)
    #expect(drums.goldStarCount == 0)
    #expect(drums.averageAccuracy == nil)
    #expect(drums.bestRank == nil)
    #expect(drums.bestRankSongId == nil)

    let vocals = response.instrumentStats(.vocals)
    #expect(vocals.songsPlayed == 0)
    #expect(vocals.fullComboCount == 0)
    #expect(vocals.goldStarCount == 0)
    #expect(vocals.fiveStarCount == 0)
}
