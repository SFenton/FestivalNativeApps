import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - List scroll offset observer

/// Reports a `List`'s top content inset and scroll offset where SwiftUI cannot:
/// `onScrollGeometryChange` needs iOS 18 / macOS 15 (issue #308).
///
/// A ``ListScrollViewLocator`` in one of the List's rows hands over the platform scroll
/// view (``ListPlatformScrollView``), the same way ``ListScrollNudger`` finds it. The
/// observer then follows its content offset (key-value observing on iOS, the clip view's
/// bounds notifications on macOS) and reports the same readings
/// `onScrollGeometryChange` gives: the top content inset and the distance scrolled from
/// the resting top. Public API only.
@MainActor
final class ListScrollOffsetObserver {
    /// One scroll position.
    struct Reading: Equatable {
        /// The scroll view's top content inset (where pinned headers pin).
        var inset: CGFloat
        /// Distance scrolled from the resting top; negative while pulled down.
        var offset: CGFloat
    }

    private weak var scrollView: ListPlatformScrollView?
    private let changed: @MainActor (Reading) -> Void
    private var last: Reading?
    #if os(iOS)
    private var observation: NSKeyValueObservation?
    #elseif os(macOS)
    nonisolated(unsafe) private var token: NSObjectProtocol?
    #endif

    /// An observer with no scroll view yet.
    ///
    /// - Parameter changed: Receives each new reading, on the main actor.
    init(changed: @escaping @MainActor (Reading) -> Void) {
        self.changed = changed
    }

    deinit {
        #if os(macOS)
        if let token { NotificationCenter.default.removeObserver(token) }
        #endif
    }

    /// Follow `scrollView`, replacing any earlier one, and report its position now.
    ///
    /// - Parameter scrollView: The List's platform scroll view.
    func attach(_ scrollView: ListPlatformScrollView) {
        guard scrollView !== self.scrollView else { return }
        self.scrollView = scrollView
        last = nil
        #if os(iOS)
        observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.report() }
        }
        #elseif os(macOS)
        if let token { NotificationCenter.default.removeObserver(token) }
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        token = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        report()
        #endif
    }

    /// Report the scroll view's current position when it changed.
    func report() {
        guard let scrollView else { return }
        #if os(iOS)
        let reading = Self.reading(
            contentOffsetY: scrollView.contentOffset.y, topInset: scrollView.adjustedContentInset.top
        )
        #elseif os(macOS)
        let clip = scrollView.contentView
        let reading = Self.reading(
            visible: clip.bounds, documentHeight: clip.documentView?.frame.height ?? 0,
            topInset: scrollView.contentInsets.top, flipped: clip.isFlipped
        )
        #endif
        guard reading != last else { return }
        last = reading
        changed(reading)
    }

    /// A reading from a `UIScrollView`'s offset, like `ScrollGeometry`.
    ///
    /// - Parameters:
    ///   - contentOffsetY: The vertical content offset (`-topInset` at rest).
    ///   - topInset: The adjusted top content inset.
    /// - Returns: The inset and the distance scrolled from the resting top.
    nonisolated static func reading(contentOffsetY: CGFloat, topInset: CGFloat) -> Reading {
        Reading(inset: topInset, offset: contentOffsetY + topInset)
    }

    /// A reading from an `NSClipView`'s visible rectangle, like `ScrollGeometry`.
    ///
    /// - Parameters:
    ///   - visible: The clip view's bounds in document coordinates.
    ///   - documentHeight: The document view's height.
    ///   - topInset: The scroll view's top content inset.
    ///   - flipped: Whether document coordinates grow downward (`NSTableView`).
    /// - Returns: The inset and the distance scrolled from the resting top, where the
    ///   visible top sits `topInset` above the document's top.
    nonisolated static func reading(
        visible: CGRect, documentHeight: CGFloat, topInset: CGFloat, flipped: Bool
    ) -> Reading {
        let offset = flipped
            ? visible.minY + topInset
            : documentHeight + topInset - visible.maxY
        return Reading(inset: topInset, offset: offset)
    }
}
