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

/// Rows split only for a selected player or band with a current score index, no
/// invalid-score substitution, standard text sizes, a Songs (not Shop) row and at least
/// 600 pt.
@Test func profilePanelGate() {
    func allows(
        allowed: Bool = true, player: Bool = true, current: Bool = true,
        invalid: Bool = false, ax: Bool = false, shop: Bool = false, width: CGFloat = 800
    ) -> Bool {
        SongProfilePanelPolicy.allows(
            allowed: allowed, hasSelectedProfile: player, scoresCurrent: current,
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

/// Compact cards keep their pills on one line: the panel takes the most columns that
/// fit, keeps stars only when they cost no extra line, and gives up (the row stays
/// plain) when even a starless card can't fit; one filtered chart wraps in one column.
@Test func profilePanelArrangement() {
    #expect(SongProfilePanelPolicy.halfWidth(contentWidth: 1012) == 500)
    #expect(SongProfilePanelPolicy.halfWidth(contentWidth: 4) == 0)
    // 52 chrome + 84 score + 66 accuracy + 80 percentile + 2 gaps = 302; + stars 160 = 462.
    let full: [SongMetadataField] = [
        .score(250_000), .accuracy(99_000, fullCombo: false, percentageVisible: true, tint: nil),
        .percentile("Top 5%", tier: .topFive), .stars(count: 5, gold: true),
    ]
    let compact = Array(full.prefix(3))
    #expect(SongProfilePanelPolicy.lineWidth(compact) == 302)
    #expect(SongProfilePanelPolicy.lineWidth(full) == 462)
    #expect(SongProfilePanelPolicy.lineWidth([]) == SongProfilePanelPolicy.tileChrome)
    #expect(SongProfilePanelPolicy.lineWidth([.score(250_000)], scale: 2) == 220)
    // A score grows with its digits: a band's seven-digit score is wider.
    #expect(SongProfilePanelPolicy.estimatedWidth(.score(1_234_567)) == 102)
    #expect(SongProfilePanelPolicy.estimatedWidth(.score(9_999)) == 60)

    let tiles = [Instrument.lead, .bass, .drums, .vocals].map {
        SongProfilePanelTile(subject: .chart($0), fields: full)
    }
    typealias Arrangement = SongProfilePanelPolicy.Arrangement
    func arrange(_ width: CGFloat, overview: Bool = true, tiles: [SongProfilePanelTile] = tiles) -> Arrangement? {
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
    // Compact cards never wrap: too narrow even without stars, no arrangement (the row
    // stays plain). A 600 pt row's half is 282 pt, below the 302 pt compact card.
    #expect(arrange(SongProfilePanelPolicy.halfWidth(contentWidth: 600 - 24)) == nil)
    #expect(arrange(301) == nil)
    #expect(arrange(302) == Arrangement(columns: 1, dropsStars: true))
    #expect(arrange(200) == nil)
    // Larger text widens every card: the same half no longer fits.
    #expect(arrange(383) != nil)
    #expect(SongProfilePanelPolicy.arrangement(width: 383, tiles: tiles, overview: true, scale: 1.5) == nil)
    // A card without stars needs no star decision.
    let plain = [SongProfilePanelTile(subject: .chart(.lead), fields: compact)]
    #expect(arrange(302, tiles: plain) == Arrangement(columns: 1, dropsStars: false))
    #expect(arrange(301, tiles: plain) == nil)
    // One filtered chart keeps every field and wraps within the half.
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

/// A selected band gets one compact card per scored song, named for VoiceOver; no row,
/// a zero score or every field hidden behave like the player cards.
@Test func profilePanelBandTiles() throws {
    let band = SelectedBandIdentity(bandType: .trios, teamKey: "a1:b2:c3", displayName: "Fixture Trio")
    let entry = try JSONDecoder().decode(BandSongPerformanceEntry.self, from: Data("""
    {"songId":"fixture-pulse","rank":3,"totalEntries":1000,"percentile":0.003,"score":1234567,
     "accuracy":1000000,"isFullCombo":true,"stars":6,"season":9,"endTime":"2026-09-27T00:00:00Z"}
    """.utf8))
    let tiles = try SongProfilePanelPolicy.bandTiles(
        band: band, entry: entry, currentSeason: 9,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    )
    #expect(tiles.count == 1)
    #expect(tiles[0].id == "band")
    #expect(tiles[0].chart == nil)
    #expect(tiles[0].subject == .band(.trios, name: "Fixture Trio"))
    // Overview fields only: no season or last played on the card.
    #expect(tiles[0].fields.map(\.id) == [.score, .accuracy, .percentile, .stars])
    #expect(tiles[0].announcement.hasPrefix("Fixture Trio, Trios band: Score 1,234,567"))
    #expect(tiles[0].announcement.contains("Full combo"))
    // A band card fits one line from 320 pt (seven-digit score) without stars, 480 with.
    #expect(SongProfilePanelPolicy.arrangement(width: 319, tiles: tiles, overview: true) == nil)
    #expect(SongProfilePanelPolicy.arrangement(width: 479, tiles: tiles, overview: true)
        == .init(columns: 1, dropsStars: true))
    #expect(SongProfilePanelPolicy.arrangement(width: 480, tiles: tiles, overview: true)
        == .init(columns: 1, dropsStars: false))

    #expect(try SongProfilePanelPolicy.bandTiles(
        band: band, entry: nil, currentSeason: 9,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    ).isEmpty)
    let zero = try JSONDecoder().decode(BandSongPerformanceEntry.self, from: Data("""
    {"songId":"fixture-pulse","rank":3,"totalEntries":1000,"percentile":0.003,"score":0}
    """.utf8))
    #expect(try SongProfilePanelPolicy.bandTiles(
        band: band, entry: zero, currentSeason: 9,
        visibility: SongMetadataVisibility(), order: MetadataField.allCases
    ).isEmpty)
}

/// In iPhone Duo book pose the cards get the trailing side of the fold (`hinge-columns`
/// R1), so the one-line fit uses that width; without a matching band, half the content.
@Test func profilePanelWidthFollowsTheFold() throws {
    // Row content 24–843 (inside 12 pt padding) under a 40 pt fold at 455–495.
    let span = HorizontalSpan(minX: 24, maxX: 843)
    let fold = CGRect(x: 455, y: 0, width: 40, height: 669)
    let band = try #require(HingeColumns.band(
        span: span, fold: fold, gutter: SongProfilePanelPolicy.gap, minimumSide: HingeColumns.minimumSide
    ))
    #expect(band == HingeBand(leadingWidth: 431, gap: 40, trailingWidth: 348))
    #expect(SongProfilePanelPolicy.panelWidth(contentWidth: span.width, band: band) == 348)
    // Flat: the halves split the content evenly.
    #expect(SongProfilePanelPolicy.panelWidth(contentWidth: span.width, band: nil)
            == SongProfilePanelPolicy.halfWidth(contentWidth: span.width))
    // A stale band from another width is ignored, as HingeRowLayout ignores it.
    #expect(SongProfilePanelPolicy.panelWidth(contentWidth: 900, band: band)
            == SongProfilePanelPolicy.halfWidth(contentWidth: 900))
}
