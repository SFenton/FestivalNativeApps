import Foundation

// MARK: - Manual clock

/// A `Clock` that only moves when a test calls `advance(by:)`.
///
/// Countdown and dwell tests inject it instead of `ContinuousClock` so their
/// assertions follow clock time the test controls. Hosted snapshot tests share
/// one main actor, and a busy suite can delay a real one-second sleep by many
/// seconds; with this clock a slow host only makes a test take longer, never
/// changes what it observes.
final class ManualTestClock: Clock, @unchecked Sendable {
    /// Offset from the clock's creation, which is `.zero`.
    struct Instant: InstantProtocol {
        /// Clock time elapsed since creation.
        let offset: Duration

        /// Move this instant by a duration.
        ///
        /// - Parameter duration: Amount to move.
        /// - Returns: The shifted instant.
        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        /// Measure the time from this instant to another.
        ///
        /// - Parameter other: Later (or earlier) instant.
        /// - Returns: Signed duration between the two.
        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var waiters: [Waiter] = []

    var now: Instant { lock.withLock { current } }

    var minimumResolution: Duration { .zero }

    // MARK: - Clock

    /// Suspend until a test advances the clock to `deadline`, or until cancelled.
    ///
    /// - Parameters:
    ///   - deadline: Clock instant to wait for; returns at once if already reached.
    ///   - tolerance: Ignored.
    /// - Throws: `CancellationError` when the sleeping task is cancelled.
    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let (outcome, ready): (Result<Void, any Error>?, [Waiter]) = lock.withLock {
                    if Task.isCancelled { return (.failure(CancellationError()), []) }
                    if deadline <= current { return (.success(()), []) }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return (nil, takeSatisfiedWaiters())
                }
                ready.forEach { $0.continuation.resume() }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: - Test control

    /// Move the clock forward and wake every sleeper whose deadline has passed.
    ///
    /// - Parameter duration: Non-negative amount of clock time to add.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Wait, without any wall-clock deadline, until at least `count` tasks sleep.
    ///
    /// - Parameter count: Number of pending sleepers to wait for.
    /// - Returns: Every pending sleeper's deadline, earliest first.
    @discardableResult
    func sleepers(atLeast count: Int) async -> [Instant] {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = lock.withLock {
                if sleepers.count >= count { return true }
                waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
        return pendingDeadlines
    }

    /// Deadlines of tasks currently sleeping on this clock, earliest first.
    var pendingDeadlines: [Instant] {
        lock.withLock { sleepers.map(\.deadline).sorted() }
    }

    /// Remove waiters satisfied by the current sleeper count; call with the lock held.
    ///
    /// - Returns: Waiters to resume after the lock is released.
    private func takeSatisfiedWaiters() -> [Waiter] {
        let ready = waiters.filter { $0.count <= sleepers.count }
        waiters.removeAll { $0.count <= sleepers.count }
        return ready
    }
}
