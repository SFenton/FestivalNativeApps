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
            .foregroundStyle(FestivalText.primary)
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
                            .foregroundStyle(FestivalText.primary)
                            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
                    case let .success(tint):
                        let fullCombo = entry.isFullCombo == true
                        let percent = "\(ScoreFormatting.accuracy(value))%"
                        let spoken = fullCombo
                            ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
                        accuracyBadge(
                            text: dynamicTypeSize.isAccessibilitySize ? spoken : percent,
                            spoken: spoken,
                            fill: fullCombo ? Color.clear
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
                        fill: Color.clear, fullCombo: true
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
    /// A full combo uses the web's gold treatment (`goldOutlineSkew`): gold bold italic
    /// text in a transparent pill with a 2pt gold outline, skewed -8°; the percentage
    /// alone is shown, since the colour already means FC. Graded accuracy keeps white
    /// text on its 25%-opaque tint.
    ///
    /// - Parameters:
    ///   - text: Visible percentage (or "FC" when a full combo has no accuracy).
    ///   - spoken: Expanded VoiceOver label that never infers a missing FC flag.
    ///   - fill: Clear for an FC, or graded 25%-opaque accuracy color otherwise.
    ///   - fullCombo: Whether to use the source's gold full-combo outline.
    /// - Returns: One scalable, accessible score-accuracy pill.
    private func accuracyBadge(
        text: String, spoken: String, fill: Color, fullCombo: Bool
    ) -> some View {
        let compact = !dynamicTypeSize.isAccessibilitySize
        // Only the outline is skewed, and it is drawn inside the badge's frame, so the
        // accessibility frame stays the shared column slot (XCUITest column checks).
        let shape = GoldSkewBadgeShape(skewed: fullCombo && compact)
        let width: CGFloat? = compact ? accuracyTextWidth + 16 : nil
        let height: CGFloat? = compact ? accuracyPillHeight : nil
        return ZStack {
            // A `Color.clear` fill is dropped from rendering, which left the inset gold
            // stroke as the only drawn path and shrank the reported accessibility frame
            // by 1pt a side (94pt vs the 96pt column). A near-invisible fill keeps the
            // full slot drawn without changing the web's transparent look.
            shape.fill(fullCombo ? Color.black.opacity(0.001) : fill)
            if fullCombo {
                shape.strokeBorder(BrandTokens.gold, lineWidth: 2)
            }
            Text(text)
                .font(fullCombo ? .body.bold().italic() : .body)
                .foregroundStyle(fullCombo ? BrandTokens.gold : FestivalText.primary)
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: !compact)
                .padding(compact ? 0 : 4)
        }
        .frame(width: width, height: height)
        // One element for the whole slot: its frame is exactly the fixed column (a
        // shape or a short "FC" text inside must never define the reported frame).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
    }

    /// The web's `GOLD_SKEW` (`skewX(-8deg)`) about the badge's vertical centre.
    ///
    /// - Parameter height: Rendered pill height, so the skew pivots on its middle.
    /// - Returns: Affine shear leaning the top edge right, like CSS `skewX(-8deg)`.
    nonisolated static func goldSkew(height: CGFloat) -> CGAffineTransform {
        let shear = tan(8 * CGFloat.pi / 180)
        return CGAffineTransform(a: 1, b: 0, c: -shear, d: 1, tx: shear * height / 2, ty: 0)
    }
}

/// Rounded badge outline, optionally sheared like the web's `GOLD_SKEW`, whose sheared
/// path still fits inside the proposed rect (it is inset horizontally before shearing).
struct GoldSkewBadgeShape: InsettableShape {
    /// Apply the -8° shear.
    var skewed: Bool
    /// Inset applied by `strokeBorder`.
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, 8 - insetAmount)
        guard skewed, box.width > 0, box.height > 0 else {
            return RoundedRectangle(cornerRadius: radius).path(in: box)
        }
        let shift = tan(8 * CGFloat.pi / 180) * box.height / 2
        let local = CGRect(
            x: shift, y: 0, width: max(0, box.width - 2 * shift), height: box.height
        )
        let transform = SongLeaderboardEntryRow.goldSkew(height: box.height)
            .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY))
        return RoundedRectangle(cornerRadius: radius).path(in: local).applying(transform)
    }

    func inset(by amount: CGFloat) -> GoldSkewBadgeShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
