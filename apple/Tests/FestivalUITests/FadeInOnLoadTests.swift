import Foundation
import Testing
@testable import FestivalUI

// MARK: - FestivalFadeIn timing

/// Pins the web `fadeInUp` timing port (`FADE_DURATION` 400 ms, `STAGGER_INTERVAL` 125 ms,
/// 12 px rise, first-screen cap) behind `festivalFadeIn(isLoaded:index:)`.
@Test func fadeInMatchesWebConstants() {
    #expect(FestivalFadeIn.duration == 0.4)
    #expect(FestivalFadeIn.staggerInterval == 0.125)
    #expect(FestivalFadeIn.riseDistance == 12)
}

@Test func fadeInStaggerDelaysFirstScreenOnly() {
    // Web `staggerDelay`: (index + 1) × 125 ms.
    #expect(FestivalFadeIn.delay(forIndex: 0) == 0.125)
    #expect(FestivalFadeIn.delay(forIndex: 1) == 0.25)
    #expect(FestivalFadeIn.delay(forIndex: 4) == 0.625)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems - 1) != nil)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems) == nil)
    #expect(FestivalFadeIn.delay(forIndex: -1) == nil)
    #expect(FestivalFadeIn.delay(forIndex: 3, maxStaggered: 3) == nil)
}

@Test func fadeInCompletionDelayCoversTheLastStaggeredItem() {
    #expect(FestivalFadeIn.completionDelay(itemCount: 0) == 0)
    #expect(abs(FestivalFadeIn.completionDelay(itemCount: 1) - 0.525) < 1e-9)
    #expect(abs(FestivalFadeIn.completionDelay(itemCount: 3) - 0.775) < 1e-9)
    // Items past the cap appear instantly, so they add no time.
    let capped = FestivalFadeIn.completionDelay(itemCount: 100)
    #expect(abs(capped - (Double(FestivalFadeIn.maxStaggeredItems) * 0.125 + 0.4)) < 1e-9)
}

// MARK: - Page scope (issue #30)

/// Only content on screen at page load fades: the scope closes once the content moves.
@MainActor
@Test func fadeScopeStaysOpenUntilTheContentScrolls() {
    let scope = FestivalFadeInScope()
    #expect(scope.isOpen)
    scope.noteContentOffset(0)
    // Sub-threshold layout jitter does not count as a scroll.
    scope.noteContentOffset(FestivalFadeInScope.scrollThreshold)
    scope.noteContentOffset(-FestivalFadeInScope.scrollThreshold)
    #expect(scope.isOpen)
    scope.noteContentOffset(-40)
    #expect(!scope.isOpen)
    // Scrolling back to the resting position never reopens it.
    scope.noteContentOffset(0)
    #expect(!scope.isOpen)
}

@MainActor
@Test func fadeScopeMeasuresFromTheFirstReportedOffset() {
    let scope = FestivalFadeInScope()
    // A non-zero resting offset (content below a bar) is the baseline, not a scroll.
    scope.noteContentOffset(116)
    scope.noteContentOffset(118)
    #expect(scope.isOpen)
    // Pulling down (rubber band / refresh) also counts.
    scope.noteContentOffset(160)
    #expect(!scope.isOpen)
}

@MainActor
@Test func fadeScopeIgnoresNonFiniteOffsetsAndClosesExplicitly() {
    let scope = FestivalFadeInScope()
    scope.noteContentOffset(.nan)
    scope.noteContentOffset(.infinity)
    scope.noteContentOffset(10)
    #expect(scope.isOpen)
    scope.close()
    #expect(!scope.isOpen)
}

// MARK: - Settled stagger and appending feeds

@Test func fadeStaggerPassesNoIndexOnceSettled() {
    #expect(FadeStagger.index(3, settled: false) == 3)
    #expect(FadeStagger.index(3, settled: true) == -1)
    #expect(FestivalFadeIn.delay(forIndex: FadeStagger.index(0, settled: true)) == nil)
}

@Test func fadeBatchIndexesStaggerOnlyTheNewestBatchInDisplayOrder() {
    let order = ["a", "b", "c", "d", "e"]
    // Earlier pages (a, b) never fade; the new page staggers from 0 in display order,
    // skipping items a filter hides (c is filtered out of `order` here by omission).
    let indexes = FadeStagger.batchIndexes(
        order: order.filter { $0 != "c" }, batch: ["c", "d", "e"], settled: false
    )
    #expect(indexes == ["d": 0, "e": 1])
    #expect(indexes["a"] == nil)
    // Once the batch has settled, rows rebuilt by scrolling appear without a fade.
    #expect(FadeStagger.batchIndexes(order: order, batch: ["d", "e"], settled: true).isEmpty)
    // Duplicate IDs keep their first position.
    #expect(FadeStagger.batchIndexes(order: ["x", "x", "y"], batch: ["x", "y"], settled: false) == ["x": 0, "y": 1])
}
