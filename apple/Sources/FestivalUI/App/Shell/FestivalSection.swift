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

    var id: Self { self }

    /// Title Case tab/sidebar label.
    var title: String { rawValue.capitalized }

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
/// - Player: Songs · Suggestions · Compete · Statistics · Settings on compact widths;
///   Leaderboards and Rivals replace Compete on regular widths (web ≥ 600 px).
/// - Band: Songs · Suggestions · Leaderboards · Statistics · Settings.
enum FestivalTabPolicy {
    /// Visible root sections in display order.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - regularWidth: True for iPad/macOS sidebars (the web's spacious bottom nav).
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

    /// Keep the user on an equivalent section when the visible set changes.
    ///
    /// Compete and Leaderboards occupy the same slot (web `activeKeys`), so selecting or
    /// deselecting a player swaps between them instead of bouncing to Songs.
    ///
    /// - Parameters:
    ///   - current: Section selected before the change.
    ///   - visible: Newly visible sections.
    /// - Returns: `current` when still visible, its slot equivalent, or Songs.
    static func resolve(_ current: FestivalSection, in visible: [FestivalSection]) -> FestivalSection {
        if visible.contains(current) { return current }
        let equivalent: FestivalSection? = switch current {
        case .compete: visible.contains(.leaderboards) ? .leaderboards : nil
        case .leaderboards, .rivals: visible.contains(.compete) ? .compete : nil
        default: nil
        }
        return equivalent ?? .songs
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
