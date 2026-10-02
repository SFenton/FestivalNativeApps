import CoreGraphics
import Combine
import Foundation
import Observation
import OSLog
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Motion presets

/// PWA-matched six-second zoom/pan endpoints in native point coordinates.
struct ArtworkMotionPreset: Equatable {
    let startScale: CGFloat
    let endScale: CGFloat
    let startX: CGFloat
    let endX: CGFloat
    let startY: CGFloat
    let endY: CGFloat

    static let all: [Self] = [
        .init(startScale: 1, endScale: 1.12, startX: 0, endX: 0, startY: 0, endY: 0),
        .init(startScale: 1.12, endScale: 1, startX: 0, endX: 0, startY: 0, endY: 0),
        .init(startScale: 1.18, endScale: 1.18, startX: 18, endX: -18, startY: 0, endY: 0),
        .init(startScale: 1.18, endScale: 1.18, startX: -18, endX: 18, startY: 0, endY: 0),
        .init(startScale: 1.18, endScale: 1.18, startX: 0, endX: 0, startY: 18, endY: -18),
        .init(startScale: 1.18, endScale: 1.18, startX: 0, endX: 0, startY: -18, endY: 18),
        .init(startScale: 1.18, endScale: 1.18, startX: -14, endX: 14, startY: -14, endY: 14),
        .init(startScale: 1.18, endScale: 1.18, startX: 14, endX: -14, startY: -14, endY: 14),
        .init(startScale: 1.18, endScale: 1.18, startX: -14, endX: 14, startY: 14, endY: -14),
        .init(startScale: 1.18, endScale: 1.18, startX: 14, endX: -14, startY: 14, endY: -14),
    ]

    static let still = Self(
        startScale: 1, endScale: 1, startX: 0, endX: 0, startY: 0, endY: 0
    )

    /// Interpolated scale and offset at a fraction of the six-second journey.
    ///
    /// - Parameter fraction: 0 at the start, 1 at the end (clamped).
    /// - Returns: Scale and translation to apply to the cover.
    func value(at fraction: Double) -> (scale: CGFloat, x: CGFloat, y: CGFloat) {
        let f = CGFloat(min(max(fraction, 0), 1))
        return (
            startScale + (endScale - startScale) * f,
            startX + (endX - startX) * f,
            startY + (endY - startY) * f
        )
    }
}

// MARK: - Timestamped backdrop state

/// Two stable compositing slots whose fades and motions are pure functions of time.
///
/// Every page mirrors the same value, so any number of on-screen copies (the
/// outgoing and incoming page of a push, or a newly selected tab) render the
/// identical frame and the animation never restarts or jumps.
struct ArtworkBackdropState: Equatable {
    struct Layer: Identifiable, Equatable {
        let id: Int
        var image: CGImage?
        var raw: String?
        var visible = false
        var moving = false
        var motion = ArtworkMotionPreset.still
        /// Start of this slot's one-second fade-in; nil when already fully shown.
        var fadeStart: Date?
        /// Start of the running six-second motion (shifted back when resuming).
        var motionStart: Date?
        /// Motion progress retained while paused.
        var motionFraction: Double = 0

        /// Motion progress at a render instant.
        ///
        /// - Parameter date: Render time.
        /// - Returns: Fraction of the six-second motion in 0...1.
        func fraction(at date: Date) -> Double {
            guard moving, let motionStart else { return motionFraction }
            return min(max(date.timeIntervalSince(motionStart) / 6, 0), 1)
        }

        /// Fade-in opacity at a render instant (ease-in-out over one second).
        ///
        /// - Parameter date: Render time.
        /// - Returns: Opacity in 0...1.
        func fadeOpacity(at date: Date) -> Double {
            guard let fadeStart else { return 1 }
            return BackdropEasing.inOut(date.timeIntervalSince(fadeStart) / 1)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.image === rhs.image && lhs.raw == rhs.raw
                && lhs.visible == rhs.visible && lhs.moving == rhs.moving
                && lhs.motion == rhs.motion && lhs.fadeStart == rhs.fadeStart
                && lhs.motionStart == rhs.motionStart
                && lhs.motionFraction == rhs.motionFraction
        }
    }

    private(set) var layers = [Layer(id: 0), Layer(id: 1)]
    private(set) var active = 0

    /// Seed a deterministic image for hosted visual tests, never a disk cache.
    ///
    /// - Parameter preview: Already decoded fixture image.
    init(preview: CGImage? = nil) {
        if let preview {
            show(preview, raw: "__preview__", fade: false)
        }
    }

    var currentRaw: String? { layers[active].raw }
    var hasImage: Bool { layers[active].image != nil }
    /// True while any slot is moving.
    var animating: Bool { layers.contains { $0.moving } }

    /// Replace the active art with one fetched under the current app session.
    ///
    /// - Parameters:
    ///   - image: Decoded, bounded image.
    ///   - raw: Original artwork URL or fixture path.
    ///   - now: Fade start instant.
    ///   - fade: Dissolve in from the brand surface rather than appearing at once.
    mutating func show(_ image: CGImage, raw: String, now: Date = .now, fade: Bool = true) {
        layers = [Layer(id: 0), Layer(id: 1)]
        active = 0
        layers[active].image = image
        layers[active].raw = raw
        layers[active].visible = true
        layers[active].fadeStart = fade ? now : nil
    }

    /// Animate the visible layer through one of ten source-backed motions.
    ///
    /// - Parameters:
    ///   - motion: Six-second zoom/pan endpoint pair.
    ///   - now: Motion start instant.
    mutating func startMotion(_ motion: ArtworkMotionPreset, now: Date = .now) {
        guard !layers[active].moving else { return }
        layers[active].motion = motion
        layers[active].motionFraction = 0
        layers[active].motionStart = now
        layers[active].moving = true
    }

    /// Continue a paused motion where it stopped, or start a fresh one.
    ///
    /// - Parameters:
    ///   - fallback: Preset used when the visible layer has no motion yet.
    ///   - now: Resume instant.
    mutating func resumeMotion(or fallback: ArtworkMotionPreset, now: Date = .now) {
        guard !layers[active].moving else { return }
        let layer = layers[active]
        guard layer.motion != .still, layer.motionFraction < 1 else {
            startMotion(fallback, now: now)
            return
        }
        layers[active].motionStart = now.addingTimeInterval(-layer.motionFraction * 6)
        layers[active].moving = true
    }

    /// Decode only one next image while the old layer remains visible.
    ///
    /// - Parameters:
    ///   - image: Incoming bounded image.
    ///   - raw: Next original artwork path.
    ///   - motion: Motion preset for the standby layer.
    mutating func stage(
        _ image: CGImage, raw: String, motion: ArtworkMotionPreset
    ) {
        layers[1 - active] = Layer(
            id: 1 - active, image: image, raw: raw, motion: motion
        )
    }

    /// Crossfade without changing either slot's identity or decoding another cover.
    ///
    /// - Parameter now: Fade and motion start instant.
    mutating func crossfade(now: Date = .now) {
        guard layers[1 - active].image != nil else { return }
        layers[active].visible = false
        layers[1 - active].visible = true
        layers[1 - active].fadeStart = now
        layers[1 - active].motionFraction = 0
        layers[1 - active].motionStart = now
        layers[1 - active].moving = true
        active = 1 - active
    }

    /// Release the old slot after its one-second opacity transition.
    mutating func releaseHidden() {
        layers[1 - active] = Layer(id: 1 - active)
        layers[active].fadeStart = nil
    }

    /// Stop work immediately while hidden or honoring reduced motion, keeping
    /// the current zoom/pan so a later resume continues without a jump.
    ///
    /// - Parameter now: Pause instant.
    mutating func pauseMotion(now: Date = .now) {
        for index in layers.indices where layers[index].moving {
            layers[index].motionFraction = layers[index].fraction(at: now)
            layers[index].motionStart = nil
            layers[index].moving = false
        }
        releaseHidden()
    }

    /// Remove both image buffers when data saving or opaque content is requested.
    mutating func clear() {
        layers = [Layer(id: 0), Layer(id: 1)]
        active = 0
    }
}

/// Shared easing so every mirror computes identical values.
enum BackdropEasing {
    /// Cubic ease-in-out.
    ///
    /// - Parameter t: Linear progress (clamped to 0...1).
    /// - Returns: Eased progress.
    static func inOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// CSS `ease`, i.e. `cubic-bezier(0.25, 0.1, 0.25, 1)` (the web's default
    /// `transition` timing, used by `BackgroundImage`'s opacity fade).
    ///
    /// - Parameter t: Linear progress (clamped to 0...1).
    /// - Returns: Eased progress.
    static func cssEase(_ t: Double) -> Double {
        cubicBezier(t, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    }

    /// Evaluate a CSS `cubic-bezier(x1, y1, x2, y2)` timing function.
    ///
    /// - Parameters:
    ///   - t: Linear progress (clamped to 0...1).
    ///   - x1: First control point x.
    ///   - y1: First control point y.
    ///   - x2: Second control point x.
    ///   - y2: Second control point y.
    /// - Returns: Eased progress.
    static func cubicBezier(
        _ t: Double, x1: Double, y1: Double, x2: Double, y2: Double
    ) -> Double {
        let x = min(max(t, 0), 1)
        if x == 0 || x == 1 { return x }
        func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        // Bisection on the monotonic x(s): 30 halvings is below 1e-9.
        var low = 0.0, high = 1.0, s = x
        for _ in 0..<30 {
            s = (low + high) / 2
            if bezier(s, x1, x2) < x { low = s } else { high = s }
        }
        return bezier((low + high) / 2, y1, y2)
    }
}

// MARK: - Modes and schedule

/// Global cover rotation on landing pages, or a static per-song detail image.
enum ArtworkBackgroundMode: Hashable {
    case carousel
    case song(String?)
}

/// Crossfades start five seconds apart, including their one-second overlap.
struct ArtworkTransitionSchedule {
    static let dwell: Duration = .seconds(5)
    static let fade: Duration = .seconds(1)
    static let motion: Duration = .seconds(6)

    /// Start no sooner than the dwell mark and never before art is ready.
    ///
    /// Generic over the instant so tests can pace the carousel with a manual clock
    /// (see `ArtworkCarouselEngine.play(_:maxPixels:policy:clock:)`).
    ///
    /// - Parameters:
    ///   - previous: Start of the preceding cover's dwell.
    ///   - ready: Time the standby image became available.
    /// - Returns: The next native fade-start instant.
    static func deadline<Instant: InstantProtocol>(
        after previous: Instant, ready: Instant
    ) -> Instant where Instant.Duration == Duration {
        max(previous.advanced(by: dwell), ready)
    }
}

// MARK: - Carousel engine

/// Loads covers and advances the timestamped backdrop on five-second deadlines.
///
/// The app shell owns one engine per session (through
/// `FestivalBackgroundCoordinator`), so tab switches and pushes never restart
/// the carousel; `ArtworkBackground` owns a private one for standalone use.
@MainActor
@Observable
final class ArtworkCarouselEngine {
    /// Current slots; mirrors render it as a pure function of time.
    private(set) var state: ArtworkBackdropState

    @ObservationIgnored
    private weak var session: FestivalSession?
    @ObservationIgnored
    private var failedArtwork: Set<String> = []
    @ObservationIgnored
    private var failurePool: [String] = []
    @ObservationIgnored
    private var failureRevision = -1
    @ObservationIgnored
    private var wasLoading = false

    private static let log = Logger(
        subsystem: "com.sfenton.festivalscoretracker", category: "artwork-background"
    )
    static let maxInitialAttempts = 3
    static let maxAttemptsPerDwell = 3
    static let maxFailuresPerPool = 5

    /// Create an engine for one session's artwork cache.
    ///
    /// - Parameters:
    ///   - session: Artwork cache owner (held weakly).
    ///   - preview: Synthetic decoded image for offline hosted snapshots.
    init(session: FestivalSession, preview: CGImage? = nil) {
        self.session = session
        state = ArtworkBackdropState(preview: preview)
    }

    /// Preload one standby cover and start fades on paced deadlines.
    ///
    /// Returns only when cancelled, when playback is not allowed, or when the
    /// publication pool's failure budget is spent.
    ///
    /// - Parameters:
    ///   - paths: Already shuffled, bounded catalogue paths or one song cover.
    ///   - maxPixels: Safe off-main decode size.
    ///   - policy: Effective system/app visibility and resource policy.
    ///   - clock: Paces dwells and retries; the real continuous clock by default.
    ///     Tests inject a manual clock so pacing never depends on wall-clock
    ///     scheduling on a busy shared main actor.
    func play(
        _ paths: [String], maxPixels: Int, policy: ArtworkPlaybackPolicy,
        clock: any Clock<Duration> = ContinuousClock()
    ) async {
        await play(paths, maxPixels: maxPixels, policy: policy, on: clock)
    }

    /// Concrete-clock body of `play(_:maxPixels:policy:clock:)`.
    ///
    /// - Parameters:
    ///   - paths: Already shuffled, bounded catalogue paths or one song cover.
    ///   - maxPixels: Safe off-main decode size.
    ///   - policy: Effective system/app visibility and resource policy.
    ///   - clock: Paces dwells and retries.
    private func play<C: Clock<Duration>>(
        _ paths: [String], maxPixels: Int, policy: ArtworkPlaybackPolicy, on clock: C
    ) async {
        guard !Task.isCancelled, let session else { return }
        if failurePool != paths || failureRevision != session.publicationRevision
            || (!wasLoading && policy.mayLoad) {
            failedArtwork.removeAll()
            failurePool = paths
            failureRevision = session.publicationRevision
        }
        wasLoading = policy.mayLoad
        guard policy.mayLoad else {
            if paths.isEmpty || policy.saveData || policy.reduceTransparency {
                state.clear()
            } else {
                state.pauseMotion()
            }
            return
        }
        var cursor = paths.firstIndex(of: state.currentRaw ?? "") ?? 0
        if !state.hasImage || !paths.contains(state.currentRaw ?? "") {
            let initialAttempt = clock.now
            while !Task.isCancelled {
                if let initial = await loadFirst(
                    paths, maxPixels: maxPixels, fade: policy.mayAnimate
                ) {
                    cursor = initial
                    break
                }
                let remaining = Set(paths).subtracting(failedArtwork)
                guard !remaining.isEmpty,
                      failedArtwork.count < Self.maxFailuresPerPool else { return }
                do {
                    try await clock.sleep(until: ArtworkTransitionSchedule.deadline(
                        after: initialAttempt, ready: clock.now
                    ), tolerance: nil)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    Self.log.error("Artwork retry unavailable: \(error.localizedDescription)")
                    return
                }
            }
            guard !Task.isCancelled else { return }
        }
        guard policy.mayAnimate else {
            state.pauseMotion()
            return
        }
        var lastTransition = clock.now
        do {
            guard let motion = ArtworkMotionPreset.all.randomElement() else {
                Self.log.error("Artwork motion presets unavailable")
                state.pauseMotion()
                return
            }
            state.resumeMotion(or: motion)
            while true {
                try Task.checkCancellation()
                let standby = try await Self.preloadNext(
                    session: session, after: cursor, paths: paths,
                    maxPixels: maxPixels, excluding: failedArtwork
                )
                try Task.checkCancellation()
                failedArtwork.formUnion(standby.rejected)
                guard let next = standby.next else {
                    let remaining = Set(paths).subtracting(failedArtwork)
                        .subtracting([paths[cursor]])
                    guard !remaining.isEmpty,
                          failedArtwork.count < Self.maxFailuresPerPool else {
                        state.pauseMotion()
                        return
                    }
                    let retryAt = ArtworkTransitionSchedule.deadline(
                        after: lastTransition, ready: clock.now
                    )
                    try await clock.sleep(until: retryAt, tolerance: nil)
                    lastTransition = retryAt
                    continue
                }
                guard let nextMotion = ArtworkMotionPreset.all.randomElement() else {
                    Self.log.error("Artwork motion presets unavailable")
                    state.pauseMotion()
                    return
                }
                state.stage(next.image, raw: paths[next.index], motion: nextMotion)
                await Task.yield()
                try Task.checkCancellation()
                let deadline = ArtworkTransitionSchedule.deadline(
                    after: lastTransition, ready: clock.now
                )
                try await clock.sleep(until: deadline, tolerance: nil)
                try Task.checkCancellation()
                state.crossfade()
                lastTransition = deadline
                try await clock.sleep(
                    until: deadline.advanced(by: ArtworkTransitionSchedule.fade), tolerance: nil
                )
                try Task.checkCancellation()
                state.releaseHidden()
                cursor = next.index
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Self.log.error("Artwork transition unavailable: \(error.localizedDescription)")
            state.pauseMotion()
        }
    }

    /// Result of one bounded standby search.
    struct Standby {
        let next: (index: Int, image: CGImage)?
        let rejected: Set<String>
    }

    /// Skip bad covers without fetching more than three candidates per dwell.
    ///
    /// - Parameters:
    ///   - session: Artwork cache owner.
    ///   - cursor: Index of the currently visible art.
    ///   - paths: Shuffled, bounded public artwork paths.
    ///   - maxPixels: Size bound for off-main decode.
    ///   - excluding: Previously failed covers in this publication pool.
    /// - Returns: One prepared standby image and explicitly logged failed paths.
    /// - Throws: Cancellation or invalid cursor; errors for individual covers are logged.
    static func preloadNext(
        session: FestivalSession, after cursor: Int, paths: [String], maxPixels: Int,
        excluding: Set<String>
    ) async throws -> Standby {
        guard paths.indices.contains(cursor) else {
            throw FestivalAPIError.invalidResource
        }
        var rejected: Set<String> = []
        let budget = min(
            maxAttemptsPerDwell, max(0, maxFailuresPerPool - excluding.count)
        )
        var attempts = 0
        if paths.count > 1 {
            for advance in 1..<paths.count {
                let index = (cursor + advance) % paths.count
                let raw = paths[index]
                if raw == paths[cursor] || excluding.contains(raw)
                    || rejected.contains(raw) {
                    continue
                }
                if attempts >= budget { break }
                attempts += 1
                do {
                    let artwork = try await session.preparedArtwork(
                        raw: raw, maxPixels: maxPixels
                    )
                    try Task.checkCancellation()
                    return Standby(next: (index, artwork.image), rejected: rejected)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw error
                } catch {
                    try Task.checkCancellation()
                    rejected.insert(raw)
                    log.error("Artwork standby unavailable: \(error.localizedDescription)")
                }
            }
        }
        return Standby(next: nil, rejected: rejected)
    }

    /// Skip invalid covers without a rapid retry loop or a misleading image.
    ///
    /// - Parameters:
    ///   - paths: Candidate artwork paths in shuffled order.
    ///   - maxPixels: Display-size decoding cap.
    ///   - fade: Dissolve the first cover in from the brand surface.
    /// - Returns: Position of the first successfully displayed image, if any.
    private func loadFirst(
        _ paths: [String], maxPixels: Int, fade: Bool
    ) async -> Int? {
        guard let session else { return nil }
        let budget = min(
            Self.maxInitialAttempts,
            max(0, Self.maxFailuresPerPool - failedArtwork.count)
        )
        var attempts = 0
        for (index, raw) in paths.enumerated() {
            if failedArtwork.contains(raw) { continue }
            if attempts >= budget { break }
            attempts += 1
            do {
                let result = try await session.preparedArtwork(
                    raw: raw, maxPixels: maxPixels
                )
                try Task.checkCancellation()
                state.show(result.image, raw: raw, fade: fade)
                return index
            } catch is CancellationError {
                return nil
            } catch let error as URLError where error.code == .cancelled {
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                failedArtwork.insert(raw)
                Self.log.error("Artwork background unavailable: \(error.localizedDescription)")
            }
        }
        guard !Task.isCancelled else { return nil }
        state.clear()
        return nil
    }
}

// MARK: - Standalone background

/// Self-driven decorative art (own engine), used by hosted tests and previews.
///
/// App pages use `.festivalBackground(_:session:visible:)` instead, which
/// mirrors the one shared engine owned by the shell.
struct ArtworkBackground: View {
    let mode: ArtworkBackgroundMode
    let session: FestivalSession
    let visible: Bool
    private let previewOnly: Bool
    private let saveDataOverride: Bool?
    private let clock: any Clock<Duration>
    @State private var engine: ArtworkCarouselEngine
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.disableAnimatedArtwork") private var disableAnimation = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible

    /// Install one background with an optional original-image visual fixture.
    ///
    /// - Parameters:
    ///   - mode: Shuffled catalogue rotation or static song artwork.
    ///   - session: One process-scoped artwork and publication cache.
    ///   - visible: True only for the currently selected root page.
    ///   - previewImage: Synthetic decoded image for offline hosted snapshots.
    ///   - saveDataOverride: Test-only constrained-path input.
    ///   - clock: Test-only pacing clock; a manual clock lets retry-pacing tests
    ///     advance dwells explicitly instead of racing real wall-clock sleeps on a
    ///     busy shared main actor.
    init(
        mode: ArtworkBackgroundMode, session: FestivalSession,
        visible: Bool = true, previewImage: CGImage? = nil,
        saveDataOverride: Bool? = nil, clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.mode = mode
        self.session = session
        self.visible = visible
        self.previewOnly = previewImage != nil
        self.saveDataOverride = saveDataOverride
        self.clock = clock
        _engine = State(initialValue: ArtworkCarouselEngine(
            session: session, preview: previewImage
        ))
    }

    /// Read the live OS and additive app preferences without a persistent timer.
    private func policy(artCount: Int) -> ArtworkPlaybackPolicy {
        let usablePath = saveDataOverride != nil || ArtworkNetworkStatus.canFetch(
            known: ArtworkNetworkStatus.shared.pathKnown,
            satisfied: ArtworkNetworkStatus.shared.pathSatisfied
        )
        return ArtworkPlaybackPolicy(
            activeScene: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
            visiblePage: visible && usablePath,
            reduceMotion: reduceMotion || systemReduceMotion,
            disableAnimation: disableAnimation || DebugAnimationOverride.stillBackground,
            reduceTransparency: lessTransparency || systemReduceTransparency,
            saveData: saveDataOverride ?? ArtworkNetworkStatus.shared.isConstrained,
            lowPower: lowPower, artCount: artCount
        )
    }

    /// Resolve images only from the catalogue or the active song.
    private var paths: [String] {
        switch mode {
        case .carousel:
            session.artworkPaths
        case let .song(raw):
            raw.flatMap { $0.isEmpty ? nil : [$0] } ?? []
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let candidates = paths
            let presentation = policy(artCount: candidates.count)
            let maxPixels = ArtworkBackdropCanvas.maxPixels(
                for: geometry.size, displayScale: displayScale
            )
            ArtworkBackdropCanvas(
                carousel: engine.state, overlay: nil, exiting: nil,
                animate: presentation.mayAnimate,
                showsArt: !presentation.saveData && !presentation.reduceTransparency,
                dimming: moreContrast || systemContrast == .increased ? 0.82 : 0.7
            )
            .task(id: TaskKey(
                mode: mode, paths: candidates, policy: presentation,
                maxPixels: maxPixels, revision: session.publicationRevision
            )) {
                if !previewOnly {
                    await engine.play(
                        candidates, maxPixels: maxPixels, policy: presentation,
                        clock: clock
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(
            NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private struct TaskKey: Hashable {
        let mode: ArtworkBackgroundMode
        let paths: [String]
        let policy: ArtworkPlaybackPolicy
        let maxPixels: Int
        let revision: Int
    }

    /// Skip bad covers without fetching more than three candidates per dwell.
    ///
    /// - Parameters:
    ///   - cursor: Index of the currently visible art.
    ///   - paths: Shuffled, bounded public artwork paths.
    ///   - maxPixels: Size bound for off-main decode.
    ///   - excluding: Previously failed covers in this publication pool.
    /// - Returns: One prepared standby image and explicitly logged failed paths.
    /// - Throws: Cancellation or invalid cursor; errors for individual covers are logged.
    func preloadNext(
        after cursor: Int, paths: [String], maxPixels: Int,
        excluding: Set<String>
    ) async throws -> ArtworkCarouselEngine.Standby {
        try await ArtworkCarouselEngine.preloadNext(
            session: session, after: cursor, paths: paths,
            maxPixels: maxPixels, excluding: excluding
        )
    }
}
