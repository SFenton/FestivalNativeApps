import Foundation
import Testing
@testable import FestivalCore

/// Locate a fixture committed under `contracts/fixtures/`.
///
/// - Parameter name: Fixture file name, including its extension.
/// - Returns: Absolute URL to the fixture inside the repository checkout.
private func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/\(name)")
}

// MARK: - Player bands

@Test func committedPlayerBandsFixtureDecodes() throws {
    let data = try Data(contentsOf: fixtureURL("player-bands-demo.json"))
    let response = try JSONDecoder().decode(PlayerBandListResponse.self, from: data)
    #expect(response.accountId == "fixture-player-1")
    #expect(response.entries.count == 2)
    #expect(response.pageCount(pageSize: 25) == 1)
    let duo = try #require(response.entries.first)
    #expect(duo.bandType == "Band_Duets")
    #expect(duo.membersLabel == "Fixture Player 1 + Fixture Player 2")
    #expect(duo.members.first?.chartedInstruments == [.lead])
    let trio = response.entries[1]
    // Second member has a null display name; membersLabel falls back like the web client.
    #expect(trio.membersLabel == "Fixture Player 1 + Unknown User + Fixture Player 3")
}

@Test func playerBandListPageCountHandlesUnevenTotals() {
    let response = PlayerBandListResponse(accountId: "x", totalCount: 51, entries: [])
    #expect(response.pageCount(pageSize: 25) == 3)
    let empty = PlayerBandListResponse(accountId: "x", totalCount: 0, entries: [])
    #expect(empty.pageCount(pageSize: 25) == 1)
}

// MARK: - Band profile (safe rankings-by-teamKey read)

@Test func committedBandDetailFixtureDecodesFromRankingsEnvelope() throws {
    let data = try Data(contentsOf: fixtureURL("band-detail-demo.json"))
    let envelope = try JSONDecoder().decode(BandProfileEnvelope.self, from: data)
    #expect(envelope.bandType == "Band_Duets")
    let detail = try #require(envelope.selectedBandEntry)
    #expect(detail.teamKey == "fixture-rank-1:fixture-rank-2")
    #expect(detail.members.count == 2)
    #expect(detail.members.first?.chartedInstruments == [.lead])
    #expect(detail.members.last?.resolvedName == "Unknown User")
    #expect(detail.rank(for: .totalscore) == 1)
    #expect(detail.ratingValue(for: .totalscore) == 222222222)
}

@Test func bandDetailRatingFallsBackWhenRawWeightedRatingIsNull() {
    let detail = BandDetail(
        bandId: "b", comboId: nil, teamKey: "t", members: [], configurations: [],
        songsPlayed: 10, totalChartedSongs: 40, coverage: 0.25, rawSkillRating: 0.3,
        adjustedSkillRating: 0.31, adjustedSkillRank: 2, weightedRating: 0.4, weightedRank: 4,
        fcRate: 0.1, fcRateRank: 8, totalScore: 3_000_000, totalScoreRank: 2, avgAccuracy: 88.4,
        fullComboCount: 1, avgStars: 3.1, bestRank: 5, avgRank: 10.0, rawWeightedRating: nil,
        computedAt: nil
    )
    #expect(detail.ratingValue(for: .weighted) == 0.4)
    #expect(detail.ratingValue(for: .fcrate) == Double(1) / Double(40))
}

// MARK: - Rank history

@Test func committedBandRankHistoryFixtureDecodesAndRanksByMetric() throws {
    let data = try Data(contentsOf: fixtureURL("band-rank-history-demo.json"))
    let response = try JSONDecoder().decode(BandRankHistoryResponse.self, from: data)
    #expect(response.history.count == 2)
    let latest = try #require(response.history.first)
    #expect(latest.rank(for: .adjusted) == 1)
    #expect(latest.rank(for: .fcrate) == 2)
    let previous = response.history[1]
    #expect(previous.rank(for: .totalscore) == 2)
}

// MARK: - Band song extremes

@Test func committedBandSongExtremesFixtureDecodesBestAndWorst() throws {
    let data = try Data(contentsOf: fixtureURL("band-song-extremes-demo.json"))
    let response = try JSONDecoder().decode(BandSongExtremesResponse.self, from: data)
    #expect(response.best.count == 1)
    #expect(response.worst.count == 1)
    #expect(response.best.first?.songId == "fixture-pulse")
    #expect(response.worst.first?.rank == 20)
}

// MARK: - Song band leaderboard

@Test func committedSongBandLeaderboardFixtureDecodesAndValidates() throws {
    let data = try Data(contentsOf: fixtureURL("song-band-leaderboard-demo.json"))
    let response = try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: data)
    try response.validate(songId: "fixture-pulse", bandType: .duets)
    #expect(response.entries.count == 2)
    #expect(response.pageCount == 2)
    let first = try #require(response.entries.first)
    #expect(first.membersLabel == "Fixture Rank One + Unknown User")
    #expect(first.members.first?.chartedInstruments == [.lead])
}

/// `accountId` adds the selected player's best band; it is the pinned footer's row and
/// highlights the matching page row. A selected row of another size is rejected.
@Test func songBandLeaderboardDecodesSelectedPlayerBand() throws {
    let data = try Data(contentsOf: fixtureURL("song-band-leaderboard-demo.json"))
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(object["entries"] as? [[String: Any]])
    var mine = try #require(entries.last)
    mine["rank"] = 29
    object["selectedPlayerEntry"] = mine
    let response = try JSONDecoder().decode(
        SongBandLeaderboardResponse.self, from: JSONSerialization.data(withJSONObject: object)
    )
    try response.validate(songId: "fixture-pulse", bandType: .duets)
    let selected = try #require(response.selectedEntry)
    #expect(selected.rank == 29)
    #expect(response.selectedBandEntry == nil)
    #expect(response.isSelected(try #require(response.entries.last)))
    #expect(!response.isSelected(try #require(response.entries.first)))
    // Without a selected row nothing is highlighted.
    let plain = try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: data)
    #expect(plain.selectedEntry == nil)
    #expect(!plain.isSelected(try #require(plain.entries.first)))
    // A selected row from another band size does not belong on this board.
    mine["bandType"] = "Band_Trios"
    object["selectedPlayerEntry"] = mine
    let mismatched = try JSONDecoder().decode(
        SongBandLeaderboardResponse.self, from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(throws: FestivalAPIError.invalidBandProfile) {
        try mismatched.validate(songId: "fixture-pulse", bandType: .duets)
    }
}

/// The per-size board carries the service's entry-total switch for its song header
/// (issue #317); an older payload without it reads as "no totals".
@Test func songBandLeaderboardDecodesEntryTotalsSwitch() throws {
    let data = try Data(contentsOf: fixtureURL("song-band-leaderboard-demo.json"))
    #expect(try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: data).showLeaderboardEntryTotals == true)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "showLeaderboardEntryTotals")
    let legacy = try JSONDecoder().decode(
        SongBandLeaderboardResponse.self, from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(legacy.showLeaderboardEntryTotals == nil)
}

@Test func songBandLeaderboardRejectsMismatchedSongOrBandType() throws {
    let data = try Data(contentsOf: fixtureURL("song-band-leaderboard-demo.json"))
    let response = try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: data)
    #expect(throws: FestivalAPIError.invalidBandProfile) {
        try response.validate(songId: "other-song", bandType: .duets)
    }
    #expect(throws: FestivalAPIError.invalidBandProfile) {
        try response.validate(songId: "fixture-pulse", bandType: .trios)
    }
}

@Test func songBandLeaderboardPageCountUsesLocalEntriesFallback() {
    let response = SongBandLeaderboardResponse(
        songId: "s", bandType: "Band_Duets", count: 0, totalEntries: 100,
        localEntries: nil, entries: []
    )
    #expect(response.pageCount == 4)
    let empty = SongBandLeaderboardResponse(
        songId: "s", bandType: "Band_Duets", count: 0, totalEntries: 0,
        localEntries: 0, entries: []
    )
    #expect(empty.pageCount == 1)
}

/// The demo page with `selectedPlayerEntry` set to the given JSON row (issue #306).
private func songBandPageWithSelected(_ selectedJSON: String) throws -> SongBandLeaderboardResponse {
    var text = try String(contentsOf: fixtureURL("song-band-leaderboard-demo.json"), encoding: .utf8)
    text = text.replacingOccurrences(of: "\"selectedPlayerEntry\": null", with: "\"selectedPlayerEntry\": \(selectedJSON)")
    return try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: Data(text.utf8))
}

private let selectedDuoJSON = """
{"bandId": "fixture-band-p", "bandType": "Band_Duets", "teamKey": "fixture-player-1:fixture-rank-9",
 "comboId": null, "members": [
  {"accountId": "fixture-player-1", "displayName": "Fixture Player One", "instruments": ["Solo_Guitar"],
   "score": 300000, "accuracy": 970000, "isFullCombo": false, "stars": 5, "difficulty": 3, "season": 9},
  {"accountId": "fixture-rank-9", "displayName": "A Very Long Bandmate Name", "instruments": ["Solo_Bass"],
   "score": 290000, "accuracy": 960000, "isFullCombo": false, "stars": 5, "difficulty": 3, "season": 9}],
 "score": 590000, "rank": 14, "accuracy": 965000, "isFullCombo": false, "stars": 5, "season": 9,
 "difficulty": 3, "percentile": 0.5, "endTime": null}
"""

@Test func songBandLeaderboardDecodesTheSelectedPlayersBandForTheFooter() throws {
    let page = try songBandPageWithSelected(selectedDuoJSON)
    try page.validate(songId: "fixture-pulse", bandType: .duets)
    let selected = try #require(page.selectedEntry)
    #expect(selected.rank == 14)
    #expect(page.selectedBandEntry == nil)
    #expect(!page.entries.contains(where: page.isSelected))
    #expect(page.isSelected(selected))

    let row = selected.footerLeaderboardEntry
    #expect(row.displayName == "Fixture Player One + A Very Long Bandmate Name")
    #expect(row.rank == 14)
    #expect(row.score == 590_000)
    #expect(row.accuracy == 965_000)
    #expect(row.isFullCombo == false)
    #expect(row.stars == 5)
    #expect(row.season == 9)
    #expect(row.difficulty == 3)
    #expect(row.accountId == "band-fixture-band-p")
}

@Test func songBandLeaderboardWithoutASelectedPlayerHasNoFooterOrHighlight() throws {
    let data = try Data(contentsOf: fixtureURL("song-band-leaderboard-demo.json"))
    let page = try JSONDecoder().decode(SongBandLeaderboardResponse.self, from: data)
    #expect(page.selectedEntry == nil)
    #expect(!page.entries.contains(where: page.isSelected))
}

@Test func songBandLeaderboardHighlightsTheSelectedBandWhenItIsOnThePage() throws {
    let first = """
    {"bandId": "fixture-band-1", "bandType": "Band_Duets", "teamKey": "fixture-rank-1:fixture-rank-2",
     "comboId": null, "members": [], "score": 999999, "rank": 1, "accuracy": 990000, "isFullCombo": true,
     "stars": 5, "season": 9, "difficulty": 3, "percentile": 0.0385, "endTime": null}
    """
    let page = try songBandPageWithSelected(first)
    #expect(page.entries.map(page.isSelected) == [true, false])
    // No members: the footer falls back to the team key, as web's `formatBandTeamName`.
    #expect(page.selectedEntry?.footerLeaderboardEntry.displayName == "fixture-rank-1:fixture-rank-2")
}

@Test func songBandLeaderboardRejectsASelectedRowOfAnotherBandSize() throws {
    let trio = selectedDuoJSON.replacingOccurrences(of: "\"Band_Duets\"", with: "\"Band_Trios\"")
    let page = try songBandPageWithSelected(trio)
    #expect(throws: FestivalAPIError.invalidBandProfile) {
        try page.validate(songId: "fixture-pulse", bandType: .duets)
    }
}

// MARK: - Endpoint URL construction

@Test func bandEndpointsAreConstrainedAndEncoded() throws {
    let base = URL(string: "https://example.com")!
    #expect(
        try PublicEndpoint.playerBands(
            accountId: "fixture-player-1", group: "duos", page: 2, pageSize: 25
        ).url(relativeTo: base).absoluteString
        == "https://example.com/api/player/fixture-player-1/bands?group=duos&page=2&pageSize=25"
    )
    #expect(
        try PublicEndpoint.playerBandsByType(
            accountId: "fixture-player-1", bandType: "Band_Duets", combo: nil
        ).url(relativeTo: base).absoluteString
        == "https://example.com/api/player/fixture-player-1/bands/Band_Duets"
    )
    #expect(
        try PublicEndpoint.bandProfile(
            bandType: "Band_Duets", teamKey: "a:b", combo: nil
        ).url(relativeTo: base).query
        == "teamKey=a:b&rankBy=adjusted&page=1&pageSize=1"
    )
    #expect(
        try PublicEndpoint.bandRankHistory(
            bandType: "Band_Duets", teamKey: "a:b", combo: nil, days: 30
        ).url(relativeTo: base).absoluteString
        == "https://example.com/api/rankings/bands/Band_Duets/a:b/history?days=30"
    )
    #expect(
        try PublicEndpoint.bandSongExtremes(
            bandType: "Band_Duets", teamKey: "a:b", combo: nil, limit: 5
        ).url(relativeTo: base).absoluteString
        == "https://example.com/api/rankings/bands/Band_Duets/a:b/songs?limit=5"
    )
    #expect(
        try PublicEndpoint.songBandLeaderboard(
            songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 0, combo: nil
        ).url(relativeTo: base).absoluteString
        == "https://example.com/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=0"
    )
    // The selected player is a query parameter only (their best band, issue #307).
    let selected = PublicEndpoint.songBandLeaderboard(
        songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 25, combo: nil,
        accountId: "fixture-player-1"
    )
    #expect(
        try selected.url(relativeTo: base).absoluteString
        == "https://example.com/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=25&accountId=fixture-player-1"
    )
    #expect(!selected.allowsSnapshotCache)
    #expect(PublicEndpoint.songBandLeaderboard(
        songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 0, combo: nil
    ).allowsSnapshotCache)
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.songBandLeaderboard(
            songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 0, combo: nil,
            accountId: "not valid"
        ).url(relativeTo: base)
    }
    #expect(
        try PublicEndpoint.songBandLeaderboard(
            songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 25, combo: nil,
            accountId: "fixture-player-1"
        ).url(relativeTo: base).query
        == "top=25&offset=25&accountId=fixture-player-1"
    )
}

@Test func bandEndpointsRejectInvalidParameters() throws {
    let base = URL(string: "https://example.com")!
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.playerBands(accountId: "not valid", group: "all", page: 1, pageSize: 25)
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.playerBands(accountId: "fixture-player-1", group: "unknown", page: 1, pageSize: 25)
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.bandProfile(bandType: "Band_Duets", teamKey: "", combo: nil)
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.bandProfile(bandType: "Band_Duets", teamKey: "a:b", combo: "has/slash")
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.bandRankHistory(bandType: "Band_Duets", teamKey: "a:b", combo: nil, days: 0)
            .url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.songBandLeaderboard(
            songId: "a/b", bandType: "Band_Duets", top: 25, offset: 0, combo: nil
        ).url(relativeTo: base)
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try PublicEndpoint.songBandLeaderboard(
            songId: "fixture-pulse", bandType: "Band_Duets", top: 25, offset: 0, combo: nil,
            accountId: "not valid"
        ).url(relativeTo: base)
    }
}

@Test func accountScopedBandEndpointsAreExcludedFromSnapshotCache() {
    #expect(!PublicEndpoint.playerBands(
        accountId: "a", group: "all", page: 1, pageSize: 25
    ).allowsSnapshotCache)
    #expect(!PublicEndpoint.playerBandsByType(
        accountId: "a", bandType: "Band_Duets", combo: nil
    ).allowsSnapshotCache)
    #expect(PublicEndpoint.bandProfile(bandType: "Band_Duets", teamKey: "a:b", combo: nil).allowsSnapshotCache)
    #expect(PublicEndpoint.songBandLeaderboard(
        songId: "s", bandType: "Band_Duets", top: 25, offset: 0, combo: nil
    ).allowsSnapshotCache)
    #expect(!PublicEndpoint.songBandLeaderboard(
        songId: "s", bandType: "Band_Duets", top: 25, offset: 0, combo: nil, accountId: "a"
    ).allowsSnapshotCache)
}

// MARK: - Player band group

@Test func playerBandGroupLabelsMatchWebFilterNames() {
    #expect(PlayerBandGroup.all.label == "All")
    #expect(PlayerBandGroup.duos.label == "Duos")
    #expect(PlayerBandGroup.trios.label == "Trios")
    #expect(PlayerBandGroup.quads.label == "Quads")
}

// MARK: - Player bands preview (profile page, issue #312)

/// A minimal player-band row for preview tests.
///
/// - Parameter index: Distinguishes the band's identifiers.
/// - Returns: A two-member Duos row.
private func previewEntry(_ index: Int) -> PlayerBandEntry {
    PlayerBandEntry(
        bandId: "band-\(index)", teamKey: "team-\(index)", bandType: "Band_Duets", appearanceCount: index,
        members: []
    )
}

@Test func playerBandsPreviewKeepsWebGroupOrderAndPreviewSize() {
    let duos = PlayerBandListResponse(accountId: "p", totalCount: 18, entries: (1...8).map(previewEntry))
    let quads = PlayerBandListResponse(accountId: "p", totalCount: 4, entries: (1...4).map(previewEntry))
    let preview = PlayerBandsPreview(responses: [.quads: quads, .duos: duos])

    #expect(preview.groups.map(\.group) == [.duos, .trios, .quads])
    let duoGroup = preview.groups[0]
    #expect(duoGroup.entries.map(\.bandId) == (1...6).map { "band-\($0)" })
    #expect(duoGroup.totalCount == 18)
    #expect(duoGroup.hasMore)
    // A group the service did not return previews as empty ("No Bands Yet"), not a failure.
    #expect(preview.groups[1].entries.isEmpty)
    #expect(preview.groups[1].totalCount == 0)
    #expect(!preview.groups[1].hasMore)
    #expect(preview.groups[2].entries.count == 4)
    #expect(!preview.groups[2].hasMore)
}

@Test func playerBandsPreviewNeverReportsFewerBandsThanItShows() {
    // A stale total below the page's rows must not hide View All nor under-count.
    let response = PlayerBandListResponse(accountId: "p", totalCount: 1, entries: (1...3).map(previewEntry))
    let group = PlayerBandsPreview.Group(group: .trios, response: response)
    #expect(group.totalCount == 3)
    #expect(!group.hasMore)
    #expect(group.id == .trios)
    #expect(PlayerBandsPreview.previewCount == 6)
}
