import Testing
@testable import FestivalUI

/// The Debug card-page scroll stress pass (issue #291 measurements).
struct PageScrollStressTests {
    @Test func planAlternatesBottomAndTopAndEndsAtTheTop() {
        let plan = PageScrollStress.plan()
        #expect(plan.count == PageScrollStress.rounds * 2)
        for pair in stride(from: 0, to: plan.count, by: 2) {
            #expect(plan[pair].edge == .bottom && plan[pair + 1].edge == .top)
        }
        #expect(plan.last?.edge == .top)
        #expect(plan.allSatisfy { $0.duration >= 0.6 && $0.pause > 0 })
    }

    @Test func planSpeedsUpEachRoundButNeverBelowItsFloor() {
        let durations = PageScrollStress.plan().enumerated()
            .filter { $0.offset % 2 == 0 }.map(\.element.duration)
        #expect(zip(durations, durations.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(durations.first == 1.6)
        #expect(durations.last == 0.6)
    }

    @Test func sharesTheMarksApplePerfReads() {
        #expect(PageScrollStress.startCounter == "songs.stress.start")
        #expect(PageScrollStress.endCounter == "songs.stress.end")
        #expect(PageScrollStress.environmentKey != SongsScrollStress.environmentKey)
    }
}
