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

    @Test("Overflow needs both measurements and more than one point of excess")
    func overflowRule() {
        #expect(!MarqueeTiming.overflows(textWidth: 200, available: 0))
        #expect(!MarqueeTiming.overflows(textWidth: 100.5, available: 100))
        #expect(!MarqueeTiming.overflows(textWidth: 101, available: 100))
        #expect(MarqueeTiming.overflows(textWidth: 101.5, available: 100))
    }

    @Test("Distance is one copy plus the gap, widened by a longer sync distance")
    func distanceRule() {
        #expect(MarqueeTiming.distance(textWidth: 120.4, gap: 28, syncDistance: nil) == 148)
        #expect(MarqueeTiming.distance(textWidth: 120, gap: 28, syncDistance: 200) == 200)
        #expect(MarqueeTiming.distance(textWidth: 120, gap: 28, syncDistance: 100) == 148)
    }

    @Test("Sync groups share widest + gap only when two or more overflow")
    func syncRule() {
        #expect(MarqueeTiming.syncDistance(widths: [], gap: 28) == nil)
        #expect(MarqueeTiming.syncDistance(widths: [300], gap: 28) == nil)
        #expect(MarqueeTiming.syncDistance(widths: [300, 0], gap: 28) == nil)
        #expect(MarqueeTiming.syncDistance(widths: [300, 250], gap: 28) == 328)
    }

    @Test("One loop is exactly the cycle: two dwells plus the scroll")
    func loopLength() {
        let cycle = 8.0
        let dwell = MarqueeTiming.dwellDuration(cycleDuration: cycle)
        let scroll = MarqueeTiming.scrollDuration(cycleDuration: cycle)
        #expect(abs(dwell - 0.4) < 1e-9 && abs(scroll - 7.2) < 1e-9)
        #expect(abs(2 * dwell + scroll - cycle) < 1e-9)
        #expect(MarqueeTiming.scrollDuration(cycleDuration: -1) == 0)
    }
}
