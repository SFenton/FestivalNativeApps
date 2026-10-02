import Foundation
import Testing
@testable import FestivalCore

/// A clock whose sleeps return at once, advancing time and recording each requested
/// duration, so the sequence's timing can be asserted without waiting.
private final class RecordingClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var recorded: [Duration] = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }
    var sleeps: [Duration] { lock.withLock { recorded } }

    /// Simulate time passing outside a sleep (for example a slow fetch).
    func advance(by duration: Duration) {
        lock.withLock { current = current.advanced(by: duration) }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        lock.withLock {
            recorded.append(current.duration(to: deadline))
            if current < deadline { current = deadline }
        }
    }
}

private typealias Step = PathSwitchTransition.Step<String>

@Test func pathSwitchTimingMatchesWebAndReduceMotionSwapsInstantly() {
    #expect(PathSwitchTransition.timing(for: .image, reduceMotion: false)
        == .init(fade: .milliseconds(300), minimumSpinner: .milliseconds(400)))
    #expect(PathSwitchTransition.timing(for: .text, reduceMotion: false)
        == .init(fade: .milliseconds(300), minimumSpinner: .milliseconds(500)))
    #expect(PathSwitchTransition.timing(for: .image, reduceMotion: true)
        == .init(fade: .zero, minimumSpinner: .milliseconds(400)))
    #expect(PathSwitchTransition.timing(for: .text, reduceMotion: true)
        == .init(fade: .zero, minimumSpinner: .milliseconds(500)))
    #expect(PathSwitchTransition.timing(for: .image, reduceMotion: false).fadeSeconds == 0.3)
    #expect(PathSwitchTransition.timing(for: .text, reduceMotion: true).fadeSeconds == 0)
}

@Test @MainActor func pathSwitchFadesOldContentThenSpinnerThenNewContent() async throws {
    let clock = RecordingClock()
    var steps: [Step] = []
    try await PathSwitchTransition.run(
        timing: PathSwitchTransition.timing(for: .image, reduceMotion: false),
        contentShown: true, clock: clock, load: { "Hard" }, apply: { steps.append($0) }
    )
    #expect(steps == [.hideContent, .showSpinner, .hideSpinner, .showContent("Hard")])
    // Fade out, the full minimum spinner (the fetch was instant), spinner fade out.
    #expect(clock.sleeps == [.milliseconds(300), .milliseconds(400), .milliseconds(300)])
}

@Test @MainActor func pathSwitchWithoutContentStartsAtTheSpinnerAndHoldsTextLonger() async throws {
    let clock = RecordingClock()
    var steps: [Step] = []
    try await PathSwitchTransition.run(
        timing: PathSwitchTransition.timing(for: .text, reduceMotion: false),
        contentShown: false, clock: clock, load: { "Table" }, apply: { steps.append($0) }
    )
    #expect(steps == [.showSpinner, .hideSpinner, .showContent("Table")])
    #expect(clock.sleeps == [.milliseconds(500), .milliseconds(300)])
}

@Test @MainActor func pathSwitchSlowFetchSkipsTheMinimumSpinnerWait() async throws {
    let clock = RecordingClock()
    var steps: [Step] = []
    try await PathSwitchTransition.run(
        timing: PathSwitchTransition.timing(for: .image, reduceMotion: false),
        contentShown: false, clock: clock,
        load: {
            clock.advance(by: .seconds(1))
            return "Expert"
        },
        apply: { steps.append($0) }
    )
    #expect(steps == [.showSpinner, .hideSpinner, .showContent("Expert")])
    #expect(clock.sleeps == [.milliseconds(300)])
}

@Test @MainActor func pathSwitchWithReduceMotionOnlyHoldsTheSpinner() async throws {
    let clock = RecordingClock()
    var steps: [Step] = []
    try await PathSwitchTransition.run(
        timing: PathSwitchTransition.timing(for: .text, reduceMotion: true),
        contentShown: true, clock: clock, load: { "Table" }, apply: { steps.append($0) }
    )
    #expect(steps == [.hideContent, .showSpinner, .hideSpinner, .showContent("Table")])
    #expect(clock.sleeps == [.milliseconds(500)])
}

/// Steps applied by a run that is cancelled (as a newer selection would) at one step.
@MainActor private final class StepLog {
    var steps: [Step] = []
}

/// Run one switch in its own task and cancel that task when `cancelAt` is applied.
///
/// - Returns: The steps applied and whether the run ended with `CancellationError`.
@MainActor private func runCancelled(
    at cancelAt: Step, contentShown: Bool, display: PathDisplayMode, reduceMotion: Bool
) async -> (steps: [Step], cancelled: Bool) {
    let log = StepLog()
    let task = Task { @MainActor in
        try await PathSwitchTransition.run(
            timing: PathSwitchTransition.timing(for: display, reduceMotion: reduceMotion),
            contentShown: contentShown, clock: RecordingClock(), load: { "Stale" },
            apply: { step in
                log.steps.append(step)
                if step == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
            }
        )
    }
    let result = await task.result
    if case let .failure(error) = result, error is CancellationError {
        return (log.steps, true)
    }
    return (log.steps, false)
}

@Test @MainActor func pathSwitchCancelledByNewerSelectionNeverShowsStaleContent() async {
    let fading = await runCancelled(at: .hideContent, contentShown: true, display: .image, reduceMotion: false)
    #expect(fading.cancelled)
    #expect(fading.steps == [.hideContent])

    let loading = await runCancelled(at: .showSpinner, contentShown: false, display: .image, reduceMotion: true)
    #expect(loading.cancelled)
    #expect(loading.steps == [.showSpinner])

    let settling = await runCancelled(at: .hideSpinner, contentShown: false, display: .text, reduceMotion: false)
    #expect(settling.cancelled)
    #expect(settling.steps == [.showSpinner, .hideSpinner])
}

@Test @MainActor func pathSwitchFetchFailureStopsBeforeShowingContent() async {
    struct Failure: Error {}
    let clock = RecordingClock()
    var steps: [Step] = []
    await #expect(throws: Failure.self) {
        try await PathSwitchTransition.run(
            timing: PathSwitchTransition.timing(for: .image, reduceMotion: false),
            contentShown: false, clock: clock, load: { throw Failure() },
            apply: { steps.append($0) }
        )
    }
    #expect(steps == [.showSpinner])
}
