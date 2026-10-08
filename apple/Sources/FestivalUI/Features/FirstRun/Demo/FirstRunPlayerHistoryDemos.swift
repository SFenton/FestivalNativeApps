import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - playerhistory-score-list

/// Ported from `pages/leaderboard/player/firstRun/demo/ScoreListDemo.tsx`: every tracked score
/// change as the page's real ``ScoreHistoryListRow``s, the personal best purple and bold,
/// cascading in 125 ms apart like the web's `FadeIn delay={i * STAGGER_INTERVAL}`.
struct FirstRunPlayerHistoryScoreListDemo: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.ownHistory.enumerated()), id: \.offset) { index, entry in
                ScoreHistoryListRow(entry: entry, isBest: index == 0)
                    .firstRunStagger(index)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - playerhistory-sort

/// Ported from `pages/leaderboard/player/firstRun/demo/SortControlsDemo.tsx`: the page's real
/// **Sort Player Scores** sheet (read-only, top of the sheet), as the Songs sort demo shows the
/// Songs sheet.
struct FirstRunPlayerHistorySortDemo: View {
    var body: some View {
        PlayerHistorySortSheet(mode: .score, ascending: false) { _, _ in }
            .firstRunSheetPreview(height: 420)
    }
}
