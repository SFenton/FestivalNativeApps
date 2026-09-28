import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Saved, independent row metadata switches; absence never fabricates a score.
struct SongMetadataVisibility: Equatable, Sendable {
    var score = true
    var percentage = true
    var percentile = true
    var season = true
    var intensity = true
    var difficulty = true
    var stars = true
    var lastPlayed = true
}

/// Selected-player score state under an ordinary catalogue Song row.
struct SongProfileSummary: View {
    let player: SelectedPlayerIdentity
    let chart: Instrument?
    let chartAvailable: Bool
    let score: PlayerScore?
    let state: SelectedPlayerLoadState
    let visibility: SongMetadataVisibility
    let filterInvalidScores: Bool
    let songId: String

    var body: some View {
        Group {
            switch state {
            case .none:
                Text("Selected player scores are not loaded")
                    .foregroundStyle(BrandTokens.gold)
            case .loading:
                Label("Loading \(player.displayName)'s scores", systemImage: "hourglass")
                    .foregroundStyle(FestivalText.primary)
            case .syncing:
                Label("Player scores are syncing", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(FestivalText.primary)
            case .failed:
                Label("Player scores unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(BrandTokens.gold)
            case .available:
                if filterInvalidScores {
                    Text("Filtered player score display is not available yet")
                        .foregroundStyle(BrandTokens.gold)
                } else if let chart, !chartAvailable {
                    Text("\(chart.label) is not charted for this song")
                        .foregroundStyle(FestivalText.primary)
                } else if let chart, let score, score.score > 0 {
                    let labels = Result {
                        try SongProfileCardPolicy.labels(
                            for: score, chart: chart, visibility: visibility
                        )
                    }
                    switch labels {
                    case let .success(values):
                        Text(values.joined(separator: " · "))
                            .foregroundStyle(FestivalText.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    case let .failure(error):
                        Text("Player score metadata unavailable: \(error.localizedDescription)")
                            .foregroundStyle(BrandTokens.gold)
                    }
                } else if let chart {
                    Text("No \(chart.label) score for \(player.displayName)")
                        .foregroundStyle(FestivalText.primary)
                } else {
                    Text("No visible instrument in Settings")
                        .foregroundStyle(BrandTokens.gold)
                }
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("fst.songs.profile-summary.\(songId)")
    }
}
