import SwiftUI

// MARK: - Sidebar menu

/// Pure contents of the iPad/macOS sections sidebar, ported from the web `Sidebar`
/// (`components/shell/desktop/Sidebar.tsx`), the same order as the phone drawer
/// (``DrawerMenu``): Songs, Suggestions*, Statistics*, Rivals*, Leaderboards, Item Shop
/// (*with a selected player). The footer holds the selected player (or Select Profile)
/// and Settings, like the web sidebar footer.
///
/// Unlike the drawer, every row is a root destination with its own navigation path:
/// Item Shop is ``FestivalSection/shop``, so it keeps the selected-row highlight
/// (HIG Split views: "Persistently highlight the current selection").
enum SidebarMenu {
    /// Rows above the footer, in web order.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - hideShop: Settings › Hide Item Shop.
    /// - Returns: Ordered sidebar sections.
    static func browse(profile: FestivalProfileKind, hideShop: Bool) -> [FestivalSection] {
        var sections: [FestivalSection] = [.songs]
        if profile != .none { sections += [.suggestions, .statistics] }
        if profile == .player { sections.append(.rivals) }
        sections.append(.leaderboards)
        if !hideShop { sections.append(.shop) }
        return sections
    }

    /// Rows pinned in the footer after the profile row.
    static let footer: [FestivalSection] = [.settings]

    /// Every sidebar destination, browse rows then footer rows: the order of the
    /// ⌘1…⌘9 keyboard shortcuts.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - hideShop: Settings › Hide Item Shop.
    /// - Returns: All visible destinations.
    static func sections(profile: FestivalProfileKind, hideShop: Bool) -> [FestivalSection] {
        browse(profile: profile, hideShop: hideShop) + footer
    }

    /// The destination a ⌘-digit shortcut selects.
    ///
    /// - Parameters:
    ///   - digit: 1…9.
    ///   - visible: Visible destinations (``sections(profile:hideShop:)``).
    /// - Returns: The destination at that position, or nil past the end.
    static func destination(forDigit digit: Int, in visible: [FestivalSection]) -> FestivalSection? {
        guard (1...9).contains(digit), digit <= visible.count else { return nil }
        return visible[digit - 1]
    }
}
