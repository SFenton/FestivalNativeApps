import Combine
import CoreGraphics
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
///   (Reduce Motion, Low Data/Power, inactive scene, in-app toggles) and pauses
///   it while a sheet covers the page (`FestivalSheetCoverage`),
/// - turns the coordinator's resolved page mode into song-cover transitions:
///   like the web's `BackgroundImage`, the cover fades in over the animated
///   background (300 ms CSS `ease`) once decoded, holds still while the
///   carousel pauses beneath it, and fades back out when a carousel page returns.
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
    @Environment(\.festivalWindowVisible) private var windowVisible

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
    }

    var body: some View {
        let coordinator = session.backgroundCoordinator
        GeometryReader { geometry in
            let maxPixels = ArtworkBackdropCanvas.maxPixels(
                for: geometry.size, displayScale: displayScale
            )
            let carouselPolicy = policy(
                visible: coordinator.carouselVisible
                    && !FestivalSheetCoverage.shared.isCovered,
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
                    maxPixels: maxPixels
                )) {
                    await present(
                        coordinator.resolvedMode, coordinator: coordinator,
                        policy: coverPolicy, maxPixels: maxPixels
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
        ArtworkPlaybackPolicy.resolve(
            sceneActive: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
            visible: visible,
            pathKnown: ArtworkNetworkStatus.shared.pathKnown,
            pathSatisfied: ArtworkNetworkStatus.shared.pathSatisfied,
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
    private func present(
        _ mode: ArtworkBackgroundMode, coordinator: FestivalBackgroundCoordinator,
        policy: ArtworkPlaybackPolicy, maxPixels: Int
    ) async {
        await coordinator.present(mode, session: session, policy: policy, maxPixels: maxPixels)
    }

    // MARK: - Debug

    #if DEBUG
    /// `FST_DEBUG_BACKGROUND_CYCLE=<seconds>` alternates carousel and a song cover
    /// so screenshots can show transitions.
    ///
    /// - Parameter coordinator: Coordinator to override.
    private func debugCycle(_ coordinator: FestivalBackgroundCoordinator) async {
        await coordinator.debugCycle(session: session)
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
        if DebugAnimationOverride.noBackdrop {
            BrandTokens.appBackground.ignoresSafeArea()
        } else if DebugAnimationOverride.flatBackdrop {
            ArtworkBackdropCanvas.gray(0.5 * (1 - dimming)).ignoresSafeArea()
        } else {
            canvas
        }
    }

    private var canvas: some View {
        let carousel = coordinator.carousel.state
        return ArtworkBackdropCanvas(
            carousel: carousel,
            overlay: coordinator.overlay,
            exiting: coordinator.exiting,
            animate: appeared,
            showsArt: BackdropPresentation.showsArt(
                appLessTransparency: lessTransparency,
                systemReduceTransparency: systemReduceTransparency,
                constrained: ArtworkNetworkStatus.shared.isConstrained
            ),
            dimming: dimming
        )
        .ignoresSafeArea()
    }

    /// Black-overlay equivalent (0.7, or 0.82 with increased contrast).
    private var dimming: Double {
        BackdropPresentation.dimming(
            appMoreContrast: moreContrast, systemIncreased: systemContrast == .increased
        )
    }
}
