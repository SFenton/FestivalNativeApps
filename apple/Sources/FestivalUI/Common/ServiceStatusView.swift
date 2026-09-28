import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Countdown clock

extension EnvironmentValues {
    /// Clock that paces automatic-retry countdowns: the real continuous clock in
    /// the app; hosted tests inject a manual clock so a countdown never races
    /// wall-clock deadlines on a busy shared main actor.
    @Entry var serviceRetryClock: any Clock<Duration> = ContinuousClock()
}

// MARK: - Shared retry backoff

/// Process-wide automatic-retry history so consecutive freezes on one screen back off
/// even though each failure recreates the status view.
@MainActor
enum ServiceRetryScheduler {
    private static var backoff = ServiceRetryBackoff()

    /// Record a failure and return the countdown length for the next automatic retry.
    ///
    /// - Parameters:
    ///   - scope: Stable screen identifier.
    ///   - retryAfter: Server-suggested delay in seconds.
    /// - Returns: Seconds to count down.
    static func nextDelay(scope: String, retryAfter: Int?) -> Int {
        backoff.nextDelay(scope: scope, retryAfter: retryAfter)
    }

    /// Drive one status view: optionally announce, then count down and retry
    /// when the issue retries automatically. Returns early when cancelled.
    ///
    /// - Parameters:
    ///   - issue: Failure being shown.
    ///   - scope: Backoff identifier.
    ///   - heading: Spoken heading, or nil to stay silent (inline sections).
    ///   - clock: Paces the one-second ticks.
    ///   - update: Receives the remaining seconds, or nil when not counting down.
    ///   - retry: Called when the countdown reaches zero.
    static func countdown(
        issue: ServiceIssue, scope: String, announcing heading: String?,
        clock: any Clock<Duration>, update: (Int?) -> Void, retry: () -> Void
    ) async {
        guard issue.retriesAutomatically else {
            update(nil)
            if let heading {
                AccessibilityNotification.Announcement("\(heading). \(issue.message)").post()
            }
            return
        }
        let delay = nextDelay(scope: scope, retryAfter: issue.retryAfter)
        update(delay)
        if let heading {
            AccessibilityNotification.Announcement(
                "\(heading). Trying again automatically in \(delay) seconds."
            ).post()
        }
        for tick in stride(from: delay - 1, through: 0, by: -1) {
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                return
            }
            update(tick)
        }
        retry()
    }
}

// MARK: - Status view

/// The one full-page status for a failed public read: scrape freeze ("Scores are
/// updating" with an automatic countdown), generic outage, offline, syncing, not
/// found and other errors.
///
/// Built from scalable native text rather than `ContentUnavailableView`, which
/// failed iOS 26.5 Dynamic Type audits. Announces its state to VoiceOver on
/// appearance and honours system and in-app Reduce Motion.
struct ServiceStatusView: View {
    let issue: ServiceIssue
    let fallbackTitle: String
    let scope: String
    let retry: () -> Void

    @State private var remaining: Int?
    @Environment(\.serviceRetryClock) private var clock
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Create a status view for one failed read.
    ///
    /// - Parameters:
    ///   - issue: Classified failure, usually `ServiceIssue(error)`.
    ///   - title: Screen-specific heading (for example "Rankings unavailable"),
    ///     used unless the issue has its own global heading.
    ///   - scope: Backoff identifier; defaults to `title`.
    ///   - retry: Reloads the screen; also called when the countdown ends.
    init(
        _ issue: ServiceIssue, title: String, scope: String? = nil,
        retry: @escaping () -> Void
    ) {
        self.issue = issue
        fallbackTitle = title
        self.scope = scope ?? title
        self.retry = retry
    }

    private var reduceMotion: Bool { appReduceMotion || systemReduceMotion }
    private var heading: String { issue.title ?? fallbackTitle }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    symbol
                    Text(heading)
                        .font(.title2.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("fst.service-status.title")
                    Text(issue.message)
                        .font(.body)
                        .foregroundStyle(BrandTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let remaining {
                        countdown(remaining)
                    }
                    retryButton
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: issue) { await run() }
    }

    // MARK: - Parts

    @ViewBuilder
    private var symbol: some View {
        let image = Image(systemName: Self.symbolName(for: issue))
            .font(.largeTitle)
            .foregroundStyle(issue.retriesAutomatically ? BrandTokens.gold : BrandTokens.textSecondary)
            .accessibilityHidden(true)
        if issue.retriesAutomatically && !reduceMotion {
            image.symbolEffect(.pulse, options: .repeating)
        } else {
            image
        }
    }

    private func countdown(_ seconds: Int) -> some View {
        Text("Trying again in \(Self.clock(seconds))")
            .font(.body.monospacedDigit())
            .foregroundStyle(BrandTokens.textSecondary)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .default, value: seconds)
            .accessibilityLabel("Trying again automatically in \(seconds) seconds")
            .accessibilityIdentifier("fst.service-status.countdown")
    }

    private var retryButton: some View {
        Button(action: retry) {
            Text(remaining == nil ? "Retry" : "Retry Now")
                .font(.body)
                .foregroundStyle(BrandTokens.textPrimary)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 12)
                .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fst.service-status.retry")
    }

    // MARK: - Behavior

    /// Announce the state, then count down and retry for a scrape freeze.
    private func run() async {
        await ServiceRetryScheduler.countdown(
            issue: issue, scope: scope, announcing: heading, clock: clock,
            update: { remaining = $0 }, retry: retry
        )
    }

    /// SF Symbol for each issue family.
    ///
    /// - Parameter issue: Classified failure.
    /// - Returns: System symbol name.
    nonisolated static func symbolName(for issue: ServiceIssue) -> String {
        switch issue {
        case .scrapeInProgress: "arrow.triangle.2.circlepath"
        case .unavailable: "exclamationmark.icloud"
        case .syncing: "hourglass"
        case .notFound: "questionmark.folder"
        case .offline: "wifi.slash"
        case .other: "exclamationmark.triangle"
        }
    }

    /// Format a countdown as `m:ss`.
    ///
    /// - Parameter seconds: Remaining seconds.
    /// - Returns: For example `0:27` or `2:00`.
    nonisolated static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }
}

// MARK: - Inline variant

/// Compact status for one section of a multi-section page (a Leaderboards card,
/// a Rivals instrument section), sharing `ServiceStatusView`'s vocabulary and
/// countdown. It does not announce, so a page with many failing sections does
/// not flood VoiceOver.
struct ServiceStatusInline: View {
    let issue: ServiceIssue
    let scope: String
    let retry: () -> Void

    @State private var remaining: Int?
    @Environment(\.serviceRetryClock) private var clock

    /// Create an inline status.
    ///
    /// - Parameters:
    ///   - issue: Classified failure.
    ///   - scope: Backoff identifier, unique per section.
    ///   - retry: Reloads just this section.
    init(_ issue: ServiceIssue, scope: String, retry: @escaping () -> Void) {
        self.issue = issue
        self.scope = scope
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ServiceStatusView.symbolName(for: issue))
                .foregroundStyle(BrandTokens.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title ?? issue.message)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let remaining {
                    Text("Trying again in \(ServiceStatusView.clock(remaining))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(BrandTokens.textMuted)
                        .accessibilityLabel("Trying again automatically in \(remaining) seconds")
                }
            }
            Spacer(minLength: 8)
            Button(remaining == nil ? "Retry" : "Retry Now", action: retry)
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("fst.service-status.retry")
        }
        .accessibilityIdentifier("fst.service-status.inline")
        .task(id: issue) {
            await ServiceRetryScheduler.countdown(
                issue: issue, scope: scope, announcing: nil, clock: clock,
                update: { remaining = $0 }, retry: retry
            )
        }
    }
}

// MARK: - Overlay modifier

extension View {
    /// Cover this view with the shared service status while `issue` is non-nil.
    ///
    /// - Parameters:
    ///   - issue: Current failure, or nil to show the content.
    ///   - title: Screen-specific heading for issues without a global one.
    ///   - retry: Reloads the screen.
    /// - Returns: The view, overlaid with an opaque status when failing.
    func serviceStatusOverlay(
        _ issue: ServiceIssue?, title: String, retry: @escaping () -> Void
    ) -> some View {
        overlay {
            if let issue {
                ServiceStatusView(issue, title: title, retry: retry)
                    .background(BrandTokens.appBackground)
            }
        }
    }
}
