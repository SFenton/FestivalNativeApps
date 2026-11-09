#if DEBUG && os(iOS)
import Foundation
import Observation
import SwiftUI

// MARK: - Component probe state

/// DEBUG-only state used by canonical component styles to execute real visual paths.
@Observable
final class PerfComponentDebugState: @unchecked Sendable {
    static let shared = PerfComponentDebugState()

    private struct MarqueeDiagnostic: Equatable {
        let rendererClass: String
        let overflow: Bool
        let visible: Bool
        let reduceMotion: Bool
        let sceneActive: Bool
        let animation: Bool
        let textLength: Int
        let textWidth: CGFloat
        let viewportWidth: CGFloat
    }

    var rowPressed = false
    var marqueeRequested = false {
        didSet {
            if marqueeRequested != oldValue {
                NotificationCenter.default.post(name: .perfMarqueeRequestChanged, object: nil)
            }
        }
    }
    private var marqueeDiagnostics: [UUID: MarqueeDiagnostic] = [:]
    private(set) var marqueeActiveIDs: Set<UUID> = []
    private var marqueeBaseline: (requested: Bool, activeIDs: Set<UUID>)?

    var marqueeAnimating: Bool { !marqueeActiveIDs.isEmpty }
    /// Readiness for the debug component action, without treating a user's
    /// already-running marquee preference as debug activation.
    var marqueeComponentReady: Bool { marqueeRequested && marqueeAnimating }
    /// Restored means the debug request and actual active-renderer registry match
    /// their pre-start state; normal user animation is not disabled.
    var marqueeComponentRestored: Bool {
        guard let marqueeBaseline else { return false }
        return marqueeRequested == marqueeBaseline.requested
            && marqueeActiveIDs == marqueeBaseline.activeIDs
    }
    var marqueeRendererCount: Int { marqueeDiagnostics.count }
    var marqueeOverflowCount: Int { marqueeDiagnostics.values.filter(\.overflow).count }
    var marqueeVisibleCount: Int { marqueeDiagnostics.values.filter(\.visible).count }
    var marqueeReduceMotionCount: Int { marqueeDiagnostics.values.filter(\.reduceMotion).count }
    var marqueeSceneActiveCount: Int { marqueeDiagnostics.values.filter(\.sceneActive).count }
    var marqueeAnimationRegistrations: Int { marqueeDiagnostics.values.filter(\.animation).count }
    var marqueeMaxTextLength: Int { marqueeDiagnostics.values.map(\.textLength).max() ?? 0 }
    var marqueeMaxTextWidth: CGFloat { marqueeDiagnostics.values.map(\.textWidth).max() ?? 0 }
    var marqueeMaxViewportWidth: CGFloat { marqueeDiagnostics.values.map(\.viewportWidth).max() ?? 0 }
    var marqueeRendererClasses: String {
        Set(marqueeDiagnostics.values.map(\.rendererClass)).sorted().joined(separator: ",")
    }
    var marqueeRoute: String {
        ProcessInfo.processInfo.environment["FST_DEBUG_ROUTE"] ?? "unknown"
    }

    func beginMarqueeComponent() {
        marqueeBaseline = (requested: marqueeRequested, activeIDs: marqueeActiveIDs)
    }

    func setMarquee(_ id: UUID, active: Bool) {
        if active {
            if !marqueeActiveIDs.contains(id) {
                marqueeActiveIDs.insert(id)
            }
        } else if marqueeActiveIDs.contains(id) {
            marqueeActiveIDs.remove(id)
        }
    }

    func updateMarquee(
        _ id: UUID, rendererClass: String, overflow: Bool, visible: Bool,
        reduceMotion: Bool, sceneActive: Bool, animation: Bool,
        textLength: Int, textWidth: CGFloat, viewportWidth: CGFloat
    ) {
        let prior = marqueeDiagnostics[id]
        let diagnostic = MarqueeDiagnostic(
            rendererClass: rendererClass, overflow: overflow, visible: visible,
            reduceMotion: reduceMotion, sceneActive: sceneActive, animation: animation,
            textLength: textLength,
            textWidth: textWidth > 0 ? textWidth : prior?.textWidth ?? 0,
            viewportWidth: viewportWidth > 0 ? viewportWidth : prior?.viewportWidth ?? 0
        )
        if marqueeDiagnostics[id] != diagnostic {
            marqueeDiagnostics[id] = diagnostic
        }
        setMarquee(id, active: diagnostic.animation)
    }

    func updateMarqueeMeasurement(_ id: UUID, textLength: Int, textWidth: CGFloat, viewportWidth: CGFloat) {
        guard let current = marqueeDiagnostics[id] else { return }
        let diagnostic = MarqueeDiagnostic(
            rendererClass: current.rendererClass, overflow: current.overflow, visible: current.visible,
            reduceMotion: current.reduceMotion, sceneActive: current.sceneActive, animation: current.animation,
            textLength: textLength, textWidth: textWidth, viewportWidth: viewportWidth
        )
        if current != diagnostic {
            marqueeDiagnostics[id] = diagnostic
        }
    }

    func removeMarquee(_ id: UUID) {
        if marqueeDiagnostics[id] != nil {
            marqueeDiagnostics.removeValue(forKey: id)
        }
        setMarquee(id, active: false)
    }

    func clearMarquees() {
        if !marqueeDiagnostics.isEmpty {
            marqueeDiagnostics.removeAll()
        }
        if !marqueeActiveIDs.isEmpty {
            marqueeActiveIDs.removeAll()
        }
    }

    var marqueeDiagnosticSummary: String {
        "requested=\(marqueeRequested ? 1 : 0) renderer_count=\(marqueeRendererCount) "
            + "overflow_count=\(marqueeOverflowCount) visible_count=\(marqueeVisibleCount) "
            + "reduce_motion_count=\(marqueeReduceMotionCount) scene_active_count=\(marqueeSceneActiveCount) "
            + "animation_registrations=\(marqueeAnimationRegistrations) "
            + "max_text_length=\(marqueeMaxTextLength) max_text_width=\(Int(marqueeMaxTextWidth.rounded())) "
            + "max_viewport_width=\(Int(marqueeMaxViewportWidth.rounded())) "
            + "renderer_classes=\(marqueeRendererClasses.isEmpty ? "none" : marqueeRendererClasses) "
            + "route=\(marqueeRoute)"
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
