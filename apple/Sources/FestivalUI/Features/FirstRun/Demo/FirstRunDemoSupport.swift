import QuartzCore
import SwiftUI
import FestivalCore
import FestivalDesign
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Reduce-motion aware pulse

/// The outline a demo's glow follows (the shape of the surface it decorates).
enum FirstRunGlowShape: Equatable {
    /// A continuous rounded rectangle (cards, the purple "View all" surface, stat tiles).
    case roundedRect(cornerRadius: CGFloat)
    /// A capsule (pills).
    case capsule

    /// The shadow outline for a surface of this size.
    ///
    /// - Parameter size: The surface's size.
    /// - Returns: The outline path in the surface's coordinates.
    func path(in size: CGSize) -> CGPath {
        let rect = CGRect(origin: .zero, size: size)
        let radius: CGFloat
        switch self {
        case let .roundedRect(cornerRadius): radius = min(cornerRadius, min(size.width, size.height) / 2)
        case .capsule: radius = min(size.width, size.height) / 2
        }
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
    }
}

/// A soft looping glow, standing in for the web's `shopBreathe*`/`pulseWrap` CSS animations.
/// Skipped entirely under Reduce Motion, matching the requirement that demos have "lightweight
/// looping animations only where the web animates" and none while Reduce Motion is on.
///
/// The loop runs on Core Animation (``FirstRunGlowLayer``: a shadow-only layer whose
/// opacity and blur breathe on the render server), so the app does no work per frame;
/// the former `repeatForever` SwiftUI shadow re-rendered the sheet every frame (about 14%
/// CPU with the sheet open, `.agents/platforms/apple/architecture.md` § Performance). It
/// runs only on the slide on screen in a visible, active window (`firstRunSlideActive`,
/// issue #28); elsewhere SwiftUI draws the dim resting glow, so `ImageRenderer` captures
/// keep it.
private struct FirstRunPulse: ViewModifier {
    let tint: Color
    let shape: FirstRunGlowShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.firstRunSlideActive) private var slideActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// The slide is on screen in an active scene whose window can be seen.
    private var visible: Bool {
        slideActive && AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible)
    }

    func body(content: Content) -> some View {
        let running = FirstRunPulsePolicy.runs(
            slideActive: visible, reduceMotion: reduceMotion,
            stillBackground: DebugAnimationOverride.stillBackground
        )
        if running {
            content.background { FirstRunGlowLayer(tint: tint, shape: shape) }
        } else {
            content.shadow(color: tint.opacity(FirstRunGlowLayer.restingOpacity), radius: FirstRunGlowLayer.restingRadius)
        }
    }
}

// MARK: - Glow layer

/// The breathing glow behind a demo surface, played by the render server: a shadow-only
/// `CALayer` (``FirstRunGlowShape`` outline as its `shadowPath`, no fill) whose shadow
/// opacity and radius ease between the resting and lit values, like the old SwiftUI
/// `.shadow(color: tint.opacity(lit ? 0.55 : 0.12), radius: lit ? 10 : 3)` loop.
struct FirstRunGlowLayer {
    let tint: Color
    let shape: FirstRunGlowShape

    /// Shadow opacity and radius at rest (and under Reduce Motion).
    static let restingOpacity = 0.12
    static let restingRadius: CGFloat = 3
    /// Shadow opacity and radius at the peak.
    static let litOpacity = 0.55
    static let litRadius: CGFloat = 10
    /// Seconds from rest to peak (the loop reverses, so one breath is twice this).
    static let halfPeriod = 1.1
}

#if os(iOS)
extension FirstRunGlowLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> FirstRunGlowView { FirstRunGlowView() }

    func updateUIView(_ view: FirstRunGlowView, context: Context) {
        view.apply(shape: shape, color: tint.resolve(in: context.environment).cgColor)
    }
}
#elseif os(macOS)
extension FirstRunGlowLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> FirstRunGlowView { FirstRunGlowView() }

    func updateNSView(_ view: FirstRunGlowView, context: Context) {
        view.apply(shape: shape, color: tint.resolve(in: context.environment).cgColor)
    }
}
#endif

/// Platform host of one glow: a single shadow layer, never clipped, never a hit-test or
/// accessibility target.
final class FirstRunGlowView: PlatformLayerHostView {
    private let glowLayer = CALayer()
    private var shape: FirstRunGlowShape = .capsule

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(iOS)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = false
        layer.addSublayer(glowLayer)
        #elseif os(macOS)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = false
        layer?.addSublayer(glowLayer)
        #endif
        glowLayer.shadowOffset = .zero
        glowLayer.shadowOpacity = Float(FirstRunGlowLayer.restingOpacity)
        glowLayer.shadowRadius = FirstRunGlowLayer.restingRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGlow()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animations are dropped while detached (paging re-hosts slides).
        if window != nil { startBreathing() }
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        layoutGlow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startBreathing() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Apply the outline and colour.
    ///
    /// - Parameters:
    ///   - shape: The surface outline.
    ///   - color: Resolved tint.
    func apply(shape: FirstRunGlowShape, color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.shadowColor = color
        if shape != self.shape {
            self.shape = shape
            layoutGlow()
        }
        CATransaction.commit()
    }

    private func layoutGlow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.frame = bounds
        glowLayer.shadowPath = shape.path(in: bounds.size)
        CATransaction.commit()
    }

    /// One repeating, autoreversing opacity + radius animation on the render server.
    private func startBreathing() {
        guard glowLayer.animation(forKey: "breathe") == nil else { return }
        let opacity = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue = FirstRunGlowLayer.restingOpacity
        opacity.toValue = FirstRunGlowLayer.litOpacity
        let radius = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue = FirstRunGlowLayer.restingRadius
        radius.toValue = FirstRunGlowLayer.litRadius
        // Children need the group's duration: a 0 duration means 0.25 s, after which
        // they would sit at the resting value for most of each breath.
        opacity.duration = FirstRunGlowLayer.halfPeriod
        radius.duration = FirstRunGlowLayer.halfPeriod
        let breathe = CAAnimationGroup()
        breathe.animations = [opacity, radius]
        breathe.duration = FirstRunGlowLayer.halfPeriod
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe.isRemovedOnCompletion = false
        breathe.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        glowLayer.add(breathe, forKey: "breathe")
    }
}

/// When a first-run demo's looping glow may run.
enum FirstRunPulsePolicy {
    /// Whether the pulse loops.
    ///
    /// - Parameters:
    ///   - slideActive: Whether the demo's slide is the one on screen.
    ///   - reduceMotion: System Reduce Motion.
    ///   - stillBackground: Debug override freezing decorative motion.
    /// - Returns: True only on the visible slide with motion allowed.
    static func runs(slideActive: Bool, reduceMotion: Bool, stillBackground: Bool) -> Bool {
        slideActive && !reduceMotion && !stillBackground
    }
}

extension EnvironmentValues {
    /// Whether the enclosing first-run slide is the page on screen. Neighbouring slides that
    /// the paged carousel keeps alive see false, so their looping demos stay idle. True
    /// outside a carousel (hosted tests, previews).
    @Entry var firstRunSlideActive: Bool = true
}

extension View {
    /// Apply a looping glow pulse in `tint` around a surface of `shape`; the dim resting
    /// glow only under Reduce Motion.
    ///
    /// - Parameters:
    ///   - tint: Glow colour.
    ///   - shape: The decorated surface's outline (a 12 pt card by default).
    /// - Returns: The view with its glow.
    func firstRunPulse(_ tint: Color, shape: FirstRunGlowShape = .roundedRect(cornerRadius: 12)) -> some View {
        modifier(FirstRunPulse(tint: tint, shape: shape))
    }
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
            .firstRunPulse(BrandTokens.accentPurple, shape: .roundedRect(cornerRadius: 12))
    }
}

/// Same surface as the Leaderboards / Song Detail "View all" buttons (their
/// `PurpleActionSurface`): the accent-purple material card on 26, solid purple under
/// Reduce Transparency or the app's contrast overrides.
struct FirstRunPurpleButtonSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.accentPurple, in: shape)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(PurpleActionSurface.tint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(RowCardStyle.rim, lineWidth: 1))
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
