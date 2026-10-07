import SwiftUI

// MARK: - Navigation sections

/// Root destinations shown as tabs on iPhone and sidebar rows on iPad/macOS.
///
/// Mirrors the web `BottomNav` (`components/shell/mobile/BottomNav.tsx`) and wide
/// `Sidebar`. Which sections are visible at a given moment is decided by
/// `FestivalTabPolicy`, never by the view.
enum FestivalSection: String, CaseIterable, Identifiable, Sendable {
    case songs
    case suggestions
    case leaderboards
    case compete
    case rivals
    case statistics
    case settings
    /// Item Shop as its own destination: only in the iPad/macOS sidebar (web `Sidebar`).
    /// Phones never show it as a tab; their drawer pushes ``AppRoute/shop`` instead.
    case shop

    var id: Self { self }

    /// Title Case tab/sidebar label.
    var title: String { self == .shop ? "Item Shop" : rawValue.capitalized }

    /// SF Symbol matching the web's Ionicons choice for the same destination.
    var symbol: String {
        switch self {
        case .songs: "music.note.list"
        case .suggestions: "sparkles"
        case .leaderboards: "trophy"
        case .compete: "trophy"
        case .rivals: "person.2"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        case .shop: "bag"
        }
    }
}

// MARK: - Profile kind

/// Which kind of profile the shell is currently scoped to.
enum FestivalProfileKind: Sendable, Equatable {
    /// Anonymous browsing.
    case none
    /// A selected player (`SelectedPlayerIdentity`).
    case player
    /// A selected band (not yet selectable natively; reserved for parity).
    case band
}

// MARK: - Tab visibility policy

/// Pure rules for which root sections exist, ported from the web `BottomNav`.
///
/// - No profile: Songs · Leaderboards · Settings.
/// - Player: Songs · Suggestions · Compete · Statistics · Settings on phone tab bars
///   (iPhone Duo folded or unfolded, issue #337); Leaderboards and Rivals replace
///   Compete in the iPad/macOS sidebar (web ≥ 600 px).
/// - Band: Songs · Suggestions · Leaderboards · Statistics · Settings.
enum FestivalTabPolicy {
    /// Visible root sections in display order.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - regularWidth: True for iPad/macOS sidebars (the web's spacious bottom nav);
    ///     false for every phone tab bar, the iPhone Duo inner display included.
    /// - Returns: Ordered sections to show as tabs or sidebar rows.
    static func sections(profile: FestivalProfileKind, regularWidth: Bool) -> [FestivalSection] {
        var sections: [FestivalSection] = [.songs]
        if profile != .none { sections.append(.suggestions) }
        switch (profile, regularWidth) {
        case (.player, true): sections += [.leaderboards, .rivals]
        case (.player, false): sections.append(.compete)
        case (.none, _), (.band, _): sections.append(.leaderboards)
        }
        if profile != .none { sections.append(.statistics) }
        sections.append(.settings)
        return sections
    }

    /// Most tabs a phone tab bar shows without a system "More" tab. The Search tab counts
    /// toward it (measured, iOS 26.5: five sections plus Search moved Search into More).
    static let phoneTabLimit = 5

    /// Sections a phone tab bar drops first to leave room for the Search tab, in order.
    /// Each stays in the drawer, which pushes it when it is not a tab (``DrawerMenu``).
    static let dropOrderForSearchTab: [FestivalSection] = [.statistics, .rivals, .suggestions, .leaderboards]

    /// Fit compact phone tabs beside the trailing Search tab (issue #92).
    ///
    /// HIG Tab bars: on iPhone a tab bar shows up to five tabs before "More", and a hidden
    /// Search tab would defeat it. With a player selected, Statistics leaves the bar
    /// (Songs · Suggestions · Compete · Settings · Search) and opens from the drawer.
    /// Songs, Compete and Settings are never dropped: the drawer lists neither Compete
    /// nor a pushable Settings.
    ///
    /// - Parameters:
    ///   - sections: Sections from ``sections(profile:regularWidth:)``.
    ///   - limit: Tab slots, the Search tab included.
    /// - Returns: `sections` in order, minus the fewest droppable sections.
    static func fittingSearchTab(_ sections: [FestivalSection], limit: Int = phoneTabLimit) -> [FestivalSection] {
        var result = sections
        for section in dropOrderForSearchTab where result.count + 1 > limit {
            result.removeAll { $0 == section }
        }
        return result
    }

    /// The page the drawer pushes for a section the phone tab bar dropped to fit the
    /// Search tab (``fittingSearchTab(_:limit:)``), so a launch or link naming it still
    /// opens it rather than a neighbouring tab.
    ///
    /// - Parameters:
    ///   - section: Requested root section.
    ///   - profile: Selected profile kind.
    ///   - visible: Sections shown as tabs.
    /// - Returns: The drawer's route for `section`, or nil when it is a visible tab or
    ///   not available for `profile` at all.
    static func searchTabOverflowRoute(
        for section: FestivalSection, profile: FestivalProfileKind, visible: [FestivalSection]
    ) -> AppRoute? {
        guard !visible.contains(section), dropOrderForSearchTab.contains(section),
              sections(profile: profile, regularWidth: false).contains(section)
        else { return nil }
        switch section {
        case .statistics: return .statistics
        case .rivals: return .rivals
        case .suggestions: return .suggestions
        case .leaderboards: return .leaderboards
        default: return nil
        }
    }

    /// Keep the user on an equivalent section when the visible set changes.
    ///
    /// Compete and Leaderboards occupy the same slot (web `activeKeys`), so selecting or
    /// deselecting a player swaps between them instead of bouncing away. A section with no
    /// equivalent falls back to the nearest visible section before it in tab order
    /// (Statistics → Leaderboards, Suggestions → Songs), else the first visible section.
    ///
    /// - Parameters:
    ///   - current: Section selected before the change.
    ///   - visible: Newly visible sections.
    /// - Returns: `current` when still visible, its slot equivalent, or the nearest section.
    static func resolve(_ current: FestivalSection, in visible: [FestivalSection]) -> FestivalSection {
        if visible.contains(current) { return current }
        // Item Shop is reached from Songs wherever it is not a sidebar row.
        if current == .shop { return visible.contains(.songs) ? .songs : visible.first ?? .songs }
        if let equivalent = slotEquivalent(of: current, in: visible) { return equivalent }
        let order = FestivalSection.allCases
        let index = order.firstIndex(of: current) ?? 0
        return order[..<index].reversed().first(where: visible.contains) ?? visible.first ?? .songs
    }

    /// The section occupying the same tab slot, if visible.
    ///
    /// - Parameters:
    ///   - current: Section that disappeared.
    ///   - visible: Newly visible sections.
    /// - Returns: Leaderboards for Compete; Compete for Leaderboards or Rivals; else nil.
    private static func slotEquivalent(
        of current: FestivalSection, in visible: [FestivalSection]
    ) -> FestivalSection? {
        switch current {
        case .compete: visible.contains(.leaderboards) ? .leaderboards : nil
        case .leaderboards, .rivals: visible.contains(.compete) ? .compete : nil
        default: nil
        }
    }

    /// Adapt the selected section and per-section paths to a new visible section set.
    ///
    /// Selecting or deselecting a profile never navigates away by itself (operator,
    /// 2026-09-28): every path is kept. Only when the selected section disappears does
    /// the selection move (``resolve(_:in:)``); a slot swap (Leaderboards ↔ Compete,
    /// Rivals → Compete) carries the nested path along, so a user who selects a player
    /// from Leaderboards › Player stays on that player's page under Compete.
    ///
    /// - Parameters:
    ///   - selected: Section selected before the change.
    ///   - paths: Per-section navigation paths.
    ///   - visible: Newly visible sections.
    /// - Returns: The new selection and paths.
    static func adapt(
        selected: FestivalSection, paths: [FestivalSection: [AppRoute]], to visible: [FestivalSection]
    ) -> (selected: FestivalSection, paths: [FestivalSection: [AppRoute]]) {
        guard !visible.contains(selected) else { return (selected, paths) }
        var paths = paths
        // Leaving the sidebar (an iPad window narrowed to compact width): the Item Shop
        // row's page stays on screen, pushed on Songs like the phone drawer does.
        if selected == .shop {
            let target = resolve(.shop, in: visible)
            paths[target] = (paths[target] ?? []) + [.shop] + (paths[.shop] ?? [])
            paths[.shop] = []
            return (target, paths)
        }
        if let equivalent = slotEquivalent(of: selected, in: visible) {
            if let carried = paths[selected], !carried.isEmpty {
                paths[equivalent] = carried
                paths[selected] = []
            }
            return (equivalent, paths)
        }
        return (resolve(selected, in: visible), paths)
    }

    /// Whether leaving this section should discard its nested route history.
    ///
    /// The web restores every tab's prior nested route except Statistics.
    ///
    /// - Parameter section: Section being left.
    /// - Returns: True when its path should be cleared.
    static func resetsPathOnLeave(_ section: FestivalSection) -> Bool {
        section == .statistics
    }
}
