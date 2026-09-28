import CoreGraphics
import Combine
import Foundation
import OSLog
import SwiftUI
import FestivalCore
import FestivalDesign

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
}

/// Two stable compositing layers keep the incoming six-second motion alive.
struct ArtworkBackdropState {
    struct Layer: Identifiable {
        let id: Int
        var image: CGImage?
        var raw: String?
        var visible = false
        var moving = false
        var motion = ArtworkMotionPreset.still
    }

    private(set) var layers = [Layer(id: 0), Layer(id: 1)]
    private(set) var active = 0

    /// Seed a deterministic image for hosted visual tests, never a disk cache.
    ///
    /// - Parameter preview: Already decoded fixture image.
    init(preview: CGImage? = nil) {
        if let preview {
            show(preview, raw: "__preview__")
        }
    }

    var currentRaw: String? { layers[active].raw }
    var hasImage: Bool { layers[active].image != nil }

    /// Replace the active art with one fetched under the current app session.
    ///
    /// - Parameters:
    ///   - image: Decoded, bounded image.
    ///   - raw: Original artwork URL or fixture path.
    mutating func show(_ image: CGImage, raw: String) {
        layers = [Layer(id: 0), Layer(id: 1)]
        active = 0
        layers[active].image = image
        layers[active].raw = raw
        layers[active].visible = true
    }

    /// Animate the visible layer through one of ten source-backed motions.
    ///
    /// - Parameter motion: Six-second zoom/pan endpoint pair.
    mutating func startMotion(_ motion: ArtworkMotionPreset) {
        guard !layers[active].moving else { return }
        layers[active].motion = motion
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
    mutating func crossfade() {
        guard layers[1 - active].image != nil else { return }
        layers[active].visible = false
        layers[1 - active].visible = true
        layers[1 - active].moving = true
        active = 1 - active
    }

    /// Release the old slot after its one-second opacity transition.
    mutating func releaseHidden() {
        layers[1 - active] = Layer(id: 1 - active)
    }

    /// Stop work immediately while hidden or honoring reduced motion.
    mutating func pauseMotion() {
        layers[0].moving = false
        layers[1].moving = false
        releaseHidden()
    }

    /// Remove both image buffers when data saving or opaque content is requested.
    mutating func clear() {
        layers = [Layer(id: 0), Layer(id: 1)]
        active = 0
    }
}

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

    /// Start no sooner than the five-second mark and never before art is ready.
    ///
    /// - Parameters:
    ///   - previous: Start of the preceding cover's dwell.
    ///   - ready: Time the standby image became available.
    /// - Returns: The next native fade-start instant.
    static func deadline(
        after previous: ContinuousClock.Instant, ready: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        max(previous.advanced(by: dwell), ready)
    }
}

/// Decorative art under native navigation and branded content, never interactive.
struct ArtworkBackground: View {
    let mode: ArtworkBackgroundMode
    let session: FestivalSession
    let visible: Bool
    private let previewOnly: Bool
    private let saveDataOverride: Bool?
    @State private var layers: ArtworkBackdropState
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var failedArtwork: Set<String> = []
    @State private var failurePool: [String] = []
    @State private var failureRevision = -1
    @State private var wasLoading = false
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.disableAnimatedArtwork") private var disableAnimation = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    private static let log = Logger(
        subsystem: "com.sfenton.festivalscoretracker", category: "artwork-background"
    )
    private static let maxInitialAttempts = 3
    private static let maxAttemptsPerDwell = 3
    private static let maxFailuresPerPool = 5

    /// Install one background with an optional original-image visual fixture.
    ///
    /// - Parameters:
    ///   - mode: Shuffled catalogue rotation or static song artwork.
    ///   - session: One process-scoped artwork and publication cache.
    ///   - visible: True only for the currently selected root page.
    ///   - previewImage: Synthetic decoded image for offline hosted snapshots.
    ///   - saveDataOverride: Test-only constrained-path input.
    init(
        mode: ArtworkBackgroundMode, session: FestivalSession,
        visible: Bool = true, previewImage: CGImage? = nil,
        saveDataOverride: Bool? = nil
    ) {
        self.mode = mode
        self.session = session
        self.visible = visible
        self.previewOnly = previewImage != nil
        self.saveDataOverride = saveDataOverride
        _layers = State(initialValue: ArtworkBackdropState(preview: previewImage))
    }

    /// Read the live OS and additive app preferences without a persistent timer.
    private func policy(artCount: Int) -> ArtworkPlaybackPolicy {
        let usablePath = saveDataOverride != nil || ArtworkNetworkStatus.canFetch(
            known: ArtworkNetworkStatus.shared.pathKnown,
            satisfied: ArtworkNetworkStatus.shared.pathSatisfied
        )
        return ArtworkPlaybackPolicy(
            activeScene: scenePhase == .active,
            visiblePage: visible && usablePath,
            reduceMotion: reduceMotion || systemReduceMotion,
            disableAnimation: disableAnimation,
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
            let maxPixels = min(
                1024, max(96, Int((max(geometry.size.width, geometry.size.height)
                    * min(displayScale, 2)).rounded(.up)))
            )
            let dimming = moreContrast || systemContrast == .increased ? 0.82 : 0.7
            ZStack {
                BrandTokens.appBackground
                if !presentation.saveData && !presentation.reduceTransparency {
                    if let image = layers.layers[0].image {
                        artworkLayer(
                            image, layer: layers.layers[0], size: geometry.size,
                            animate: presentation.mayAnimate, dimming: dimming
                        )
                    }
                    if let image = layers.layers[1].image {
                        artworkLayer(
                            image, layer: layers.layers[1], size: geometry.size,
                            animate: presentation.mayAnimate, dimming: dimming
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .transaction { transaction in
                if !presentation.mayAnimate {
                    transaction.animation = nil
                }
            }
            .task(id: TaskKey(
                mode: mode, paths: candidates, policy: presentation,
                maxPixels: maxPixels, revision: session.publicationRevision
            )) {
                if !previewOnly {
                    await play(candidates, maxPixels: maxPixels, policy: presentation)
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

    /// Keep one compositor layer stable through its full six-second transform.
    ///
    /// - Parameters:
    ///   - image: Decoded background cover.
    ///   - layer: Stable A/B slot and selected motion preset.
    ///   - size: Available page background bounds.
    ///   - animate: Whether OS and app preferences permit animation.
    ///   - dimming: Black-overlay equivalent applied without a translucent layer.
    /// - Returns: Noninteractive, scaled-to-fill cover.
    private func artworkLayer(
        _ image: CGImage, layer: ArtworkBackdropState.Layer,
        size: CGSize, animate: Bool, dimming: Double
    ) -> some View {
        let lightness = 1 - dimming
        return Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .colorMultiply(Color(
                .sRGB, red: lightness, green: lightness,
                blue: lightness, opacity: 1
            ))
            .frame(width: size.width, height: size.height)
            .scaleEffect(
                animate && layer.moving ? layer.motion.endScale : layer.motion.startScale
            )
            .offset(
                x: animate && layer.moving ? layer.motion.endX : layer.motion.startX,
                y: animate && layer.moving ? layer.motion.endY : layer.motion.startY
            )
            .animation(animate ? .linear(duration: 6) : nil, value: layer.moving)
            .opacity(layer.visible ? 1 : 0)
            .animation(animate ? .easeInOut(duration: 1) : nil, value: layer.visible)
            .accessibilityHidden(true)
    }

    private struct TaskKey: Hashable {
        let mode: ArtworkBackgroundMode
        let paths: [String]
        let policy: ArtworkPlaybackPolicy
        let maxPixels: Int
        let revision: Int
    }

    /// Preload one standby cover and start fades on five-second deadlines.
    ///
    /// - Parameters:
    ///   - paths: Already shuffled, bounded catalogue paths or one song cover.
    ///   - maxPixels: Safe off-main decode size.
    ///   - policy: Effective system/app visibility and resource policy.
    private func play(
        _ paths: [String], maxPixels: Int, policy: ArtworkPlaybackPolicy
    ) async {
        guard !Task.isCancelled else { return }
        if failurePool != paths || failureRevision != session.publicationRevision
            || (!wasLoading && policy.mayLoad) {
            failedArtwork.removeAll()
            failurePool = paths
            failureRevision = session.publicationRevision
        }
        wasLoading = policy.mayLoad
        guard policy.mayLoad else {
            if paths.isEmpty || policy.saveData || policy.reduceTransparency {
                layers.clear()
            } else {
                layers.pauseMotion()
            }
            return
        }
        var cursor = paths.firstIndex(of: layers.currentRaw ?? "") ?? 0
        if !layers.hasImage || !paths.contains(layers.currentRaw ?? "") {
            let clock = ContinuousClock()
            let initialAttempt = clock.now
            while !Task.isCancelled {
                if let initial = await loadFirst(paths, maxPixels: maxPixels) {
                    cursor = initial
                    break
                }
                let remaining = Set(paths).subtracting(failedArtwork)
                guard !remaining.isEmpty,
                      failedArtwork.count < Self.maxFailuresPerPool else { return }
                do {
                    try await clock.sleep(until: ArtworkTransitionSchedule.deadline(
                        after: initialAttempt, ready: clock.now
                    ))
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
            layers.pauseMotion()
            return
        }
        let clock = ContinuousClock()
        var lastTransition = clock.now
        do {
            guard let motion = ArtworkMotionPreset.all.randomElement() else {
                Self.log.error("Artwork motion presets unavailable")
                layers.pauseMotion()
                return
            }
            withAnimation(.linear(duration: 6)) {
                layers.startMotion(motion)
            }
            while true {
                try Task.checkCancellation()
                let standby = try await preloadNext(
                    after: cursor, paths: paths,
                    maxPixels: maxPixels, excluding: failedArtwork
                )
                try Task.checkCancellation()
                failedArtwork.formUnion(standby.rejected)
                guard let next = standby.next else {
                    let remaining = Set(paths).subtracting(failedArtwork)
                        .subtracting([paths[cursor]])
                    guard !remaining.isEmpty,
                          failedArtwork.count < Self.maxFailuresPerPool else {
                        layers.pauseMotion()
                        return
                    }
                    let retryAt = ArtworkTransitionSchedule.deadline(
                        after: lastTransition, ready: clock.now
                    )
                    try await clock.sleep(until: retryAt)
                    lastTransition = retryAt
                    continue
                }
                guard let nextMotion = ArtworkMotionPreset.all.randomElement() else {
                    Self.log.error("Artwork motion presets unavailable")
                    layers.pauseMotion()
                    return
                }
                layers.stage(next.image, raw: paths[next.index], motion: nextMotion)
                await Task.yield()
                try Task.checkCancellation()
                let deadline = ArtworkTransitionSchedule.deadline(
                    after: lastTransition, ready: clock.now
                )
                try await clock.sleep(until: deadline)
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 1)) {
                    layers.crossfade()
                }
                lastTransition = deadline
                try await clock.sleep(
                    until: deadline.advanced(by: ArtworkTransitionSchedule.fade)
                )
                try Task.checkCancellation()
                layers.releaseHidden()
                cursor = next.index
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Self.log.error("Artwork transition unavailable: \(error.localizedDescription)")
            layers.pauseMotion()
        }
    }

    struct Standby {
        let next: (index: Int, image: CGImage)?
        let rejected: Set<String>
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
    ) async throws -> Standby {
        guard paths.indices.contains(cursor) else {
            throw FestivalAPIError.invalidResource
        }
        var rejected: Set<String> = []
        let budget = min(
            Self.maxAttemptsPerDwell,
            max(0, Self.maxFailuresPerPool - excluding.count)
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
                    Self.log.error(
                        "Artwork standby unavailable: \(error.localizedDescription)"
                    )
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
    /// - Returns: Position of the first successfully displayed image, if any.
    private func loadFirst(
        _ paths: [String], maxPixels: Int
    ) async -> Int? {
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
                layers.show(result.image, raw: raw)
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
        layers.clear()
        return nil
    }
}
