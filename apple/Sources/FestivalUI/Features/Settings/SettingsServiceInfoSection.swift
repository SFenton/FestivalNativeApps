import QuartzCore
import SwiftUI
import FestivalCore
import FestivalDesign
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    /// False on the list/detail Settings' Service Info page (issue #371).
    let titled: Bool
    @State private var model: SettingsServiceInfoModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// System or in-app Reduce Motion (Settings' additive preference, load-transition R6).
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// Create the section.
    ///
    /// - Parameters:
    ///   - session: Shared session whose client performs the keyless reads.
    ///   - isVisible: Poll only while true (Settings tab selected).
    ///   - titled: Show the section title (false on its own list/detail page).
    ///   - initialPhase: Starting state; hosted tests pass a fixed snapshot with `isVisible` false.
    init(
        session: FestivalSession, isVisible: Bool, titled: Bool = true,
        initialPhase: SettingsServiceInfoModel.Phase = .loading
    ) {
        self.session = session
        self.isVisible = isVisible
        self.titled = titled
        _model = State(initialValue: SettingsServiceInfoModel(phase: initialPhase))
    }

    var body: some View {
        let rows = ServiceInfoRows.make(model.phase)
        SettingsSectionCard(ServiceInfoText.title, subtitle: ServiceInfoText.hint, titled: titled) {
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

    /// Title and state description with the process state trailing: the shared
    /// `SettingsValueRow`, so the state stacks under the label only when it doesn't fit
    /// beside it (pattern `settings-value-row` R1) and "Leaderboard Service State" is never
    /// squeezed into hyphenation.
    private func stateRow(_ rows: ServiceInfoRows) -> some View {
        SettingsValueRow(
            ServiceInfoText.serviceStateTitle, detail: rows.stateDescription,
            spokenValue: rows.processState.label, identifier: "fst.settings.service-info.state"
        ) {
            HStack(spacing: 8) {
                Text(rows.processState.label)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                if rows.processState == .loading || rows.processState == .updating {
                    FestivalLoadingView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// The web's phase row: semibold title (`toggleLabel`), the bar a gap-xs below, and the
    /// registered-band discovery lookup line under it (`toggleDesc`). Percent and units are
    /// spoken, not printed — `SettingsServiceProgressCard` shows neither. One static-text
    /// element like `SettingsValueRow` (R3): without the trait the Mac tree reports an unknown
    /// role and drops the value, so VoiceOver never read the progress or attempt line (#399).
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
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(title)
        .accessibilityValue(
            [rows.progressText, rows.unitsText, rows.attemptText].compactMap { $0 }.joined(separator: ". ")
        )
        .accessibilityIdentifier("fst.settings.service-info.phase")
    }
}

// MARK: - Bar

/// Web-style capsule progress bar (purple fill on a muted track, 0.65 rem tall). An unknown
/// total shows the web's sliding 38 % segment (`ServiceProgressSweep`, 1.25 s ease-in-out);
/// it holds a still, empty track under system or in-app Reduce Motion, in an inactive scene
/// or hidden window, and in UI-test runs (`FST_DEBUG_STILL_BACKGROUND`), where a perpetual
/// animation would keep XCUITest from idling.
struct ServiceProgressBar: View {
    /// 0–100, or nil for an unknown total.
    let percent: Double?
    /// System or in-app Reduce Motion.
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// Whether an unknown total sweeps the indeterminate segment.
    ///
    /// - Parameters:
    ///   - percent: 0–100, or nil for an unknown total.
    ///   - reduceMotion: System or in-app Reduce Motion.
    ///   - sceneActive: Active scene in a visible window (`AnimationActivity.sceneActive`).
    ///   - still: The UI-test still-animation override.
    /// - Returns: True only for an unknown total with motion allowed in an active scene.
    static func sweeps(percent: Double?, reduceMotion: Bool, sceneActive: Bool, still: Bool) -> Bool {
        percent == nil && !reduceMotion && sceneActive && !still
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandTokens.surfaceMuted)
                if let percent {
                    Capsule()
                        .fill(BrandTokens.accentPurple)
                        .frame(width: max(8, proxy.size.width * percent / 100))
                } else if Self.sweeps(
                    percent: percent, reduceMotion: reduceMotion,
                    sceneActive: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
                    still: DebugAnimationOverride.stillBackground
                ) {
                    ServiceProgressSweep(color: BrandTokens.accentPurple)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percent)
        .accessibilityHidden(true)
    }
}

// MARK: - Indeterminate sweep

/// The web's `settings-progress-indeterminate` segment, played by Core Animation on the
/// render server (Apple architecture: continuous decoration never runs in SwiftUI).
///
/// It was a one-shot `repeatForever` state animation started in `onAppear`, which SwiftUI
/// dropped when the lazily hosted Settings card was realized or re-hosted on iPhone; setting
/// the same state again restarted nothing, so the segment stayed parked off the track and
/// the bar never moved (issue #556). Like `ShopPulseView` and `MarqueeTrackView`, the host
/// view re-adds its animation whenever it enters a window or its width changes, phased on
/// the shared wall clock (`ShopPulseClock.elapsed`), and the segment's model position is
/// off the track, so a dropped animation leaves an empty track, never a frozen segment.
struct ServiceProgressSweep {
    /// Segment fill (`BrandTokens.accentPurple`, web `--settings-progress-fill`).
    let color: Color

    /// Segment width as a fraction of the track (web `width: 38%`).
    static let segmentFraction: CGFloat = 0.38
    /// One sweep (web `animation: settings-progress-indeterminate 1.25s`).
    static let period: Double = 1.25
    /// Web keyframes' `translateX` at 0 %, 50 % and 100 %, in segment widths.
    static let keyframes: [CGFloat] = [-1.1, 1.65, 3.0]
    /// Keyframe times (web `0%`, `50%`, `100%`).
    static let keyTimes: [Double] = [0, 0.5, 1]

    /// The sweep animation for a track: the web's keyframes in points, CSS `ease-in-out`
    /// on each half (CSS applies the timing function per keyframe interval; Core
    /// Animation's `easeInEaseOut` is the same `cubic-bezier(0.42, 0, 0.58, 1)`), repeating,
    /// with its cycle aligned to the wall clock so re-adding it resumes mid-sweep.
    ///
    /// - Parameters:
    ///   - trackWidth: Track width in points.
    ///   - mediaTime: `CACurrentMediaTime()` now.
    ///   - date: Wall-clock now.
    /// - Returns: A `transform.translation.x` animation for the segment layer.
    static func animation(trackWidth: CGFloat, mediaTime: CFTimeInterval, date: Date) -> CAKeyframeAnimation {
        let segment = trackWidth * segmentFraction
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = keyframes.map { NSNumber(value: Double($0 * segment)) }
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: keyframes.count - 1
        )
        animation.calculationMode = .linear
        animation.duration = period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = mediaTime - ShopPulseClock.elapsed(period: period, at: date)
        return animation
    }

    /// Resting translation of the segment: the first keyframe, fully left of the track.
    ///
    /// - Parameter trackWidth: Track width in points.
    /// - Returns: The model-layer x translation.
    static func restingOffset(trackWidth: CGFloat) -> CGFloat {
        keyframes[0] * trackWidth * segmentFraction
    }
}

#if os(iOS)
extension ServiceProgressSweep: UIViewRepresentable {
    func makeUIView(context: Context) -> ServiceProgressSweepView { ServiceProgressSweepView() }

    func updateUIView(_ view: ServiceProgressSweepView, context: Context) {
        view.apply(color: color.resolve(in: context.environment).cgColor)
    }
}
#elseif os(macOS)
extension ServiceProgressSweep: NSViewRepresentable {
    func makeNSView(context: Context) -> ServiceProgressSweepView { ServiceProgressSweepView() }

    func updateNSView(_ view: ServiceProgressSweepView, context: Context) {
        view.apply(color: color.resolve(in: context.environment).cgColor)
    }
}
#endif

/// Capsule-clipped host of the sweeping segment layer; never a hit-test or accessibility
/// target.
final class ServiceProgressSweepView: PlatformLayerHostView {
    /// Animation key of the running sweep.
    static let animationKey = "sweep"
    /// The sweeping segment (exposed to hosted tests).
    let segmentLayer = CALayer()
    /// Track width the running animation was planned for.
    private var plannedWidth: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(iOS)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.addSublayer(segmentLayer)
        #elseif os(macOS)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = true
        layer?.addSublayer(segmentLayer)
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animations are dropped while detached (lazy realization, tab switches).
        plannedWidth = nil
        refresh()
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        plannedWidth = nil
        refresh()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #endif

    /// Apply the resolved segment colour.
    ///
    /// - Parameter color: Segment fill.
    func apply(color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        segmentLayer.backgroundColor = color
        CATransaction.commit()
        refresh()
    }

    /// Lay out the capsule clip and segment, and (re)start the sweep when the view is in a
    /// window and its width changed or the animation was dropped.
    private func refresh() {
        let size = bounds.size
        let width = size.width
        let segment = width * ServiceProgressSweep.segmentFraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        #if os(iOS)
        layer.cornerRadius = size.height / 2
        #elseif os(macOS)
        layer?.cornerRadius = size.height / 2
        #endif
        segmentLayer.cornerRadius = size.height / 2
        segmentLayer.bounds = CGRect(x: 0, y: 0, width: segment, height: size.height)
        segmentLayer.anchorPoint = .zero
        segmentLayer.position = .zero
        segmentLayer.setAffineTransform(CGAffineTransform(
            translationX: ServiceProgressSweep.restingOffset(trackWidth: width), y: 0
        ))
        CATransaction.commit()
        let running = window != nil && width > 0
        let dropped = segmentLayer.animation(forKey: Self.animationKey) == nil
        guard running else {
            plannedWidth = nil
            segmentLayer.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard plannedWidth != width || dropped else { return }
        plannedWidth = width
        segmentLayer.removeAnimation(forKey: Self.animationKey)
        segmentLayer.add(
            ServiceProgressSweep.animation(trackWidth: width, mediaTime: CACurrentMediaTime(), date: Date()),
            forKey: Self.animationKey
        )
    }
}
