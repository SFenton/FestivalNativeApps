import Foundation

// MARK: - Publication refresh transition (issue #304)

/// The in-place refresh of one page when the service publishes a new generation, ported
/// from the web's `PublicationBoundary` (which remounts the app under the same route)
/// combined with its load fade:
///
/// 1. **Content out:** the page's content fades out while the spinner fades in (web
///    `QUICK_FADE_MS`, 150 ms). The old content stays mounted but hidden so the page's
///    title and toolbar stay put; it is never shown again.
/// 2. **Spinner:** holds at least ``ReloadTransition/Timing/minimumSpinnerDuration``
///    (400 ms) and until the page has **prepared** for the new generation (for example,
///    re-read a song from the new catalogue), so old and new data are never mixed.
/// 3. **Content in:** the page is rebuilt (``generation`` changes) and fades in, while the
///    spinner fades out; the rebuilt page then loads its own data with its own load fade.
///
/// A newer generation while the spinner is up keeps the spinner and waits for the newer
/// preparation. This is a pure value type: the view applies ``phase``, runs the wait named
/// by ``pendingWait`` and the preparation named by ``preparationRevision``, then reports
/// back with ``minimumSpinnerElapsed()`` and ``prepared(revision:)``.
public struct PublicationRefreshTransition: Equatable, Sendable {
    /// What the page shows.
    public enum Phase: Equatable, Sendable {
        /// The page content.
        case content
        /// The spinner over hidden content, while the page refreshes.
        case spinner
    }

    /// A timed step the view must wait for.
    public enum Wait: Equatable, Sendable {
        /// The spinner's minimum time on screen.
        case minimumSpinner
    }

    /// Content fade-out / spinner fade-in (web `QUICK_FADE_MS`).
    public static let fadeOutDuration: Duration = ReloadTransition.Timing.spinnerInDuration
    /// Shortest spinner time (web `MIN_SPINNER_MS`), kept under Reduce Motion so it never blinks.
    public static let minimumSpinnerDuration: Duration = ReloadTransition.Timing.minimumSpinnerDuration

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

    /// Whether the content is visible.
    public var showsContent: Bool { phase == .content }
    /// Whether the refresh spinner is visible.
    public var showsSpinner: Bool { phase == .spinner }

    /// The wait the view must run now, if any.
    public var pendingWait: Wait? {
        phase == .spinner && !spinnerHeld ? .minimumSpinner : nil
    }

    /// The generation the page must prepare for now, or nil when it is ready.
    public var preparationRevision: Int? {
        preparedRevision == targetRevision ? nil : targetRevision
    }

    /// The service published a newer generation.
    ///
    /// - Parameter revision: The session's new publication revision.
    /// - Returns: True when this starts or extends a refresh.
    @discardableResult
    public mutating func publicationChanged(to revision: Int) -> Bool {
        guard revision > targetRevision else { return false }
        targetRevision = revision
        if phase == .content {
            phase = .spinner
            spinnerHeld = false
        }
        return true
    }

    /// The spinner has been up for its minimum time.
    public mutating func minimumSpinnerElapsed() {
        guard phase == .spinner else { return }
        spinnerHeld = true
        revealIfReady()
    }

    /// The page finished preparing for a generation (successfully or with its own error
    /// state). A preparation for an older generation is ignored.
    ///
    /// - Parameter revision: The generation the preparation was for.
    public mutating func prepared(revision: Int) {
        guard revision == targetRevision else { return }
        preparedRevision = revision
        revealIfReady()
    }

    /// Show the rebuilt page once the spinner held and preparation matches.
    private mutating func revealIfReady() {
        guard phase == .spinner, spinnerHeld, preparedRevision == targetRevision else { return }
        phase = .content
        generation += 1
        spinnerHeld = false
    }
}
