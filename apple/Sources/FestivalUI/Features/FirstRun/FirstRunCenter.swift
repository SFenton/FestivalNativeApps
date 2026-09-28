import Foundation
import Observation
import FestivalCore

// MARK: - Debug mode

/// Controls how aggressively first-run carousels show, driven by `FST_DEBUG_FIRST_RUN` (see
/// `DebugLaunchRoute` in `FestivalRootView.swift` for the sibling `FST_DEBUG_*` conventions).
///
/// Debug builds default to `.off` so other lanes' screenshot/driver scripts aren't blocked by an
/// unexpected onboarding sheet; Release always behaves as `.normal`.
public enum FirstRunDebugMode: Sendable, Equatable {
    /// Never show any carousel (Debug default).
    case off
    /// Show every gate-passing slide on every page, ignoring seen-state (Debug opt-in).
    case force
    /// Real seen-state behavior (Release, or Debug opt-in via `FST_DEBUG_FIRST_RUN=on`).
    case normal

    /// Resolve from the process environment.
    ///
    /// - Parameter environment: Process environment (injectable for tests).
    /// - Returns: `.off` in Debug by default, `.normal` in Release always.
    public static func resolve(environment: [String: String]) -> FirstRunDebugMode {
        #if DEBUG
        switch environment["FST_DEBUG_FIRST_RUN"] {
        case "force": .force
        case "on": .normal
        default: .off
        }
        #else
        .normal
        #endif
    }
}

// MARK: - Coordinator

/// One session-scoped first-run coordinator: owns the persisted seen-state store and arbitrates
/// "one carousel at a time" across every page that applies `.firstRun(page:session:)`, mirroring
/// the web's `FirstRunContext` (`activeCarouselKey`, `markSeen`, `getUnseenSlides`).
@MainActor
@Observable
public final class FirstRunCenter {
    @ObservationIgnored
    let store: FirstRunSeenStore
    @ObservationIgnored
    public let debugMode: FirstRunDebugMode

    /// The page key currently presenting its carousel, or nil. Only one page may claim this at
    /// a time; a second page's evaluation simply doesn't show until the first releases it.
    private(set) var activeKey: String?

    /// Create a coordinator.
    ///
    /// - Parameters:
    ///   - store: Seen-state persistence; a fresh in-memory-backed store by default.
    ///   - debugMode: Resolved once at session start from the launch environment.
    public init(
        store: FirstRunSeenStore = FirstRunSeenStore(),
        debugMode: FirstRunDebugMode = .resolve(environment: ProcessInfo.processInfo.environment)
    ) {
        self.store = store
        self.debugMode = debugMode
    }

    /// Attempt to claim the single active-carousel slot for a page.
    ///
    /// - Parameter key: Page key requesting to show its carousel.
    /// - Returns: True when this page now owns (or already owned) the slot.
    func claim(_ key: String) -> Bool {
        guard activeKey == nil || activeKey == key else { return false }
        activeKey = key
        return true
    }

    /// Release the active-carousel slot if this page currently owns it.
    ///
    /// - Parameter key: Page key releasing the slot (on dismiss or disappearance).
    func release(_ key: String) {
        guard activeKey == key else { return }
        activeKey = nil
    }

    /// Every registered page and its label, for the Settings "First-Run Guides" list, in the
    /// same fixed order the web page registers them.
    public static var registeredPages: [(page: FirstRunPageKey, label: String)] {
        FirstRunPageKey.allCases.map { ($0, $0.label) }
    }
}
