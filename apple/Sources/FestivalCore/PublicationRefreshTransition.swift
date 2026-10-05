import Foundation

// MARK: - Publication refresh transition (issue #304)

/// The in-place refresh of one page when the service publishes a new generation, ported
/// from the web's `PublicationBoundary` (which remounts the app under the same route)
/// combined with its load phases (`useLoadPhase`, load-transition R3):
///
/// 1. **Content out:** the page's content fades out (web `CONTENT_OUT_MS`, 300 ms). It is
///    already inert and hidden from VoiceOver, and stays mounted so the page's title and
///    toolbar stay put; it is never shown again.
/// 2. **Spinner:** fades in (web `QUICK_FADE_MS`, 150 ms) and holds at least
///    ``ReloadTransition/Timing/minimumSpinnerDuration`` (400 ms) and until the page has
///    **prepared** for the new generation (for example, re-read a song from the new
///    catalogue). Preparation starts only once the content is hidden, so a fading page
///    never draws new data and old and new data are never mixed.
/// 3. **Spinner out:** the spinner fades out (web `SPINNER_FADE_MS`, 500 ms).
/// 4. **Content in:** the page is rebuilt (``generation`` changes) and fades in; the
///    rebuilt page then loads its own data with its own load fade.
///
/// A newer generation at any point keeps the content hidden and waits for the newer
/// preparation (during spinner-out the spinner comes back). This is a pure value type: the
/// view applies ``phase``, runs the wait named by ``pendingWait`` for
/// ``Timing/duration(of:)`` and the preparation named by ``preparationRevision``, then
/// reports back with ``timerFired(_:)`` and ``prepared(revision:)``.
public struct PublicationRefreshTransition: Equatable, Sendable {
    /// What the page shows.
    public enum Phase: Equatable, Sendable {
        /// The page content.
        case content
        /// The old content fading out; inert and hidden from VoiceOver.
        case contentOut
        /// The spinner over hidden content, fading in or holding while the page prepares.
        case spinner
        /// The spinner fading out before the rebuilt content fades in.
        case spinnerOut
    }

    /// A timed step the view must wait for before calling ``timerFired(_:)``.
    public enum Wait: Equatable, Sendable {
        /// The old content's fade-out.
        case contentOut
        /// The spinner's minimum time on screen.
        case minimumSpinner
        /// The spinner's fade-out.
        case spinnerOut
    }

    /// Fade and hold durations for a publication refresh (load-transition R3).
    public struct Timing: Equatable, Sendable {
        /// Old content fade-out; zero swaps instantly.
        public let contentOut: Duration
        /// Spinner fade-in; zero swaps instantly.
        public let spinnerIn: Duration
        /// Shortest time the spinner stays.
        public let minimumSpinner: Duration
        /// Spinner fade-out; zero swaps instantly.
        public let spinnerOut: Duration

        /// - Parameters:
        ///   - contentOut: Old content fade-out.
        ///   - spinnerIn: Spinner fade-in.
        ///   - minimumSpinner: Shortest spinner time.
        ///   - spinnerOut: Spinner fade-out.
        public init(contentOut: Duration, spinnerIn: Duration, minimumSpinner: Duration, spinnerOut: Duration) {
            self.contentOut = contentOut
            self.spinnerIn = spinnerIn
            self.minimumSpinner = minimumSpinner
            self.spinnerOut = spinnerOut
        }

        /// The page timing: web 300 ms content-out, 150 ms spinner-in, 400 ms minimum
        /// spinner and 500 ms spinner-out. With Reduce Motion every fade is an instant
        /// swap and the spinner keeps its 400 ms minimum so it never blinks (HIG
        /// Accessibility: "Be cautious with fast-moving and blinking effects").
        ///
        /// - Parameter reduceMotion: System or in-app Reduce Motion.
        /// - Returns: The durations to use.
        public static func standard(reduceMotion: Bool) -> Timing {
            let reload = ReloadTransition.Timing.self
            return reduceMotion
                ? Timing(contentOut: .zero, spinnerIn: .zero,
                         minimumSpinner: reload.minimumSpinnerDuration, spinnerOut: .zero)
                : Timing(contentOut: reload.contentOutDuration, spinnerIn: reload.spinnerInDuration,
                         minimumSpinner: reload.minimumSpinnerDuration, spinnerOut: reload.spinnerOutDuration)
        }

        /// Frozen fades (`festivalFadeInEnabled == false`, snapshots): no fades, no hold.
        public static let instant = Timing(contentOut: .zero, spinnerIn: .zero, minimumSpinner: .zero, spinnerOut: .zero)

        /// The wait for `wait`.
        ///
        /// - Parameter wait: The pending step.
        /// - Returns: How long to wait before calling ``PublicationRefreshTransition/timerFired(_:)``.
        public func duration(of wait: Wait) -> Duration {
            switch wait {
            case .contentOut: contentOut
            case .minimumSpinner: minimumSpinner
            case .spinnerOut: spinnerOut
            }
        }
    }

    /// What the page shows now.
    public private(set) var phase: Phase
    /// Bumps for every rebuilt page; use it as the content's identity.
    public private(set) var generation: Int
    /// The newest generation (publication revision) the page must show.
    public private(set) var targetRevision: Int
    /// The generation the page last finished preparing for.
    public private(set) var preparedRevision: Int
    /// Whether the spinner has been up for its minimum time.
    private var spinnerHeld: Bool

    /// Start a page showing content for the current generation.
    ///
    /// - Parameter revision: The session's publication revision when the page appeared.
    public init(revision: Int) {
        phase = .content
        generation = 0
        targetRevision = revision
        preparedRevision = revision
        spinnerHeld = false
    }

    /// Whether the content is visible, readable and interactive; it fades out, inert and
    /// hidden from VoiceOver, from ``Phase/contentOut`` on.
    public var showsContent: Bool { phase == .content }
    /// Whether the refresh spinner is on screen (it is removed, fading, during ``Phase/spinnerOut``).
    public var showsSpinner: Bool { phase == .spinner }
    /// Whether a refresh is under way (content hidden from VoiceOver).
    public var isRefreshing: Bool { phase != .content }

    /// The timed step the view must run now, if any.
    public var pendingWait: Wait? {
        switch phase {
        case .content: nil
        case .contentOut: .contentOut
        case .spinner: spinnerHeld ? nil : .minimumSpinner
        case .spinnerOut: .spinnerOut
        }
    }

    /// The generation the page must prepare for now, or nil when it is ready or its old
    /// content is still fading out.
    public var preparationRevision: Int? {
        phase == .spinner && preparedRevision != targetRevision ? targetRevision : nil
    }

    /// The service published a newer generation.
    ///
    /// - Parameter revision: The session's new publication revision.
    /// - Returns: True when this starts or extends a refresh.
    @discardableResult
    public mutating func publicationChanged(to revision: Int) -> Bool {
        guard revision > targetRevision else { return false }
        targetRevision = revision
        switch phase {
        case .content:
            phase = .contentOut
            spinnerHeld = false
        case .spinnerOut:
            // The hold already ran; the spinner returns until the newer preparation ends.
            phase = .spinner
        case .contentOut, .spinner:
            break
        }
        return true
    }

    /// A wait from ``pendingWait`` finished. Stale waits (the phase moved on) are ignored.
    ///
    /// - Parameter wait: The wait that finished.
    public mutating func timerFired(_ wait: Wait) {
        switch (wait, phase) {
        case (.contentOut, .contentOut):
            phase = .spinner
            spinnerHeld = false
        case (.minimumSpinner, .spinner):
            spinnerHeld = true
            fadeSpinnerOutIfReady()
        case (.spinnerOut, .spinnerOut):
            guard preparedRevision == targetRevision else {
                phase = .spinner
                return
            }
            phase = .content
            generation += 1
            spinnerHeld = false
        default:
            break
        }
    }

    /// The page finished preparing for a generation (successfully or with its own error
    /// state). A preparation for an older generation is ignored.
    ///
    /// - Parameter revision: The generation the preparation was for.
    public mutating func prepared(revision: Int) {
        guard revision == targetRevision else { return }
        preparedRevision = revision
        fadeSpinnerOutIfReady()
    }

    /// Fade the spinner out once it held and preparation matches.
    private mutating func fadeSpinnerOutIfReady() {
        guard phase == .spinner, spinnerHeld, preparedRevision == targetRevision else { return }
        phase = .spinnerOut
    }
}
