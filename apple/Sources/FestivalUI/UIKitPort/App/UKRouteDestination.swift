#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Route → controller

/// Maps every ``AppRoute`` and root ``FestivalSection`` to its UIKit screen: the UIKit
/// counterpart of ``AppRouteDestination`` and the SwiftUI shell's `content(for:)`.
///
/// Orchestrator-owned. Each feature lane fills its own `UK<Lane>Routes` factory
/// (`UIKitPort/Features/<Lane>/`), so lanes never edit this switch; a factory returns
/// nil for a route it has not ported yet and the placeholder shows instead.
@MainActor
enum UKRouteDestination {
    /// The controller for a pushed route.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The feature screen, or a placeholder for a route not ported yet.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController {
        let made: UIViewController?
        switch route {
        case .songDetail:
            made = UKSongDetailRoutes.make(route, context: context)
        case .shop:
            made = UKSongsRoutes.make(route, context: context)
        case .songLeaderboard, .songBandLeaderboard, .playerHistory, .leaderboards,
             .fullRankings, .fullComboRankings, .bandRankings:
            made = UKLeaderboardsRoutes.make(route, context: context)
        case .player, .playerBands, .bands, .band, .statistics:
            made = UKProfileRoutes.make(route, context: context)
        case .rivals, .allRivals, .rivalDetail, .rivalry, .compete, .suggestions:
            made = UKRivalsRoutes.make(route, context: context)
        case .licenses, .settingsTopic:
            made = UKSettingsRoutes.make(route, context: context)
        }
        let controller = made ?? UKPlaceholderViewController(title: route.ukPlaceholderTitle, context: context)
        controller.ukRoute = route
        return controller
    }

    /// The root controller of a section's stack.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The section's root screen, or a placeholder.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController {
        let made: UIViewController?
        switch section {
        case .songs, .shop: made = UKSongsRoutes.root(for: section, context: context)
        case .leaderboards: made = UKLeaderboardsRoutes.root(for: section, context: context)
        case .statistics: made = UKProfileRoutes.root(for: section, context: context)
        case .suggestions, .compete, .rivals: made = UKRivalsRoutes.root(for: section, context: context)
        case .settings: made = UKSettingsRoutes.root(for: section, context: context)
        }
        return made ?? UKPlaceholderViewController(title: section.title, context: context)
    }
}

// MARK: - Route on a controller

/// The associated-object key for ``UIKit/UIViewController/ukRoute``.
nonisolated(unsafe) private var ukRouteKey: UInt8 = 0

extension UIViewController {
    /// The route this controller was pushed for (nil for a section root), so the shell can
    /// rebuild a stack's ``AppRoute`` path from its `viewControllers`.
    var ukRoute: AppRoute? {
        get { (objc_getAssociatedObject(self, &ukRouteKey) as? UKRouteBox)?.route }
        set { objc_setAssociatedObject(self, &ukRouteKey, newValue.map(UKRouteBox.init), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// Boxes a route for an associated object.
private final class UKRouteBox: NSObject {
    let route: AppRoute
    init(_ route: AppRoute) { self.route = route }
}

extension AppRoute {
    /// A short title for a placeholder screen.
    var ukPlaceholderTitle: String {
        switch self {
        case let .songDetail(song): song.title
        case .songLeaderboard: "Leaderboard"
        case .songBandLeaderboard: "Band Leaderboard"
        case .playerHistory: "Score History"
        case let .player(_, name): name ?? "Player"
        case .playerBands: "Bands"
        case .bands: "Bands"
        case let .band(_, name, _, _): name ?? "Band"
        case .leaderboards: "Leaderboards"
        case .fullRankings, .fullComboRankings: "Rankings"
        case .bandRankings: "Band Rankings"
        case .rivals: "Rivals"
        case .allRivals: "All Rivals"
        case let .rivalDetail(_, name, _): name ?? "Rival"
        case .rivalry: "Rivalry"
        case .statistics: "Statistics"
        case .suggestions: "Suggestions"
        case .compete: "Compete"
        case .shop: "Item Shop"
        case .licenses: "Licenses"
        case .settingsTopic: "Settings"
        }
    }
}
#endif
