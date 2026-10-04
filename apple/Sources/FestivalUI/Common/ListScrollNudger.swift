import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - List scroll nudger

/// Moves a SwiftUI `List` by a few points, so a jump can land a row below the top edge
/// instead of flush with it (issue #286).
///
/// On a `List`, `ScrollViewProxy.scrollTo(_:anchor:)` honours `.top`, `.center` and
/// `.bottom`, but any other unit point centres the row (measured on iOS 26.5: a 0.05
/// anchor put the Songs "K" title mid-screen), and `ScrollPosition.scrollTo(y:)` leaves
/// a `List` where it is. So a jump scrolls with `.top`, then moves the platform scroll
/// view hosting the List (`UIScrollView`, `NSScrollView`) by the remaining distance.
/// A ``ListScrollViewLocator`` in one of the List's rows finds that scroll view. This
/// uses public API only. Until a locator has found the scroll view, nothing moves and
/// the jump stays flush with the top.
@MainActor
public final class ListScrollNudger {
    #if os(iOS)
    typealias PlatformScrollView = UIScrollView
    #elseif os(macOS)
    typealias PlatformScrollView = NSScrollView
    #endif

    /// The scroll view hosting the List, once a locator has found it.
    weak var scrollView: PlatformScrollView?

    /// A nudger with no scroll view yet.
    public init() {}

    /// Move the List's content by `distance` points, clamped to the content's ends.
    ///
    /// - Parameter distance: Positive moves the content down the screen (a row at `y`
    ///   ends at `y + distance`); negative moves it up.
    /// - Returns: `true` when the content moved; `false` with no located scroll view,
    ///   or when the content is already at that end.
    @discardableResult
    func moveContent(by distance: CGFloat) -> Bool {
        guard distance.isFinite, let scrollView, scrollView.window != nil else { return false }
        #if os(iOS)
        let insets = scrollView.adjustedContentInset
        let current = scrollView.contentOffset.y
        let target = Self.offset(
            from: current, moving: distance, lowest: -insets.top,
            highest: scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
        )
        guard abs(target - current) >= Self.minimumMove else { return false }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
        return true
        #elseif os(macOS)
        let clip = scrollView.contentView
        let bounds = clip.bounds
        // A flipped document (NSTableView) scrolls down as the origin's y grows.
        let down: CGFloat = clip.isFlipped ? 1 : -1
        var moved = bounds
        moved.origin.y -= down * distance
        let target = clip.constrainBoundsRect(moved).origin
        guard abs(target.y - bounds.origin.y) >= Self.minimumMove else { return false }
        clip.scroll(to: target)
        scrollView.reflectScrolledClipView(clip)
        return true
        #endif
    }

    /// Movement smaller than this is rounding, not a landing error.
    nonisolated static let minimumMove: CGFloat = 0.5

    /// The content offset after moving the content `distance` points down the screen.
    ///
    /// - Parameters:
    ///   - current: The current vertical content offset.
    ///   - distance: Points to move the content down (negative: up).
    ///   - lowest: The offset at the top of the content (minus the top inset).
    ///   - highest: The offset at the bottom of the content; below `lowest` for content
    ///     shorter than the viewport, which then stays at `lowest`.
    /// - Returns: The clamped offset.
    nonisolated static func offset(
        from current: CGFloat, moving distance: CGFloat, lowest: CGFloat, highest: CGFloat
    ) -> CGFloat {
        min(max(current - distance, lowest), max(lowest, highest))
    }
}

// MARK: - Locator

/// An invisible view in a `List` row that hands the List's platform scroll view to a
/// ``ListScrollNudger`` once it is in a window. Not hit-testable and hidden from
/// accessibility.
#if os(iOS)
struct ListScrollViewLocator: UIViewRepresentable {
    let nudger: ListScrollNudger

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.nudger = nudger
        return view
    }

    func updateUIView(_ view: LocatorView, context: Context) {
        view.nudger = nudger
        view.attach()
    }

    /// Walks up to the nearest scroll view: the List's collection view.
    final class LocatorView: UIView {
        weak var nudger: ListScrollNudger?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil, let nudger else { return }
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    if nudger.scrollView !== scrollView { nudger.scrollView = scrollView }
                    return
                }
                view = current.superview
            }
        }
    }
}
#elseif os(macOS)
struct ListScrollViewLocator: NSViewRepresentable {
    let nudger: ListScrollNudger

    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.setAccessibilityElement(false)
        view.nudger = nudger
        return view
    }

    func updateNSView(_ view: LocatorView, context: Context) {
        view.nudger = nudger
        view.attach()
    }

    /// Finds the nearest enclosing scroll view: the List's table view's.
    final class LocatorView: NSView {
        weak var nudger: ListScrollNudger?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func attach() {
            guard window != nil, let nudger, let scrollView = enclosingScrollView else { return }
            if nudger.scrollView !== scrollView { nudger.scrollView = scrollView }
        }
    }
}
#endif
