import Testing
@testable import FestivalUI

/// Pure cycle-math coverage for ``MarqueeTiming``, the timing engine behind
/// ``MarqueeText``. Kept independent of any hosted SwiftUI render.
@Suite("MarqueeTiming")
struct MarqueeTimingTests {
    @Test("Holds at the start of the cycle through the dwell fraction")
    func holdsAtStart() {
        #expect(MarqueeTiming.progress(atPhase: 0) == 0)
        #expect(MarqueeTiming.progress(atPhase: 0.03) == 0)
        #expect(MarqueeTiming.progress(atPhase: MarqueeTiming.dwellFraction) == 0)
    }

    @Test("Holds at the end of the cycle through the dwell fraction")
    func holdsAtEnd() {
        #expect(MarqueeTiming.progress(atPhase: 1) == 1)
        #expect(MarqueeTiming.progress(atPhase: 0.97) == 1)
        #expect(MarqueeTiming.progress(atPhase: 1 - MarqueeTiming.dwellFraction) == 1)
    }

    @Test("Scrolls linearly between the two dwell plateaus")
    func scrollsLinearlyBetweenPlateaus() {
        let midpoint = MarqueeTiming.progress(atPhase: 0.5)
        #expect(abs(midpoint - 0.5) < 0.0001)
        let quarter = MarqueeTiming.progress(atPhase: 0.05 + 0.9 * 0.25)
        #expect(abs(quarter - 0.25) < 0.0001)
    }

    @Test("Phase wraps into 0..<1 for any elapsed time, including negative offsets")
    func phaseWrapsIntoUnitRange() {
        #expect(MarqueeTiming.phase(elapsed: 0, cycleDuration: 8) == 0)
        #expect(abs(MarqueeTiming.phase(elapsed: 4, cycleDuration: 8) - 0.5) < 0.0001)
        #expect(abs(MarqueeTiming.phase(elapsed: 8, cycleDuration: 8) - 0) < 0.0001)
        #expect(abs(MarqueeTiming.phase(elapsed: 20, cycleDuration: 8) - 0.5) < 0.0001)
        let negative = MarqueeTiming.phase(elapsed: -2, cycleDuration: 8)
        #expect(negative >= 0 && negative < 1)
        #expect(abs(negative - 0.75) < 0.0001)
    }

    @Test("A non-positive cycle duration never divides by zero or goes negative")
    func nonPositiveCycleDurationIsSafe() {
        #expect(MarqueeTiming.phase(elapsed: 42, cycleDuration: 0) == 0)
        #expect(MarqueeTiming.phase(elapsed: 42, cycleDuration: -1) == 0)
    }
}
