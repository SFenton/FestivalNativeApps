import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Shop status tone

/// Item Shop status of one song, for the Song Detail shop action's breathing fill
/// (web `anim.shopBreathe` / `shopBreatheGold` / `shopBreatheRed`,
/// `FortniteFestivalWeb/src/styles/animations.module.css:104-132,197-208`).
enum ShopStatusTone: Equatable, Sendable {
    /// In the shop (green).
    case inShop
    /// New in the shop (gold).
    case new
    /// Leaving the shop tomorrow (red).
    case leaving

    /// The web's resting fill, `rgb(18 24 38 / 96%)`.
    static let base = Color(.sRGB, red: 18 / 255, green: 24 / 255, blue: 38 / 255, opacity: 0.96)
    /// One full breathe cycle (web: `3s ease-in-out infinite`).
    static let period: Double = 3
    /// Highest opacity of the status colour over the base (no bloom on EDR displays).
    static let peakOpacity: Double = 0.8

    /// Resolve the tone the web would pulse with (`useShopState.isShopHighlighted`).
    ///
    /// - Parameters:
    ///   - offer: Validated current Shop row for this song, if any.
    ///   - hidden: Hide Item Shop setting.
    ///   - highlightingDisabled: Disable Shop highlighting setting.
    /// - Returns: Leaving, then New, then In Shop; nil when not in the shop or when
    ///   highlighting is hidden/disabled (the action then stays a plain button).
    static func tone(
        for offer: ShopSong?, hidden: Bool, highlightingDisabled: Bool
    ) -> ShopStatusTone? {
        guard let offer, !hidden, !highlightingDisabled else { return nil }
        switch ShopPresentationPolicy.highlight(
            for: offer, hidden: false, highlightingDisabled: false
        ) {
        case .leavingTomorrow: return .leaving
        case .new: return .new
        case nil: return .inShop
        }
    }

    /// Peak fill: `--color-status-green-stroke` #1E7F46, `--color-gold-stroke` #CFA500,
    /// `--color-leaving-red` #EF4444 (no brand token for the last yet).
    var target: Color {
        switch self {
        case .inShop: BrandTokens.statusGreenStroke
        case .new: BrandTokens.goldStroke
        case .leaving: Color(.sRGB, red: 239 / 255, green: 68 / 255, blue: 68 / 255, opacity: 1)
        }
    }

    /// Status appended to the action's spoken label; colour is never the only cue.
    var spokenStatus: String {
        switch self {
        case .inShop: "In the Item Shop"
        case .new: "New in the Item Shop"
        case .leaving: "Leaving the Item Shop tomorrow"
        }
    }
}

// MARK: - Breathing fill

/// Circular fill that breathes between ``ShopStatusTone/base`` and the tone's colour
/// (capped at ``ShopStatusTone/peakOpacity``), without a glow.
///
/// Driven by a Core Animation layer on the shared ``ShopPulseClock`` rather than a
/// `repeatForever` state animation (toolbar items are re-hosted by the navigation
/// bar, which dropped the implicit repeating animation and left a static fill,
/// operator report; the layer re-joins the clock whenever it re-enters a window) or
/// a per-view `TimelineView` (a SwiftUI update every frame). Reduce Motion (system
/// or the app's override), an inactive scene or `FST_DEBUG_STILL_BACKGROUND` (UI tests)
/// hold a static tint at the tone's colour.
struct ShopStatusBreathe: ViewModifier {
    let tone: ShopStatusTone
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// Whether the breathe should run in the current environment.
    ///
    /// - Parameters:
    ///   - reduceMotion: System or app Reduce Motion.
    ///   - sceneActive: Whether the scene is active.
    ///   - still: The UI-test still-animation override.
    /// - Returns: True when the fill should animate.
    static func animates(reduceMotion: Bool, sceneActive: Bool, still: Bool) -> Bool {
        !reduceMotion && sceneActive && !still
    }

    /// Breathe intensity (0 = resting base, 1 = full status colour) at a time.
    ///
    /// A raised cosine over ``ShopStatusTone/period``: 0 at the cycle start, 1 at the
    /// half-period, easing in and out like the web's `ease-in-out` keyframes.
    ///
    /// - Parameters:
    ///   - time: Seconds since any fixed reference.
    ///   - animating: False returns the static tint (1).
    /// - Returns: Intensity in 0...1.
    static func intensity(at time: TimeInterval, animating: Bool) -> Double {
        guard animating else { return 1 }
        let phase = time.truncatingRemainder(dividingBy: ShopStatusTone.period)
            / ShopStatusTone.period
        return (1 - cos(2 * .pi * phase)) / 2
    }

    func body(content: Content) -> some View {
        let running = Self.animates(
            reduceMotion: systemReduceMotion || appReduceMotion,
            sceneActive: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
            still: DebugAnimationOverride.stillBackground
        )
        // The web only cross-fades the fill; the former glow read as an overblown
        // HDR bloom (operator batch 7), so there is none, and the peak is capped
        // below the full status colour. The breathing layer plays on the render
        // server from the shared ``ShopPulseClock``.
        // Still: plain SwiftUI shapes (captured by `ImageRenderer`, unlike a layer).
        content.background {
            ZStack {
                Circle().fill(ShopStatusTone.base)
                if running {
                    ShopPulseLayer(
                        shape: .disc, color: tone.target, period: ShopStatusTone.period,
                        restingOpacity: ShopStatusTone.peakOpacity, running: true
                    ) { Self.intensity(at: $0, animating: true) * ShopStatusTone.peakOpacity }
                } else {
                    Circle().fill(tone.target).opacity(ShopStatusTone.peakOpacity)
                }
            }
        }
    }
}

// MARK: - Row border pulse

extension ShopStatusTone {
    /// Tone for a Songs row already known to be in the Shop.
    ///
    /// - Parameter highlight: New / Leaving Tomorrow, or nil for a plain offer.
    init(highlight: ShopHighlight?) {
        switch highlight {
        case .leavingTomorrow: self = .leaving
        case .new: self = .new
        case nil: self = .inShop
        }
    }

    /// Border colour of the web's row pulse (`shopPulse*`: #2ECC71, gold, red).
    var borderColor: Color {
        switch self {
        case .inShop: BrandTokens.diffPillEasy
        case .new: BrandTokens.gold
        case .leaving: Color(.sRGB, red: 239 / 255, green: 68 / 255, blue: 68 / 255, opacity: 1)
        }
    }
}

/// The web's `shopPulse` row border: 2pt, opacity 0 → 0.7 → 0 over 2 s (ease-in-out).
/// Reduce Motion, an inactive scene or the UI-test still override hold it at 0.7.
///
/// Every row follows the one shared ``ShopPulseClock`` on the render server, so a
/// screen of Shop rows costs no app work per frame (each row formerly ran its own
/// 30 fps `TimelineView`).
struct ShopRowPulseBorder: View {
    let tone: ShopStatusTone
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// Web keyframe peak.
    static let peak: Double = 0.7
    /// Web cycle length.
    static let period: Double = 2

    /// Border opacity at a time.
    ///
    /// - Parameters:
    ///   - time: Seconds since any fixed reference.
    ///   - animating: False holds the peak.
    /// - Returns: 0…``peak``.
    static func opacity(at time: TimeInterval, animating: Bool) -> Double {
        guard animating else { return peak }
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return peak * (1 - cos(2 * .pi * phase)) / 2
    }

    var body: some View {
        let running = ShopStatusBreathe.animates(
            reduceMotion: systemReduceMotion || appReduceMotion,
            sceneActive: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
            still: DebugAnimationOverride.stillBackground
        )
        Group {
            if running {
                ShopPulseLayer(
                    shape: .roundedStroke(cornerRadius: cornerRadius, lineWidth: 2),
                    color: tone.borderColor, period: Self.period, restingOpacity: Self.peak,
                    running: true
                ) { Self.opacity(at: $0, animating: true) }
            } else {
                // Still: a plain SwiftUI stroke (captured by `ImageRenderer`).
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tone.borderColor, lineWidth: 2)
                    .opacity(Self.peak)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
