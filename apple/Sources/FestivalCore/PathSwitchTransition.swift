import Foundation

// MARK: - Paths switch transition

/// How the Paths sheet swaps one chart for another (issue #70), matching the web
/// `PathsModal` sequence: fade the old image or table out, fade a spinner in, hold it for
/// a minimum time, fade it out, then fade the new image or table in.
///
/// The fetch starts at once (during the fade-out). Cancelling the running task — a newer
/// instrument, difficulty or view choice — stops the sequence before it can show the
/// stale result. With Reduce Motion the fades are instant swaps; the spinner keeps its
/// minimum time so it never blinks.
public enum PathSwitchTransition {
    /// Web `FADE_MS`: content and spinner fade time.
    public static let fade: Duration = .milliseconds(300)

    /// Web `MIN_SPINNER_MS` (image) and `MIN_TEXT_SPINNER_MS` (text).
    ///
    /// - Parameter display: The view being loaded.
    /// - Returns: The shortest time the spinner stays up.
    public static func minimumSpinner(for display: PathDisplayMode) -> Duration {
        switch display {
        case .image: .milliseconds(400)
        case .text: .milliseconds(500)
        }
    }

    /// Fade and spinner times for one switch.
    public struct Timing: Equatable, Sendable {
        /// Each fade's duration; zero means an instant swap.
        public let fade: Duration
        /// The shortest time the spinner stays up.
        public let minimumSpinner: Duration

        /// ``fade`` in seconds, for SwiftUI animations; zero means no animation.
        public var fadeSeconds: Double {
            Double(fade.components.seconds) + Double(fade.components.attoseconds) / 1e18
        }

        /// - Parameters:
        ///   - fade: Each fade's duration; zero means an instant swap.
        ///   - minimumSpinner: The shortest time the spinner stays up.
        public init(fade: Duration, minimumSpinner: Duration) {
            self.fade = fade
            self.minimumSpinner = minimumSpinner
        }
    }

    /// Times for a switch to `display`.
    ///
    /// - Parameters:
    ///   - display: The view being loaded.
    ///   - reduceMotion: System Reduce Motion; swaps instantly instead of fading.
    /// - Returns: Fade and minimum spinner durations.
    public static func timing(for display: PathDisplayMode, reduceMotion: Bool) -> Timing {
        Timing(fade: reduceMotion ? .zero : fade, minimumSpinner: minimumSpinner(for: display))
    }

    /// One visible change in the sequence, applied by the view.
    public enum Step<Value> {
        /// Fade the current image, table or error out (and drop it).
        case hideContent
        /// Fade the spinner in.
        case showSpinner
        /// Fade the spinner out.
        case hideSpinner
        /// Fade the loaded result in.
        case showContent(Value)
    }

    /// Run one switch: hide the old content, show the spinner while `load` finishes (for at
    /// least `timing.minimumSpinner`), hide it and show the result.
    ///
    /// - Parameters:
    ///   - timing: Fade and spinner times (see ``timing(for:reduceMotion:)``).
    ///   - contentShown: Whether an image, table or error is on screen to fade out first.
    ///   - clock: Paces the fades and the minimum spinner time.
    ///   - load: Fetches the new content; starts immediately.
    ///   - apply: Performs each step, on the main actor, in order.
    /// - Throws: `CancellationError` when a newer selection cancels the task; nothing
    ///   further is applied after that. Rethrows any error `load` throws.
    @MainActor
    public static func run<Value: Sendable, C: Clock>(
        timing: Timing,
        contentShown: Bool,
        clock: C,
        load: @escaping @Sendable @MainActor () async throws -> Value,
        apply: (Step<Value>) -> Void
    ) async throws where C.Duration == Duration {
        async let pending = load()
        if contentShown {
            apply(.hideContent)
            try await pause(timing.fade, on: clock)
        }
        try Task.checkCancellation()
        apply(.showSpinner)
        let spinnerStart = clock.now
        let value = try await pending
        try Task.checkCancellation()
        try await pause(timing.minimumSpinner - spinnerStart.duration(to: clock.now), on: clock)
        apply(.hideSpinner)
        try await pause(timing.fade, on: clock)
        apply(.showContent(value))
    }

    /// Sleep for a positive duration; otherwise only honour cancellation.
    ///
    /// - Parameters:
    ///   - duration: Time to wait; zero or negative skips the sleep.
    ///   - clock: The clock to sleep on.
    /// - Throws: `CancellationError` when the task is cancelled.
    private static func pause<C: Clock>(_ duration: Duration, on clock: C) async throws
    where C.Duration == Duration {
        if duration > .zero {
            try await clock.sleep(for: duration)
        }
        try Task.checkCancellation()
    }
}

extension PathSwitchTransition.Step: Equatable where Value: Equatable {}
extension PathSwitchTransition.Step: Sendable where Value: Sendable {}
