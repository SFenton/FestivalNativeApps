import CoreGraphics
import FestivalCore
import Observation
import os
import SwiftUI

// MARK: - Scroll-driven Songs chrome

/// Scroll-driven Songs chrome state, kept out of `SongsScreen`'s own state (issue #8).
///
/// Whether the List has left its top, which in-list section titles have scrolled up to the section bar, and where that bar
/// ends all change while the user scrolls, mostly
/// near the top of the list. As `@State` on `SongsScreen` every change re-ran the whole
/// screen: re-filter and re-sort the catalogue, re-diff every List row and re-render
/// every visible row. Quick scrolling near the top produced bursts of those passes:
/// stutters, hangs and, on device, freezes. Here only the views that show the state (the
/// floating section bar and the row mask) read it, so `SongsScreen` never re-renders
/// for it, and writes that would not change a value are dropped so they notify no one.
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

    // MARK: Landing line

    /// Vertical padding above and below the floating section bar's title.
    nonisolated static let barTitlePadding: CGFloat = 6
    /// Padding above an in-list section title.
    nonisolated static let inlineTitleTopPadding: CGFloat = 8
    /// Padding below an in-list section title.
    nonisolated static let inlineTitleBottomPadding: CGFloat = 2

    /// How far below the List's top inset a section's in-list title rests after a jump,
    /// and where it hands its name to the section bar (issue #286).
    ///
    /// Rows fade in over `fade` points below the bar (``SectionBarEdgeFade``). A title
    /// landed flush with the bar left its first row inside that fade, so the section
    /// looked half-faded, and scrolling it clear moved the title back below the bar,
    /// which then named the previous section. Landing the title so that its bottom (the
    /// first row's top) meets the end of the fade shows the first row fully opaque, and
    /// using the same line for "passed" keeps the bar on the destination. The two titles
    /// share a font, so only their paddings differ.
    ///
    /// - Parameter fade: The current row fade height (0 with Reduce Transparency or
    ///   Increase Contrast).
    /// - Returns: The landing line's distance below the top inset, in points.
    nonisolated static func landingOffset(fade: CGFloat) -> CGFloat {
        let bar = 2 * barTitlePadding
        let inline = inlineTitleTopPadding + inlineTitleBottomPadding
        return max(0, bar - inline + max(0, fade))
    }

    /// Whether a section title has scrolled up to the section bar's landing line
    /// (issues #9, #286).
    ///
    /// The bar sits at the List's top content inset, below the navigation bar, and a jump
    /// lands a title `landingOffset` below it (``landingOffset(fade:)``). Titles are
    /// measured in the scroll view's space, whose origin is the top of the screen under
    /// the bars, so comparing with 0 named a section only after its title had slid a
    /// further inset (116pt) behind the bars: the bar trailed by one section after every
    /// rail jump and while scrolling.
    ///
    /// - Parameters:
    ///   - minY: The title's top in `.scrollView` space.
    ///   - topInset: The List's top content inset.
    ///   - landingOffset: The landing line below the inset (0: flush with the bar).
    /// - Returns: True once the title's top has reached the landing line.
    nonisolated static func headerPassed(
        minY: CGFloat, topInset: CGFloat, landingOffset: CGFloat = 0
    ) -> Bool {
        minY <= topInset + landingOffset + headerTolerance
    }

    /// The landing line below the List's top inset (``landingOffset(fade:)``). Read by
    /// the titles' geometry checks and the rail's jumps, so never observed.
    let landingLine = TopInset()

    /// Record the landing line for the current accessibility settings.
    ///
    /// - Parameter offset: ``landingOffset(fade:)``.
    func setLandingLine(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        landingLine.value = max(0, offset)
    }

    /// Moves the List onto the landing line after a `.top` jump: a `List` centres any
    /// other scroll anchor (``ListScrollNudger``). The in-list titles locate its scroll
    /// view.
    @ObservationIgnored let listNudger = ListScrollNudger()

    /// The title a jump is settling, and its latest measured top (`.scrollView` space)
    /// since the last read. Never observed.
    @ObservationIgnored private var probeKey: String?
    @ObservationIgnored private var probeMinY: CGFloat?

    /// Record an in-list title's top while a jump is settling on it.
    ///
    /// - Parameters:
    ///   - key: The title's key.
    ///   - minY: Its top in `.scrollView` space.
    func recordTitleTop(_ key: String, minY: CGFloat) {
        guard key == probeKey, minY.isFinite else { return }
        probeMinY = minY
    }

    /// How far to move the List so a title at `minY` rests on the landing line.
    ///
    /// - Parameters:
    ///   - minY: The title's top in `.scrollView` space.
    ///   - topInset: The List's top content inset.
    ///   - landingOffset: The landing line below the inset.
    /// - Returns: Points to move the content down (negative: up), or `nil` when the
    ///   title is already within ``ListScrollNudger/minimumMove`` of the line.
    nonisolated static func landingCorrection(
        minY: CGFloat, topInset: CGFloat, landingOffset: CGFloat
    ) -> CGFloat? {
        let distance = topInset + landingOffset - minY
        return abs(distance) < ListScrollNudger.minimumMove ? nil : distance
    }

    /// Start measuring a jump target's title; call before scrolling to it, since a title
    /// reports its top only when it moves.
    ///
    /// - Parameter key: The target title's key.
    func watchLanding(_ key: String) {
        probeKey = key
        probeMinY = nil
    }

    /// After a `.top` jump, move the List until the target title rests on the landing
    /// line (issue #286), unless a newer jump replaces this one.
    ///
    /// A title reports its top only when it moves, so each round reads the newest report
    /// and corrects by what remains; it stops once landed, when the List cannot move
    /// further (content end) or after ``landingRounds`` rounds.
    ///
    /// - Parameters:
    ///   - key: The target title's key, already passed to ``watchLanding(_:)``.
    ///   - generation: ``jumpGeneration`` when the jump started.
    /// - Returns: The rounds waited before the settle ended (0 with no landing line).
    @discardableResult
    func settleLanding(on key: String, generation: Int) async -> Int {
        defer { if jumpGeneration == generation { probeKey = nil } }
        guard landingLine.value > 0 else { return 0 }
        for round in 1...Self.landingRounds {
            try? await Task.sleep(for: .milliseconds(32))
            guard jumpGeneration == generation, probeKey == key else { return round }
            guard let minY = probeMinY else { continue }
            probeMinY = nil
            guard let distance = Self.landingCorrection(
                minY: minY, topInset: listTopInset.value, landingOffset: landingLine.value
            ) else { return round }
            guard listNudger.moveContent(by: distance) else { return round }
        }
        return Self.landingRounds
    }

    /// Correction rounds before a landing gives up (about a third of a second).
    nonisolated static let landingRounds = 10

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

    // MARK: Section push (issue #288)

    /// The section bar's top edge (global). Read by the titles' geometry checks, so never
    /// observed.
    let barTop = TopInset()
    /// The height of the bar's current title. Read by the titles' geometry checks, so
    /// never observed.
    let barHeight = TopInset()

    /// Tops of the in-list section titles inside the push band
    /// (``pushBandTop(titleTop:landingOffset:barHeight:)``), relative to the bar's top.
    /// Read only by the section bar.
    private(set) var titleTops: [String: CGFloat] = [:]

    /// Title movement smaller than this is layout jitter.
    nonisolated static let titleTopTolerance: CGFloat = 0.1

    /// Record the section bar's top edge and its current title's height.
    ///
    /// - Parameters:
    ///   - top: The bar's global `minY`.
    ///   - height: The current title's height.
    func setBarMetrics(top: CGFloat, height: CGFloat) {
        if top.isFinite { barTop.value = top }
        if height.isFinite, height > 0 { barHeight.value = height }
        if top.isFinite, height.isFinite, height > 0 { setSectionBarBottom(top + height) }
    }

    /// Record where one in-list section title sits in the push band, or that it left it.
    ///
    /// - Parameters:
    ///   - key: The title's key.
    ///   - top: Its top relative to the bar's top, or nil outside the band.
    /// - Returns: True when the recorded tops changed.
    @discardableResult
    func setTitleTop(_ key: String, top: CGFloat?) -> Bool {
        guard let top, top.isFinite else {
            guard titleTops[key] != nil else { return false }
            titleTops[key] = nil
            return true
        }
        if let old = titleTops[key], abs(old - top) < Self.titleTopTolerance { return false }
        titleTops[key] = top
        return true
    }

    /// How far the bar's title text sits above an in-list title's text when both frames
    /// share a top: the two differ only in their top padding.
    nonisolated static let titleAlignment: CGFloat = inlineTitleTopPadding - barTitlePadding

    /// A title's top within the push band, where the section bar draws it itself.
    ///
    /// Below the band the title is an ordinary row. From the band's bottom
    /// (`landingOffset + barHeight` below the bar's top) it is drawn by the bar at the same
    /// place and hidden in the List, so the row fade under the bar never dims it. That
    /// line is below the end of the fade, so the hand-off shows no change. Titles far
    /// above the bar are clamped, so they stop reporting once pinned.
    ///
    /// - Parameters:
    ///   - titleTop: The title's top minus the bar's top (global points).
    ///   - landingOffset: ``landingOffset(fade:)``.
    ///   - barHeight: The bar's current title height (0 while unknown).
    /// - Returns: The clamped top, or nil below the band.
    nonisolated static func pushBandTop(
        titleTop: CGFloat, landingOffset: CGFloat, barHeight: CGFloat
    ) -> CGFloat? {
        guard titleTop.isFinite, titleTop <= landingOffset + max(0, barHeight) else { return nil }
        return max(titleTop, -(titleAlignment + 1))
    }

    /// Where the section bar draws its titles (issue #288), relative to its top.
    struct SectionBarLayout: Equatable {
        /// The current section's title, or nil when nothing is pinned yet or it has been
        /// pushed out.
        var currentY: CGFloat?
        /// The incoming section's title, or nil while it is still an ordinary row.
        var nextY: CGFloat?
    }

    /// Lay out the section bar like a plain list's pinned headers (issue #288).
    ///
    /// A title follows its row 1:1 until it reaches the bar's top, then pins there. The
    /// incoming title pushes the pinned one up as it enters the push band, so the pinned
    /// title is fully out exactly when the incoming title reaches the landing line, where
    /// it becomes current (``headerPassed(minY:topInset:landingOffset:)``) and where a jump
    /// lands it (issue #286). Every position follows the scroll offset, so scrolling back
    /// reverses the push with no jump.
    ///
    /// - Parameters:
    ///   - currentTop: The current section title's band top
    ///     (``pushBandTop(titleTop:landingOffset:barHeight:)``), nil outside the band.
    ///   - currentPassed: The current title has passed the landing line (a jump, or a
    ///     title that scrolled far above the bar).
    ///   - nextTop: The next section title's band top, nil outside the band.
    ///   - landingOffset: ``landingOffset(fade:)``.
    ///   - barHeight: The bar's current title height.
    /// - Returns: Title positions in bar space.
    nonisolated static func sectionBarLayout(
        currentTop: CGFloat?, currentPassed: Bool, nextTop: CGFloat?,
        landingOffset: CGFloat, barHeight: CGFloat
    ) -> SectionBarLayout {
        var current = currentTop.map { max(0, $0 + titleAlignment) } ?? (currentPassed ? 0 : nil)
        guard let nextTop else { return SectionBarLayout(currentY: current, nextY: nil) }
        if let pinned = current {
            let pushed = min(pinned, nextTop - landingOffset - barHeight)
            current = pushed <= -barHeight ? nil : pushed
        }
        return SectionBarLayout(currentY: current, nextY: nextTop + titleAlignment)
    }
}

// MARK: - Top inset

/// One measured length (the List's top content inset, the landing line, the visible
/// height), readable from the section titles' geometry checks, which SwiftUI may run
/// off the main actor.
final class TopInset: Sendable {
    private let storage = OSAllocatedUnfairLock<CGFloat>(initialState: 0)

    /// The last recorded inset, in points.
    var value: CGFloat {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
