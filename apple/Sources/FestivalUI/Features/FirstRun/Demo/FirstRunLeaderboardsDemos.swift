import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - leaderboards-overview

/// Ported from `pages/leaderboards/firstRun/demo/RankingsOverviewDemo.tsx`: one instrument's
/// top rankings.
struct FirstRunLeaderboardsOverviewDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstRunInstrumentHeader(instrument: .lead)
            VStack(spacing: 6) {
                ForEach(Array(FirstRunDemoPool.rankings.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    FirstRunRankRow(entry: entry)
                        .firstRunStagger(index)
                }
            }
            FirstRunViewAllRow(title: "View all rankings (12,480)")
        }
        .accessibilityHidden(true)
    }
}

// MARK: - leaderboards-experimental-metrics

/// Ported from `pages/leaderboards/firstRun/demo/ExperimentalMetricsDemo.tsx`: the "Rank By"
/// metric picker limited to the experimental metrics.
struct FirstRunLeaderboardsExperimentalMetricsDemo: View {
    private let metrics: [(String, String)] = [
        ("Adjusted Percentile", "Estimated skill from your rank position."),
        ("Popularity-Weighted Percentile", "Adjusts for how many players know this song."),
        ("FC Rate", "Share of your tracked scores that were full combos."),
        ("Max Score %", "How close your best score is to the song's ceiling."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rank By").font(.caption.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                HStack {
                    Image(systemName: index == 0 ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(index == 0 ? BrandTokens.accentBlue : FestivalText.deemphasized)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.0).foregroundStyle(FestivalText.primary)
                        Text(metric.1).font(.caption2).foregroundStyle(FestivalText.deemphasized)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - leaderboards-your-rank

/// Ported from `pages/leaderboards/firstRun/demo/YourRankDemo.tsx`: the neighborhood around the
/// player's own rank, plus a pulsing "View all rankings" row.
struct FirstRunLeaderboardsYourRankDemo: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(FirstRunDemoPool.rankingNeighborhood.enumerated()), id: \.element.id) { index, entry in
                FirstRunRankRow(entry: entry)
                    .firstRunStagger(index)
            }
            FirstRunViewAllRow(title: "View all rankings (12,480)")
        }
        .accessibilityHidden(true)
    }
}
