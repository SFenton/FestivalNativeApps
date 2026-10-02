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
                guard !reduceMotion, !DebugAnimationOverride.stillBackground else { return }
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

/// A per-row fade/rise-in on the web's cascading `FadeIn` timing (`fadeInUp`: 400 ms ease-out
/// from 12 pt below, 125 ms apart). Skipped under Reduce Motion so rows simply appear —
/// matching the spec's "no stagger… when Reduce Motion is on."
private struct FirstRunStagger: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : FirstRunDemoTiming.entranceRise)
            .onAppear {
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(
                    .easeOut(duration: FirstRunDemoTiming.fadeSeconds)
                        .delay(Double(index) * FirstRunDemoTiming.staggerSeconds)
                ) {
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

/// A leaderboard row drawn with the app's real Leaderboards row (`RankingRowLayout` on a
/// `RankingRowSurface` glass card, the selected player's purple accent), operator batch 7.
struct FirstRunRankRow: View {
    let entry: FirstRunDemoPool.RankingEntry

    var body: some View {
        RankingRowLayout(
            rank: entry.rank, name: entry.name, songs: entry.songs,
            spokenSongs: "\(entry.songs) songs", rating: entry.rating, bayesian: nil,
            emphasized: entry.isPlayer
        )
        .modifier(RankingRowSurface(isSelected: entry.isPlayer))
    }
}

/// A rival row (direction dot, name, ahead/behind pills, shared count), echoing
/// `RivalRowContent`'s layout without depending on a live `RivalRowDisplayable`.
struct FirstRunRivalRow: View {
    enum Direction { case above, below }

    let rival: FirstRunDemoPool.RivalEntry
    let direction: Direction

    var body: some View {
        // The app's real rival row (`RivalRowContent`) on a glass card (operator batch 7).
        RivalRowContent(rival: rival, direction: direction == .above ? .above : .below)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .festivalGlass(.card, cornerRadius: 12)
    }
}

/// A pulsing "View all…" call-to-action row, echoing the web's `pulseWrap` button.
struct FirstRunViewAllRow: View {
    let title: String

    var body: some View {
        // The app's purple "View all" button surface, pulsing as the web demo's
        // call-to-action does.
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .modifier(FirstRunPurpleButtonSurface())
            .firstRunPulse(BrandTokens.accentPurple)
    }
}

/// Same surface as the Leaderboards / Song Detail "View all" buttons (their
/// `PurpleGlassButtonSurface` is file-private in each screen): accent-purple interactive
/// glass on 26, solid purple under Reduce Transparency or the app's contrast overrides.
struct FirstRunPurpleButtonSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.accentPurple, in: shape)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(BrandTokens.accentPurple).interactive(), in: shape)
        } else {
            content
                .background(BrandTokens.accentPurple.opacity(0.85), in: shape)
                .overlay(shape.stroke(BrandTokens.glassBorder, lineWidth: 1))
        }
    }
}

/// The Leaderboards/Song Detail instrument header: 36 pt icon and a bold title outside the
/// card (web `InstrumentHeader` MD), as the real pages draw it.
struct FirstRunInstrumentHeader: View {
    let instrument: Instrument

    var body: some View {
        HStack(spacing: 10) {
            InstrumentIcon(instrument, size: 36)
            Text(instrument.label)
                .font(.title3.weight(.bold))
                .foregroundStyle(FestivalText.primary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
    }
}

/// A demo song's album art through the app's shared bounded artwork cache, or a muted tile
/// for a placeholder song or when no session can load art (hosted tests).
struct FirstRunSongArt: View {
    let song: Song
    let session: FestivalSession?
    var size: CGFloat = 44

    var body: some View {
        if let session, !song.isFirstRunPlaceholder {
            ArtworkTile(raw: song.albumArt, session: session, size: size)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BrandTokens.surfaceMuted)
                .frame(width: size, height: size)
        }
    }
}

extension View {
    /// Redact this song text while `song` is a loading/unavailable placeholder, so demos show
    /// the system placeholder treatment instead of invented titles.
    ///
    /// - Parameter song: The song the text describes.
    /// - Returns: The view, redacted with `.placeholder` for a placeholder song.
    func firstRunRedacted(_ song: Song) -> some View {
        redacted(reason: song.isFirstRunPlaceholder ? .placeholder : [])
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
