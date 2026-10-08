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
///
/// The gradient spans the full width under horizontal safe areas too (``extendedEdges``):
/// the iPhone Duo vertical bar is a leading or trailing inset, and a scrim that stopped
/// there left the art under the bar brighter than the page beside it (issue #335). HIG
/// Layout: "Extend full-screen backgrounds beneath sidebars, toolbars, and tab bars to
/// window/screen edges."
struct TopEdgeScrim: ViewModifier {
    /// The tallest the scrim gets: the status bar, a collapsed iPhone bar and a little
    /// of the content below.
    static let maxHeight: CGFloat = 150

    /// Safe-area edges the gradient extends under: the top (status bar and navigation
    /// bar) and both horizontal edges (the iPhone Duo vertical bar), like the backdrop
    /// beneath it. A split pane already ignores the safe area facing its divider, so
    /// the divider band's own gradient (`SplitDivider`) never doubles it.
    static let extendedEdges: Edge.Set = [.top, .horizontal]

    /// The page's top safe-area inset (status bar plus navigation bar), once measured.
    @State private var topInset: CGFloat?
    /// The split pane this page is in, if any.
    @Environment(\.splitPane) private var pane
    /// The split's shared height: the leading page writes it, the trailing pane reads it.
    @Environment(\.splitTopScrim) private var sharedScrim

    /// The black-to-clear gradient (also drawn across a split's divider band).
    static let gradient = LinearGradient(
        colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
        startPoint: .top, endPoint: .bottom
    )

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
                if pane == .leading, let sharedScrim {
                    let height = Self.height(topInset: inset)
                    if sharedScrim.height != height { sharedScrim.height = height }
                }
            }
            .overlay(alignment: .top) {
                Self.gradient
                .frame(height: SplitPaneChrome.topScrimHeight(
                    pane: pane, own: Self.height(topInset: topInset), leading: sharedScrim?.height
                ))
                .ignoresSafeArea(edges: Self.extendedEdges)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

/// The system top scroll-edge style a page asks for (`.agents/patterns/scroll-edge.md`
/// R6, R7).
enum PageTopScrollEdge: Equatable {
    /// The soft variable blur (R6's approved variant).
    case soft
    /// The hard style: an opaque edge, so nothing reads through behind the bar.
    case hard

    /// The style for the merged accessibility settings.
    ///
    /// System Reduce Transparency and Increase Contrast already make the system edge
    /// opaque, but the app's own Less Transparency and Increase Contrast do not reach
    /// the system, so with only those on a soft edge still showed rows behind the
    /// title (#393). HIG Scroll views: a hard style is an "opaque blur, defined edge".
    ///
    /// - Parameter hardEdge: `ScrollEdgeHardEdge`'s decision.
    /// - Returns: ``hard`` when the page's edge must not show content, else ``soft``.
    static func resolve(hardEdge: Bool) -> PageTopScrollEdge {
        hardEdge ? .hard : .soft
    }
}

/// The top-edge style a page header resolved, published for hosted tests that check
/// the real modifier rather than a copy of its decision.
struct PageTopScrollEdgeKey: PreferenceKey {
    static let defaultValue: PageTopScrollEdge? = nil

    static func reduce(value: inout PageTopScrollEdge?, nextValue: () -> PageTopScrollEdge?) {
        value = value ?? nextValue()
    }
}

/// `scrollEdgeEffectStyle(.soft, for: .top)` where available, or `.hard` with any R7
/// accessibility setting on (``PageTopScrollEdge``).
private struct SoftTopScrollEdge: ViewModifier {
    @ScrollEdgeHardEdge private var hardEdge

    func body(content: Content) -> some View {
        let edge = PageTopScrollEdge.resolve(hardEdge: hardEdge)
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                content.scrollEdgeEffectStyle(edge == .hard ? .hard : .soft, for: .top)
            } else {
                content
            }
        }
        .preference(key: PageTopScrollEdgeKey.self, value: edge)
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
