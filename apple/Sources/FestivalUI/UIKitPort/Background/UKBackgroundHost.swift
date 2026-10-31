#if os(iOS)
import CoreGraphics
import FestivalCore
import UIKit

// MARK: - Host

/// Drives the session's single shared backdrop for a window: the UIKit counterpart of
/// ``FestivalBackgroundHost``, owned by ``UKBackgroundView`` and living as long as it.
///
/// It runs the one `ArtworkCarouselEngine` under the full artwork policy (Reduce Motion,
/// Low Data / Low Power, inactive scene, the in-app toggles, sheet coverage) and turns the
/// coordinator's resolved page mode into song-cover transitions through the same
/// `FestivalBackgroundCoordinator.present` the SwiftUI host calls. Because the root hosts
/// it once, the carousel's loader and clock never restart on tab switches or pushes.
///
/// Its inputs are the observable session / coordinator / sheet-coverage / network state
/// (re-evaluated through ``UKObservation``) and the non-observable system state (settings,
/// accessibility switches, power state, scene activation, size), which call
/// ``evaluate()`` directly. Like SwiftUI's `.task(id:)`, a task restarts only when its key
/// changes.
@MainActor
final class UKBackgroundHost {
    private let session: FestivalSession
    nonisolated(unsafe) private var observations: [NSObjectProtocol] = []
    private let observation = UKObservationBag()
    private var carouselKey: CarouselKey?
    private var coverKey: CoverKey?
    private var carouselTask: Task<Void, Never>?
    private var coverTask: Task<Void, Never>?
    private var catalogueTask: Task<Void, Never>?
    private var catalogueRevision: Int?
    private var debugTask: Task<Void, Never>?
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var size: CGSize = .zero
    private var scale: CGFloat = 2

    /// Times the carousel loader was (re)started; a debug probe reads it to prove tab
    /// switches and pushes never restart the carousel.
    private(set) var carouselPlays = 0

    /// Called after every evaluation (the debug probe refreshes from it).
    var didEvaluate: (() -> Void)?

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

    /// Creates the host and starts following the system state.
    ///
    /// - Parameter session: Artwork cache and coordinator owner.
    init(session: FestivalSession) {
        self.session = session
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UKSettings.didChange, Notification.Name.NSProcessInfoPowerStateDidChange,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIScene.didActivateNotification, UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification,
        ]
        for name in names {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let name = note.name
                MainActor.assumeIsolated {
                    switch name {
                    case .NSProcessInfoPowerStateDidChange:
                        self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                    case UIScene.didActivateNotification:
                        self?.sceneActive = true
                    case UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification:
                        // `willDeactivate` fires before the state flips: ScenePhase.inactive.
                        self?.sceneActive = false
                    default:
                        break
                    }
                    self?.evaluate()
                }
            })
        }
    }

    deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
        carouselTask?.cancel()
        coverTask?.cancel()
        catalogueTask?.cancel()
        debugTask?.cancel()
    }

    // MARK: Inputs

    /// Starts following observable state and runs the first evaluation.
    func start() {
        observation.observe { [weak self] in self?.evaluate() }
        #if DEBUG
        if debugTask == nil {
            let coordinator = session.backgroundCoordinator
            debugTask = Task { [session] in await coordinator.debugCycle(session: session) }
        }
        #endif
    }

    /// Records the backdrop's size (the decode bound follows it) and screen scale.
    ///
    /// - Parameters:
    ///   - size: Backdrop size in points.
    ///   - scale: Screen scale.
    func resize(_ size: CGSize, scale: CGFloat) {
        guard size != self.size || scale != self.scale else { return }
        self.size = size
        self.scale = scale
        evaluate()
    }

    // MARK: Policy

    /// Whether continuous decoration may run: an active (foreground) window scene, the
    /// UIKit counterpart of ``AnimationActivity/sceneActive(_:windowVisible:)``.
    private var sceneActive = UKBackgroundHost.anySceneActive()

    /// Whether any window scene is foreground-active right now.
    private static func anySceneActive() -> Bool {
        UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }

    /// Combine system and in-app preferences into one artwork policy.
    ///
    /// - Parameters:
    ///   - visible: Whether the carousel is uncovered.
    ///   - artCount: Number of candidate covers.
    /// - Returns: Loading and animation decisions.
    private func policy(visible: Bool, artCount: Int) -> ArtworkPlaybackPolicy {
        ArtworkPlaybackPolicy.resolve(
            sceneActive: sceneActive,
            visible: visible,
            pathKnown: ArtworkNetworkStatus.shared.pathKnown,
            pathSatisfied: ArtworkNetworkStatus.shared.pathSatisfied,
            reduceMotion: UKSettings.bool("fst.accessibility.reduceMotion", default: false)
                || UIAccessibility.isReduceMotionEnabled,
            disableAnimation: UKSettings.bool("fst.accessibility.disableAnimatedArtwork", default: false),
            reduceTransparency: UKSettings.bool("fst.accessibility.lessTransparency", default: false)
                || UIAccessibility.isReduceTransparencyEnabled,
            saveData: ArtworkNetworkStatus.shared.isConstrained,
            lowPower: lowPower, artCount: artCount
        )
    }

    /// Re-read every input and restart whichever task's key changed.
    func evaluate() {
        defer { didEvaluate?() }
        let coordinator = session.backgroundCoordinator
        let maxPixels = ArtworkBackdropCanvas.maxPixels(for: size, displayScale: scale)
        let revision = session.publicationRevision
        if catalogueRevision != revision {
            catalogueRevision = revision
            catalogueTask?.cancel()
            catalogueTask = Task { [session] in await session.loadArtworkCatalogIfNeeded() }
        }
        // Read every observable input before the size guard, so the tracking that runs
        // this method also follows them while the size is still unknown.
        let paths = session.artworkPaths
        let mode = coordinator.resolvedMode
        let carouselPolicy = policy(
            visible: coordinator.carouselVisible && !FestivalSheetCoverage.shared.isCovered,
            artCount: paths.count
        )
        let coverPolicy = policy(visible: true, artCount: 1)
        guard size != .zero else { return }
        let nextCarousel = CarouselKey(
            paths: paths, policy: carouselPolicy, maxPixels: maxPixels, revision: revision
        )
        if nextCarousel != carouselKey {
            carouselKey = nextCarousel
            carouselPlays += 1
            carouselTask?.cancel()
            carouselTask = Task {
                await coordinator.carousel.play(paths, maxPixels: maxPixels, policy: carouselPolicy)
            }
        }
        let nextCover = CoverKey(mode: mode, policy: coverPolicy, maxPixels: maxPixels)
        if nextCover != coverKey {
            coverKey = nextCover
            coverTask?.cancel()
            coverTask = Task { [session] in
                await coordinator.present(mode, session: session, policy: coverPolicy, maxPixels: maxPixels)
            }
        }
    }
}
#endif
