import Testing
@testable import FestivalCore

// MARK: - Fixtures

private let sections = ["a", "b", "c", "d"].map { QuickLinkSection(id: $0, title: $0.uppercased()) }

/// Build a frame dictionary from `(id, minY, height)` triples.
///
/// - Parameter entries: Section id, viewport-relative top and height.
/// - Returns: Frames keyed by id.
private func frames(_ entries: [(String, Double, Double)]) -> [String: QuickLinkFrame] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.0, QuickLinkFrame(minY: $0.1, maxY: $0.1 + $0.2)) })
}

// MARK: - Visibility and ordering

@Test func entryPointNeedsAtLeastTwoSections() {
    #expect(!QuickLinks.isAvailable(sectionCount: 0))
    #expect(!QuickLinks.isAvailable(sectionCount: 1))
    #expect(QuickLinks.isAvailable(sectionCount: 2))
}

@Test func explicitSectionsWinOverDiscoveredOnes() {
    let explicit = [QuickLinkSection(id: "x", title: "X"), QuickLinkSection(id: "y", title: "Y")]
    #expect(QuickLinks.ordered(explicit: explicit, discovered: sections).map(\.id) == ["x", "y"])
    #expect(QuickLinks.ordered(explicit: nil, discovered: sections).map(\.id) == ["a", "b", "c", "d"])
}

@Test func orderingDropsDuplicateIdsKeepingFirst() {
    let discovered = [
        QuickLinkSection(id: "a", title: "First"), QuickLinkSection(id: "b", title: "B"),
        QuickLinkSection(id: "a", title: "Second"),
    ]
    let ordered = QuickLinks.ordered(explicit: nil, discovered: discovered)
    #expect(ordered.map(\.id) == ["a", "b"])
    #expect(ordered[0].title == "First")
}

@Test func negativeDepthClampsToZero() {
    #expect(QuickLinkSection(id: "a", title: "A", depth: -3).depth == 0)
    #expect(QuickLinkSection(id: "a", title: "A", depth: 2).depth == 2)
}

@Test func visibilityRequiresIntersectingTheViewport() {
    #expect(!QuickLinks.isVisible(nil, viewportHeight: 600))
    #expect(QuickLinks.isVisible(QuickLinkFrame(minY: -100, maxY: 1), viewportHeight: 600))
    #expect(!QuickLinks.isVisible(QuickLinkFrame(minY: -100, maxY: 0), viewportHeight: 600))
    #expect(!QuickLinks.isVisible(QuickLinkFrame(minY: 600, maxY: 900), viewportHeight: 600))
    #expect(QuickLinkFrame(minY: 10, maxY: 5).maxY == 10)
}

// MARK: - Natural active section

@Test func naturalActiveIsLastSectionPastTheActivationLine() {
    let f = frames([("a", -500, 300), ("b", -200, 200), ("c", 10, 300), ("d", 400, 300)])
    #expect(QuickLinks.naturalActive(sections: sections, frames: f) == "c")
    #expect(QuickLinks.naturalActive(sections: sections, frames: f, activationOffset: 0) == "b")
}

@Test func naturalActiveDefaultsToFirstAndSkipsUnbuiltSections() {
    #expect(QuickLinks.naturalActive(sections: [], frames: [:]) == nil)
    #expect(QuickLinks.naturalActive(sections: sections, frames: [:]) == "a")
    let f = frames([("a", 50, 300)])
    #expect(QuickLinks.naturalActive(sections: sections, frames: f) == "a")
    // Lazy container: a and b not built, c scrolled past the line.
    let lazy = frames([("c", -40, 400), ("d", 500, 300)])
    #expect(QuickLinks.naturalActive(sections: sections, frames: lazy) == "c")
}

// MARK: - Jump tracker

@Test func idleTrackerFollowsScrollPosition() {
    var tracker = QuickLinkTracker()
    tracker.update(sections: sections, frames: frames([("a", -300, 200), ("b", -100, 400)]), viewportHeight: 600)
    #expect(tracker.activeID == "b")
    #expect(tracker.phase == .idle)
}

@Test func jumpMarksTargetActiveWhileScrollingEvenIfNotBuilt() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "d")
    #expect(tracker.activeID == "d")
    tracker.update(sections: sections, frames: frames([("a", 0, 300)]), viewportHeight: 600)
    #expect(tracker.activeID == "d")
    #expect(tracker.phase == .scrolling(target: "d"))
}

@Test func jumpReleasesWhenPageRemovesTheTarget() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "z")
    tracker.update(sections: sections, frames: frames([("a", 0, 300)]), viewportHeight: 600)
    #expect(tracker.activeID == "a")
    #expect(tracker.phase == .idle)
}

@Test func settledJumpOwnsUntilTheReaderScrollsAway() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "b")
    let landed = frames([("a", -300, 300), ("b", 0, 300), ("c", 300, 300)])
    tracker.settle(sections: sections, frames: landed, viewportHeight: 600)
    #expect(tracker.phase == .owned(target: "b", anchorMinY: 0, lockWhileVisible: false))
    // Small drift back up keeps the target (reachable band), though "a" is natural.
    tracker.update(sections: sections, frames: frames([("a", -250, 300), ("b", 50, 300)]), viewportHeight: 600)
    #expect(tracker.activeID == "b")
    // Scrolling well past the band releases to the natural section.
    tracker.update(sections: sections, frames: frames([("b", -400, 300), ("c", -100, 300)]), viewportHeight: 600)
    #expect(tracker.activeID == "c")
    #expect(tracker.phase == .idle)
}

@Test func settledJumpNearTheEndLocksWhileVisible() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "d")
    // "d" is short and at the very end: it could only scroll to 350.
    let landed = frames([("c", -50, 400), ("d", 350, 200)])
    tracker.settle(sections: sections, frames: landed, viewportHeight: 600)
    #expect(tracker.phase == .owned(target: "d", anchorMinY: 350, lockWhileVisible: true))
    tracker.update(sections: sections, frames: frames([("c", 100, 400), ("d", 500, 200)]), viewportHeight: 600)
    #expect(tracker.activeID == "d")
    tracker.update(sections: sections, frames: frames([("b", 0, 400), ("d", 700, 200)]), viewportHeight: 600)
    #expect(tracker.activeID == "b")
    #expect(tracker.phase == .idle)
}

@Test func settleFallsBackWhenTargetIsOffScreenOrMissing() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "c")
    // The reader dragged mid-animation; the target never arrived.
    tracker.settle(sections: sections, frames: frames([("a", -10, 300), ("c", 900, 300)]), viewportHeight: 600)
    #expect(tracker.phase == .idle)
    #expect(tracker.activeID == "a")
    // Settling without a jump is a no-op.
    tracker.settle(sections: sections, frames: [:], viewportHeight: 600)
    #expect(tracker.phase == .idle)
}

@Test func ownedTargetReleasesWhenFrameDisappears() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "b")
    tracker.settle(sections: sections, frames: frames([("b", 0, 300)]), viewportHeight: 600)
    tracker.update(sections: sections, frames: frames([("a", 0, 300)]), viewportHeight: 600)
    #expect(tracker.activeID == "a")
    #expect(tracker.phase == .idle)
}

@Test func ownedTargetHoldsAtAnchorEvenOutsideReachableBand() {
    var tracker = QuickLinkTracker()
    tracker.beginJump(to: "b")
    // Activation offset 0 with a target that landed exactly on its anchor.
    tracker.settle(sections: sections, frames: frames([("a", -600, 400), ("b", 0, 900)]), viewportHeight: 600, activationOffset: 0)
    tracker.update(sections: sections, frames: frames([("b", 4, 900)]), viewportHeight: 600, activationOffset: 0)
    #expect(tracker.activeID == "b")
}
