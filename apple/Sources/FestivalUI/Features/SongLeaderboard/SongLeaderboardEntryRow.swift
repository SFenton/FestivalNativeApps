import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Scalable score row shared by the native preview and the paginated Solo chart.
struct SongLeaderboardEntryRow: View {
    let entry: LeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var accuracyTextWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var accuracyPillHeight: CGFloat = 24

    var body: some View {
        let rank = Text("#\(entry.rank.formatted())")
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(BrandTokens.textSecondary)
        let name = Text(
            entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
        )
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        let score = Text(entry.score.formatted())
            .font(.body)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let valuesLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                rank
                name.frame(maxWidth: .infinity, alignment: .leading)
            }
            valuesLayout {
                score
                if let value = entry.accuracy {
                    let color: Result<ScoreAccuracyTint, Error> = Result {
                        try ScoreFormatting.accuracyTint(value)
                    }
                    switch color {
                    case let .failure(error):
                        Text("Accuracy unavailable: \(error.localizedDescription)")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
                    case let .success(tint):
                        let fullCombo = entry.isFullCombo == true
                        let percent = "\(ScoreFormatting.accuracy(value))%"
                        let spoken = fullCombo
                            ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
                        accuracyBadge(
                            text: dynamicTypeSize.isAccessibilitySize
                                ? spoken : fullCombo ? "FC \(percent)" : percent,
                            spoken: spoken,
                            fill: fullCombo ? BrandTokens.cardBackground
                                : Color(
                                    .sRGB,
                                    red: Double(tint.red) / 255,
                                    green: Double(tint.green) / 255,
                                    blue: Double(tint.blue) / 255,
                                    opacity: 0.25
                                ),
                            fullCombo: fullCombo
                        )
                    }
                } else if entry.isFullCombo == true {
                    accuracyBadge(
                        text: dynamicTypeSize.isAccessibilitySize ? "Full combo" : "FC",
                        spoken: "Full combo; accuracy unavailable",
                        fill: BrandTokens.cardBackground, fullCombo: true
                    )
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Color.clear
                        .frame(
                            width: accuracyTextWidth + 16,
                            height: accuracyPillHeight
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }

    /// Keep the compact and large-text accuracy states legible and independently spoken.
    ///
    /// - Parameters:
    ///   - text: Visible percentage with a full-combo prefix only when explicitly true.
    ///   - spoken: Expanded VoiceOver label that never infers a missing FC flag.
    ///   - fill: Opaque card for an FC, or graded 25%-opaque accuracy color otherwise.
    ///   - fullCombo: Whether to add the source's gold full-combo outline.
    /// - Returns: One scalable, accessible score-accuracy pill.
    private func accuracyBadge(
        text: String, spoken: String, fill: Color, fullCombo: Bool
    ) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(BrandTokens.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyTextWidth + 16,
                height: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyPillHeight
            )
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if fullCombo {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BrandTokens.gold, lineWidth: 2)
                }
            }
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
    }
}
