import SwiftUI
import FestivalCore
import FestivalDesign
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Reduce-motion aware pulse

/// The outline a demo's pulse follows (the shape of the surface it decorates).
enum FirstRunGlowShape: Equatable {
    /// A continuous rounded rectangle (cards, the purple "View all" surface, stat tiles).
    case roundedRect(cornerRadius: CGFloat)
    /// A capsule (pills and prominent buttons).
    case capsule

    /// The canonical pulse layer's shape for this outline: the web's 2 px pulse border.
    var pulseShape: ShopPulseShape {
        switch self {
        case let .roundedRect(cornerRadius):
            .roundedStroke(cornerRadius: cornerRadius, lineWidth: FirstRunPulse.lineWidth)
        case .capsule:
            .capsuleStroke(lineWidth: FirstRunPulse.lineWidth)
        }
    }
}

/// The web demos' call-to-action pulse (`anim.pulseWrap`, `shopHighlight*`,
/// `styles/animations.module.css`): a 2 pt border in `tint` whose opacity eases
/// 0 → 0.7 → 0 every 2 s around the decorated surface (issue #380).
///
/// It is the app's own Item Shop row pulse (``ShopRowPulseBorder``, the shared
/// ``ShopPulseLayer`` on ``ShopPulseClock``), so the render server plays it with no app
/// work per frame. It loops only on the slide on screen in a visible, active window
/// (`firstRunSlideActive`, issue #28). Reduce Motion (system or the app's), another slide
/// or the UI-test still override hold the border at the web's reduced-motion 0.7, like
/// `@media (prefers-reduced-motion)`.
struct FirstRunPulse: ViewModifier {
    let tint: Color
    let shape: FirstRunGlowShape
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.firstRunSlideActive) private var slideActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// Border width (web `border: 2px solid`).
    static let lineWidth: CGFloat = 2

    /// The slide is on screen in an active scene whose window can be seen.
    private var visible: Bool {
        slideActive && AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible)
    }

    func body(content: Content) -> some View {
        let running = FirstRunPulsePolicy.runs(
            slideActive: visible, reduceMotion: systemReduceMotion || appReduceMotion,
            stillBackground: DebugAnimationOverride.stillBackground
        )
        content.overlay {
            Group {
                if running {
                    ShopPulseLayer(
                        shape: shape.pulseShape, color: tint, period: ShopRowPulseBorder.period,
                        restingOpacity: ShopRowPulseBorder.peak, running: true
                    ) { ShopRowPulseBorder.opacity(at: $0, animating: true) }
                } else {
                    // Still: a plain SwiftUI stroke (captured by `ImageRenderer`).
                    still.opacity(ShopRowPulseBorder.peak)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var still: some View {
        switch shape {
        case let .roundedRect(cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tint, lineWidth: Self.lineWidth)
        case .capsule:
            Capsule().stroke(tint, lineWidth: Self.lineWidth)
        }
    }
}

/// When a first-run demo's looping pulse may run.
enum FirstRunPulsePolicy {
    /// Whether the pulse loops.
    ///
    /// - Parameters:
    ///   - slideActive: Whether the demo's slide is the one on screen.
    ///   - reduceMotion: System or app Reduce Motion.
    ///   - stillBackground: Debug override freezing decorative motion.
    /// - Returns: True only on the visible slide with motion allowed.
    static func runs(slideActive: Bool, reduceMotion: Bool, stillBackground: Bool) -> Bool {
        slideActive && !reduceMotion && !stillBackground
    }
}

extension EnvironmentValues {
    /// Whether the enclosing first-run slide is the page on screen. Neighbouring slides that
    /// the paged carousel keeps alive see false, so their looping demos stay idle and their
    /// entrance cascade replays when they come on screen. True outside a carousel (hosted
    /// tests, previews).
    @Entry var firstRunSlideActive: Bool = true
}

extension View {
    /// Pulse a 2 pt `tint` border around a surface of `shape` (the web's `pulseWrap`); a
    /// steady border under Reduce Motion.
    ///
    /// - Parameters:
    ///   - tint: Border colour.
    ///   - shape: The decorated surface's outline (a 12 pt card by default).
    /// - Returns: The view with its pulse.
    func firstRunPulse(_ tint: Color, shape: FirstRunGlowShape = .roundedRect(cornerRadius: 12)) -> some View {
        modifier(FirstRunPulse(tint: tint, shape: shape))
    }
}

// MARK: - Reduce-motion aware entrance

/// The web's `FadeIn` (`fadeInUp`: 400 ms ease-out from 12 pt below) after `delay`.
///
/// The web remounts a slide each time it becomes the visible page, so its cascade replays;
/// here the entrance plays whenever the slide becomes active and the content eases out
/// (web 200 ms ease-in) when it leaves. Reduce Motion (system or the app's) and the
/// UI-test still override show the content at rest with no motion (issue #380).
private struct FirstRunStagger: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.firstRunSlideActive) private var slideActive
    @State private var shown = false

    private var animates: Bool {
        FirstRunMotion.entranceAnimates(
            reduceMotion: systemReduceMotion || appReduceMotion,
            stillBackground: DebugAnimationOverride.stillBackground
        )
    }

    func body(content: Content) -> some View {
        let visible = shown || !animates
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : FirstRunDemoTiming.entranceRise)
            .onAppear { if slideActive { reveal() } }
            .onChange(of: slideActive) { _, active in
                if active {
                    reveal()
                } else if animates {
                    withAnimation(.easeIn(duration: FirstRunMotion.exitSeconds)) { shown = false }
                }
            }
    }

    private func reveal() {
        guard animates else {
            shown = true
            return
        }
        withAnimation(.easeOut(duration: FirstRunDemoTiming.fadeSeconds).delay(delay)) {
            shown = true
        }
    }
}

extension View {
    /// Cascade this row's entrance by `index` steps of `interval` (web `FadeIn
    /// delay={i * interval}`); at rest under Reduce Motion.
    ///
    /// - Parameters:
    ///   - index: Cascade position.
    ///   - interval: Seconds per step; the web's 125 ms `STAGGER_INTERVAL` by default.
    /// - Returns: The view with its entrance.
    func firstRunStagger(_ index: Int, interval: Double = FirstRunMotion.staggerSeconds) -> some View {
        modifier(FirstRunStagger(delay: Double(index) * interval))
    }

    /// Fade this view up after `delay` seconds each time its slide comes on screen (web
    /// `FadeIn delay`); at rest under Reduce Motion.
    ///
    /// - Parameter delay: Seconds after the slide becomes visible.
    /// - Returns: The view with its entrance.
    func firstRunFadeIn(delay: Double) -> some View {
        modifier(FirstRunStagger(delay: delay))
    }
}

// MARK: - Shared row styles

/// A leaderboard row drawn with the app's real Leaderboards row (`RankingRowLayout` on a
/// `RankingRowSurface`, the selected player's purple accent), operator batch 7: an entry of
/// a flush ``FestivalGlassSection`` like the real overview cards (#381), its own card
/// elsewhere.
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
    @Environment(\.festivalGroupedRow) private var grouped

    var body: some View {
        // The app's real rival row (`RivalRowContent`, operator batch 7): an entry of the
        // group card like the Rivals page (#381), or its own material card.
        let content = RivalRowContent(rival: rival, direction: direction == .above ? .above : .below)
        if grouped {
            content.modifier(FestivalRowPadding())
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .festivalCard(cornerRadius: 12)
        }
    }
}

/// A pulsing "View all…" call-to-action: the app's real purple button
/// (``PurpleActionLabel``, view-all-cta) inside the web's blue `pulseWrap` border. The demos
/// pass it as their group card's `action`, so it draws the real buttons' flat in-card
/// purple through the shared ``PurpleActionSurface`` (view-all-cta R1, #382).
struct FirstRunViewAllRow: View {
    let title: String

    var body: some View {
        PurpleActionLabel(title: title)
            .firstRunPulse(
                BrandTokens.accentBlue,
                shape: .roundedRect(cornerRadius: PurpleActionSurface.cornerRadius)
            )
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
