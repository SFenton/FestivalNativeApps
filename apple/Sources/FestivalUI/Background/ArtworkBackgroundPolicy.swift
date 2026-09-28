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
