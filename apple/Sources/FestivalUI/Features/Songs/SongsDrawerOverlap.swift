import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Policy

/// How far the pinned "Filter Songs" drawer reaches below the SwiftUI safe area.
///
/// iPhone Duo outer display in landscape (compact width and height, vertical bar),
/// iOS 27.1: the navigation bar draws its title and the always-shown search drawer down
/// to y 136 pt (UIKit's own safe area agrees), yet SwiftUI lays the Songs list out from
/// y 65 pt, so the first rows started under the field (`/duo` P3, `duo-notes.md`).
/// Portrait reports 136 pt to both. The list adds the measured difference as top
/// safe-area padding, in compact height only, so iPhone (portrait only), iPad and the
/// inner display never change.
enum SongsDrawerOverlap {
    /// Differences below this are layout rounding, not an overlap.
    nonisolated static let minimumOverlap: CGFloat = 1

    /// Top padding the Songs list needs to start below the navigation bar.
    ///
    /// - Parameters:
    ///   - barBottom: The navigation bar's bottom edge (search drawer included), in
    ///     window points; NaN until measured.
    ///   - safeTop: The top of the list container's SwiftUI safe area, in window points;
    ///     NaN until measured.
    ///   - compactHeight: Whether the window has a compact vertical size class.
    /// - Returns: The positive difference in compact height, else 0.
    nonisolated static func padding(barBottom: CGFloat, safeTop: CGFloat, compactHeight: Bool) -> CGFloat {
        guard compactHeight, barBottom.isFinite, safeTop.isFinite else { return 0 }
        let overlap = (barBottom - safeTop).rounded()
        return overlap >= minimumOverlap ? overlap : 0
    }
}

// MARK: - Reader

#if os(iOS)
/// An invisible view behind the Songs list that reports the bottom edge of the
/// enclosing navigation bar, search drawer included (``SongsDrawerOverlap``). Not
/// hit-testable and hidden from accessibility.
struct SongsDrawerBarReader: UIViewRepresentable {
    /// Receives the bar's window-space bottom edge whenever it changes.
    let changed: (_ barBottom: CGFloat) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.changed = changed
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.changed = changed
        view.measure()
    }

    /// Finds the nearest navigation controller's bar and measures it.
    final class ReaderView: UIView {
        var changed: ((CGFloat) -> Void)?
        private var last: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measure()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measure()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            measure()
        }

        /// Report the bar's bottom edge (window points) when it changes.
        func measure() {
            guard window != nil, let bar = navigationBar() else { return }
            // The search drawer can draw outside the bar's own bounds, so take the
            // lowest of the bar and any search bar inside it.
            let barBottom = Self.lowestEdge(in: bar, below: bar.convert(bar.bounds, to: nil).maxY)
            if let last, abs(last - barBottom) < 0.5 { return }
            last = barBottom
            let report = changed
            // Out of the layout pass: the report writes SwiftUI state.
            DispatchQueue.main.async { report?(barBottom) }
        }

        /// The lowest window-space bottom edge of `view`'s visible search bars.
        ///
        /// - Parameters:
        ///   - view: The navigation bar (searched recursively).
        ///   - edge: The lowest edge found so far, in window points.
        /// - Returns: The larger of `edge` and every visible `UISearchBar`'s bottom.
        private static func lowestEdge(in view: UIView, below edge: CGFloat) -> CGFloat {
            var lowest = edge
            for child in view.subviews where !child.isHidden && child.alpha > 0.01 {
                if let search = child as? UISearchBar {
                    lowest = max(lowest, search.convert(search.bounds, to: nil).maxY)
                } else {
                    lowest = lowestEdge(in: child, below: lowest)
                }
            }
            return lowest
        }

        /// The navigation bar of the nearest enclosing navigation controller.
        private func navigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController,
                   !navigation.isNavigationBarHidden {
                    return navigation.navigationBar
                }
                responder = current.next
            }
            return nil
        }
    }
}
#endif
