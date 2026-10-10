import CoreGraphics
import Foundation

// MARK: - Large-title rest

/// Decides where a `List` under a collapsing large title must come to rest when it has
/// stopped part-way through the title's collapse (issue #560).
///
/// UIKit snaps a large title fully open or fully closed only when a *drag* ends. A
/// programmatic content offset (``ListScrollNudger`` landing corrections, a `.top`
/// `scrollTo` while the inset changes, Quick Links settles) can leave the List resting
/// between the two: the large title then sits half-way up behind the leading toolbar
/// button and the first section title under the Filter field. Measured on iOS 27
/// (iPhone 17 Pro): while the title is part-way, the List keeps the expanded title's
/// top inset (222 pt) and only its content offset moves; once fully collapsed the inset
/// drops to the collapsed bar's (170 pt).
///
/// So a List at rest with the expanded inset and an offset less than the band past its
/// top is part-way collapsed. ``restingOffset(offsetY:topInset:)`` returns the nearer
/// end, as UIKit's own drag-end snap does. The band is known only once both ends have
/// been seen at this width; until then (or with no collapsing title at all: macOS, a
/// List the bar does not track) nothing moves, so a legitimate rest is never snapped.
struct LargeTitleRest: Equatable {
    /// Points of layout rounding ignored when comparing offsets and insets.
    static let tolerance: CGFloat = 1

    /// The smallest top inset seen at ``containerWidth``: the collapsed bar's.
    private(set) var collapsedInset: CGFloat?
    /// The largest top inset seen at ``containerWidth`` while the List rested at its top:
    /// the expanded title's.
    private(set) var expandedInset: CGFloat?
    /// The width the insets were measured at (a rotation or resize resets them).
    private var containerWidth: CGFloat?

    /// Fold one scroll-geometry sample into the known insets.
    ///
    /// - Parameters:
    ///   - offsetY: The scroll view's vertical content offset.
    ///   - topInset: The scroll view's current top content inset.
    ///   - containerWidth: The scroll view's visible width; 0 before first layout.
    mutating func update(offsetY: CGFloat, topInset: CGFloat, containerWidth width: CGFloat) {
        guard width > 0, offsetY.isFinite, topInset.isFinite else { return }
        if width != containerWidth {
            containerWidth = width
            collapsedInset = topInset
            expandedInset = nil
        } else {
            collapsedInset = min(collapsedInset ?? topInset, topInset)
        }
        if abs(offsetY + topInset) < Self.tolerance {
            expandedInset = max(expandedInset ?? topInset, topInset)
        }
    }

    /// The content offset a List resting at `offsetY` must move to, or `nil` when it
    /// already rests at an end of the large title's collapse.
    ///
    /// - Parameters:
    ///   - offsetY: The resting vertical content offset.
    ///   - topInset: The resting top content inset.
    /// - Returns: `-topInset` (title open, List at its top) or `-topInset + band` (title
    ///   closed), whichever is nearer; `nil` when nothing needs to move or the band is
    ///   not known yet.
    func restingOffset(offsetY: CGFloat, topInset: CGFloat) -> CGFloat? {
        guard offsetY.isFinite, topInset.isFinite, let expandedInset, let collapsedInset,
              topInset >= expandedInset - Self.tolerance else { return nil }
        let band = expandedInset - collapsedInset
        let past = offsetY + topInset
        guard band > Self.tolerance, past > Self.tolerance, past < band - Self.tolerance
        else { return nil }
        return past < band / 2 ? -topInset : -topInset + band
    }
}

// MARK: - Rest watch

/// Runs ``LargeTitleRest`` once a List has come to rest, on every supported system
/// (issue #560, section-jump-landing R9).
///
/// Feed it every scroll sample with ``record(offsetY:topInset:width:)``. On iOS 18 /
/// macOS 15 and later the scroll phase also reports when the List is idle
/// (``setPhaseIdle(_:)``); on iOS 17, or with `FST_DEBUG_LEGACY_SCROLL_GEOMETRY=1`, there
/// is no phase, so the samples come from ``PlatformScrollObserver`` and `isInteracting`
/// (the scroll view's tracking, dragging and deceleration) decides. Either way the check
/// runs ``settleDelay`` after the last sample, waits while a finger is down or the List
/// decelerates, and then asks `settle` to move to the nearer end of a part-way collapse.
@MainActor
final class LargeTitleRestWatch {
    /// How long the List must be still before a rest check: longer than UIKit's own snap
    /// and the landing corrections' rounds take to start.
    static let settleDelay: Duration = .milliseconds(400)

    /// The collapse band learned so far.
    private(set) var decision = LargeTitleRest()
    /// The newest sample's content offset and top inset.
    private var latest: (offsetY: CGFloat, topInset: CGFloat)?
    /// Whether the scroll phase is idle; stays `true` where no phase is reported.
    private(set) var phaseIdle = true
    private let delay: Duration
    private let isInteracting: @MainActor () -> Bool
    private let settle: @MainActor (CGFloat) -> Void
    private var check: Task<Void, Never>?

    /// A watch with nothing learned yet.
    ///
    /// - Parameters:
    ///   - delay: How long the List must be still before a check.
    ///   - isInteracting: Whether a finger is on the List or it is still decelerating.
    ///   - settle: Moves the List to the given content offset.
    init(
        delay: Duration = LargeTitleRestWatch.settleDelay,
        isInteracting: @escaping @MainActor () -> Bool,
        settle: @escaping @MainActor (CGFloat) -> Void
    ) {
        self.delay = delay
        self.isInteracting = isInteracting
        self.settle = settle
    }

    /// Fold one scroll sample in and restart the rest check.
    ///
    /// - Parameters:
    ///   - offsetY: The vertical content offset.
    ///   - topInset: The top content inset.
    ///   - width: The scroll view's visible width.
    func record(offsetY: CGFloat, topInset: CGFloat, width: CGFloat) {
        decision.update(offsetY: offsetY, topInset: topInset, containerWidth: width)
        latest = (offsetY, topInset)
        schedule()
    }

    /// Note the scroll phase (iOS 18 / macOS 15 and later) and restart the rest check.
    ///
    /// - Parameter idle: Whether the List's scroll phase is idle.
    func setPhaseIdle(_ idle: Bool) {
        phaseIdle = idle
        schedule()
    }

    /// Check the List once it has been still for the delay, waiting out touches and
    /// deceleration; any new sample or phase restarts the wait.
    private func schedule() {
        check?.cancel()
        guard phaseIdle else { return }
        let delay = delay
        check = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.phaseIdle else { return }
                if self.isInteracting() { continue }
                guard let latest = self.latest, let target = self.decision.restingOffset(
                    offsetY: latest.offsetY, topInset: latest.topInset
                ) else { return }
                self.settle(target)
                return
            }
        }
    }
}
