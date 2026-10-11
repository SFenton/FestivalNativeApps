import CoreGraphics
import Foundation
import Testing
@testable import FestivalUI

// MARK: - LargeTitleRest (issue #560)

/// iPhone 17 Pro on iOS 27: the expanded title's top inset is 222 pt, the collapsed
/// bar's 170 pt, so the collapse band is 52 pt.
private let expanded: CGFloat = 222
private let collapsed: CGFloat = 170

/// A decision that has seen the List at its top with the title open.
private func openedAtTop(width: CGFloat = 402) -> LargeTitleRest {
    var rest = LargeTitleRest()
    rest.update(offsetY: -expanded, topInset: expanded, containerWidth: width)
    return rest
}

/// A decision that has also seen the title collapse.
private func collapsedOnce() -> LargeTitleRest {
    var rest = openedAtTop()
    rest.update(offsetY: -150, topInset: expanded, containerWidth: 402)
    rest.update(offsetY: 400, topInset: collapsed, containerWidth: 402)
    return rest
}

/// Before the title has collapsed once at this width the band is unknown, so nothing
/// moves: a List the bar does not track keeps the expanded inset however far it scrolls.
@Test func partWayRestBeforeAnyCollapseIsLeftAlone() {
    let rest = openedAtTop()
    #expect(rest.collapsedInset == expanded)
    #expect(rest.restingOffset(offsetY: -185, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: 600, topInset: expanded) == nil)
}

/// The reported state (the expanded inset with the content 37 pt past its top) and
/// others: once the band is known, the List settles at the nearer end, like UIKit's
/// drag-end snap.
@Test func partWayRestSettlesAtTheNearerEnd() {
    let rest = collapsedOnce()
    #expect(rest.collapsedInset == collapsed)
    #expect(rest.expandedInset == expanded)
    #expect(rest.restingOffset(offsetY: -207, topInset: expanded) == -expanded)
    #expect(rest.restingOffset(offsetY: -197, topInset: expanded) == -expanded)
    #expect(rest.restingOffset(offsetY: -185, topInset: expanded) == -collapsed)
    #expect(rest.restingOffset(offsetY: -172, topInset: expanded) == -collapsed)
}

/// Every legitimate rest is left alone: open at the top, pulled down, closed at the top
/// (an A–Z jump to "#"), scrolled into the list, and sub-point rounding.
@Test func legitimateRestsDoNotMove() {
    let rest = collapsedOnce()
    #expect(rest.restingOffset(offsetY: -expanded, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -expanded + 0.5, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -300, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -collapsed, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: -150, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: 2400, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: -collapsed - 0.5, topInset: expanded) == nil)
}

/// A List that has never rested at its top (it appeared scrolled) has no expanded inset
/// to compare with, so nothing moves; nor does a List whose inset never changes
/// (macOS, pages without a large title).
@Test func unknownInsetsNeverMove() {
    var deep = LargeTitleRest()
    deep.update(offsetY: 900, topInset: collapsed, containerWidth: 402)
    #expect(deep.restingOffset(offsetY: 30, topInset: collapsed) == nil)

    var flat = LargeTitleRest()
    flat.update(offsetY: -52, topInset: 52, containerWidth: 800)
    flat.update(offsetY: 30, topInset: 52, containerWidth: 800)
    #expect(flat.restingOffset(offsetY: 30, topInset: 52) == nil)
}

/// A new width (rotation, window resize) forgets both insets; zero or non-finite samples
/// are ignored.
@Test func widthChangeAndBadSamplesReset() {
    var rest = collapsedOnce()
    rest.update(offsetY: -116, topInset: 116, containerWidth: 874)
    #expect(rest.expandedInset == 116)
    #expect(rest.collapsedInset == 116)
    rest.update(offsetY: .nan, topInset: 116, containerWidth: 874)
    rest.update(offsetY: -500, topInset: 500, containerWidth: 0)
    #expect(rest.expandedInset == 116)
    #expect(rest.restingOffset(offsetY: .infinity, topInset: 116) == nil)
}

/// The expanded inset is the largest seen at the top, so the collapsed-at-top rest does
/// not replace it.
@Test func collapsedAtTopKeepsTheExpandedInset() {
    var rest = collapsedOnce()
    rest.update(offsetY: -collapsed, topInset: collapsed, containerWidth: 402)
    #expect(rest.expandedInset == expanded)
}

// MARK: - LargeTitleRestWatch (both scroll-reading paths)

/// Records the watch's settles and fakes the scroll view's interaction state.
@MainActor
private final class WatchProbe {
    var settles: [CGFloat] = []
    var interacting = false
    lazy var watch = LargeTitleRestWatch(
        delay: .milliseconds(10),
        isInteracting: { [unowned self] in self.interacting },
        settle: { [unowned self] in self.settles.append($0) }
    )

    /// Teach the watch the 52 pt band: open at the top, part-way, then collapsed.
    func learnBand() {
        watch.record(offsetY: -expanded, topInset: expanded, width: 402)
        watch.record(offsetY: -150, topInset: expanded, width: 402)
        watch.record(offsetY: 400, topInset: collapsed, width: 402)
    }
}

/// Wait up to `timeout` for `condition`.
@MainActor
private func eventually(_ timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// The iOS 17 path (no scroll phase; `PlatformScrollObserver` samples only): a List
/// parked 15 pt into the band settles once, back at its open top.
@MainActor
@Test func legacyWatchSettlesAProgrammaticParkOnce() async {
    let probe = WatchProbe()
    probe.learnBand()
    probe.watch.record(offsetY: -expanded, topInset: expanded, width: 402)
    probe.watch.record(offsetY: -207, topInset: expanded, width: 402)
    #expect(await eventually { probe.settles == [-expanded] })
    // The settle's own animation ends at the open top: nothing more moves.
    probe.watch.record(offsetY: -expanded, topInset: expanded, width: 402)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(probe.settles == [-expanded])
    #expect(probe.watch.phaseIdle)
}

/// Without a phase, a finger held still in the band (or a deceleration) is waited out:
/// the watch settles only once the scroll view stops interacting.
@MainActor
@Test func legacyWatchWaitsOutTouchesAndDeceleration() async {
    let probe = WatchProbe()
    probe.learnBand()
    probe.interacting = true
    probe.watch.record(offsetY: -185, topInset: expanded, width: 402)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(probe.settles.isEmpty)
    probe.interacting = false
    #expect(await eventually { probe.settles == [-collapsed] })
}

/// iOS 18 and later: nothing settles while the scroll phase is not idle, and the idle
/// phase starts the check.
@MainActor
@Test func phaseWatchSettlesOnlyWhenIdle() async {
    let probe = WatchProbe()
    probe.learnBand()
    probe.watch.setPhaseIdle(false)
    probe.watch.record(offsetY: -207, topInset: expanded, width: 402)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(probe.settles.isEmpty)
    probe.watch.setPhaseIdle(true)
    #expect(await eventually { probe.settles == [-expanded] })
}

/// Only the resting sample counts: passing through the band and stopping at an end, or
/// resting part-way before the band is known, never moves the List.
@MainActor
@Test func watchIgnoresPassingSamplesAndUnknownBands() async {
    let probe = WatchProbe()
    probe.learnBand()
    probe.watch.record(offsetY: -190, topInset: expanded, width: 402)
    probe.watch.record(offsetY: 300, topInset: collapsed, width: 402)
    let fresh = WatchProbe()
    fresh.watch.record(offsetY: -expanded, topInset: expanded, width: 402)
    fresh.watch.record(offsetY: -190, topInset: expanded, width: 402)
    try? await Task.sleep(for: .milliseconds(150))
    #expect(probe.settles.isEmpty)
    #expect(fresh.settles.isEmpty)
}

// MARK: - Debug park request

/// `FST_DEBUG_SONGS_PARK_TOP` takes points and an optional delay or trigger file.
@Test func parkRequestParses() {
    #expect(SongsScrollStress.parseParkRequest("15@/tmp/a@b/park")
        == .init(points: 15, delay: 0, trigger: "/tmp/a@b/park"))
    #expect(SongsScrollStress.parseParkRequest("0@/tmp/park") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@tmp/park") == nil)
    #expect(SongsScrollStress.parseParkRequest("37") == .init(points: 37, delay: 3))
    #expect(SongsScrollStress.parseParkRequest("15@12.5") == .init(points: 15, delay: 12.5))
    #expect(SongsScrollStress.parseParkRequest("0") == nil)
    #expect(SongsScrollStress.parseParkRequest("-4") == nil)
    #expect(SongsScrollStress.parseParkRequest("x") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@-1") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@1@2") == nil)
}

/// A trigger-file park waits for the file, however long, and a delay park for its delay.
@Test func parkWaitsForItsTrigger() async throws {
    let trigger = FileManager.default.temporaryDirectory
        .appendingPathComponent("park-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: trigger) }
    let park = try #require(SongsScrollStress.parseParkRequest("15@\(trigger)"))
    let waiting = Task { await SongsScrollStress.waitForPark(park); return Date() }
    try await Task.sleep(for: .milliseconds(400))
    let created = Date()
    #expect(FileManager.default.createFile(atPath: trigger, contents: nil))
    let parked = await waiting.value
    #expect(parked >= created)
    let start = Date()
    await SongsScrollStress.waitForPark(.init(points: 15, delay: 0.2))
    #expect(Date().timeIntervalSince(start) >= 0.19)
}
