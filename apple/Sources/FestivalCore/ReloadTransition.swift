import Foundation

// MARK: - Page reload transition

/// The app-wide load and reload sequence for a page's content area (issue #71), ported
/// from the web's `useLoadPhase` / `LoadGate` (`hooks/data/useLoadPhase.ts`,
/// `components/page/LoadGate.tsx`):
///
/// 1. **Content out:** when the selection changes (instrument, metric, filter, sort, mode,
///    page) or a refetch starts, the shown content leaves at once, like the web's `Page`,
///    which renders no content outside `ContentIn`, and the spinner fades in (web
///    `QUICK_FADE_MS`, 150 ms). Content is never faded out, because lazily built rows
///    read the live selection: a fading copy showed the old rows with the newly
///    chosen metric or instrument.
/// 2. **Spinner:** the spinner stays until the new data is ready, and at least
///    ``Timing/minimumSpinner`` (web `MIN_SPINNER_MS`, 400 ms) so it never blinks.
/// 3. **Spinner out:** the spinner fades out (web `SPINNER_FADE_MS`, 500 ms).
/// 4. **Content in:** the new content is rebuilt (``generation`` changes) so its web
///    `fadeInUp` stagger plays again.
///
/// A newer selection at any point restarts from the spinner without ever showing the stale
/// content again; selectors stay usable throughout. This is a pure value type: the view
/// applies ``phase`` and runs the wait named by ``pendingWait``, then calls
/// ``timerFired(_:)``.
public struct ReloadTransition: Equatable, Sendable {
    /// What the content area shows.
    public enum Phase: Equatable, Sendable {
        /// The loaded content (or its empty/error state).
        case content
        /// The spinner, fading in or holding while data loads.
        case spinner
        /// The spinner fading out before the new content fades in.
        case spinnerOut
    }

    /// A timed step the view must wait for before calling ``timerFired(_:)``.
    public enum Wait: Equatable, Sendable {
        /// The spinner's minimum time on screen.
        case minimumSpinner
        /// The spinner's fade-out.
        case spinnerOut
    }

    /// Fade and hold durations for one page.
    public struct Timing: Equatable, Sendable {
        /// Spinner fade-in after the old content leaves; zero swaps instantly.
        public let spinnerIn: Duration
        /// Shortest time the spinner stays before it may fade out.
        public let minimumSpinner: Duration
        /// Spinner fade-out before the new content appears; zero swaps instantly.
        public let spinnerOut: Duration

        /// - Parameters:
        ///   - spinnerIn: Spinner fade-in; zero swaps instantly.
        ///   - minimumSpinner: Shortest spinner time.
        ///   - spinnerOut: Spinner fade-out; zero swaps instantly.
        public init(spinnerIn: Duration, minimumSpinner: Duration, spinnerOut: Duration) {
            self.spinnerIn = spinnerIn
            self.minimumSpinner = minimumSpinner
            self.spinnerOut = spinnerOut
        }

        /// Web `QUICK_FADE_MS`.
        public static let spinnerInDuration: Duration = .milliseconds(150)
        /// Web `MIN_SPINNER_MS`: the spinner never blinks.
        public static let minimumSpinnerDuration: Duration = .milliseconds(400)
        /// Web `SPINNER_FADE_MS`.
        public static let spinnerOutDuration: Duration = .milliseconds(500)

        /// The page timing.
        ///
        /// With Reduce Motion every fade is an instant swap and the spinner keeps its
        /// 400 ms minimum (HIG Accessibility: "Be cautious with fast-moving and blinking
        /// effects").
        ///
        /// - Parameter reduceMotion: System or in-app Reduce Motion.
        /// - Returns: The durations to use.
        public static func standard(reduceMotion: Bool) -> Timing {
            reduceMotion
                ? Timing(spinnerIn: .zero, minimumSpinner: minimumSpinnerDuration, spinnerOut: .zero)
                : Timing(spinnerIn: spinnerInDuration, minimumSpinner: minimumSpinnerDuration,
                         spinnerOut: spinnerOutDuration)
        }

        /// The wait for `wait`.
        ///
        /// - Parameter wait: The pending step.
        /// - Returns: How long to wait before calling ``ReloadTransition/timerFired(_:)``.
        public func duration(of wait: Wait) -> Duration {
            switch wait {
            case .minimumSpinner: minimumSpinner
            case .spinnerOut: spinnerOut
            }
        }
    }

    /// What the content area shows now.
    public private(set) var phase: Phase
    /// Bumps every time content is shown anew; use it as the content's identity so its
    /// load-in fade plays again after a reload.
    public private(set) var generation: Int
    /// Whether the page's data is still loading.
    public private(set) var isLoading: Bool
    /// Whether the spinner has been up for its minimum time.
    private var spinnerHeld: Bool

    /// Start a page.
    ///
    /// - Parameter isLoading: Whether the data is still loading; when it is, the page
    ///   starts on the spinner, otherwise on its content.
    public init(isLoading: Bool) {
        phase = isLoading ? .spinner : .content
        generation = 0
        self.isLoading = isLoading
        spinnerHeld = false
    }

    /// Whether the content is on screen.
    public var showsContent: Bool { phase == .content }

    /// Whether the spinner is on screen (it is removed, fading, during ``Phase/spinnerOut``).
    public var showsSpinner: Bool { phase == .spinner }

    /// The timed step the view should run now, if any.
    public var pendingWait: Wait? {
        switch phase {
        case .content: nil
        case .spinner: spinnerHeld ? nil : .minimumSpinner
        case .spinnerOut: .spinnerOut
        }
    }

    /// The selection changed: hide the content and show the spinner until the new data
    /// is ready. A reload while the spinner is fading out brings it back.
    public mutating func reload() {
        switch phase {
        case .content, .spinnerOut:
            phase = .spinner
            spinnerHeld = false
        case .spinner:
            break
        }
    }

    /// Record whether the data is loading. Loading that starts while content is shown is
    /// a reload; loading that ends lets a held spinner fade out.
    ///
    /// - Parameter loading: Whether the page's data is loading.
    public mutating func setLoading(_ loading: Bool) {
        isLoading = loading
        if loading {
            if phase != .spinner { reload() }
        } else if phase == .spinner, spinnerHeld {
            phase = .spinnerOut
        }
    }

    /// A wait from ``pendingWait`` finished. Stale waits (the phase moved on) are ignored.
    ///
    /// - Parameter wait: The wait that finished.
    public mutating func timerFired(_ wait: Wait) {
        switch (wait, phase) {
        case (.minimumSpinner, .spinner):
            spinnerHeld = true
            if !isLoading { phase = .spinnerOut }
        case (.spinnerOut, .spinnerOut):
            phase = .content
            generation += 1
        default:
            break
        }
    }
}
