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
}

@Test func accountScopedBandEndpointsAreExcludedFromSnapshotCache() {
    #expect(!PublicEndpoint.playerBands(
        accountId: "a", group: "all", page: 1, pageSize: 25
    ).allowsSnapshotCache)
    #expect(!PublicEndpoint.playerBandsByType(
        accountId: "a", bandType: "Band_Duets", combo: nil
    ).allowsSnapshotCache)
    #expect(PublicEndpoint.bandProfile(bandType: "Band_Duets", teamKey: "a:b", combo: nil).allowsSnapshotCache)
}

// MARK: - Player band group

@Test func playerBandGroupLabelsMatchWebFilterNames() {
    #expect(PlayerBandGroup.all.label == "All")
    #expect(PlayerBandGroup.duos.label == "Duos")
    #expect(PlayerBandGroup.trios.label == "Trios")
    #expect(PlayerBandGroup.quads.label == "Quads")
}
