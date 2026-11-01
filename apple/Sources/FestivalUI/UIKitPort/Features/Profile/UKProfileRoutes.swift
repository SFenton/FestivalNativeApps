#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Profile lane routes

/// The Player profile, player bands, Bands and Statistics lane's screens in the UIKit port (ports `Features/Profile, Features/Bands, Features/Statistics`).
///
/// Owned by the Profile lane: `.player`, `.playerBands`, `.bands`, `.band`, `.statistics`; root `.statistics`. ``UKRouteDestination`` calls these; return nil for a
/// route not ported yet and the placeholder shows.
@MainActor
enum UKProfileRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        switch route {
        case let .player(accountId, displayName):
            UKPlayerProfileViewController(context: context, accountId: accountId, displayName: displayName)
        case let .playerBands(accountId, displayName, group):
            UKPlayerBandsViewController(context: context, accountId: accountId, displayName: displayName, group: group)
        case .bands:
            UKBandsViewController(context: context)
        case let .band(bandId, name, bandType, teamKey):
            UKBandDetailViewController(context: context, bandId: bandId, name: name, bandType: bandType, teamKey: teamKey)
        case .statistics:
            UKStatisticsViewController(context: context)
        default:
            nil
        }
    }

    /// The root controller of a section this lane owns.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The ported root, or nil while it is not ported.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController? {
        section == .statistics ? UKStatisticsViewController(context: context) : nil
    }
}
#endif
