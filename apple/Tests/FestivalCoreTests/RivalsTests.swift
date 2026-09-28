import Foundation
import Testing
@testable import FestivalCore

/// Load one checked-in Rivals fixture captured from (or, where noted, hand
/// authored to match) the live `FSTService` Rivals/LeaderboardRivals endpoints.
///
/// - Parameter name: File under `contracts/fixtures/`, without extension.
/// - Returns: Raw wire bytes.
/// - Throws: A missing fixture file.
private func rivalsFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/\(name).json"))
}

// MARK: - Wire decoding

/// A live capture (`GET /api/player/{id}/rivals/Solo_Guitar`) decodes with the
/// server's fractional `rivalScore`/`avgSignedDelta`, not integers.
@Test func rivalsListDecodesLiveCaptureWithFractionalScores() throws {
    let response = try JSONDecoder().decode(
        RivalsListResponse.self, from: rivalsFixture("rivals-list-demo")
    )
    #expect(response.combo == "01")
    #expect(response.above.count == 3)
    #expect(response.below.count == 3)
    let first = try #require(response.above.first)
    #expect(first.accountId == "408abb67d81446f0ac714506950ce178")
    #expect(first.rivalScore == 863.541259765625)
    #expect(first.avgSignedDelta == -6.541779041290283)
    #expect(!response.isEmpty)
}

/// A live capture (`GET /api/player/{id}/leaderboard-rivals/Solo_Guitar`) decodes,
/// including an empty `above` array (the player was rank 1).
@Test func leaderboardRivalsDecodesLiveCaptureWithEmptyAboveGroup() throws {
    let response = try JSONDecoder().decode(
        LeaderboardRivalsListResponse.self, from: rivalsFixture("leaderboard-rivals-demo")
    )
    #expect(response.instrument == "Solo_Guitar")
    #expect(response.rankBy == "totalscore")
    #expect(response.userRank == 1)
    #expect(response.above.isEmpty)
    #expect(response.below.count == 3)
    #expect(!response.isEmpty)
    let first = try #require(response.below.first)
    #expect(first.leaderboardRank == 2)
    #expect(first.userLeaderboardRank == 1)
}

/// The overview endpoint's per-combo counts decode; hex hybrid combos included.
@Test func rivalsOverviewDecodesComboSummaries() throws {
    let response = try JSONDecoder().decode(
        RivalsOverviewResponse.self, from: rivalsFixture("rivals-overview-demo")
    )
    #expect(response.accountId == "e408c4613c8f4da5907090b390bda80c")
    #expect(response.combos.count == 5)
    #expect(response.combos.first?.combo == "01")
    #expect(response.combos.first?.aboveCount == 10)
}

/// Detail response (hand-authored to match the verified `RivalsEndpoints.cs`
/// shape; live captures returned 503 "published data unavailable" while this
/// fixture was made) decodes both compared songs and gap arrays.
@Test func rivalDetailDecodesSongsAndGaps() throws {
    let response = try JSONDecoder().decode(
        RivalDetailResponse.self, from: rivalsFixture("rival-detail-demo")
    )
    #expect(response.rival.accountId == "408abb67d81446f0ac714506950ce178")
    #expect(response.combo == "01")
    #expect(response.songs.count == 4)
    #expect(response.songsToCompete?.count == 1)
    #expect(response.yourExclusiveSongs?.count == 1)
    let tied = try #require(response.songs.first { $0.rankDelta == 0 })
    #expect(tied.userScore == tied.rivalScore)
}

/// The leaderboard rival detail envelope omits `combo`/`offset`/`limit` and adds
/// `instrument`/`rankBy`; both must decode through the same shared type.
@Test func leaderboardRivalDetailDecodesWithoutComboOrOffset() throws {
    let response = try JSONDecoder().decode(
        RivalDetailResponse.self, from: rivalsFixture("leaderboard-rival-detail-demo")
    )
    #expect(response.combo == nil)
    #expect(response.instrument == "Solo_Guitar")
    #expect(response.rankBy == "totalscore")
    #expect(response.offset == nil)
    #expect(response.songs.count == 2)
}

// MARK: - Empty-state normalization

@Test func emptyFactoriesProduceValidZeroResults() {
    let list = RivalsListResponse.empty(combo: "Solo_Guitar")
    #expect(list.isEmpty)
    #expect(list.combo == "Solo_Guitar")

    let detail = RivalDetailResponse.empty(rivalId: "fixture-rival", displayName: "Fixture Rival")
    #expect(detail.songs.isEmpty)
    #expect(detail.rival.accountId == "fixture-rival")
    #expect(detail.rival.displayName == "Fixture Rival")
    #expect(detail.totalSongs == 0)
}

// MARK: - Categorization (native port of `categorizeRivalSongs`)

private func song(id: String, delta: Int) -> RivalSongComparison {
    let json = """
    {"songId":"\(id)","title":null,"artist":null,"instrument":"Solo_Guitar",
     "userInstrument":null,"rivalInstrument":null,
     "userRank":1,"rivalRank":1,"rankDelta":\(delta),"userScore":100,"rivalScore":90}
    """
    return try! JSONDecoder().decode(RivalSongComparison.self, from: Data(json.utf8))
}

@Test func categorizationSplitsByDirectionAndMagnitude() {
    let songs = [
        song(id: "a", delta: 5), song(id: "b", delta: 40), song(id: "c", delta: 80),
        song(id: "d", delta: -3), song(id: "e", delta: -50),
        song(id: "f", delta: 1), song(id: "g", delta: 2),
    ]
    let categories = RivalCategorization.categorize(songs)
    let keys = categories.map(\.key)
    #expect(keys.contains("closest_battles"))
    #expect(keys.contains("almost_passed"))
    #expect(keys.contains("slipping_away"))
    #expect(keys.contains("barely_winning") || keys.contains("pulling_forward") || keys.contains("dominating_them"))

    // Closest Battles pulls the 5 smallest |delta| regardless of direction.
    let closest = try! #require(categories.first { $0.key == "closest_battles" })
    #expect(closest.songs.count == min(5, songs.count))
    #expect(closest.songs.allSatisfy { abs($0.rankDelta) <= 40 })
}

@Test func categorizationOfEmptySongsProducesNoCategories() {
    #expect(RivalCategorization.categorize([]).isEmpty)
}

// MARK: - AllRivals category encoding

@Test func allRivalsCategoryRoundTripsSongScope() {
    let scope = RivalAllCategory.song(instrument: "Solo_Guitar")
    #expect(scope.encoded == "song:Solo_Guitar")
    #expect(RivalAllCategory.decode(scope.encoded) == scope)
}

@Test func allRivalsCategoryRoundTripsLeaderboardScope() {
    let scope = RivalAllCategory.leaderboard(instrument: "Solo_Drums", rankBy: .adjusted)
    #expect(scope.encoded == "leaderboard:Solo_Drums:adjusted")
    #expect(RivalAllCategory.decode(scope.encoded) == scope)
}

@Test func allRivalsCategoryTreatsBareInstrumentAsSongScope() {
    #expect(RivalAllCategory.decode("Solo_Bass") == .song(instrument: "Solo_Bass"))
}

@Test func allRivalsCategoryRejectsMalformedLeaderboardToken() {
    #expect(RivalAllCategory.decode("leaderboard:Solo_Bass") == nil)
    #expect(RivalAllCategory.decode("leaderboard:Solo_Bass:not-a-metric") == nil)
}

// MARK: - Endpoint URL construction

@Test func rivalsEndpointBuildsExpectedListURL() throws {
    let url = try RivalsEndpoint.list(accountId: "abc123", instrument: .lead)
        .url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    #expect(url.absoluteString == "https://festivalscoretracker.com/api/player/abc123/rivals/Solo_Guitar")
}

@Test func rivalsEndpointRejectsUnsafeAccountId() {
    #expect(throws: RivalsAPIError.invalidResource) {
        _ = try RivalsEndpoint.list(accountId: "../etc/passwd", instrument: .lead)
            .url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    }
}

@Test func rivalsEndpointRejectsUnknownSort() {
    #expect(throws: RivalsAPIError.invalidResource) {
        _ = try RivalsEndpoint.detail(
            accountId: "abc123", instrument: .lead, rivalId: "def456",
            sort: "dangerous", limit: 0, offset: 0
        ).url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    }
}

@Test func rivalsEndpointBuildsExpectedLeaderboardDetailURLWithQuery() throws {
    let url = try RivalsEndpoint.leaderboardDetail(
        accountId: "abc123", instrument: .drums, rivalId: "def456",
        rankBy: .weighted, sort: "they_lead"
    ).url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    #expect(components?.path == "/api/player/abc123/leaderboard-rivals/Solo_Drums/def456")
    let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
    #expect(query["rankBy"] == "weighted")
    #expect(query["sort"] == "they_lead")
}

// MARK: - Navigation bridge

@MainActor
@Test func navigationBridgeConsumesStashedContextOnce() {
    let bridge = RivalNavigationBridge.shared
    bridge.stash(.song(instruments: ["Solo_Guitar", "Solo_Bass"]), forRivalId: "fixture-rival-bridge")
    let first = bridge.consume(forRivalId: "fixture-rival-bridge")
    #expect(first?.source == .song)
    #expect(first?.instruments == ["Solo_Guitar", "Solo_Bass"])
    #expect(bridge.consume(forRivalId: "fixture-rival-bridge") == nil)
}

@MainActor
@Test func navigationBridgeReturnsNilForUnstashedRival() {
    #expect(RivalNavigationBridge.shared.consume(forRivalId: "fixture-never-stashed") == nil)
}
