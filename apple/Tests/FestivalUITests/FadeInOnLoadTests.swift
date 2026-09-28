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
    #expect(FestivalFadeIn.delay(forIndex: 0) == 0)
    #expect(FestivalFadeIn.delay(forIndex: 1) == 0.125)
    #expect(FestivalFadeIn.delay(forIndex: 4) == 0.5)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems - 1) != nil)
    #expect(FestivalFadeIn.delay(forIndex: FestivalFadeIn.maxStaggeredItems) == nil)
    #expect(FestivalFadeIn.delay(forIndex: -1) == nil)
    #expect(FestivalFadeIn.delay(forIndex: 3, maxStaggered: 3) == nil)
}

@Test func fadeInCompletionDelayMatchesWebFormula() {
    #expect(FestivalFadeIn.completionDelay(itemCount: 0) == 0)
    #expect(FestivalFadeIn.completionDelay(itemCount: 1) == 0.4)
    #expect(abs(FestivalFadeIn.completionDelay(itemCount: 3) - 0.65) < 1e-9)
    // Items past the cap appear instantly, so they add no time.
    let capped = FestivalFadeIn.completionDelay(itemCount: 100)
    #expect(abs(capped - (Double(FestivalFadeIn.maxStaggeredItems - 1) * 0.125 + 0.4)) < 1e-9)
}
