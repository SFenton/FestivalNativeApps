import Foundation

// MARK: - Song Details page tools

/// Which of Song Details' page tools show: Item Shop, Paths and Quick Links.
///
/// Every tool acts on the page's loaded content, so none shows, or reaches VoiceOver,
/// while the first-load spinner is up. They appear together with the revealed content,
/// so the toolbar or floating page tools do not grow in steps, and stay while shown
/// content refreshes (`.agents/patterns/load-transition.md` R1, issue #585; web gates
/// Quick Links on `LoadPhase.ContentIn`). The macOS and
/// iPadOS Song menu keeps its items listed and disables them instead (HIG The menu bar:
/// "Disable, don't hide, unavailable items").
struct SongDetailPageTools: Equatable {
    /// The official Item Shop action.
    var shop: Bool
    /// The Paths action.
    var paths: Bool
    /// The Quick Links menu.
    var quickLinks: Bool

    /// Resolve the tools for the page's state.
    ///
    /// - Parameters:
    ///   - contentShown: The first-load gate has revealed the page (stays true through
    ///     later quiet reloads).
    ///   - hasShopOffer: The song is in a validated Shop feed and Shop is not hidden.
    ///   - hasPathCharts: Settings show at least one non-Karaoke chart with paths.
    /// - Returns: The tools to offer.
    static func resolve(contentShown: Bool, hasShopOffer: Bool, hasPathCharts: Bool) -> Self {
        SongDetailPageTools(
            shop: contentShown && hasShopOffer,
            paths: contentShown && hasPathCharts,
            quickLinks: contentShown
        )
    }
}
