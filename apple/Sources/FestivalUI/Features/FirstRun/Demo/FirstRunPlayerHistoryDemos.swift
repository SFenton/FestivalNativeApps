import SwiftUI
import FestivalDesign

// MARK: - playerhistory-score-list

/// Ported from `pages/leaderboard/player/firstRun/demo/ScoreListDemo.tsx`: every tracked score
/// change, with the player's personal best highlighted (purple), matching `FirstRunRankRow`'s
/// player-highlight treatment.
struct FirstRunPlayerHistoryScoreListDemo: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.ownScores.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 16) {
                    Text(entry.name)
                        .font(.subheadline)
                        .foregroundStyle(BrandTokens.textPrimary)
                    Spacer(minLength: 0)
                    Text(entry.score.formatted())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BrandTokens.textPrimary)
                    Text("\(entry.accuracyPercent)%")
                        .font(.caption)
                        .foregroundStyle(BrandTokens.textSecondary)
                    if entry.isFullCombo {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(BrandTokens.gold)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    index == 0 ? BrandTokens.accentPurple.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .festivalGlass(.card, cornerRadius: 12)
                .firstRunStagger(index)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - playerhistory-sort

/// Ported from `pages/leaderboard/player/firstRun/demo/SortControlsDemo.tsx`: the sort-mode list
/// (Date/Score/Accuracy/Season) plus the ascending/descending direction row, mirroring the
/// Songs sort demo's established layout for consistency (`FirstRunSortDemo`).
struct FirstRunPlayerHistorySortDemo: View {
    private let modes = ["Date", "Score", "Accuracy", "Season"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sort By").font(.caption.weight(.semibold))
                .foregroundStyle(BrandTokens.textSecondary)
            ForEach(modes, id: \.self) { mode in
                HStack {
                    Image(systemName: mode == "Score" ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(mode == "Score" ? BrandTokens.accentBlue : BrandTokens.textMuted)
                    Text(mode).foregroundStyle(BrandTokens.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Image(systemName: "arrow.down").foregroundStyle(BrandTokens.accentBlue)
                Text("Descending").foregroundStyle(BrandTokens.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up").foregroundStyle(BrandTokens.textMuted)
                Text("Ascending").foregroundStyle(BrandTokens.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}
