import SwiftUI
import FestivalDesign

// MARK: - compete-hub

/// Ported from `pages/compete/firstRun/demo/CompeteHubDemo.tsx`: the web alternates between a
/// leaderboard layout and a rivals layout on a timer. This static port shows both halves at
/// once (a compact ranking snippet plus one rival above/below) so the "competitive snapshot"
/// description reads correctly without a timer that would keep running while off-screen.
struct FirstRunCompeteHubDemo: View {
    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                ForEach(FirstRunDemoPool.rankings.prefix(2)) { entry in
                    FirstRunRankRow(entry: entry)
                }
                FirstRunRankRow(entry: FirstRunDemoPool.rankingNeighborhood[3])
            }
            if let above = FirstRunDemoPool.rivalsAbove.first,
               let below = FirstRunDemoPool.rivalsBelow.first {
                FirstRunRivalRow(rival: above, direction: .above)
                FirstRunRivalRow(rival: below, direction: .below)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - compete-leaderboards

/// Ported from `pages/compete/firstRun/demo/CompeteLeaderboardsDemo.tsx`: the same top-ranked
/// preview as the Leaderboards hub's own overview slide.
struct FirstRunCompeteLeaderboardsDemo: View {
    var body: some View {
        FirstRunLeaderboardsOverviewDemo()
    }
}

// MARK: - compete-rivals

/// Ported from `pages/compete/firstRun/demo/CompeteRivalsDemo.tsx`: Above You / Below You rival
/// sections.
struct FirstRunCompeteRivalsDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Above You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            ForEach(FirstRunDemoPool.rivalsAbove.prefix(2)) { rival in
                FirstRunRivalRow(rival: rival, direction: .above)
            }
            Text("Below You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            ForEach(FirstRunDemoPool.rivalsBelow.prefix(2)) { rival in
                FirstRunRivalRow(rival: rival, direction: .below)
            }
        }
        .accessibilityHidden(true)
    }
}
