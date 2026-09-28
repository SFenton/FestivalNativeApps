import SwiftUI
import FestivalCore
import FestivalDesign
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Reduce-motion aware pulse

/// A soft looping glow, standing in for the web's `shopBreathe*`/`pulseWrap` CSS animations.
/// Skipped entirely under Reduce Motion, matching the requirement that demos have "lightweight
/// looping animations only where the web animates" and none while Reduce Motion is on.
///
/// Implemented as a single `repeatForever` SwiftUI animation (no `Timer`/Combine subscription),
/// so it costs nothing while a slide is off-screen in the carousel.
private struct FirstRunPulse: ViewModifier {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .shadow(color: tint.opacity(lit ? 0.55 : 0.12), radius: lit ? 10 : 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}

extension View {
    /// Apply a looping glow pulse in `tint`; a no-op under Reduce Motion.
    func firstRunPulse(_ tint: Color) -> some View { modifier(FirstRunPulse(tint: tint)) }
}

// MARK: - Reduce-motion aware stagger

/// A brief per-row fade/rise-in, standing in for the web's cascading `FadeIn` stagger. Skipped
/// under Reduce Motion so rows simply appear — matching the spec's "no stagger… when Reduce
/// Motion is on."
private struct FirstRunStagger: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.easeOut(duration: 0.28).delay(Double(index) * 0.05)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Stagger this row's entrance by `index`; appears immediately under Reduce Motion.
    func firstRunStagger(_ index: Int) -> some View { modifier(FirstRunStagger(index: index)) }
}

// MARK: - Shared row styles

/// A flat leaderboard row (rank, name, rating), echoing `AccountRankingRow`'s layout without
/// depending on a live `AccountRankingEntry`.
struct FirstRunRankRow: View {
    let entry: FirstRunDemoPool.RankingEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(BrandTokens.textSecondary)
                .frame(minWidth: 32, alignment: .trailing)
            Text(entry.name)
                .font(.body.weight(entry.isPlayer ? .semibold : .regular))
                .foregroundStyle(BrandTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(entry.rating)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BrandTokens.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            entry.isPlayer ? BrandTokens.accentPurple.opacity(0.22) : .clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if entry.isPlayer {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BrandTokens.accentPurple.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

/// A rival row (direction dot, name, ahead/behind pills, shared count), echoing
/// `RivalRowContent`'s layout without depending on a live `RivalRowDisplayable`.
struct FirstRunRivalRow: View {
    enum Direction { case above, below }

    let rival: FirstRunDemoPool.RivalEntry
    let direction: Direction

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(direction == .below ? BrandTokens.statusGreen : BrandTokens.statusRed)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(rival.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    pill("\(rival.ahead) ahead", BrandTokens.statusGreen)
                    pill("\(rival.behind) behind", BrandTokens.statusRed)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(rival.shared)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                Text("shared")
                    .font(.caption2)
                    .foregroundStyle(BrandTokens.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .festivalGlass(.card, cornerRadius: 12)
    }

    private func pill(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

/// A pulsing "View all…" call-to-action row, echoing the web's `pulseWrap` button.
struct FirstRunViewAllRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BrandTokens.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .festivalGlass(.card, cornerRadius: 12)
            .firstRunPulse(BrandTokens.accentBlue)
    }
}

/// A small instrument header (icon + label), standing in for the web's `InstrumentHeader`.
struct FirstRunInstrumentHeader: View {
    let instrument: Instrument

    var body: some View {
        HStack(spacing: 8) {
            InstrumentIcon(instrument, size: 22)
            Text(instrument.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTokens.textPrimary)
        }
    }
}

/// A stand-in album art tile — demos never load network artwork.
struct FirstRunAlbumArtPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandTokens.surfaceMuted)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(BrandTokens.textSecondary)
            )
            .frame(width: 44, height: 44)
    }
}

/// Accuracy-to-color ramp approximating the web's `accuracyColor` gradient: red at the low end,
/// through blue, to green near 100%; full combo always reads gold.
///
/// - Parameters:
///   - accuracy: Percent accuracy, 0...100.
///   - isFullCombo: Whether this score was a full combo.
/// - Returns: The tint this score's bar/badge should use.
func firstRunAccuracyTint(_ accuracy: Double, isFullCombo: Bool) -> Color {
    if isFullCombo && accuracy >= 100 { return BrandTokens.gold }
    let t = max(0, min(1, accuracy / 100))
    if t < 0.5 {
        return BrandTokens.statusRed.mix(with: BrandTokens.accentBlue, by: t * 2)
    }
    return BrandTokens.accentBlue.mix(with: BrandTokens.statusGreen, by: (t - 0.5) * 2)
}

extension Color {
    /// Linear-blend two colors in sRGB — enough fidelity for a decorative demo gradient.
    fileprivate func mix(with other: Color, by amount: Double) -> Color {
        let a = amount.clamped(to: 0...1)
        let lhs = self.resolvedComponents
        let rhs = other.resolvedComponents
        return Color(
            .sRGB,
            red: lhs.r + (rhs.r - lhs.r) * a,
            green: lhs.g + (rhs.g - lhs.g) * a,
            blue: lhs.b + (rhs.b - lhs.b) * a,
            opacity: lhs.a + (rhs.a - lhs.a) * a
        )
    }

    private var resolvedComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(color.redComponent), Double(color.greenComponent),
                Double(color.blueComponent), Double(color.alphaComponent))
        #else
        return (0.5, 0.5, 0.5, 1)
        #endif
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
