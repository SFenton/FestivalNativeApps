import Foundation
import Network
import Observation

/// Share one system Low Data Mode signal between visible page backgrounds.
@MainActor
@Observable
final class ArtworkNetworkStatus {
    static let shared = ArtworkNetworkStatus()

    @ObservationIgnored
    private let monitor = NWPathMonitor()
    @ObservationIgnored
    private let queue = DispatchQueue(label: "com.sfenton.festivalscoretracker.artwork-network")
    private(set) var pathKnown = false
    private(set) var pathSatisfied = false
    private(set) var isConstrained = false

    /// Observe the current network path without persisting or requesting data.
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let constrained = path.isConstrained
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConstrained = constrained
                self?.pathSatisfied = satisfied
                self?.pathKnown = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// A known but unsatisfied network path must never start decorative HTTP work.
    ///
    /// - Parameters:
    ///   - known: Whether Network.framework delivered an initial path.
    ///   - satisfied: Whether that path can send a request.
    /// - Returns: True only for a known usable path.
    nonisolated static func canFetch(known: Bool, satisfied: Bool) -> Bool {
        known && satisfied
    }
}

/// Pure, testable accessibility, energy and visibility decisions for artwork.
struct ArtworkPlaybackPolicy: Hashable {
    let activeScene: Bool
    let visiblePage: Bool
    let reduceMotion: Bool
    let disableAnimation: Bool
    let reduceTransparency: Bool
    let saveData: Bool
    let lowPower: Bool
    let artCount: Int

    /// Do not fetch decoration while hidden, on constrained data, or with opaque UI.
    var mayLoad: Bool {
        activeScene && visiblePage && !reduceTransparency && !saveData && artCount > 0
    }

    /// A single cover or reduced-motion preference never schedules transitions.
    var mayAnimate: Bool {
        mayLoad && artCount > 1 && !reduceMotion && !disableAnimation && !lowPower
    }
}

// MARK: - Shared resolution

extension ArtworkPlaybackPolicy {
    /// Combine system and in-app preferences into one artwork policy, for the SwiftUI host
    /// and the UIKit port's host alike.
    ///
    /// - Parameters:
    ///   - sceneActive: ``AnimationActivity/sceneActive(_:windowVisible:)`` or the UIKit scene's state.
    ///   - visible: Whether the artwork is uncovered by a sheet or a full cover.
    ///   - pathKnown: ``ArtworkNetworkStatus/pathKnown``.
    ///   - pathSatisfied: ``ArtworkNetworkStatus/pathSatisfied``.
    ///   - reduceMotion: `fst.accessibility.reduceMotion` or the system setting.
    ///   - disableAnimation: `fst.accessibility.disableAnimatedArtwork` (the debug still
    ///     background is added here).
    ///   - reduceTransparency: `fst.accessibility.lessTransparency` or the system setting.
    ///   - saveData: Low Data Mode.
    ///   - lowPower: Low Power Mode.
    ///   - artCount: Number of candidate covers.
    /// - Returns: Loading and animation decisions.
    static func resolve(
        sceneActive: Bool, visible: Bool, pathKnown: Bool, pathSatisfied: Bool,
        reduceMotion: Bool, disableAnimation: Bool, reduceTransparency: Bool,
        saveData: Bool, lowPower: Bool, artCount: Int
    ) -> Self {
        Self(
            activeScene: sceneActive,
            visiblePage: visible && ArtworkNetworkStatus.canFetch(
                known: pathKnown, satisfied: pathSatisfied
            ),
            reduceMotion: reduceMotion,
            disableAnimation: disableAnimation || DebugAnimationOverride.stillBackground,
            reduceTransparency: reduceTransparency,
            saveData: saveData, lowPower: lowPower, artCount: artCount
        )
    }
}

/// How the shared backdrop is drawn under the user's accessibility settings.
enum BackdropPresentation {
    /// Black-overlay equivalent: 0.7, or 0.82 with increased contrast.
    ///
    /// - Parameters:
    ///   - appMoreContrast: `fst.accessibility.moreContrast`.
    ///   - systemIncreased: The system's Increase Contrast.
    /// - Returns: Dimming in 0...1.
    static func dimming(appMoreContrast: Bool, systemIncreased: Bool) -> Double {
        appMoreContrast || systemIncreased ? 0.82 : 0.7
    }

    /// Whether album art is drawn at all (otherwise the plain brand surface).
    ///
    /// - Parameters:
    ///   - appLessTransparency: `fst.accessibility.lessTransparency`.
    ///   - systemReduceTransparency: The system's Reduce Transparency.
    ///   - constrained: Low Data Mode.
    /// - Returns: False for opaque accessibility presentation or data saving.
    static func showsArt(
        appLessTransparency: Bool, systemReduceTransparency: Bool, constrained: Bool
    ) -> Bool {
        !(appLessTransparency || systemReduceTransparency || constrained)
    }
}
