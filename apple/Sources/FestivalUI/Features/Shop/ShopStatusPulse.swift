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

/// Circular fill that breathes between ``ShopStatusTone/base`` and the tone's colour.
///
/// Reduce Motion, an inactive scene or `FST_DEBUG_STILL_BACKGROUND` (UI tests) show
/// a static tint at the tone's colour instead, so nothing animates off-screen or
/// blocks XCUITest's idle wait.
struct ShopStatusBreathe: ViewModifier {
    let tone: ShopStatusTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lit = false

    private var animates: Bool {
        !reduceMotion && scenePhase == .active && !DebugAnimationOverride.stillBackground
    }

    func body(content: Content) -> some View {
        content
            .background(
                Circle().fill(animates ? (lit ? tone.target : ShopStatusTone.base) : tone.target)
            )
            .onAppear { restart() }
            .onChange(of: animates) { _, _ in restart() }
            .onChange(of: tone) { _, _ in restart() }
    }

    /// Start (or stop) the repeating breathe from the resting colour.
    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { lit = false }
        guard animates else { return }
        withAnimation(
            .easeInOut(duration: ShopStatusTone.period / 2).repeatForever(autoreverses: true)
        ) {
            lit = true
        }
    }
}
