import Foundation
import SwiftUI
import FestivalDesign

// MARK: - Song row card

/// The Song row's card surface: a standard material tuned to look like the tinted
/// Liquid Glass card it replaced, at a fraction of the main-thread cost.
///
/// Every Songs row built while scrolling paid for a live `glassEffect` (glass
/// container resolution, shape metrics and material state per row): about 30% of a
/// row's main-thread build time on iPad and iPhone. HIG Materials: "Don't use Liquid
/// Glass in the content layer. Use standard materials for content-layer elements",
/// and a Song row is content. The card is `ultraThinMaterial` (one backdrop blur per
/// row, composited by the render server) under a flat tint and a 1 pt rim, all as
/// plain `background(_:in:)`/`overlay` modifiers: the same layers in a nested
/// `ViewBuilder` background cost nearly as much as the glass did. The tint and rim
/// per platform were fitted against captures of the old glass card over the same
/// backdrops (`.agents/design/apple/liquid-glass.md` § Song row card).
///
/// Accessibility overrides are unchanged from ``FestivalGlassRole/card``: system
/// Reduce Transparency and the in-app Reduce Transparency and Increase Contrast
/// toggles draw the opaque `cardBackground` + `borderSubtle` card. Before iOS/macOS
/// 26 the row keeps the frosted fallback every glass card uses.
struct FestivalRowCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    /// Draw the opaque, material or frosted card behind the row content.
    ///
    /// - Parameter content: Row content, already padded.
    /// - Returns: Content on the card surface, shaped as a continuous rounded rectangle.
    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if RowCardComparison.enabled && RowCardComparison.shared.showsGlass {
            content.festivalGlass(.card, cornerRadius: cornerRadius)
        } else {
            surface(content)
        }
        #else
        surface(content)
        #endif
    }

    /// The shipping surface for the current accessibility settings and OS.
    ///
    /// - Parameter content: Row content.
    /// - Returns: Content on the opaque, material or pre-26 frosted card.
    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.cardBackground, in: shape)
                .overlay(shape.stroke(BrandTokens.borderSubtle, lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(RowCardStyle.tint(increasedContrast: contrast == .increased), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(RowCardStyle.rim, lineWidth: 1))
        } else {
            content
                .background(BrandTokens.surfaceFrosted, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(BrandTokens.glassBorder, lineWidth: 1))
        }
    }
}

// MARK: - Tuned colours

/// Tint and rim of the material row card, fitted per platform to the Liquid Glass
/// card (`Glass.regular.tint(cardBackground.opacity(0.35))`) it replaced.
enum RowCardStyle {
    #if os(macOS)
    /// macOS glass over the dimmed artwork reads lighter than its backdrop; a 17%
    /// neutral veil over the dark ultra-thin material matches its brightness. System
    /// Increase Contrast keeps it (not measured: the system setting stays untouched).
    private static let baseTint = Color(.sRGB, red: 138.0 / 255, green: 135.0 / 255, blue: 138.0 / 255, opacity: 0.17)
    private static let contrastTint = baseTint
    /// macOS glass shows almost no edge; a faint top highlight only.
    static let rim = LinearGradient(
        colors: [.white.opacity(0.06), .white.opacity(0)], startPoint: .top, endPoint: .bottom
    )
    #else
    /// iOS/iPadOS glass stays dark over the dimmed artwork; a 68% near-neutral navy
    /// over the dark ultra-thin material matches it (`cardBackground` reads too blue).
    /// Under system Increase Contrast the glass darkens by 6–8 levels; 88% matches it.
    private static let tintColor = Color(.sRGB, red: 15.0 / 255, green: 17.0 / 255, blue: 23.0 / 255)
    private static let baseTint = tintColor.opacity(0.68)
    private static let contrastTint = tintColor.opacity(0.88)
    /// iOS glass edge: a light top rim fading towards the bottom.
    static let rim = LinearGradient(
        colors: [.white.opacity(0.14), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom
    )
    #endif

    /// The tint layer above the material.
    ///
    /// - Parameter increasedContrast: System Increase Contrast is on.
    /// - Returns: The platform's fitted tint.
    static func tint(increasedContrast: Bool) -> Color {
        increasedContrast ? contrastTint : baseTint
    }
}

extension View {
    /// Render this view on the shared Song row card (Songs and the Item Shop list).
    ///
    /// - Parameter cornerRadius: Continuous corner radius of the card.
    /// - Returns: The decorated view.
    func festivalRowCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(FestivalRowCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Debug A/B

#if DEBUG
/// Debug-only A/B switch for tuning the row card against the Liquid Glass card
/// over an identical backdrop.
///
/// With `FST_DEBUG_ROW_CARD_AB=<path>`, rows draw the old glass card while that
/// file contains `glass` and the shipping card otherwise; the file is polled every
/// 0.3 s, so a capture script can flip it between two window captures
/// (`FST_DEBUG_STILL_BACKGROUND=1` keeps the backdrop still).
@MainActor @Observable
final class RowCardComparison {
    /// The switch file, when the override is set.
    nonisolated static let path = ProcessInfo.processInfo.environment["FST_DEBUG_ROW_CARD_AB"]
    /// Whether any comparison is active (rows never touch ``shared`` otherwise).
    nonisolated static let enabled = path != nil
    /// The process-wide switch.
    static let shared = RowCardComparison()
    /// Whether rows currently draw the Liquid Glass card.
    private(set) var showsGlass = false

    private init() {
        guard let path = Self.path else { return }
        Task { @MainActor in
            while !Task.isCancelled {
                let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                let glass = text.trimmingCharacters(in: .whitespacesAndNewlines) == "glass"
                if glass != showsGlass { showsGlass = glass }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
#endif
