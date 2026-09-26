import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

private struct SummaryFixtureProfiles: Decodable {
    let profiles: [String: PlayerProfileResponse]
}

/// Load the same original profile bytes served by the device fixture.
///
/// - Returns: Two individually validated synthetic player envelopes.
/// - Throws: A missing fixture or invalid compact score row.
private func selectedFixtureProfiles() throws -> [String: PlayerProfileResponse] {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contracts/fixtures/player-demo.json")
    let fixtures = try JSONDecoder().decode(
        SummaryFixtureProfiles.self, from: Data(contentsOf: fixtureURL)
    )
    for (accountId, profile) in fixtures.profiles {
        #expect(try profile.validate(requestedAccountId: accountId) == .available)
    }
    return fixtures.profiles
}

@Test func selectedPlayerChangesSongScoreAndExplicitFullCombo() throws {
    let profiles = try selectedFixtureProfiles()
    let first = try #require(
        profiles["fixture-player-1"]?.scoreIndex(
            requestedAccountId: "fixture-player-1"
        )["fixture-pulse"]?[.lead]
    )
    let second = try #require(
        profiles["fixture-player-2"]?.scoreIndex(
            requestedAccountId: "fixture-player-2"
        )["fixture-pulse"]?[.lead]
    )
    #expect(first.score == 99_900)
    #expect(second.score == 99_800)
    #expect(first.isFullCombo == false)
    #expect(second.isFullCombo == true)
    #expect(first.accuracy == 979_000)
    #expect(SongProfileCardPolicy.labels(
        for: first, chart: .lead, visibility: SongMetadataVisibility()
    ).contains("Score \(first.score.formatted())"))
    #expect(SongProfileCardPolicy.labels(
        for: second, chart: .lead, visibility: SongMetadataVisibility()
    ).contains("Score \(second.score.formatted())"))
    #expect(SongProfileCardPolicy.labels(
        for: second, chart: .lead, visibility: SongMetadataVisibility()
    ).contains("Top 10%"))
}

@Test func eachBackedScoreMetadataSwitchHidesOnlyItsOwnLabel() throws {
    let response = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-metadata","totalScores":1,"scores":[{
      "si":"fixture-pulse","ins":"01","sc":99900,"acc":979,"fc":true,
      "st":5,"dif":3,"sn":9,"rk":1,"te":26,"lp":"2026-09-26T00:00:00Z"}]}
    """.utf8))
    _ = try response.validate(requestedAccountId: "fixture-metadata")
    let score = try #require(response.scores.first)
    let all = SongProfileCardPolicy.labels(
        for: score, chart: .lead, visibility: SongMetadataVisibility()
    )
    for required in ["Score ", "Accuracy ", "Top ", "Season ", "Expert", "stars",
                     "Last played "] {
        #expect(all.contains(where: { $0.contains(required) }))
    }
    let switches: [(WritableKeyPath<SongMetadataVisibility, Bool>, String)] = [
        (\.score, "Score "), (\.percentage, "Accuracy "),
        (\.percentile, "Top "), (\.season, "Season "),
        (\.difficulty, "Expert"), (\.stars, "stars"),
        (\.lastPlayed, "Last played "),
    ]
    for (key, hiddenLabel) in switches {
        var changed = SongMetadataVisibility()
        changed[keyPath: key] = false
        let labels = SongProfileCardPolicy.labels(
            for: score, chart: .lead, visibility: changed
        )
        #expect(labels.count == all.count - 1)
        #expect(!labels.contains(where: { $0.contains(hiddenLabel) }))
    }
    var preference = SongMetadataVisibility()
    preference.score = false
    preference.percentage = false
    preference.percentile = false
    preference.season = false
    preference.difficulty = false
    preference.stars = false
    preference.lastPlayed = false
    let hidden = SongProfileCardPolicy.labels(
        for: score, chart: .bass, visibility: preference
    )
    #expect(hidden == ["Bass"])
    #expect(preference.intensity)
    preference.intensity = false
    #expect(!preference.intensity)
}

@Test func missingMetadataAndInvalidDatesNeverInventACorrectPlayerScore() throws {
    let response = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-empty-metadata","totalScores":1,"scores":[{
      "si":"fixture-pulse","ins":"02","sc":0,"fc":false,"lp":"not-a-date"}]}
    """.utf8))
    _ = try response.validate(requestedAccountId: "fixture-empty-metadata")
    let score = try #require(response.scores.first)
    let labels = SongProfileCardPolicy.labels(
        for: score, chart: .bass, visibility: SongMetadataVisibility()
    )
    #expect(!labels.contains("Score 0"))
    #expect(labels.contains("Last played date unavailable"))
    #expect(!labels.contains(where: { $0.contains("Accuracy") || $0.contains("Top ") }))
}

/// Valid historical time wins over raw time, including real seven-digit ISO seconds.
@Test func validLastPlayedDateTakesPriorityWithoutLosingFractionalWireDates() throws {
    let response = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-date","totalScores":1,"scores":[{
      "si":"fixture-pulse","ins":"01","sc":99900,
      "lp":"2024-09-20T12:34:56.1234567Z",
      "vlp":"2026-09-20T12:34:56.1234567Z"}]}
    """.utf8))
    _ = try response.validate(requestedAccountId: "fixture-date")
    let score = try #require(response.scores.first)
    let labels = SongProfileCardPolicy.labels(
        for: score, chart: .lead, visibility: SongMetadataVisibility()
    )
    let date = try #require(labels.first(where: { $0.hasPrefix("Last played ") }))
    #expect(date.contains("2026"))
    #expect(!date.contains("2024"))
    #expect(!date.contains("unavailable"))
}

/// A real SwiftUI host must lay out each selected and unavailable score state.
@MainActor
@Test func profileSummaryStatesRenderWithoutInventingAnonymousScores() throws {
    let profiles = try selectedFixtureProfiles()
    let first = try #require(profiles["fixture-player-1"])
    let score = try #require(first.scores.first)
    let searched = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1"}
    """.utf8))
    let player = try SelectedPlayerIdentity(searchResult: searched)
    for state: SelectedPlayerLoadState in [
        .loading, .available, .syncing, .failed("Synthetic 403")
    ] {
        let summary = SongProfileSummary(
            player: player, chart: .lead, chartAvailable: true,
            score: state == .available ? score : nil, state: state,
            visibility: SongMetadataVisibility(), filterInvalidScores: false,
            songId: "fixture-pulse"
        )
        let rendered = ImageRenderer(content: summary.frame(width: 390, height: 110))
        rendered.scale = 1
        #expect(rendered.cgImage?.width == 390)
    }
}
