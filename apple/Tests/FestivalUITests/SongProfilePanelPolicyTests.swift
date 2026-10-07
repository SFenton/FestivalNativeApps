import CoreGraphics
import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Load the synthetic catalogue's charted Pulse song (Lead, Bass, Drums, Vocals only).
///
/// - Returns: The song.
/// - Throws: Inconsistent fixture bytes or a missing fixture song.
private func pulseSong() throws -> Song {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/songs-demo.json")
    let catalogue = try JSONDecoder().decode(SongsResponse.self, from: Data(contentsOf: fixtureURL))
    try catalogue.validate()
    return try #require(catalogue.songs.first { $0.songId == "fixture-pulse" })
}

/// A synthetic compact score index for Pulse: Lead FC, Bass zero, Drums scored and an
/// uncharted Pro Lead row that must never show.
///
/// - Returns: Scores keyed by chart.
/// - Throws: Invalid fixture JSON.
private func pulseScores() throws -> [Instrument: PlayerScore] {
    let response = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-panel","totalScores":4,"scores":[
      {"si":"fixture-pulse","ins":"01","sc":120000,"fc":true,"acc":1000,"st":6,"sn":3,"rk":5,"te":1000},
      {"si":"fixture-pulse","ins":"02","sc":0},
      {"si":"fixture-pulse","ins":"04","sc":80000,"fc":false,"acc":950,"st":4,"sn":2},
      {"si":"fixture-pulse","ins":"10","sc":9999}]}
    """.utf8))
    _ = try response.validate(requestedAccountId: "fixture-panel")
    return Dictionary(uniqueKeysWithValues: response.scores.map { ($0.instrument, $0) })
}

/// Rows split only for a selected player with a current score index, no invalid-score
/// substitution, standard text sizes, a Songs (not Shop) row and at least 600 pt.
@Test func profilePanelGate() {
    func allows(
        allowed: Bool = true, player: Bool = true, current: Bool = true,
        invalid: Bool = false, ax: Bool = false, shop: Bool = false, width: CGFloat = 800
    ) -> Bool {
        SongProfilePanelPolicy.allows(
            allowed: allowed, hasSelectedPlayer: player, scoresCurrent: current,
            filterInvalidScores: invalid, accessibilitySize: ax, shopRow: shop, rowWidth: width
        )
    }
    #expect(allows())
    #expect(allows(width: 600))
    #expect(!allows(width: 599))
    #expect(!allows(width: 0))
    #expect(!allows(allowed: false))
    // No profile: today's row.
    #expect(!allows(player: false))
    // Loading, paused (publication mismatch) or failed index: today's row states.
    #expect(!allows(current: false))
    #expect(!allows(invalid: true))
    #expect(!allows(ax: true))
    #expect(!allows(shop: true))
}

/// Cards keep their pills on one line: the panel takes the most columns that fit,
/// keeps stars only when they cost no extra line, and wraps one column when nothing fits.
@Test func profilePanelArrangement() {
    #expect(SongProfilePanelPolicy.halfWidth(contentWidth: 1012) == 500)
    #expect(SongProfilePanelPolicy.halfWidth(contentWidth: 4) == 0)
    // 52 chrome + 84 score + 66 accuracy + 80 percentile + 2 gaps = 302; + stars 160 = 462.
    #expect(SongProfilePanelPolicy.lineWidth([.score, .accuracy, .percentile]) == 302)
    #expect(SongProfilePanelPolicy.lineWidth([.score, .accuracy, .percentile, .stars]) == 462)
    #expect(SongProfilePanelPolicy.lineWidth([]) == SongProfilePanelPolicy.tileChrome)
    #expect(SongProfilePanelPolicy.lineWidth([.score], scale: 2) == 220)

    let full: [SongMetadataField] = [
        .score(250_000), .accuracy(99_000, fullCombo: false, percentageVisible: true, tint: nil),
        .percentile("Top 5%", tier: .topFive), .stars(count: 5, gold: true),
    ]
    let tiles = [Instrument.lead, .bass, .drums, .vocals].map {
        SongProfilePanelTile(chart: $0, fields: full)
    }
    typealias Arrangement = SongProfilePanelPolicy.Arrangement
    func arrange(_ width: CGFloat, overview: Bool = true, tiles: [SongProfilePanelTile] = tiles) -> Arrangement {
        SongProfilePanelPolicy.arrangement(width: width, tiles: tiles, overview: overview)
    }
    // iPad 11 portrait half (~383 pt): stars would wrap, so one compact column.
    #expect(arrange(383) == Arrangement(columns: 1, dropsStars: true))
    // iPad 11 landscape half (~563 pt): stars fit and two compact columns don't.
    #expect(arrange(563) == Arrangement(columns: 1, dropsStars: false))
    // Two compact columns (612 pt) beat one column with stars.
    #expect(arrange(612) == Arrangement(columns: 2, dropsStars: true))
    // Two columns with stars (932 pt) cost no extra line over three compact ones (2 lines each).
    #expect(arrange(932) == Arrangement(columns: 2, dropsStars: false))
    #expect(arrange(1300) == Arrangement(columns: 4, dropsStars: true))
    // Never more columns than cards.
    #expect(arrange(1300, tiles: Array(tiles.prefix(2))) == Arrangement(columns: 2, dropsStars: false))
    // Too narrow even compact: one wrapping column.
    #expect(arrange(200) == Arrangement(columns: 1, dropsStars: true))
    // One filtered chart keeps every field and wraps.
    #expect(arrange(200, overview: false) == Arrangement(columns: 1, dropsStars: false))
}

/// All charts: one compact card per supported, visible chart with a positive score, in
/// chip order and the saved field order; zero and uncharted scores never get a card.
@Test func profilePanelTilesAllCharts() throws {
    let song = try pulseSong()
    let scores = try pulseScores()
    let tiles = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: nil,
        visibleInstruments: Set(Instrument.allCases), currentSeason: 3,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(tiles.map(\.chart) == [.lead, .drums])
    for tile in tiles {
        #expect(tile.fields.allSatisfy { SongProfilePanelPolicy.overviewKinds.contains($0.id) })
    }
    #expect(tiles[0].fields.first == .score(120000))
    #expect(tiles[0].announcement.hasPrefix("Lead: Score 120,000"))
    #expect(tiles[0].announcement.contains("Full combo"))

    // Hidden charts drop their card.
    let leadHidden = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: nil,
        visibleInstruments: [.bass, .drums], currentSeason: 3,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(leadHidden.map(\.chart) == [.drums])

    // Saved order applies: stars before score.
    let reordered = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: nil,
        visibleInstruments: Set(Instrument.allCases), currentSeason: 3,
        visibility: SongMetadataVisibility(),
        order: [.stars] + MetadataField.allCases.filter { $0 != .stars }
    )
    #expect(reordered[0].fields.first?.id == .stars)
}

/// One filtered chart shows every enabled field; a song with no positive score on the
/// shown charts gets no cards, so its row stays plain.
@Test func profilePanelTilesFilteredAndEmpty() throws {
    let song = try pulseSong()
    let scores = try pulseScores()
    let lead = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: .lead,
        visibleInstruments: Set(Instrument.allCases), currentSeason: 3,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(lead.map(\.chart) == [.lead])
    #expect(lead[0].fields.contains { $0.id == .season })
    #expect(lead[0].fields.contains { $0.id == .intensity })

    let bass = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: .bass,
        visibleInstruments: Set(Instrument.allCases), currentSeason: 3,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(bass.isEmpty)
    let none = try SongProfilePanelPolicy.tiles(
        song: song, scores: [:], instrumentFilter: nil,
        visibleInstruments: Set(Instrument.allCases), currentSeason: 3,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(none.isEmpty)

    // Every field hidden still names the chart for VoiceOver.
    var hidden = SongMetadataVisibility()
    hidden.score = false; hidden.percentage = false; hidden.percentile = false; hidden.stars = false
    let bare = try SongProfilePanelPolicy.tiles(
        song: song, scores: scores, instrumentFilter: nil,
        visibleInstruments: [.drums], currentSeason: 3,
        visibility: hidden, order: MetadataField.allCases
    )
    #expect(bare.map(\.fields) == [[]])
    #expect(bare.first?.announcement == "Drums, scored")
}
