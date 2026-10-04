import SwiftUI
import FestivalCore
import FestivalDesign
#if os(iOS)
import UIKit
#endif

// MARK: - Top edge legibility

/// Keeps content under the navigation bar readable over bright artwork (operator,
/// 2026-09-28): iOS 26's soft top scroll-edge effect plus a subtle dark gradient behind
/// the bar region. Earlier iOS gets the gradient over the system bar material.
/// `.agents/design/apple/nav-accessories.md`, `liquid-glass.md`.
///
/// The gradient ends no lower than a Quick Links jump's landing line, 32 pt below the
/// bar (issue #286). A fixed 150 pt suits an iPhone's 116 pt status bar and collapsed
/// bar, but under a shorter bar (iPad, iPhone landscape, iPhone Duo) it reached past
/// that line and dimmed the section a jump had just shown. HIG Layout: "Respect [the
/// safe area] so system UI and hardware do not cover controls/content."
struct TopEdgeScrim: ViewModifier {
    /// The tallest the scrim gets: the status bar, a collapsed iPhone bar and a little
    /// of the content below.
    static let maxHeight: CGFloat = 150

    /// The page's top safe-area inset (status bar plus navigation bar), once measured.
    @State private var topInset: CGFloat?

    /// The scrim's height for a page's top safe-area inset.
    ///
    /// - Parameter topInset: Status bar plus navigation bar, in points; `nil` or 0 while
    ///   unmeasured or where the page reports none.
    /// - Returns: ``maxHeight``, or less when the bar ends higher, so the gradient stops
    ///   by the Quick Links landing line (`QuickLinks.defaultActivationOffset`).
    static func height(topInset: CGFloat?) -> CGFloat {
        guard let topInset, topInset.isFinite, topInset > 0 else { return maxHeight }
        return min(maxHeight, topInset + CGFloat(QuickLinks.defaultActivationOffset))
    }

    func body(content: Content) -> some View {
        content
            .modifier(SoftTopScrollEdge())
            .onGeometryChange(for: CGFloat.self) { proxy in
                // Whole points: a collapsing large title moves the inset every frame.
                proxy.safeAreaInsets.top.rounded()
            } action: { inset in
                topInset = inset
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: Self.height(topInset: topInset))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

/// `scrollEdgeEffectStyle(.soft, for: .top)` where available.
private struct SoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Inline title size

/// Navigation bar title styling applied once at launch.
enum NavigationTitleStyle {
    /// Make the collapsed inline title 20 pt semibold (Dynamic Type scaled) so it holds
    /// its own beside the glass toolbar buttons (operator, 2026-09-28).
    @MainActor static func apply() {
        #if os(iOS)
        let font = UIFontMetrics(forTextStyle: .title3)
            .scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
        UINavigationBar.appearance().titleTextAttributes = [.font: font]
        #endif
    }
}
