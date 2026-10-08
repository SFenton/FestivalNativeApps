import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - compete-hub

/// Ported from `pages/compete/firstRun/demo/CompeteHubDemo.tsx`: like the web, the demo
/// alternates every 5 s between a leaderboard layout (top rankings plus the player's row) and a
/// rivals layout (Above You / Below You), fading the whole demo out and in with a 6 pt drop.
struct FirstRunCompeteHubDemo: View {
    @FirstRunReduceMotion private var reduceMotion
    @State private var showsRivals = false
    @State private var fading: Set<Int> = []

    var body: some View {
        Group {
            if showsRivals {
                rivals
            } else {
                leaderboard
            }
        }
        .firstRunSwapRow(0, rise: 6)
        .environment(\.firstRunFadingRows, fading)
        .accessibilityHidden(true)
        .firstRunDemoTicker { await swap() }
    }

    // Group cards like the real Compete and Rivals cards (#381).
    private var leaderboard: some View {
        FestivalGlassSection(rows: .flush(separatorInset: RankingRowLayout.horizontalPadding)) {
            ForEach(FirstRunDemoPool.rankings.prefix(4)) { FirstRunRankRow(entry: $0) }
            FirstRunRankRow(entry: FirstRunDemoPool.rankingNeighborhood[3])
        }
    }

    private var rivals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Above You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            FestivalGlassSection(rows: .flush(separatorInset: 16)) {
                ForEach(FirstRunDemoPool.rivalsAbove.prefix(2)) { FirstRunRivalRow(rival: $0, direction: .above) }
            }
            Text("Below You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            FestivalGlassSection(rows: .flush(separatorInset: 16)) {
                ForEach(FirstRunDemoPool.rivalsBelow.prefix(2)) { FirstRunRivalRow(rival: $0, direction: .below) }
            }
        }
    }

    private func swap() async {
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion,
            fadeOut: { fading = [0] },
            update: { showsRivals.toggle() },
            fadeIn: { fading = [] }
        )
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
/// sections, alternately swapping each whole group every 5 s like the web.
struct FirstRunCompeteRivalsDemo: View {
    var body: some View {
        FirstRunRivalGroupsDemo(visible: 2, staggers: true)
    }
}
