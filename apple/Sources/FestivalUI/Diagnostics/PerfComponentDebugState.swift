#if DEBUG && os(iOS)
import Foundation
import Observation
import SwiftUI

// MARK: - Component probe state

/// DEBUG-only state used by canonical component styles to execute real visual paths.
@Observable
final class PerfComponentDebugState: @unchecked Sendable {
    static let shared = PerfComponentDebugState()

    var rowPressed = false
    var marqueeRequested = false {
        didSet { NotificationCenter.default.post(name: .perfMarqueeRequestChanged, object: nil) }
    }
    private(set) var marqueeActiveIDs: Set<UUID> = []

    var marqueeAnimating: Bool { !marqueeActiveIDs.isEmpty }

    func setMarquee(_ id: UUID, active: Bool) {
        if active {
            marqueeActiveIDs.insert(id)
        } else {
            marqueeActiveIDs.remove(id)
        }
    }

    func clearMarquees() {
        marqueeActiveIDs.removeAll()
    }
}

extension Notification.Name {
    static let perfMarqueeRequestChanged = Notification.Name("fst.perf.marquee-request-changed")
}

private struct PerfComponentDebugStateKey: EnvironmentKey {
    static let defaultValue = PerfComponentDebugState.shared
}

extension EnvironmentValues {
    var perfComponentDebugState: PerfComponentDebugState {
        get { self[PerfComponentDebugStateKey.self] }
        set { self[PerfComponentDebugStateKey.self] = newValue }
    }
}
#endif
