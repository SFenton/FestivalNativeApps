import Combine
import CoreGraphics
import OSLog
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Shell-level background driver

/// Drives the session's single shared backdrop; hosted once by the app shell.
///
/// The host lives for the whole process, so the carousel's loader and clock
/// never restart on tab switches or pushes. It:
/// - loads the catalogue for the carousel when no page has (e.g. launching on
///   Leaderboards or a deep link),
/// - runs the one `ArtworkCarouselEngine` under the full artwork policy
///   (Reduce Motion, Low Data/Power, inactive scene, in-app toggles),
/// - turns the coordinator's resolved page mode into song-cover transitions:
///   the cover zooms out of the tapped list tile (or dissolves in), holds
///   still while the carousel pauses beneath it, and dissolves back when an
///   animated page returns.
///
/// Pages draw the backdrop themselves by mirroring this shared, timestamped
/// state (`FestivalBackdropView`), because `TabView` keeps an opaque container
/// above anything drawn behind it. The host itself draws nothing.
struct FestivalBackgroundHost: View {
    let session: FestivalSession

    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false
    @AppStorage("fst.accessibility.disableAnimatedArtwork") private var disableAnimation = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    private static let log = Logger(
        subsystem: "com.sfenton.festivalscoretracker", category: "artwork-background"
    )

    /// Inputs of the carousel loader; any change restarts it from the same state.
    private struct CarouselKey: Hashable {
        let paths: [String]
        let policy: ArtworkPlaybackPolicy
        let maxPixels: Int
        let revision: Int
    }

    /// Inputs that decide which song cover (if any) is shown.
    private struct CoverKey: Hashable {
        let mode: ArtworkBackgroundMode
        let policy: ArtworkPlaybackPolicy
        let maxPixels: Int
        let screen: CGRect
    }

    var body: some View {
        let coordinator = session.backgroundCoordinator
        GeometryReader { geometry in
            let maxPixels = ArtworkBackdropCanvas.maxPixels(
                for: geometry.size, displayScale: displayScale
            )
            let screen = geometry.frame(in: .global)
            let carouselPolicy = policy(
                visible: coordinator.carouselVisible,
                artCount: session.artworkPaths.count
            )
            let coverPolicy = policy(visible: true, artCount: 1)
            Color.clear
                .task(id: CarouselKey(
                    paths: session.artworkPaths, policy: carouselPolicy,
                    maxPixels: maxPixels, revision: session.publicationRevision
                )) {
                    await coordinator.carousel.play(
                        session.artworkPaths, maxPixels: maxPixels, policy: carouselPolicy
                    )
                }
                .task(id: CoverKey(
                    mode: coordinator.resolvedMode, policy: coverPolicy,
                    maxPixels: maxPixels, screen: screen
                )) {
                    await present(
                        coordinator.resolvedMode, coordinator: coordinator,
                        policy: coverPolicy, maxPixels: maxPixels, screen: screen
                    )
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: session.publicationRevision) {
            await session.loadArtworkCatalogIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        #if DEBUG
        .task { await debugCycle(coordinator) }
        #endif
    }

    /// Combine system and in-app preferences into one artwork policy.
    ///
    /// - Parameters:
    ///   - visible: Whether the carousel is uncovered.
    ///   - artCount: Number of candidate covers.
    /// - Returns: Loading and animation decisions.
    private func policy(visible: Bool, artCount: Int) -> ArtworkPlaybackPolicy {
        ArtworkPlaybackPolicy(
            activeScene: scenePhase == .active,
            visiblePage: visible && ArtworkNetworkStatus.canFetch(
                known: ArtworkNetworkStatus.shared.pathKnown,
                satisfied: ArtworkNetworkStatus.shared.pathSatisfied
            ),
            reduceMotion: reduceMotion || systemReduceMotion,
            disableAnimation: disableAnimation,
            reduceTransparency: lessTransparency || systemReduceTransparency,
            saveData: ArtworkNetworkStatus.shared.isConstrained,
            lowPower: lowPower, artCount: artCount
        )
    }

    // MARK: - Mode changes

    /// Move the shared backdrop to the page-on-top's mode.
    ///
    /// - Parameters:
    ///   - mode: Mode of the page on top.
    ///   - coordinator: Shared backdrop state.
    ///   - policy: Artwork policy for a single still cover.
    ///   - maxPixels: Decode bound for a full-screen cover.
    ///   - screen: Host frame in global coordinates (tile origins must intersect it).
    private func present(
        _ mode: ArtworkBackgroundMode, coordinator: FestivalBackgroundCoordinator,
        policy: ArtworkPlaybackPolicy, maxPixels: Int, screen: CGRect
    ) async {
        switch mode {
        case .carousel:
            coordinator.dismissOverlay()
        case let .song(optionalRaw):
            let raw = optionalRaw ?? ""
            let opaque = policy.saveData || policy.reduceTransparency
            if let current = coordinator.overlay, current.raw == raw,
               current.image != nil || opaque || raw.isEmpty {
                return
            }
            let motion = !policy.reduceMotion
            let origin = motion ? coordinator.sourceFrame(for: raw).flatMap {
                screen.intersects($0) ? $0 : nil
            } : nil
            var image: CGImage?
            if !raw.isEmpty && !opaque {
                // Keep the carousel until the scene and network allow a fetch.
                guard policy.mayLoad else { return }
                do {
                    image = try await session.preparedArtwork(
                        raw: raw, maxPixels: maxPixels
                    ).image
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code == .cancelled {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.log.error("Song backdrop unavailable: \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled else { return }
            let style: SongOverlay.Style = !motion
                ? .plain : origin != nil && image != nil ? .zoom : .dissolve
            coordinator.showOverlay(SongOverlay(
                raw: raw, image: image, origin: origin, start: .now, style: style
            ))
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel and a song cover
    /// (from a visible list tile when possible) so screenshots can show transitions.
    ///
    /// - Parameter coordinator: Coordinator to override.
    private func debugCycle(_ coordinator: FestivalBackgroundCoordinator) async {
        guard let raw = ProcessInfo.processInfo.environment["FST_DEBUG_BACKGROUND_CYCLE"],
              let seconds = Double(raw), seconds > 0 else { return }
        var showSong = true
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let art = coordinator.debugVisibleTileRaw() ?? session.artworkPaths.first
            else { continue }
            coordinator.debugOverride(showSong ? .song(art) : .carousel)
            showSong.toggle()
        }
    }
    #endif
}

// MARK: - Page mirror

/// A page's copy of the shared backdrop, identical on every page at any instant.
struct FestivalBackdropView: View {
    let coordinator: FestivalBackgroundCoordinator
    /// Whether the owning page is on screen (off-screen copies never tick).
    let appeared: Bool

    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast

    var body: some View {
        let carousel = coordinator.carousel.state
        ArtworkBackdropCanvas(
            carousel: carousel,
            overlay: coordinator.overlay,
            exiting: coordinator.exiting,
            animate: appeared,
            ticking: appeared && coordinator.overlayAnimating,
            showsArt: !(lessTransparency || systemReduceTransparency
                || ArtworkNetworkStatus.shared.isConstrained),
            dimming: moreContrast || systemContrast == .increased ? 0.82 : 0.7
        )
        .ignoresSafeArea()
    }
}
