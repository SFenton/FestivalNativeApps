import Foundation

// MARK: - Songs scroll stress pass (Debug)

/// Debug-only in-app scroll stress pass for the Songs list (issue #8).
///
/// With `FST_DEBUG_SONGS_SCROLL_STRESS=1` the Songs list replays ``plan(groupCount:)``
/// once after it loads: animated jumps between the top and the first few sections, plus
/// longer trips down the list and back to the top. Paired with
/// ``MainThreadStallMonitor`` (`FST_DEBUG_STALL_LOG`) it measures main-thread stalls
/// without XCUITest, whose accessibility snapshots add their own main-thread work.
///
/// The jumps target section titles because List rows inside a section's `ForEach`
/// cannot be `scrollTo` targets.
enum SongsScrollStress {
    /// Environment key that starts the pass.
    static let environmentKey = "FST_DEBUG_SONGS_SCROLL_STRESS"
    /// ``MainThreadStallMonitor`` counter recorded when the pass starts.
    static let startCounter = "songs.stress.start"
    /// ``MainThreadStallMonitor`` counter recorded when the pass completes.
    static let endCounter = "songs.stress.end"
    /// Passes through the pattern.
    static let rounds = 6

    /// One animated jump.
    struct Step: Equatable {
        /// Index of the target section, in list order.
        let group: Int
        /// Seconds to wait before the next jump.
        let pause: Double
    }

    /// True when the launch environment asks for a pass.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// The jumps for a list with `groupCount` sections.
    ///
    /// Each round flicks to sections 1–3 and back to the top with shrinking pauses (the
    /// top-of-list chrome changes), then travels further down each round and returns
    /// to the top (a fling back to the top).
    ///
    /// - Parameter groupCount: Sections in the list.
    /// - Returns: The jumps in order; empty when the list has fewer than four sections.
    static func plan(groupCount: Int) -> [Step] {
        guard groupCount >= 4 else { return [] }
        let last = groupCount - 1
        return (0..<rounds).flatMap { round -> [Step] in
            let far = min(last, 10 + round * 2)
            return [
                Step(group: 1, pause: 0.5), Step(group: 0, pause: 0.5),
                Step(group: 2, pause: 0.4), Step(group: 0, pause: 0.4),
                Step(group: 1, pause: 0.3), Step(group: 0, pause: 0.3),
                Step(group: far, pause: 0.8), Step(group: 0, pause: 0.9),
                Step(group: 3, pause: 0.25), Step(group: 0, pause: 0.25),
            ]
        }
    }
}
