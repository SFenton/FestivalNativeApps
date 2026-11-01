#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Song Detail lane routes

/// The Song Detail lane's screen in the UIKit port (ports `Features/SongDetail`).
///
/// Owned by the Song Detail lane: `.songDetail`. ``UKRouteDestination`` calls this; return nil
/// while it is not ported and the placeholder shows.
@MainActor
enum UKSongDetailRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        guard case let .songDetail(song) = route else { return nil }
        return UKSongDetailViewController(song: song, context: context)
    }
}
#endif
