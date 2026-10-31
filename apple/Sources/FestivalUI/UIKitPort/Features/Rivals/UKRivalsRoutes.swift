#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Rivals lane routes

/// The Rivals, Compete and Suggestions lane's screens in the UIKit port (ports `Features/Rivals, Features/Compete, Features/Suggestions`).
///
/// Owned by the Rivals lane: `.rivals`, `.allRivals`, `.rivalDetail`, `.rivalry`, `.compete`, `.suggestions`; roots `.suggestions`, `.compete`, `.rivals`. ``UKRouteDestination`` calls these; return nil for a
/// route not ported yet and the placeholder shows.
@MainActor
enum UKRivalsRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        switch route {
        case .rivals: UKRivalsViewController(context: context)
        case let .allRivals(scope): UKAllRivalsViewController(context: context, scope: scope)
        case let .rivalDetail(rivalId, name, scope): UKRivalDetailViewController(context: context, rivalId: rivalId, name: name, scope: scope)
        case let .rivalry(rivalId, mode, name, scope):
            UKRivalryViewController(context: context, rivalId: rivalId, mode: mode, name: name, scope: scope)
        case .compete: UKCompeteViewController(context: context)
        case .suggestions: UKSuggestionsViewController(context: context)
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
        case .rivals: UKRivalsViewController(context: context)
        case .compete: UKCompeteViewController(context: context)
        case .suggestions: UKSuggestionsViewController(context: context)
        default: nil
        }
    }
}
#endif
