import Foundation

// MARK: - Freeze reason

/// The service's `X-FST-Public-Read-Freeze-Reason` vocabulary.
///
/// `PublicReadGateMiddleware` stamps this header on every `/api/` response while
/// public reads are frozen (`FSTService/Api/PublicReadGateMiddleware.cs`). The
/// scrape lifecycle sets `scrape`, then `post-process`, then `publish`, and the
/// publication commit adds `publication-commit`/`publication-commit-deferred`
/// (`FSTService/Scraping/ScrapeLifecycleNotifier.cs`,
/// `FSTService/Persistence/PublicReadFreezeState.cs`). All of those mean new
/// scores are being published; anything else (failure isolation, max-score
/// maintenance, a future reason) is shown as a generic outage.
public enum ServiceFreezeReason {
    /// Response header that names why public reads are frozen.
    public static let header = "X-FST-Public-Read-Freeze-Reason"

    /// Reasons that belong to the normal scrape → publish lifecycle.
    public static let scoreUpdateReasons: Set<String> = [
        "scrape", "post-process", "publish", "publication-commit", "publication-commit-deferred",
    ]

    /// Whether a freeze reason means "scores are updating" rather than an outage.
    ///
    /// - Parameter reason: Raw header value in any capitalization.
    /// - Returns: True for a scrape-lifecycle reason.
    public static func isScoreUpdate(_ reason: String) -> Bool {
        scoreUpdateReasons.contains(
            reason.trimmingCharacters(in: .whitespaces).lowercased()
        )
    }
}

// MARK: - Service issue

/// The one user-facing vocabulary for a failed public read.
///
/// Screens convert any thrown error with `ServiceIssue(_:)` and render it with the
/// shared `ServiceStatusView`, instead of each screen interpreting HTTP codes.
/// The app is online-only: `.offline` only means "you're offline, retry" and
/// never implies a cached copy is shown.
public enum ServiceIssue: Equatable, Sendable {
    /// Public reads are frozen while new scores are scraped and published.
    case scrapeInProgress(retryAfter: Int?)
    /// The service answered 503 for another reason.
    case unavailable(retryAfter: Int?)
    /// The service accepted the request but the data is still being prepared (HTTP 202).
    case syncing
    /// The resource does not exist (HTTP 404).
    case notFound
    /// The device could not reach the service.
    case offline
    /// Any other failure, with a readable message that never exposes server text.
    case other(message: String)

    // MARK: - Mapping

    /// Classify any error thrown by `FestivalAPI` or its transport.
    ///
    /// - Parameter error: A `FestivalAPIError`, `URLError` or domain error.
    public init(_ error: any Error) {
        switch error {
        case let error as FestivalAPIError:
            switch error {
            case let .publicReadFrozen(reason, retryAfter):
                let seconds = Self.retryAfterSeconds(retryAfter)
                self = ServiceFreezeReason.isScoreUpdate(reason)
                    ? .scrapeInProgress(retryAfter: seconds) : .unavailable(retryAfter: seconds)
            case let .unavailable(retryAfter):
                self = .unavailable(retryAfter: Self.retryAfterSeconds(retryAfter))
            case .syncing:
                self = .syncing
            case .httpStatus(404):
                self = .notFound
            default:
                self = .other(message: error.localizedDescription)
            }
        case let error as URLError where error.isOffline:
            self = .offline
        default:
            self = .other(message: error.localizedDescription)
        }
    }

    /// Parse a delta-seconds `Retry-After` value; HTTP-date forms are ignored.
    ///
    /// - Parameter value: Raw header value.
    /// - Returns: Seconds in `1...86_400`, or nil when absent or unusable.
    public static func retryAfterSeconds(_ value: String?) -> Int? {
        guard let value, let seconds = Int(value.trimmingCharacters(in: .whitespaces)),
              (1...86_400).contains(seconds) else {
            return nil
        }
        return seconds
    }

    // MARK: - Presentation

    /// Server-suggested wait, when one was sent.
    public var retryAfter: Int? {
        switch self {
        case let .scrapeInProgress(retryAfter), let .unavailable(retryAfter): retryAfter
        default: nil
        }
    }

    /// Whether the UI should count down and retry on its own.
    ///
    /// Only a scrape freeze does: it is expected, transient and announced by the
    /// service. Other failures wait for the person to choose Retry.
    public var retriesAutomatically: Bool {
        if case .scrapeInProgress = self { return true }
        return false
    }

    /// Heading to show, or nil to use the screen's own "… unavailable" title.
    public var title: String? {
        switch self {
        case .scrapeInProgress: "Scores are updating"
        case .offline: "You're offline"
        case .syncing: "Still syncing"
        default: nil
        }
    }

    /// Body text for the status view.
    public var message: String {
        switch self {
        case .scrapeInProgress:
            "New scores are being published. This page will try again automatically."
        case let .unavailable(retryAfter):
            if let retryAfter {
                "The service is temporarily unavailable. Try again in \(retryAfter) seconds."
            } else {
                "The service is temporarily unavailable. Try again."
            }
        case .syncing:
            "This data is still being prepared. Try again shortly."
        case .notFound:
            "This content is no longer available."
        case .offline:
            "Check your connection and try again."
        case let .other(message):
            message
        }
    }
}

// MARK: - Retry backoff

/// Consecutive automatic-retry delays for one screen, capped with exponential backoff.
///
/// The first delay honours `Retry-After` (the service sends 30 s during a freeze);
/// each consecutive failure within the grace window doubles it up to `cap`. A
/// failure after a quiet period starts over, so a screen that recovered and
/// later hits a new freeze waits only the server's suggested time.
public struct ServiceRetryBackoff: Sendable {
    /// Delay used when the service sent no usable `Retry-After`.
    public static let defaultDelay = 30
    /// Longest automatic wait between attempts.
    public static let cap = 300
    /// Extra seconds after a countdown during which a failure still counts as consecutive.
    public static let grace: TimeInterval = 20

    private struct Attempt: Sendable {
        var count: Int
        var delay: Int
        var at: Date
    }

    private var attempts: [String: Attempt] = [:]

    /// Create an empty backoff history.
    public init() {}

    /// Record a failure and return how long to wait before the next automatic retry.
    ///
    /// - Parameters:
    ///   - scope: Stable identifier for the screen or request being retried.
    ///   - retryAfter: Server-suggested delay in seconds, if any.
    ///   - now: Failure time; injectable for tests.
    /// - Returns: Seconds to wait, at least one and at most `cap`.
    public mutating func nextDelay(scope: String, retryAfter: Int?, now: Date = Date()) -> Int {
        let base = min(Self.cap, max(1, retryAfter ?? Self.defaultDelay))
        var count = 0
        if let previous = attempts[scope],
           now.timeIntervalSince(previous.at) <= TimeInterval(previous.delay) + Self.grace {
            count = previous.count + 1
        }
        let factor = 1 << min(count, 8)
        let delay = min(Self.cap, base * factor)
        attempts[scope] = Attempt(count: count, delay: delay, at: now)
        return delay
    }

    /// Forget a scope after it loads successfully.
    ///
    /// - Parameter scope: Identifier passed to `nextDelay(scope:retryAfter:now:)`.
    public mutating func reset(scope: String) {
        attempts[scope] = nil
    }
}

// MARK: - Literal convenience

extension ServiceIssue: ExpressibleByStringLiteral {
    /// A literal message is an `.other` issue, so previews, fixtures and tests
    /// can write `.failed("Synthetic outage")` for a screen's failed state.
    ///
    /// - Parameter value: Readable failure text.
    public init(stringLiteral value: String) {
        self = .other(message: value)
    }
}
