import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Platform scroll view

#if os(iOS)
/// The platform scroll view hosting a SwiftUI `List` (its collection view).
typealias ListPlatformScrollView = UIScrollView
#elseif os(macOS)
/// The platform scroll view hosting a SwiftUI `List` (its table view's).
typealias ListPlatformScrollView = NSScrollView
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
    typealias PlatformScrollView = ListPlatformScrollView

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

    /// Finish a large title's part-way collapse (``LargeTitleRest``): animate the List's
    /// content offset to `offsetY`, as UIKit's own snap does when a drag ends.
    ///
    /// - Parameter offsetY: The target vertical content offset.
    /// - Returns: `true` when the List started moving; always `false` on macOS, whose
    ///   toolbar titles never collapse into the content.
    @discardableResult
    func settleLargeTitle(at offsetY: CGFloat) -> Bool {
        #if os(iOS)
        guard offsetY.isFinite, let scrollView, scrollView.window != nil,
              !scrollView.isTracking, !scrollView.isDecelerating,
              abs(scrollView.contentOffset.y - offsetY) >= Self.minimumMove else { return false }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offsetY), animated: true)
        return true
        #else
        return false
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
/// ``ListScrollNudger`` or a ``ListScrollOffsetObserver`` once it is in a window. Not
/// hit-testable and hidden from accessibility.
#if os(iOS)
struct ListScrollViewLocator: UIViewRepresentable {
    let found: @MainActor (ListPlatformScrollView) -> Void

    /// A locator that reports the scroll view to `found` whenever it attaches.
    init(found: @escaping @MainActor (ListPlatformScrollView) -> Void) {
        self.found = found
    }

    /// A locator that hands the scroll view to `nudger`.
    init(nudger: ListScrollNudger) {
        self.init { [weak nudger] scrollView in
            if let nudger, nudger.scrollView !== scrollView { nudger.scrollView = scrollView }
        }
    }

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.found = found
        return view
    }

    func updateUIView(_ view: LocatorView, context: Context) {
        view.found = found
        view.attach()
    }

    /// Walks up to the nearest scroll view: the List's collection view.
    final class LocatorView: UIView {
        var found: (@MainActor (ListPlatformScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil, let found else { return }
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    found(scrollView)
                    return
                }
                view = current.superview
            }
        }
    }
}
#elseif os(macOS)
struct ListScrollViewLocator: NSViewRepresentable {
    let found: @MainActor (ListPlatformScrollView) -> Void

    /// A locator that reports the scroll view to `found` whenever it attaches.
    init(found: @escaping @MainActor (ListPlatformScrollView) -> Void) {
        self.found = found
    }

    /// A locator that hands the scroll view to `nudger`.
    init(nudger: ListScrollNudger) {
        self.init { [weak nudger] scrollView in
            if let nudger, nudger.scrollView !== scrollView { nudger.scrollView = scrollView }
        }
    }

    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.setAccessibilityElement(false)
        view.found = found
        return view
    }

    func updateNSView(_ view: LocatorView, context: Context) {
        view.found = found
        view.attach()
    }

    /// Finds the nearest enclosing scroll view: the List's table view's.
    final class LocatorView: NSView {
        var found: (@MainActor (ListPlatformScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func attach() {
            guard window != nil, let found, let scrollView = enclosingScrollView else { return }
            found(scrollView)
        }
    }
}
#endif
