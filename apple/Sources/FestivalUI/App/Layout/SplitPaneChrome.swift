import SwiftUI
import Observation
#if os(iOS)
import UIKit
#endif

// MARK: - Shared split chrome

/// What both panes of an on-demand split share so they read as one page
/// (operator 2026-10-05, `.agents/design/apple/split-view.md` "One background"):
///
/// - **One backdrop.** The split container draws the session's backdrop once, behind
///   both panes and the divider band; pages inside the panes draw none and their
///   navigation containers are clear. The leading (parent) page alone registers its
///   artwork with the coordinator, so opening or closing an item never swaps or
///   crossfades the image. HIG Layout: "Extend full-screen backgrounds beneath
///   sidebars, toolbars, and tab bars to window/screen edges."
/// - **One top scrim height.** The trailing pane's top-edge gradient takes the leading
///   page's height (``SplitTopScrim``), and the divider band carries the same gradient,
///   so the darkening is level across the whole width.
/// - **Full-page insets.** UIKit reports a zero minimum layout margin at a mid-window
///   edge, so the trailing pane's large title sat flush against the divider: each pane's
///   bar gets a window edge's margins (``SplitPaneBarMargins``, iOS). UIKit also gives
///   every stack the iPhone Duo vertical bar's safe area, which left 84 pt of dead space
///   beside the hinge in the leading pane: each pane ignores the safe area at the edge
///   facing the divider (``edgesFacingDivider(role:isOpen:)``). HIG Layout: "Respect
///   system safe areas, margins, and guides".
enum SplitPaneChrome {
    /// Whether the split can draw one backdrop behind clear navigation containers
    /// (iOS: `containerBackground(_:for: .navigation)`, iOS 18; a macOS stack draws no
    /// fill). Earlier iOS keeps each page's own backdrop copy.
    static var sharesBackdrop: Bool {
        #if os(iOS)
        if #available(iOS 18.0, *) { true } else { false }
        #else
        true
        #endif
    }

    /// Whether a page registers its background with the coordinator: every page except
    /// those in the trailing pane, whose parent page decides the shared backdrop.
    ///
    /// - Parameter pane: The page's split pane, or nil outside a split.
    /// - Returns: False in the trailing pane.
    static func registersBackground(pane: SplitPaneRole?) -> Bool { pane != .trailing }

    /// Whether a page draws its own backdrop copy.
    ///
    /// - Parameter sharedBySplit: Whether a split container draws the backdrop behind it.
    /// - Returns: False inside a split that shares one backdrop.
    static func drawsOwnBackdrop(sharedBySplit: Bool) -> Bool { !sharedBySplit }

    /// The trailing pane's top scrim height: the leading page's, so both halves darken
    /// to the same depth even where the trailing bar moved into the iPhone Duo vertical
    /// bar (a shorter top inset).
    ///
    /// - Parameters:
    ///   - pane: The page's split pane, or nil outside a split.
    ///   - own: The height from the page's own top inset.
    ///   - leading: The leading page's height, once measured.
    /// - Returns: The height to draw.
    static func topScrimHeight(pane: SplitPaneRole?, own: CGFloat, leading: CGFloat?) -> CGFloat {
        pane == .trailing ? (leading ?? own) : own
    }

    /// The horizontal edges of a pane that face the divider while the split is open:
    /// its safe area there is ignored, because any inset at a mid-window edge belongs to
    /// the window's far edge (the iPhone Duo vertical bar, applied by UIKit to every
    /// stack in the window). The pane's own page margins then apply from the band, as a
    /// full page's apply from a window edge.
    ///
    /// - Parameters:
    ///   - role: The pane, or nil outside a split.
    ///   - isOpen: Whether the trailing pane is open (the leading pane is half width).
    /// - Returns: The edge set to ignore.
    static func edgesFacingDivider(role: SplitPaneRole?, isOpen: Bool) -> Edge.Set {
        switch role {
        case .leading: isOpen ? .trailing : []
        case .trailing: .leading
        case nil: []
        }
    }

    /// Horizontal bar margins for a pane: at least a window edge's standard margin on
    /// both edges, as a full page gets, never less than the margins it already has.
    /// UIKit reports a zero system minimum at an edge inside the window (the trailing
    /// pane's leading edge), which put its large title flush against the divider.
    ///
    /// - Parameters:
    ///   - current: The bar's own leading/trailing margins.
    ///   - windowEdge: The window root's system minimum margin (20 pt on iPad).
    /// - Returns: The leading and trailing margins to set.
    static func barMargins(
        current: (leading: CGFloat, trailing: CGFloat), windowEdge: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        (max(current.leading, windowEdge), max(current.trailing, windowEdge))
    }
}

extension EnvironmentValues {
    /// True for pages inside an on-demand split whose container draws the one shared
    /// backdrop (`SplitPaneChrome`); such pages draw no backdrop of their own.
    @Entry var splitSharesBackdrop = false
    /// The split's shared top-scrim height, nil outside a split.
    @Entry var splitTopScrim: SplitTopScrim?
}

// MARK: - Top scrim

/// The leading page's top-edge scrim height, shared with the trailing pane and the
/// divider band so the split darkens evenly.
@MainActor
@Observable
final class SplitTopScrim {
    /// The leading page's scrim height, once measured.
    var height: CGFloat?
}

// MARK: - Container backdrop

/// The one backdrop behind a split's panes: a mirror of the session's shared backdrop
/// (`FestivalBackdropView`) sized to the whole split container.
struct SplitBackdrop: View {
    let coordinator: FestivalBackgroundCoordinator
    @State private var appeared = false

    var body: some View {
        FestivalBackdropView(coordinator: coordinator, appeared: appeared)
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
            .accessibilityHidden(true)
    }
}

// MARK: - Clear navigation container

/// Clears a split page's navigation container so the split's one backdrop shows
/// through; elsewhere it keeps the platform's default fill.
///
/// Always applied with the same structure, so a page moving between a split and one
/// stack (rotation) keeps its identity and scroll position.
struct SplitNavigationContainerBackground: ViewModifier {
    /// Whether the page is in a split that shares one backdrop.
    let clear: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            content.containerBackground(for: .navigation) {
                if clear { Color.clear } else { Color(uiColor: .systemBackground) }
            }
        } else {
            content
        }
        #else
        // A macOS `NavigationStack` draws no container fill (`.navigation` is iOS only).
        content
        #endif
    }
}

// MARK: - Bar margins (iOS)

#if os(iOS)
/// Gives the navigation bar of the stack hosting it at least a window edge's
/// horizontal layout margins, so a pane that starts mid-window lays out its large
/// title and bar like a full page at a window edge. Hosted in a page's background.
struct SplitPaneBarMargins: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Anchor { Anchor() }

    func updateUIViewController(_ anchor: Anchor, context: Context) { anchor.apply() }

    /// An invisible child controller that finds its navigation controller.
    final class Anchor: UIViewController {
        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        /// Raise the bar's horizontal margins to a window edge's (idempotent).
        func apply() {
            guard let navigation = navigationController,
                  let root = view.window?.rootViewController?.systemMinimumLayoutMargins
            else { return }
            let bar = navigation.navigationBar
            var margins = bar.directionalLayoutMargins
            let target = SplitPaneChrome.barMargins(
                current: (margins.leading, margins.trailing), windowEdge: max(root.leading, root.trailing)
            )
            guard target.leading != margins.leading || target.trailing != margins.trailing else { return }
            margins.leading = target.leading
            margins.trailing = target.trailing
            bar.directionalLayoutMargins = margins
        }
    }
}
#endif
