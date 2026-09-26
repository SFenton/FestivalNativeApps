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

/// Typed selected-player fields before native text and accessibility presentation.
enum SongProfileCardPolicy {
    /// Compose only reported data and enabled fields for the chosen visible chart.
    ///
    /// - Parameters:
    ///   - score: Validated compact-wire player score.
    ///   - chart: One visible solo instrument, not an inferred multi-chart result.
    ///   - visibility: Persisted Settings switches.
    /// - Returns: Human-readable metadata labels without inventing a full combo.
    static func labels(
        for score: PlayerScore, chart: Instrument, visibility: SongMetadataVisibility
    ) -> [String] {
        var labels = [chart.label]
        if visibility.score, score.score > 0 {
            labels.append("Score \(score.score.formatted())")
        }
        if visibility.percentage, let accuracy = score.accuracy {
            labels.append("Accuracy \(ScoreFormatting.accuracy(accuracy))%")
        }
        if visibility.percentile, let rank = score.rank,
           let total = score.totalEntries,
           let bucket = ScoreFormatting.percentileBucket(rank: rank, totalEntries: total) {
            labels.append(bucket)
        }
        if visibility.season, let season = score.season, season > 0 {
            labels.append("Season \(season)")
        }
        if visibility.difficulty, let difficulty = score.difficulty,
           difficulty.rounded() == difficulty, (0...3).contains(difficulty) {
            labels.append(["Easy", "Medium", "Hard", "Expert"][Int(difficulty)])
        }
        if visibility.stars, let stars = score.stars, stars > 0 {
            labels.append("\(stars) stars")
        }
        if visibility.lastPlayed,
           let rawDate = score.validLastPlayedAt ?? score.lastPlayedAt {
            do {
                let date = try Date.ISO8601FormatStyle().parse(rawDate)
                labels.append("Last played \(date.formatted(date: .abbreviated, time: .omitted))")
            } catch {
                labels.append("Last played date unavailable")
            }
        }
        return labels
    }
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
                    .foregroundStyle(BrandTokens.textSecondary)
            case .syncing:
                Label("Player scores are syncing", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(BrandTokens.textSecondary)
            case .failed:
                Label("Player scores unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(BrandTokens.gold)
            case .available:
                if filterInvalidScores {
                    Text("Filtered player score display is not available yet")
                        .foregroundStyle(BrandTokens.gold)
                } else if let chart, !chartAvailable {
                    Text("\(chart.label) is not charted for this song")
                        .foregroundStyle(BrandTokens.textSecondary)
                } else if let chart, let score, score.score > 0 {
                    HStack(alignment: .top, spacing: 8) {
                        Text(
                            SongProfileCardPolicy.labels(
                                for: score, chart: chart, visibility: visibility
                            ).joined(separator: " · ")
                        )
                        .foregroundStyle(BrandTokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        if score.isFullCombo == true {
                            Text("FC")
                                .fontWeight(.bold)
                                .foregroundStyle(BrandTokens.gold)
                                .frame(minWidth: 28, minHeight: 24)
                                .overlay {
                                    Capsule().stroke(BrandTokens.gold, lineWidth: 1.5)
                                }
                                .accessibilityLabel("Full combo")
                        }
                    }
                } else if let chart {
                    Text("No \(chart.label) score for \(player.displayName)")
                        .foregroundStyle(BrandTokens.textSecondary)
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
