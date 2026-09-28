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

/// Circular fill that breathes between ``ShopStatusTone/base`` and the tone's colour,
/// with a soft glow in the same colour at the peak.
///
/// Driven by `TimelineView(.animation)` rather than a `repeatForever` state animation:
/// toolbar items are re-hosted by the navigation bar, which dropped the implicit
/// repeating animation and left a static fill (operator report). Reduce Motion (system
/// or the app's override), an inactive scene or `FST_DEBUG_STILL_BACKGROUND` (UI tests)
/// pause the timeline on a static tint at the tone's colour.
struct ShopStatusBreathe: ViewModifier {
    let tone: ShopStatusTone
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.scenePhase) private var scenePhase

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
            sceneActive: scenePhase == .active,
            still: DebugAnimationOverride.stillBackground
        )
        content.background {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
                let level = Self.intensity(
                    at: context.date.timeIntervalSinceReferenceDate, animating: running
                )
                ZStack {
                    Circle().fill(ShopStatusTone.base)
                    Circle().fill(tone.target).opacity(level)
                }
                .shadow(color: tone.target.opacity(0.7 * level), radius: 6 * level)
            }
        }
    }
}
