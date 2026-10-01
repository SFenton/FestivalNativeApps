import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Model

/// Polls `GET /api/service-info` while Settings is visible and reduces each read through the
/// web's monotonic progress rules, the native form of `useServiceInfo('settings')` +
/// `SettingsServiceProgressCard`.
@MainActor
@Observable
final class SettingsServiceInfoModel {
    /// Load phase of the latest poll.
    enum Phase: Equatable {
        case loading
        case loaded(ServiceInfoSnapshot, ServiceProgressDisplay)
        case failed
    }

    /// Web cadence (`SERVICE_INFO_SETTINGS_POLL_MS` / `…_UNAVAILABLE_RETRY_MS`): 5 s either way.
    static let pollInterval: Duration = .seconds(5)

    private(set) var phase: Phase
    @ObservationIgnored private var memory: ServiceProgressMemory?

    /// Create a model.
    ///
    /// - Parameter phase: Starting phase; `.loading` in the app, a fixed state in hosted tests.
    init(phase: Phase = .loading) {
        self.phase = phase
    }

    /// Fold one read (or failure) into the displayed state. A failure after a success keeps
    /// the failure visible rather than silently showing old progress.
    ///
    /// - Parameter result: Latest read.
    func apply(_ result: Result<ServiceInfoSnapshot, Error>) {
        switch result {
        case let .success(snapshot):
            let reduced = ServiceProgressReducer.reduce(memory, snapshot.info)
            memory = reduced.memory
            phase = .loaded(snapshot, reduced.display)
        case .failure:
            phase = .failed
        }
    }

    /// Poll until cancelled (the view's `.task(id:)` cancels when Settings hides).
    ///
    /// - Parameter read: One service-info read.
    func poll(_ read: @escaping @Sendable () async throws -> ServiceInfoSnapshot) async {
        while !Task.isCancelled {
            do {
                let snapshot = try await read()
                try Task.checkCancellation()
                apply(.success(snapshot))
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                apply(.failure(error))
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}

// MARK: - Rows

/// Everything the card shows for one state, derived without SwiftUI so it can be unit-tested.
struct ServiceInfoRows: Equatable {
    /// Leading row: "Leaderboard Service State" with description and trailing process state.
    var stateDescription: String
    var processState: ServiceProcessState
    /// Phase row title, or nil when there is no phase to show.
    var phaseTitle: String?
    /// Bar: nil = no bar; `.some(nil)` = indeterminate; `.some(x)` = 0–100.
    var barPercent: Double??
    var progressText: String?
    var unitsText: String?
    /// Registered-band discovery lookup line under the bar, nil for every other phase.
    var attemptText: String?
    /// Last publication row; nil until the first successful read (the web shows only the
    /// state row while loading or after a failed first read).
    var lastPublished: String?
    /// Public-read freeze explanation (native addition), nil when reads are live.
    var freezeNotice: String?

    /// Build rows for a load phase.
    ///
    /// - Parameters:
    ///   - phase: Model phase.
    ///   - timeZone: Display time zone.
    ///   - locale: Display locale.
    /// - Returns: Row content.
    static func make(
        _ phase: SettingsServiceInfoModel.Phase, timeZone: TimeZone = .current, locale: Locale = .current
    ) -> ServiceInfoRows {
        switch phase {
        case .loading:
            return ServiceInfoRows(stateDescription: "Loading", processState: .loading)
        case .failed:
            return ServiceInfoRows(stateDescription: "Failed to load", processState: .stopped)
        case let .loaded(snapshot, display):
            let info = snapshot.info
            let updating = info.currentUpdate.status == "updating"
            let state = ServiceInfoText.processState(info)
            let phaseLabel = ServiceInfoText.phaseLabel(info, display: display)
            let showPhase = updating || display.phaseId != nil || info.currentUpdate.phase != nil
            let bar = display.barProgress
            let showBar = updating && bar?.kind != .notApplicable
            let determinate = bar?.kind == .exact && bar?.percent != nil
            return ServiceInfoRows(
                stateDescription: updating ? phaseLabel : ServiceInfoText.serviceState(info, state: state),
                processState: state,
                phaseTitle: showPhase
                    ? ServiceInfoText.phaseTitle(
                        phase: phaseLabel, subphase: ServiceInfoText.subphaseLabel(info, display: display))
                    : nil,
                barPercent: showBar ? .some(determinate ? bar?.percent : nil) : nil,
                progressText: showBar ? ServiceInfoText.progressText(bar) : nil,
                unitsText: showBar ? ServiceInfoText.unitsText(bar) : nil,
                attemptText: showBar ? ServiceInfoText.discoveryAttemptText(display) : nil,
                lastPublished: ServiceInfoText.lastPublished(info, timeZone: timeZone, locale: locale),
                freezeNotice: ServiceInfoText.freezeNotice(snapshot)
            )
        }
    }
}

// MARK: - Section

/// Settings "Service Info" card: live leaderboard update state, phase progress and last
/// publication, refreshed every 5 s while Settings is visible (web `useServiceInfo`).
///
/// Reads only the keyless operational `/api/service-info` (documented in
/// `.agents/platforms/service-safety.md`); polls every 5 s only while `isVisible`.
struct SettingsServiceInfoSection: View {
    let session: FestivalSession
    let isVisible: Bool
    @State private var model: SettingsServiceInfoModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Create the section.
    ///
    /// - Parameters:
    ///   - session: Shared session whose client performs the keyless reads.
    ///   - isVisible: Poll only while true (Settings tab selected).
    ///   - initialPhase: Starting state; hosted tests pass a fixed snapshot with `isVisible` false.
    init(
        session: FestivalSession, isVisible: Bool,
        initialPhase: SettingsServiceInfoModel.Phase = .loading
    ) {
        self.session = session
        self.isVisible = isVisible
        _model = State(initialValue: SettingsServiceInfoModel(phase: initialPhase))
    }

    var body: some View {
        let rows = ServiceInfoRows.make(model.phase)
        FestivalGlassSection(ServiceInfoText.title, subtitle: ServiceInfoText.hint) {
            stateRow(rows)
            if let title = rows.phaseTitle {
                phaseRow(title: title, rows: rows)
            }
            if let lastPublished = rows.lastPublished {
                SettingLabel(ServiceInfoText.lastPublishedTitle, detail: lastPublished)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fst.settings.service-info.last-published")
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            let session = session
            await model.poll { try await session.client().serviceInfo() }
        }
    }

    /// Title and state description with the process state trailing, like the other
    /// Settings value rows; at accessibility text sizes the state stacks under the label so
    /// "Leaderboard Service State" is never squeezed into hyphenation.
    private func stateRow(_ rows: ServiceInfoRows) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            SettingLabel(ServiceInfoText.serviceStateTitle, detail: rows.stateDescription)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            HStack(spacing: 8) {
                Text(rows.processState.label)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if rows.processState == .loading || rows.processState == .updating {
                    FestivalLoadingView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fst.settings.service-info.state")
    }

    /// The web's phase row: semibold title (`toggleLabel`), the bar a gap-xs below, and the
    /// registered-band discovery lookup line under it (`toggleDesc`). Percent and units are
    /// spoken, not printed — `SettingsServiceProgressCard` shows neither.
    private func phaseRow(title: String, rows: ServiceInfoRows) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let barPercent = rows.barPercent {
                ServiceProgressBar(percent: barPercent, reduceMotion: reduceMotion)
                if let attemptText = rows.attemptText {
                    Text(attemptText)
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            [rows.progressText, rows.unitsText, rows.attemptText].compactMap { $0 }.joined(separator: ". ")
        )
        .accessibilityIdentifier("fst.settings.service-info.phase")
    }
}

// MARK: - Bar

/// Web-style capsule progress bar (purple fill on a muted track, 0.65 rem tall). An unknown
/// total shows the web's sliding 38 % segment (1.25 s ease-in-out); it holds still under
/// Reduce Motion and in UI-test runs (`FST_DEBUG_STILL_BACKGROUND`), where a perpetual
/// animation would keep XCUITest from idling.
private struct ServiceProgressBar: View {
    /// 0–100, or nil for an unknown total.
    let percent: Double?
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandTokens.surfaceMuted)
                if let percent {
                    Capsule()
                        .fill(BrandTokens.accentPurple)
                        .frame(width: max(8, proxy.size.width * percent / 100))
                } else if !reduceMotion && !DebugAnimationOverride.stillBackground {
                    IndeterminateSegment(width: proxy.size.width)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percent)
        .accessibilityHidden(true)
    }
}

/// The web's `settings-progress-indeterminate` keyframes: a 38 %-wide segment sweeping
/// across the track.
private struct IndeterminateSegment: View {
    let width: CGFloat
    @State private var leading = false

    var body: some View {
        Capsule()
            .fill(BrandTokens.accentPurple)
            .frame(width: width * 0.38)
            .offset(x: leading ? width : -width * 0.38)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) {
                    leading = true
                }
            }
    }
}
