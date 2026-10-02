import CoreGraphics
import Observation
import os

// MARK: - Scroll-driven Songs chrome

/// Scroll-driven Songs chrome state, kept out of `SongsScreen`'s own state (issue #8).
///
/// Whether the List has left its top, whether the page tools sit in the navigation bar,
/// which in-list section titles have scrolled up to the section bar, and where that bar
/// ends all change while the user scrolls, mostly
/// near the top of the list. As `@State` on `SongsScreen` every change re-ran the whole
/// screen: re-filter and re-sort the catalogue, re-diff every List row and re-render
/// every visible row. Quick scrolling near the top produced bursts of those passes:
/// stutters, hangs and, on device, freezes. Here only the views that show the state (the
/// floating section bar and the row mask) read it, so `SongsScreen` never re-renders
/// for it, and writes that would not change a value are dropped so they notify no one.
/// The page tools' placement is read only by the toolbar modifier, for the same reason.
@MainActor @Observable
final class SongsScrollChrome {
    /// Section-bar edge movement smaller than this is layout jitter.
    static let barBottomTolerance: CGFloat = 0.5
    /// A title this close below the List's top inset already counts as at the bar
    /// (sub-pixel rounding of a landed jump).
    nonisolated static let headerTolerance: CGFloat = 1

    /// The List has scrolled away from its top (the large title has collapsed).
    private(set) var listScrolled = false
    /// Keys of the in-list section titles that have scrolled up to the section bar.
    private(set) var passedHeaders: Set<String> = []
    /// Bottom edge of the floating section bar (global), for masking rows under it.
    private(set) var sectionBarBottom: CGFloat = 0
    /// Scrolled away from the top with a profile selected: Filter/Sort/Quick Links move
    /// from the floating dock into the navigation bar (operator batch 7), and back at
    /// the top.
    private(set) var toolsInBar = false

    /// Record whether the List has left its top.
    ///
    /// - Parameter scrolled: The scroll-away decision (``ScrollAwayGate``).
    /// - Returns: True when the value changed.
    @discardableResult
    func setScrolled(_ scrolled: Bool) -> Bool {
        guard scrolled != listScrolled else { return false }
        listScrolled = scrolled
        return true
    }

    /// Move the page tools into (or out of) the navigation bar.
    ///
    /// - Parameter inBar: True to show them in the navigation bar.
    /// - Returns: True when the value changed.
    @discardableResult
    func setToolsInBar(_ inBar: Bool) -> Bool {
        guard inBar != toolsInBar else { return false }
        toolsInBar = inBar
        return true
    }

    /// Record whether one section title has scrolled up to the section bar.
    ///
    /// - Parameters:
    ///   - key: The section title's stable key.
    ///   - passed: True once its top reaches the bar.
    /// - Returns: True when the set changed.
    @discardableResult
    func setHeader(_ key: String, passed: Bool) -> Bool {
        guard passedHeaders.contains(key) != passed else { return false }
        if passed { passedHeaders.insert(key) } else { passedHeaders.remove(key) }
        return true
    }

    /// The List's top content inset: where the section bar sits and where a jump lands a
    /// section title. Read by the titles' geometry checks only, so never observed.
    let listTopInset = TopInset()

    /// Record the List's top content inset (it changes as the large title collapses).
    ///
    /// - Parameter inset: `ScrollGeometry.contentInsets.top`.
    func setListTopInset(_ inset: CGFloat) {
        guard inset.isFinite else { return }
        listTopInset.value = inset
    }

    /// Whether a section title has scrolled up to the section bar (issue #9).
    ///
    /// The bar sits at the List's top content inset, below the navigation bar, and a jump
    /// lands a title exactly there. Titles are measured in the scroll view's space, whose
    /// origin is the top of the screen under the bars, so comparing with 0 named a
    /// section only after its title had slid a further inset (116pt) behind the bars:
    /// the bar trailed by one section after every rail jump and while scrolling.
    ///
    /// - Parameters:
    ///   - minY: The title's top in `.scrollView` space.
    ///   - topInset: The List's top content inset.
    /// - Returns: True once the title's top has reached the bar.
    nonisolated static func headerPassed(minY: CGFloat, topInset: CGFloat) -> Bool {
        minY <= topInset + headerTolerance
    }

    /// Bumped by every ``jump(to:in:)`` so a delayed corrective scroll can tell whether a
    /// newer jump has replaced it. Never observed: nothing renders it.
    @ObservationIgnored private(set) var jumpGeneration = 0

    /// Record an instant jump that puts one section's title at the top (A–Z rail, Quick
    /// Links): every title up to and including the target has passed the bar, none after.
    ///
    /// The in-list titles cannot tell this themselves (issue #9): they report only when
    /// their own position changes, so titles dismantled during the jump keep their last
    /// answer. Without this the bar showed a letter from before the jump (# → P read
    /// "B"), or a later one after jumping back.
    ///
    /// - Parameters:
    ///   - key: The target section title's key.
    ///   - keys: Section title keys in list order.
    /// - Returns: True when the passed set changed.
    @discardableResult
    func jump(to key: String, in keys: [String]) -> Bool {
        jumpGeneration &+= 1
        guard let index = keys.firstIndex(of: key) else { return false }
        let passed = Set(keys[...index])
        guard passed != passedHeaders else { return false }
        passedHeaders = passed
        return true
    }

    /// Forget every passed title (a re-sort or re-filter starts again at the top).
    ///
    /// - Returns: True when the set changed.
    @discardableResult
    func resetHeaders() -> Bool {
        guard !passedHeaders.isEmpty else { return false }
        passedHeaders = []
        return true
    }

    /// Record the section bar's bottom edge.
    ///
    /// - Parameter bottom: The bar's global `maxY`.
    /// - Returns: True when it moved by at least ``barBottomTolerance``.
    @discardableResult
    func setSectionBarBottom(_ bottom: CGFloat) -> Bool {
        guard bottom.isFinite,
              abs(bottom - sectionBarBottom) >= Self.barBottomTolerance else { return false }
        sectionBarBottom = bottom
        return true
    }

    /// The section whose title belongs in the bar: the last one, in list order, whose
    /// in-list title has scrolled up to the bar, else the first.
    ///
    /// - Parameter keys: Section title keys in list order.
    /// - Returns: Index into `keys`, or nil when there are no sections.
    func currentSectionIndex(in keys: [String]) -> Int? {
        guard !keys.isEmpty else { return nil }
        return keys.lastIndex { passedHeaders.contains($0) } ?? 0
    }
}

// MARK: - Top inset

/// The List's top content inset, readable from the section titles' geometry checks,
/// which SwiftUI may run off the main actor.
final class TopInset: Sendable {
    private let storage = OSAllocatedUnfairLock<CGFloat>(initialState: 0)

    /// The last recorded inset, in points.
    var value: CGFloat {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
