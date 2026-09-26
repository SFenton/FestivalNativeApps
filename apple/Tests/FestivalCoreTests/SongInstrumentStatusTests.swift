import Foundation
import Testing
@testable import FestivalCore

/// Decode one original, synthetic four-chart Song with an unavailable chart sentinel.
///
/// - Returns: Chart support independent of a selected account's score bytes.
/// - Throws: Invalid locally authored catalogue fields.
private func chipFixtureSong() throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Synthetic Quartet",
     "difficulty":{"guitar":2,"bass":3,"drums":4,"vocals":1,
                   "proGuitar":99,"proDrums":0}}
    """.utf8))
}

/// Build one multi-chart player index without affecting any shared mock listener.
///
/// - Returns: Validated Lead, Bass, inconsistent Vocals and uncharted Pro Lead rows.
/// - Throws: A malformed compact wire row or duplicate chart.
private func chipFixtureScores() throws -> [Instrument: PlayerScore] {
    let profile = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-chip-test","totalScores":4,"scores":[
      {"si":"fixture-pulse","ins":"01","sc":99900,"fc":true},
      {"si":"fixture-pulse","ins":"02","sc":88800},
      {"si":"fixture-pulse","ins":"08","sc":0,"fc":true},
      {"si":"fixture-pulse","ins":"10","sc":77700,"fc":true}]}
    """.utf8))
    return try #require(profile.scoreIndex(requestedAccountId: "fixture-chip-test")["fixture-pulse"])
}

/// Preserve nine source-order statuses without hiding a scored non-Lead chart.
@Test func chipStatusesCoverAllChartsAndUnchartedScorePrecedence() throws {
    let statuses = SongInstrumentStatusPolicy.badges(
        for: try chipFixtureSong(), visibleInstruments: Set(Instrument.allCases),
        scores: try chipFixtureScores()
    )
    #expect(statuses.count == 9)
    #expect(statuses.map(\.instrument) == Instrument.allCases)
    #expect(statuses.map(\.status) == [
        .fullCombo, .scored, .noScore, .inconsistentFullCombo,
        .unavailable, .unavailable, .unavailable, .unavailable, .noScore
    ])
    #expect(statuses[0].id == .lead)
    #expect(statuses[0].announcement == "Lead, full combo")
    #expect(statuses[1].announcement == "Bass, scored")
    #expect(statuses[2].announcement == "Drums, no score")
    #expect(statuses[3].announcement
            == "Tap Vocals, score missing despite a reported full combo")
    #expect(statuses[4].announcement == "Pro Lead, not charted")
}

/// An HTTP 200 empty profile is not a loading or syncing error.
@Test func chipEmptyScoresStayHonestAndVisibleOnlyForAnAvailablePlayer() throws {
    let visible = Set(Instrument.allCases)
    let statuses = SongInstrumentStatusPolicy.badges(
        for: try chipFixtureSong(), visibleInstruments: visible, scores: [:]
    )
    #expect(statuses.count == 9)
    #expect(statuses[0].status == .noScore)
    #expect(statuses[1].status == .noScore)
    #expect(statuses[4].status == .unavailable)
    #expect(SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: true, iconsEnabled: true,
        instrumentFilter: nil, filterInvalidScores: false,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: false, scoresAvailable: true, iconsEnabled: true,
        instrumentFilter: nil, filterInvalidScores: false,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: false, iconsEnabled: true,
        instrumentFilter: nil, filterInvalidScores: false,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: true, iconsEnabled: false,
        instrumentFilter: nil, filterInvalidScores: false,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: true, iconsEnabled: true,
        instrumentFilter: .bass, filterInvalidScores: false,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: true, iconsEnabled: true,
        instrumentFilter: nil, filterInvalidScores: true,
        visibleInstruments: visible
    ))
    #expect(!SongInstrumentStatusPolicy.showsChips(
        hasSelectedPlayer: true, scoresAvailable: true, iconsEnabled: true,
        instrumentFilter: nil, filterInvalidScores: false,
        visibleInstruments: []
    ))
}

/// Hidden charts must not reappear even when another chart has a real score.
@Test func chipVisibilityFollowsEnabledInstrumentsNotStoredScores() throws {
    let badges = SongInstrumentStatusPolicy.badges(
        for: try chipFixtureSong(), visibleInstruments: [.bass, .drums],
        scores: try chipFixtureScores()
    )
    #expect(badges.map(\.instrument) == [.bass, .drums])
    #expect(badges.map(\.status) == [.scored, .noScore])
}

/// Missing, invalid and sentinel difficulties cannot masquerade as playable charts.
@Test func chipAvailabilityUsesActualChartedSongDifficulty() throws {
    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Synthetic Quartet",
     "difficulty":{"guitar":99,"bass":-1,"drums":0}}
    """.utf8))
    let statuses = SongInstrumentStatusPolicy.badges(
        for: song, visibleInstruments: Set(Instrument.allCases),
        scores: try chipFixtureScores()
    )
    #expect(statuses[0].status == .unavailable)
    #expect(statuses[1].status == .unavailable)
    #expect(statuses[2].status == .noScore)
    #expect(statuses[3].status == .unavailable)
}
