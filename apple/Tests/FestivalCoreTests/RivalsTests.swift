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
    #expect(first.accountId == "f1c749eb07c32578cfa3e59ec38c03a8")
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
    #expect(response.accountId == "f1c7fea37bf9b1069250832ae4211461")
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
    #expect(response.rival.accountId == "f1c749eb07c32578cfa3e59ec38c03a8")
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

// MARK: - RivalScope debug-token round-tripping

@Test func rivalScopeDebugTokenRoundTripsSongScope() {
    let scope = RivalScope.song(instruments: ["Solo_Guitar", "Solo_Bass"])
    #expect(scope.debugToken == "song:Solo_Guitar,Solo_Bass")
    #expect(RivalScope(debugToken: scope.debugToken) == scope)
}

@Test func rivalScopeDebugTokenRoundTripsLeaderboardScope() {
    let scope = RivalScope.leaderboard(instrument: "Solo_Drums", rankBy: .adjusted)
    #expect(scope.debugToken == "leaderboard:Solo_Drums:adjusted")
    #expect(RivalScope(debugToken: scope.debugToken) == scope)
}

@Test func rivalScopeDebugTokenRoundTripsComboScope() {
    let scope = RivalScope.combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"])
    #expect(scope.debugToken == "combo:03:Solo_Guitar,Solo_Bass")
    #expect(RivalScope(debugToken: scope.debugToken) == scope)
}

@Test func rivalScopeDebugTokenRejectsMalformedTokens() {
    #expect(RivalScope(debugToken: "leaderboard:Solo_Bass") == nil)
    #expect(RivalScope(debugToken: "leaderboard:Solo_Bass:not-a-metric") == nil)
    #expect(RivalScope(debugToken: "unknown:Solo_Bass") == nil)
}

// MARK: - Cross-instrument combo derivation (native `comboUtils.ts`/`combos.ts`)

@Test func comboIdMatchesWebBitmaskForLeadAndBass() {
    #expect(RivalCombo.comboId(for: [.lead, .bass]) == "03")
}

@Test func comboIdMatchesWebBitmaskForFullOgBand() {
    #expect(RivalCombo.comboId(for: [.lead, .bass, .drums, .vocals]) == "0f")
}

@Test func comboIdMatchesWebBitmaskForProStrings() {
    #expect(RivalCombo.comboId(for: [.proLead, .proBass]) == "30")
}

@Test func deriveScopeReturnsNilForFewerThanTwoInstruments() {
    #expect(RivalCombo.deriveScope(visible: [.lead]) == nil)
    #expect(RivalCombo.deriveScope(visible: []) == nil)
}

@Test func deriveScopeReturnsNilForCrossGroupInstruments() {
    // Lead (OG band) + Pro Lead (Pro Strings) span two different groups.
    #expect(RivalCombo.deriveScope(visible: [.lead, .proLead]) == nil)
}

@Test func deriveScopeReturnsWithinGroupCombo() {
    let scope = RivalCombo.deriveScope(visible: [.bass, .lead])
    #expect(scope == .instruments(comboId: "03", instruments: [.bass, .lead]))
    #expect(scope?.token == "03")
    #expect(scope?.label == "Combo")
}

@Test func deriveScopeDetectsExactProDrumsFamily() {
    let scope = RivalCombo.deriveScope(visible: [.proCymbals, .proDrums])
    #expect(scope == .proDrumsFamily)
    #expect(scope?.token == "pro_drums")
    #expect(scope?.label == "Pro Drums Family")
}

@Test func deriveScopeIgnoresProDrumsFamilyPlusExtraInstrument() {
    // Not *exactly* the two-instrument Pro Drums family, and Pro Cymbals/Pro Drums
    // aren't within either supported bitmask group, so no scope is derived.
    #expect(RivalCombo.deriveScope(visible: [.proCymbals, .proDrums, .lead]) == nil)
}

// MARK: - Common Rivals intersection (native `RivalsPage.tsx`'s `commonRivals` memo)

private func rivalSummary(
    id: String, rivalScore: Double, sharedSongCount: Int = 10
) -> RivalSummary {
    let json = """
    {"accountId":"\(id)","displayName":"Fixture \(id)","rivalScore":\(rivalScore),
     "sharedSongCount":\(sharedSongCount),"aheadCount":1,"behindCount":1,"avgSignedDelta":0}
    """
    return try! JSONDecoder().decode(RivalSummary.self, from: Data(json.utf8))
}

@Test func commonRivalsRequiresAtLeastTwoLists() {
    let list = RivalsListResponse(combo: "Solo_Guitar", above: [rivalSummary(id: "a", rivalScore: 1)], below: [])
    let result = RivalCommonRivals.intersect([list])
    #expect(result.above.isEmpty)
    #expect(result.below.isEmpty)
}

@Test func commonRivalsKeepsOnlyRivalsInEveryList() {
    let shared = rivalSummary(id: "shared", rivalScore: 50)
    let onlyInFirst = rivalSummary(id: "solo", rivalScore: 999)
    let guitar = RivalsListResponse(combo: "Solo_Guitar", above: [shared, onlyInFirst], below: [])
    let bass = RivalsListResponse(combo: "Solo_Bass", above: [shared], below: [])
    let result = RivalCommonRivals.intersect([guitar, bass])
    #expect(result.above.map(\.accountId) == ["shared"])
    #expect(result.below.isEmpty)
}

@Test func commonRivalsSortsByRivalScoreDescending() {
    let low = rivalSummary(id: "low", rivalScore: 10)
    let high = rivalSummary(id: "high", rivalScore: 90)
    let guitar = RivalsListResponse(combo: "Solo_Guitar", above: [low, high], below: [])
    let bass = RivalsListResponse(combo: "Solo_Bass", above: [low, high], below: [])
    let result = RivalCommonRivals.intersect([guitar, bass])
    #expect(result.above.map(\.accountId) == ["high", "low"])
}

@Test func commonRivalsPicksDirectionByMajorityVote() {
    let rival = rivalSummary(id: "rival", rivalScore: 1)
    // Above in two of three lists → majority "above".
    let a = RivalsListResponse(combo: "a", above: [rival], below: [])
    let b = RivalsListResponse(combo: "b", above: [rival], below: [])
    let c = RivalsListResponse(combo: "c", above: [], below: [rival])
    let result = RivalCommonRivals.intersect([a, b, c])
    #expect(result.above.map(\.accountId) == ["rival"])
    #expect(result.below.isEmpty)
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

@Test func rivalsEndpointBuildsExpectedComboListURL() throws {
    let url = try RivalsEndpoint.comboList(accountId: "abc123", token: "03")
        .url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    #expect(url.absoluteString == "https://festivalscoretracker.com/api/player/abc123/rivals/03")
}

@Test func rivalsEndpointBuildsExpectedComboDetailURL() throws {
    let url = try RivalsEndpoint.comboDetail(
        accountId: "abc123", token: "pro_drums", rivalId: "def456",
        sort: "closest", limit: 0, offset: 0
    ).url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    #expect(components?.path == "/api/player/abc123/rivals/pro_drums/def456")
}

@Test func rivalsEndpointRejectsUnsafeComboToken() {
    #expect(throws: RivalsAPIError.invalidResource) {
        _ = try RivalsEndpoint.comboList(accountId: "abc123", token: "../etc/passwd")
            .url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    }
    #expect(throws: RivalsAPIError.invalidResource) {
        _ = try RivalsEndpoint.comboList(accountId: "abc123", token: "toolonghex")
            .url(relativeTo: URL(string: "https://festivalscoretracker.com")!)
    }
}
