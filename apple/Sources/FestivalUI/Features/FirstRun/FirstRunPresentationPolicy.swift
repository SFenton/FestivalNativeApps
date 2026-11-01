import Foundation
import FestivalCore

// MARK: - Presentation policy

/// When a page's first-run carousel shows: the gate facts and the slide choice the
/// SwiftUI ``FirstRunPageModifier`` and the UIKit port both use.
enum FirstRunPresentationPolicy {
    /// Current gate facts.
    ///
    /// `ready` is always true: this app resolves the selected-player identity
    /// synchronously from storage at session start (`FestivalSession.init`).
    ///
    /// - Parameters:
    ///   - hasPlayer: Whether a profile is selected.
    ///   - hideShop: `fst.settings.hideShop`.
    ///   - disableShopHighlighting: `fst.settings.disableShopHighlighting`.
    ///   - experimentalRanks: Settings › Experimental Ranks.
    ///   - alwaysShow: Debug `force` mode.
    /// - Returns: The context slide gates are evaluated against.
    static func gateContext(
        hasPlayer: Bool, hideShop: Bool, disableShopHighlighting: Bool, experimentalRanks: Bool, alwaysShow: Bool
    ) -> FirstRunGateContext {
        FirstRunGateContext(
            hasPlayer: hasPlayer,
            shopHighlightEnabled: !hideShop && !disableShopHighlighting,
            experimentalRanksEnabled: experimentalRanks,
            ready: true,
            alwaysShow: alwaysShow
        )
    }

    /// The slides a page should show now: none while debug mode is off.
    ///
    /// - Parameters:
    ///   - page: The page whose catalogue to evaluate.
    ///   - debugMode: The coordinator's debug mode.
    ///   - context: Current gate facts.
    ///   - seen: Persisted seen-state.
    /// - Returns: Gate-passing slides (all of them when forced, else only unseen ones).
    static func slides(
        for page: FirstRunPageKey, debugMode: FirstRunDebugMode, context: FirstRunGateContext, seen: FirstRunSeenStorage
    ) -> [FirstRunSlide] {
        guard debugMode != .off else { return [] }
        let catalog = FirstRunCatalog.slides(for: page)
        return context.alwaysShow
            ? FirstRunSlideEvaluator.gatePassingSlides(catalog, context: context)
            : FirstRunSlideEvaluator.unseenSlides(catalog, context: context, seen: seen)
    }
}

extension AppRoute {
    /// The first-run carousel page of the route, if it has one.
    var firstRunPage: FirstRunPageKey? {
        switch self {
        case .songDetail: .songInfo
        case .playerHistory: .playerHistory
        case .leaderboards: .leaderboards
        case .rivals: .rivals
        case .statistics: .statistics
        case .suggestions: .suggestions
        case .compete: .compete
        case .shop: .shop
        default: nil
        }
    }
}
