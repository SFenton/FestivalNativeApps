#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

private struct SummaryStateCase {
    let name: String
    let state: SelectedPlayerLoadState
    let chart: Instrument?
    let chartAvailable: Bool
    let score: PlayerScore?
    let filterInvalidScores: Bool
    let gold: Bool
}

/// Unavailable and hidden-chart fallbacks must paint distinct honest messages.
@MainActor
@Test func selectedScoreSummaryPaintsEveryUnscoredFallback() throws {
    let profile = try #require(selectedFixtureProfiles()["fixture-player-1"])
    let score = try #require(profile.scores.first)
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1"}
    """.utf8))
    let player = try SelectedPlayerIdentity(searchResult: result)
    let cases: [SummaryStateCase] = [
        SummaryStateCase(
            name: "not-loaded", state: .none, chart: .lead,
            chartAvailable: true, score: nil, filterInvalidScores: false, gold: true
        ),
        SummaryStateCase(
            name: "no-visible-chart", state: .available, chart: nil,
            chartAvailable: false, score: nil, filterInvalidScores: false, gold: true
        ),
        SummaryStateCase(
            name: "uncharted", state: .available, chart: .proDrums,
            chartAvailable: false, score: nil, filterInvalidScores: false, gold: false
        ),
        SummaryStateCase(
            name: "no-bass-score", state: .available, chart: .bass,
            chartAvailable: true, score: nil, filterInvalidScores: false, gold: false
        ),
        SummaryStateCase(
            name: "invalid-filter-paused", state: .available, chart: .lead,
            chartAvailable: true, score: score, filterInvalidScores: true, gold: true
        ),
        SummaryStateCase(
            name: "valid-lead", state: .available, chart: .lead,
            chartAvailable: true, score: score, filterInvalidScores: false, gold: false
        ),
    ]
    var screenshots: [String: Data] = [:]
    for scenario in cases {
        let renderer = ImageRenderer(content:
            SongProfileSummary(
                player: player, chart: scenario.chart,
                chartAvailable: scenario.chartAvailable, score: scenario.score,
                state: scenario.state, visibility: SongMetadataVisibility(),
                filterInvalidScores: scenario.filterInvalidScores,
                songId: "fixture-pulse"
            )
            .frame(width: 390, height: 110)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 390 && image.height == 110)
        let goldPixels = paintedPixels(near: (255, 215, 0), in: image, sampleStep: 1)
        #expect((goldPixels > 10) == scenario.gold)
        screenshots[scenario.name] = try nativeHostedPNG(
            image, filename: "songs-summary-\(scenario.name).png",
            environment: "FST_SONG_ROW_RENDER_OUT"
        )
    }
    #expect(screenshots["not-loaded"] != screenshots["no-visible-chart"])
    #expect(screenshots["uncharted"] != screenshots["no-bass-score"])
    #expect(screenshots["invalid-filter-paused"] != screenshots["valid-lead"])
}
#endif
