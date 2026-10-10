import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Fling pass (issue #553)

/// The scripted fling pass and its frame tally (`apple_perf.py --fling`).
struct ScrollFlingStressTests {
    @Test func flingStepMovesAndDecelerates() {
        let step = ScrollFlingStress.step(offset: 100, velocity: 5000, seconds: 0.01, range: 0...10_000)
        #expect(abs(step.offset - 150) < 0.001)
        #expect(step.velocity > 4000 && step.velocity < 5000)
        #expect(!step.done)
    }

    @Test func flingStepStopsAtTheEndsAndWhenSlow() {
        let bottom = ScrollFlingStress.step(offset: 9_990, velocity: 5000, seconds: 0.01, range: 0...10_000)
        #expect(bottom.offset == 10_000)
        #expect(bottom.done && bottom.velocity == 0)
        let top = ScrollFlingStress.step(offset: 10, velocity: -5000, seconds: 0.01, range: 0...10_000)
        #expect(top.offset == 0)
        #expect(top.done)
        let slow = ScrollFlingStress.step(offset: 500, velocity: 200, seconds: 0.01, range: 0...10_000)
        #expect(slow.done)
    }

    @Test func flingStepRejectsInvalidReadings() {
        for seconds in [0, -1, Double.nan] {
            let step = ScrollFlingStress.step(offset: 40, velocity: 5000, seconds: seconds, range: 0...100)
            #expect(step.offset == 40 && step.velocity == 0 && step.done)
        }
    }

    @Test func tallyCountsLateFramesAndBudgets() {
        var tally = FrameBudgetTally()
        let target = FrameBudgetTally.standardBudgetMs
        tally.record(intervalMs: target, targetMs: target, workMs: 4)
        tally.record(intervalMs: target, targetMs: target, workMs: 10)
        tally.record(intervalMs: target * 3, targetMs: target, workMs: 40)
        tally.record(intervalMs: .nan, targetMs: target, workMs: 1)
        #expect(tally.frames == 3)
        #expect(tally.late == 1)
        #expect(abs(tally.hitchMs - target * 2) < 0.001)
        #expect(tally.overPromotion == 2)
        #expect(tally.overStandard == 1)
        #expect(tally.worstWorkMs == 40)
        #expect(abs(tally.meanWorkMs - 18) < 0.001)
        #expect(abs(tally.hitchRatio - target * 2 / (target * 5 / 1000)) < 0.001)
        #expect(tally.summary["fling.over8ms"] == 2)
        #expect(tally.summary["fling.frames"] == 3)
    }

    @Test func emptyTallyReportsZeros() {
        let tally = FrameBudgetTally()
        #expect(tally.hitchRatio == 0)
        #expect(tally.meanWorkMs == 0)
    }
}

// MARK: - Per-frame observers (issue #553)

/// Scroll-driven inputs only rows near an edge (or regions not yet built) observe.
@MainActor
struct ScrollObserverScopeTests {
    @Test func rowMaskDepthReadsTheLimitOnlyNearTheEdge() {
        var reads = 0
        let limit: () -> CGFloat? = { reads += 1; return 4 }
        #expect(PinnedHeaderEdgeFade.rowMaskDepth(near: false, fade: 40, limit: limit) == 40)
        #expect(reads == 0)
        #expect(PinnedHeaderEdgeFade.rowMaskDepth(near: true, fade: 40, limit: limit)
            == PinnedHeaderEdgeFade.depth(scrollOffset: 4, fade: 40))
        #expect(reads == 1)
        #expect(PinnedHeaderEdgeFade.rowMaskDepth(near: true, fade: 40, limit: { nil }) == 40)
    }

    /// Records whether an observation fired.
    private final class ObserverFlag: @unchecked Sendable {
        var value = false
    }

    @Test func rowEdgeNeverObservesTheMovingLimit() {
        let chrome = SongsScrollChrome()
        _ = chrome.setScrolled(true)
        chrome.setBarMetrics(top: 170, height: 28)
        chrome.setFadeLimit("A", limit: 6)
        #expect(chrome.rowEdge(enabled: true) == .init(edge: 198, active: true, depthLimit: nil))
        let fired = ObserverFlag()
        withObservationTracking { _ = chrome.rowEdge(enabled: true) } onChange: { fired.value = true }
        chrome.setFadeLimit("A", limit: 2)
        #expect(!fired.value)
        chrome.setBarMetrics(top: 180, height: 28)
        #expect(fired.value)
        #expect(chrome.rowEdge(enabled: false) == .inactive)
    }

    @Test func rowEdgeAtTheTopIsInactive() {
        let chrome = SongsScrollChrome()
        chrome.setBarMetrics(top: 170, height: 28)
        #expect(chrome.rowEdge(enabled: true) == .inactive)
    }

    @Test func nearViewportLatchesWithinReach() {
        typealias Region = NearViewport<EmptyView, EmptyView>
        let reach = Region.reach
        #expect(Region.isNear(CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(Region.isNear(CGRect(x: 0, y: reach - 1, width: 10, height: 10)))
        #expect(!Region.isNear(CGRect(x: 0, y: reach, width: 10, height: 10)))
        #expect(!Region.isNear(CGRect(x: 0, y: -reach - 20, width: 10, height: 10)))
        #expect(Region.isNear(CGRect(x: 0, y: -reach - 20, width: 10, height: 40)))
    }
}
