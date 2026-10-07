import FestivalCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Scroll edge tracking

/// Where the scroll-edge fades read the scroll position (`.agents/patterns/scroll-edge.md`,
/// issue #308).
enum ScrollEdgeTracking {
    /// Whether scroll positions come from the platform scroll view
    /// (``PlatformScrollObserver``) because `onScrollGeometryChange` is missing: iOS 17 and
    /// macOS 14, or `FST_DEBUG_LEGACY_SCROLL_GEOMETRY=1` in Debug builds, which exercises
    /// that path on a newer simulator.
    static var usesLegacyPath: Bool {
        if DebugAnimationOverride.legacyScrollGeometry { return true }
        if #available(iOS 18.0, macOS 15.0, *) { return false }
        return true
    }
}

// MARK: - Reader

extension View {
    /// Reports the scroll position of the scroll view this view is or contains, the same
    /// way on every supported system: from `onScrollGeometryChange` on iOS 18 / macOS 15
    /// and later, otherwise from the platform scroll view through an
    /// ``EnclosedScrollViewLocator`` and a ``PlatformScrollObserver``. The sheet-header
    /// fade and the bottom-chrome fade read it, so their ramps grow and shrink with the
    /// scroll on iOS 17 / macOS 14 too (scroll-edge R3, R4).
    ///
    /// - Parameters:
    ///   - legacy: Read the platform scroll view; tests set it to cover the iOS 17 /
    ///     macOS 14 path on newer systems.
    ///   - transform: The value to report for a reading. Keep it coarse (clamped,
    ///     rounded) so only changes that matter reach `action`.
    ///   - action: Receives each new value, on the main actor.
    /// - Returns: The view, observed.
    func onScrollEdgeReading<Value: Equatable>(
        legacy: Bool = ScrollEdgeTracking.usesLegacyPath,
        _ transform: @escaping (PlatformScrollObserver.Reading) -> Value,
        action: @escaping (Value) -> Void
    ) -> some View {
        modifier(ScrollEdgeReader(legacy: legacy, transform: transform, action: action))
    }
}

/// The modifier behind ``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``.
private struct ScrollEdgeReader<Value: Equatable>: ViewModifier {
    let legacy: Bool
    let transform: (PlatformScrollObserver.Reading) -> Value
    let action: (Value) -> Void
    @State private var relay = ScrollEdgeReadingRelay()

    func body(content: Content) -> some View {
        if legacy {
            let relay = relay
            content.background {
                EnclosedScrollViewLocator(
                    current: { relay.observer.scrollView },
                    found: { relay.observer.attach($0) },
                    refresh: { relay.observer.report() }
                )
                .onChange(of: legacy, initial: true) { relay.deliver = deliver }
                .accessibilityHidden(true)
            }
        } else if #available(iOS 18.0, macOS 15.0, *) {
            let relay = relay, action = action
            content.onScrollGeometryChange(for: Value.self) { geometry in
                let value = transform(.geometry(
                    contentOffsetY: geometry.contentOffset.y, topInset: geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.visibleRect.height,
                    bottomInset: geometry.contentInsets.bottom
                ))
                relay.reconcile(value, action: action)
                return value
            } action: { _, value in
                relay.last = value
                action(value)
            }
        } else {
            content
        }
    }

    /// Hand a reading to `action` when its value changed.
    private var deliver: @MainActor (PlatformScrollObserver.Reading) -> Void {
        let transform = transform, action = action
        return { [relay] reading in
            let value = transform(reading)
            guard relay.last.map({ ($0 as? Value) != value }) ?? true else { return }
            relay.last = value
            action(value)
        }
    }
}

/// Holds one reader's observer across renders; never observed by SwiftUI.
@MainActor
private final class ScrollEdgeReadingRelay {
    /// The latest delivery closure from the modifier.
    var deliver: (@MainActor (PlatformScrollObserver.Reading) -> Void)? {
        didSet { if let reading = lastReading { deliver?(reading) } }
    }
    /// The last delivered value, so equal values are not re-delivered.
    var last: Any?
    private var lastReading: PlatformScrollObserver.Reading?
    /// The newest value `onScrollGeometryChange` computed, awaiting ``reconcile(_:action:)``.
    private var pending: Any?
    private var reconciling = false

    /// Delivers `value` on the next main-actor turn if `onScrollGeometryChange` has not
    /// by then. It sometimes records a changed value without calling its action: a
    /// scroll view that outlived a reload gate's content swap (Song Band's header stays
    /// through reloads, issue #317) got its taller rows' 0 → 40 pt bottom fade value
    /// recorded but never delivered, so the rows were cut hard at the pager until the
    /// next change. A normal change is delivered by the action first, so this does
    /// nothing then.
    ///
    /// - Parameters:
    ///   - value: The value just computed for the scroll view's geometry.
    ///   - action: The reader's action.
    func reconcile<Value: Equatable>(_ value: Value, action: @escaping (Value) -> Void) {
        pending = value
        guard (last as? Value) != value, !reconciling else { return }
        reconciling = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            reconciling = false
            guard let value = pending as? Value, (last as? Value) != value else { return }
            last = value
            action(value)
        }
    }

    lazy var observer = PlatformScrollObserver { [weak self] reading in
        self?.lastReading = reading
        self?.deliver?(reading)
    }
}

// MARK: - Enclosed scroll view search

/// Picks the scroll view that belongs to some content, from outside it.
enum EnclosedScrollViewSearch {
    /// Smallest share of the content's area a scroll view must cover to be its scroll view.
    static let minimumCoverage: CGFloat = 0.5

    /// The candidate that covers most of `target`, preferring the earliest (outermost) on a
    /// tie, or nil when none covers ``minimumCoverage`` of it.
    ///
    /// - Parameters:
    ///   - target: The content's frame.
    ///   - candidates: Candidate scroll view frames in the same coordinates, outermost
    ///     first.
    /// - Returns: The chosen candidate's index.
    static func best(target: CGRect, candidates: [CGRect]) -> Int? {
        let area = target.width * target.height
        guard area.isFinite, area > 0 else { return nil }
        var best: (index: Int, covered: CGFloat)?
        for (index, frame) in candidates.enumerated() {
            let overlap = frame.intersection(target)
            guard !overlap.isNull else { continue }
            let covered = overlap.width * overlap.height
            guard covered.isFinite, covered >= area * minimumCoverage else { continue }
            if covered > (best?.covered ?? 0) { best = (index, covered) }
        }
        return best?.index
    }
}

// MARK: - Enclosed scroll view locator

/// An invisible view placed behind some content that finds the content's platform scroll
/// view (``ListPlatformScrollView``) and keeps a ``PlatformScrollObserver`` on it.
///
/// A ``ListScrollViewLocator`` sits inside a List row, but the sheet-header and
/// bottom-chrome fades wrap content they don't own (a `List`, a `ScrollView`, a sheet's
/// whole root view), so this locator searches from beside it instead: from its own place
/// up to the hosting view controller's view (never beyond, so a page behind a sheet is
/// never chosen), for the scroll view, not an ancestor, that covers most of the content's
/// frame (``EnclosedScrollViewSearch``). While in a window it re-checks twice a second, so
/// content that swaps in a new scroll view (a spinner replaced by a List) is followed and
/// inset changes are read. It only runs on the iOS 17 / macOS 14 path. Not hit-testable
/// and hidden from accessibility.
#if os(iOS)
struct EnclosedScrollViewLocator: UIViewRepresentable {
    /// The scroll view currently followed.
    let current: @MainActor () -> ListPlatformScrollView?
    /// Receives a newly found scroll view.
    let found: @MainActor (ListPlatformScrollView) -> Void
    /// Re-reads the followed scroll view.
    let refresh: @MainActor () -> Void

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.locator = self
        return view
    }

    func updateUIView(_ view: LocatorView, context: Context) {
        view.locator = self
        view.check()
    }

    static func dismantleUIView(_ view: LocatorView, coordinator: ()) {
        view.stop()
    }

    /// Searches for the content's scroll view.
    final class LocatorView: UIView {
        var locator: EnclosedScrollViewLocator?
        private var timer: Timer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                stop()
            } else {
                check()
                timer = timer ?? Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check() }
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            check()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        /// Find the scroll view when the followed one is gone; otherwise re-read it.
        func check() {
            guard window != nil, let locator else { return }
            if let current = locator.current(), current.window != nil {
                locator.refresh()
            } else if let scrollView = search() {
                locator.found(scrollView)
            }
        }

        private func search() -> UIScrollView? {
            let target = convert(bounds, to: nil)
            var ancestors: [UIView] = []
            var view: UIView? = superview
            while let current = view {
                ancestors.append(current)
                if current.next is UIViewController { break }
                view = current.superview
            }
            let excluded = Set(ancestors.map(ObjectIdentifier.init))
            for ancestor in ancestors {
                var candidates: [UIScrollView] = []
                var queue = ancestor.subviews
                while !queue.isEmpty {
                    let next = queue.removeFirst()
                    if next === self || next.isHidden { continue }
                    if let scroll = next as? UIScrollView, !excluded.contains(ObjectIdentifier(scroll)) {
                        candidates.append(scroll)
                    }
                    queue.append(contentsOf: next.subviews)
                }
                let frames = candidates.map { $0.convert($0.bounds, to: nil) }
                if let index = EnclosedScrollViewSearch.best(target: target, candidates: frames) {
                    return candidates[index]
                }
            }
            return nil
        }
    }
}
#elseif os(macOS)
struct EnclosedScrollViewLocator: NSViewRepresentable {
    /// The scroll view currently followed.
    let current: @MainActor () -> ListPlatformScrollView?
    /// Receives a newly found scroll view.
    let found: @MainActor (ListPlatformScrollView) -> Void
    /// Re-reads the followed scroll view.
    let refresh: @MainActor () -> Void

    func makeNSView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.setAccessibilityElement(false)
        view.locator = self
        return view
    }

    func updateNSView(_ view: LocatorView, context: Context) {
        view.locator = self
        view.check()
    }

    static func dismantleNSView(_ view: LocatorView, coordinator: ()) {
        view.stop()
    }

    /// Searches for the content's scroll view.
    final class LocatorView: NSView {
        var locator: EnclosedScrollViewLocator?
        private var timer: Timer?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stop()
            } else {
                check()
                timer = timer ?? Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check() }
                }
            }
        }

        override func layout() {
            super.layout()
            check()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        /// Find the scroll view when the followed one is gone; otherwise re-read it.
        func check() {
            guard window != nil, let locator else { return }
            if let current = locator.current(), current.window != nil {
                locator.refresh()
            } else if let scrollView = search() {
                locator.found(scrollView)
            }
        }

        private func search() -> NSScrollView? {
            let target = convert(bounds, to: nil)
            var ancestors: [NSView] = []
            var view: NSView? = superview
            while let current = view {
                ancestors.append(current)
                if current.nextResponder is NSViewController || current === window?.contentView { break }
                view = current.superview
            }
            let excluded = Set(ancestors.map(ObjectIdentifier.init))
            for ancestor in ancestors {
                var candidates: [NSScrollView] = []
                var queue = ancestor.subviews
                while !queue.isEmpty {
                    let next = queue.removeFirst()
                    if next === self || next.isHidden { continue }
                    if let scroll = next as? NSScrollView, !excluded.contains(ObjectIdentifier(scroll)) {
                        candidates.append(scroll)
                    }
                    queue.append(contentsOf: next.subviews)
                }
                let frames = candidates.map { $0.convert($0.bounds, to: nil) }
                if let index = EnclosedScrollViewSearch.best(target: target, candidates: frames) {
                    return candidates[index]
                }
            }
            return nil
        }
    }
}
#endif
