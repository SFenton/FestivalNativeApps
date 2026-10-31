#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Settings lane routes

/// The Settings, Licenses and settings topics lane's screens in the UIKit port (ports `Features/Settings (and FirstRun, WhatsNew, Notifications sheets)`).
///
/// Owned by the Settings lane: `.licenses`, `.settingsTopic`; root `.settings`. ``UKRouteDestination`` calls these; return nil for a
/// route not ported yet and the placeholder shows.
@MainActor
enum UKSettingsRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        nil
    }

    /// The root controller of a section this lane owns.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The ported root, or nil while it is not ported.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController? {
        nil
    }
}
#endif
