import SwiftUI
import FestivalDesign
#if os(iOS)
import UIKit
#endif

// MARK: - Top edge legibility

/// Keeps content under the navigation bar readable over bright artwork (operator,
/// 2026-09-28): iOS 26's soft top scroll-edge effect plus a subtle dark gradient behind
/// the bar region. Earlier iOS gets the gradient over the system bar material.
/// `.agents/design/apple/nav-accessories.md`, `liquid-glass.md`.
struct TopEdgeScrim: ViewModifier {
    /// Covers the status bar, a collapsed bar and a little of the content below.
    static let height: CGFloat = 150

    func body(content: Content) -> some View {
        content
            .modifier(SoftTopScrollEdge())
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: Self.height)
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
