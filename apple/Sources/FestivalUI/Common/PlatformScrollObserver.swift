import FestivalCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Platform scroll observer

/// Reports a scroll view's position where SwiftUI cannot: `onScrollGeometryChange` needs
/// iOS 18 / macOS 15 (issue #308).
///
/// Every scroll-edge fade reads the same three values on every supported system (see
/// ``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``). Before iOS 18 / macOS 15 a
/// locator hands over the platform scroll view (``ListPlatformScrollView``): a
/// ``ListScrollViewLocator`` inside a List row, or an ``EnclosedScrollViewLocator`` beside
/// arbitrary scroll content. The observer then follows its content offset and content size
/// (key-value observing on iOS; the clip view's bounds and the document's frame
/// notifications on macOS) and reports what `ScrollGeometry` would. Public API only.
@MainActor
final class PlatformScrollObserver {
    /// One scroll position, as `ScrollGeometry` reports it.
    struct Reading: Equatable {
        /// The scroll view's top content inset (where pinned headers pin).
        var inset: CGFloat
        /// Distance scrolled from the resting top; negative while pulled down.
        var offset: CGFloat
        /// How far the content still runs below the scroll view's unobscured bottom edge
        /// (``ScrollEdgeFade/contentOverflow(contentHeight:offsetY:containerHeight:bottomInset:)``):
        /// 0 at the end, nil for an unreadable size.
        var overflow: CGFloat?

        /// A reading.
        ///
        /// - Parameters:
        ///   - inset: The top content inset.
        ///   - offset: Distance scrolled from the resting top.
        ///   - overflow: Content left below the unobscured bottom edge.
        init(inset: CGFloat, offset: CGFloat, overflow: CGFloat? = nil) {
            self.inset = inset
            self.offset = offset
            self.overflow = overflow
        }

        /// The reading for a scroll view's raw geometry, shared by `ScrollGeometry` and the
        /// platform scroll views.
        ///
        /// - Parameters:
        ///   - contentOffsetY: The vertical content offset (`-topInset` at rest).
        ///   - topInset: The top content inset.
        ///   - contentHeight: The content's height.
        ///   - containerHeight: The scroll view's height, including its inset regions.
        ///   - bottomInset: The bottom content inset (pinned bottom chrome).
        /// - Returns: The reading.
        nonisolated static func geometry(
            contentOffsetY: CGFloat, topInset: CGFloat, contentHeight: CGFloat,
            containerHeight: CGFloat, bottomInset: CGFloat
        ) -> Reading {
            Reading(
                inset: topInset, offset: contentOffsetY + topInset,
                overflow: ScrollEdgeFade.contentOverflow(
                    contentHeight: Double(contentHeight), offsetY: Double(contentOffsetY),
                    containerHeight: Double(containerHeight), bottomInset: Double(bottomInset)
                ).map { CGFloat($0) }
            )
        }
    }

    /// The scroll view being followed, while it exists.
    private(set) weak var scrollView: ListPlatformScrollView?
    private let changed: @MainActor (Reading) -> Void
    private var last: Reading?
    #if os(iOS)
    private var observations: [NSKeyValueObservation] = []
    #elseif os(macOS)
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
    #endif

    /// An observer with no scroll view yet.
    ///
    /// - Parameter changed: Receives each new reading, on the main actor.
    init(changed: @escaping @MainActor (Reading) -> Void) {
        self.changed = changed
    }

    deinit {
        #if os(macOS)
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        #endif
    }

    /// Follow `scrollView`, replacing any earlier one, and report its position now.
    ///
    /// - Parameter scrollView: The platform scroll view.
    func attach(_ scrollView: ListPlatformScrollView) {
        guard scrollView !== self.scrollView else { return }
        self.scrollView = scrollView
        last = nil
        #if os(iOS)
        observations = [
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.report() }
            },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.report() }
            },
        ]
        #elseif os(macOS)
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        })
        if let document = scrollView.documentView {
            document.postsFrameChangedNotifications = true
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: document, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
        }
        #endif
        report()
    }

    /// Report the scroll view's current position when it changed.
    func report() {
        guard let scrollView else { return }
        #if os(iOS)
        let insets = scrollView.adjustedContentInset
        let reading = Self.reading(
            contentOffsetY: scrollView.contentOffset.y, topInset: insets.top,
            contentHeight: scrollView.contentSize.height, containerHeight: scrollView.bounds.height,
            bottomInset: insets.bottom
        )
        #elseif os(macOS)
        let clip = scrollView.contentView
        let reading = Self.reading(
            visible: clip.bounds, documentHeight: clip.documentView?.frame.height ?? 0,
            topInset: scrollView.contentInsets.top, bottomInset: scrollView.contentInsets.bottom,
            flipped: clip.isFlipped
        )
        #endif
        guard reading != last else { return }
        last = reading
        changed(reading)
    }

    /// A reading from a `UIScrollView`, like `ScrollGeometry`.
    ///
    /// - Parameters:
    ///   - contentOffsetY: The vertical content offset (`-topInset` at rest).
    ///   - topInset: The adjusted top content inset.
    ///   - contentHeight: The content size's height.
    ///   - containerHeight: The scroll view's bounds height.
    ///   - bottomInset: The adjusted bottom content inset.
    /// - Returns: The inset, the distance scrolled from the resting top and the content
    ///   left below the unobscured bottom edge.
    nonisolated static func reading(
        contentOffsetY: CGFloat, topInset: CGFloat, contentHeight: CGFloat = 0,
        containerHeight: CGFloat = 0, bottomInset: CGFloat = 0
    ) -> Reading {
        .geometry(
            contentOffsetY: contentOffsetY, topInset: topInset, contentHeight: contentHeight,
            containerHeight: containerHeight, bottomInset: bottomInset
        )
    }

    /// A reading from an `NSClipView`'s visible rectangle, like `ScrollGeometry`.
    ///
    /// - Parameters:
    ///   - visible: The clip view's bounds in document coordinates.
    ///   - documentHeight: The document view's height.
    ///   - topInset: The scroll view's top content inset.
    ///   - bottomInset: The scroll view's bottom content inset.
    ///   - flipped: Whether document coordinates grow downward (`NSTableView`).
    /// - Returns: The inset, the distance scrolled from the resting top, where the visible
    ///   top sits `topInset` above the document's top, and the content left below the
    ///   unobscured bottom edge.
    nonisolated static func reading(
        visible: CGRect, documentHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat = 0,
        flipped: Bool
    ) -> Reading {
        let contentOffsetY = flipped ? visible.minY : documentHeight - visible.maxY
        return .geometry(
            contentOffsetY: contentOffsetY, topInset: topInset, contentHeight: documentHeight,
            containerHeight: visible.height, bottomInset: bottomInset
        )
    }
}
