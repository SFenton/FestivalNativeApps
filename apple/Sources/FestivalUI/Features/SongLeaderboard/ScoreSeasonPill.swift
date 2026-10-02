import SwiftUI
import FestivalDesign

// MARK: - ScoreSeasonPill

/// The season a score was achieved in, as a compact pill before the score (web
/// `SeasonPill`, `components/songs/metadata/SeasonPill.tsx`): "S9" in secondary text on
/// a subtle chip with a 2 pt subtle border; the current season inverts its colours.
/// At accessibility text sizes it drops the fixed frame and spells out "Season 9" so
/// it wraps instead of clipping (HIG Layout: accommodate Dynamic Type).
///
/// Rows decide whether to show it with `ScoreRowSeasonPolicy` (issue #32).
struct ScoreSeasonPill: View {
    /// Season number; nil draws an invisible placeholder that keeps the score column
    /// aligned with rows that have one (web hidden `SeasonPill`).
    let season: Int?
    /// Whether `season` is the catalogue's current season.
    var current = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var pillWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var pillHeight: CGFloat = 24

    var body: some View {
        if let season {
            let compact = !dynamicTypeSize.isAccessibilitySize
            let shape = RoundedRectangle(cornerRadius: 6)
            Text(compact ? "S\(season)" : "Season \(season)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(current ? BrandTokens.surfaceSubtle : BrandTokens.textSecondary)
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: !compact)
                .padding(compact ? 0 : 4)
                .frame(width: compact ? pillWidth : nil, height: compact ? pillHeight : nil)
                .background(current ? BrandTokens.textSecondary : BrandTokens.surfaceSubtle, in: shape)
                .overlay(shape.stroke(current ? BrandTokens.surfaceSubtle : BrandTokens.borderSubtle, lineWidth: 2))
                .accessibilityLabel(Self.spokenLabel(season: season, current: current))
        } else if !dynamicTypeSize.isAccessibilitySize {
            Color.clear
                .frame(width: pillWidth, height: pillHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// VoiceOver text for a season pill.
    ///
    /// - Parameters:
    ///   - season: Season number.
    ///   - current: Whether it is the current season.
    /// - Returns: "Season 9" or "Current season 9".
    static func spokenLabel(season: Int, current: Bool) -> String {
        current ? "Current season \(season)" : "Season \(season)"
    }
}
