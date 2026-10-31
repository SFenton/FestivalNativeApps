#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Songs lane routes

/// The Songs and Item Shop lane's screens in the UIKit port (ports `Features/Songs, Features/Shop`).
///
/// Owned by the Songs lane: `.shop`; roots `.songs`, `.shop`. ``UKRouteDestination`` calls these; return nil for a
/// route not ported yet and the placeholder shows.
@MainActor
enum UKSongsRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        switch route {
        case .shop: UKShopViewController(context: context, pushed: true)
        default: nil
        }
    }

    /// The root controller of a section this lane owns.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The ported root, or nil while it is not ported.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController? {
        switch section {
        case .songs: UKSongsViewController(context: context)
        case .shop: UKShopViewController(context: context, pushed: false)
        default: nil
        }
    }
}
#endif
