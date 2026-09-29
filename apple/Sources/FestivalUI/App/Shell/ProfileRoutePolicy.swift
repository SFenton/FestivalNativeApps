import Foundation

// MARK: - Profile-only routes

/// Pages that need a selected player (web parity, operator 2026-09-28): Suggestions,
/// Statistics, Compete, Rivals and its drill-downs. Without a profile their tabs are
/// hidden (`FestivalTabPolicy`) and any such route in a stack is dropped, so the user
/// lands back on the section root (Songs or Leaderboards) — the web's redirect to Songs.
enum ProfileRoutePolicy {
    /// Whether a route is only meaningful with a selected player.
    ///
    /// - Parameter route: Route to classify.
    /// - Returns: True for Suggestions, Statistics, Compete, Rivals, All Rivals, Rival
    ///   Detail and Rivalry.
    static func requiresPlayer(_ route: AppRoute) -> Bool {
        switch route {
        case .suggestions, .statistics, .compete, .rivals, .allRivals, .rivalDetail, .rivalry:
            true
        default:
            false
        }
    }

    /// A stack with every profile-only route (and anything pushed above it) removed when
    /// no player is selected.
    ///
    /// - Parameters:
    ///   - path: Section navigation path.
    ///   - hasPlayer: Whether a player is selected.
    /// - Returns: `path` unchanged with a player; otherwise truncated before the first
    ///   profile-only route.
    static func resolve(_ path: [AppRoute], hasPlayer: Bool) -> [AppRoute] {
        guard !hasPlayer, let index = path.firstIndex(where: requiresPlayer) else { return path }
        return Array(path.prefix(index))
    }
}
