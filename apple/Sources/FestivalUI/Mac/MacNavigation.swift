import CoreGraphics
import Foundation
import Observation
import SwiftUI

// MARK: - Mac sidebar destinations

/// Root destinations of the macOS sidebar, in the web's pinned-sidebar order
/// (`components/shell/desktop/PinnedSidebar.tsx`): Songs, Suggestions*, Statistics*,
/// Rivals*, Compete*, Leaderboards, Item Shop (* selected player only).
///
/// Settings is not a destination: on the Mac it is the app's Settings window (⌘,), HIG
/// Settings › macOS ("Put Settings in the App menu, not a window toolbar").
enum MacDestination: String, CaseIterable, Identifiable, Sendable {
    case songs
    case suggestions
    case statistics
    case rivals
    case compete
    case leaderboards
    case shop

    var id: Self { self }

    /// Title Case sidebar and Go-menu label.
    var title: String {
        switch self {
        case .shop: "Item Shop"
        default: rawValue.capitalized
        }
    }

    /// SF Symbol (web Ionicons equivalents; the shell's sidebar honours the accent colour).
    var symbol: String {
        switch self {
        case .songs: "music.note.list"
        case .suggestions: "sparkles"
        case .statistics: "chart.bar"
        case .rivals: "person.2"
        case .compete: "flag.2.crossed"
        case .leaderboards: "trophy"
        case .shop: "bag"
        }
    }

    /// Whether the destination exists only while a player is selected.
    var requiresPlayer: Bool {
        switch self {
        case .suggestions, .statistics, .rivals, .compete: true
        case .songs, .leaderboards, .shop: false
        }
    }

    /// The shared section whose list/detail and first-run rules this destination uses,
    /// or nil for Item Shop (a pushed page on iPhone).
    var section: FestivalSection? {
        switch self {
        case .songs: .songs
        case .suggestions: .suggestions
        case .statistics: .statistics
        case .rivals: .rivals
        case .compete: .compete
        case .leaderboards: .leaderboards
        case .shop: nil
        }
    }

    /// Stable accessibility identifier of the sidebar row.
    var accessibilityIdentifier: String { "fst.nav.\(rawValue)" }
}

// MARK: - Sidebar policy

/// Pure sidebar and keyboard-navigation rules for the macOS shell.
enum MacSidebarPolicy {
    /// Visible destinations in order.
    ///
    /// - Parameters:
    ///   - hasPlayer: Whether a player is selected.
    ///   - hideShop: The Settings "Hide Item Shop" preference.
    /// - Returns: The sidebar rows.
    static func destinations(hasPlayer: Bool, hideShop: Bool) -> [MacDestination] {
        MacDestination.allCases.filter { destination in
            if destination.requiresPlayer && !hasPlayer { return false }
            if destination == .shop && hideShop { return false }
            return true
        }
    }

    /// Keep the selection when visible, else fall back.
    ///
    /// Player-only destinations fall back to Songs except Rivals/Compete, which share the
    /// web's Leaderboards slot; a hidden Item Shop falls back to Songs.
    ///
    /// - Parameters:
    ///   - current: Destination selected before the change.
    ///   - visible: Newly visible destinations.
    /// - Returns: The destination to show.
    static func resolve(_ current: MacDestination, in visible: [MacDestination]) -> MacDestination {
        if visible.contains(current) { return current }
        if current == .rivals || current == .compete, visible.contains(.leaderboards) {
            return .leaderboards
        }
        return visible.first ?? .songs
    }

    /// The destination for ⌘1…⌘9: the n-th visible sidebar row.
    ///
    /// - Parameters:
    ///   - number: 1-based shortcut number.
    ///   - visible: Visible destinations.
    /// - Returns: The destination, or nil when there is no such row.
    static func destination(forShortcut number: Int, in visible: [MacDestination]) -> MacDestination? {
        guard number >= 1, number <= visible.count else { return nil }
        return visible[number - 1]
    }

    /// Map a shared section (Debug `FST_DEBUG_TAB`, player-stat links) to a destination.
    ///
    /// - Parameter section: Shared root section.
    /// - Returns: The Mac destination, or nil for Settings (the Settings window).
    static func destination(for section: FestivalSection) -> MacDestination? {
        switch section {
        case .songs: .songs
        case .suggestions: .suggestions
        case .leaderboards: .leaderboards
        case .compete: .compete
        case .rivals: .rivals
        case .statistics: .statistics
        case .shop: .shop
        case .settings: nil
        }
    }

    /// Where a root-level route opens when it is also a sidebar destination, so a deep
    /// link to `/shop` or `/statistics` selects the row instead of pushing a copy.
    ///
    /// - Parameter route: Route being opened from the Debug launch.
    /// - Returns: The destination, or nil when the route is pushed.
    static func destination(for route: AppRoute) -> MacDestination? {
        switch route {
        case .shop: .shop
        case .statistics: .statistics
        case .suggestions: .suggestions
        case .compete: .compete
        case .rivals: .rivals
        case .leaderboards: .leaderboards
        default: nil
        }
    }

    /// The path after Back.
    ///
    /// With two populated columns the detail root belongs to the list page beside it, so
    /// Back first pops the detail column's pushes, then the list column's page together
    /// with its selection; it never empties the detail column of a root list (the shell
    /// would only auto-select it again).
    ///
    /// - Parameters:
    ///   - path: Destination path.
    ///   - section: Shared section (list/detail rules), nil for Item Shop.
    ///   - split: Whether the destination currently shows two columns.
    /// - Returns: The new path, or nil when Back is unavailable.
    static func backPath(_ path: [AppRoute], section: FestivalSection?, split: Bool) -> [AppRoute]? {
        guard !path.isEmpty else { return nil }
        guard split, let section, let cut = ListDetailPolicy.split(section: section, path: path),
              cut.selection != nil
        else { return Array(path.dropLast()) }
        if cut.detail.count > 1 { return Array(path.dropLast()) }
        guard !cut.list.isEmpty else { return nil }
        return Array(cut.list.dropLast())
    }
}

// MARK: - Mac layout policy

/// Pure width rules for the Mac window's content area (right of the sidebar).
enum MacLayoutPolicy {
    /// Narrowest content width that shows list and detail side by side: a 340 pt list
    /// plus a 480 pt detail (HIG Split views › macOS: "set reasonable minimum/maximum
    /// defaults so the divider stays visible").
    static let splitMinimumWidth: CGFloat = 820
    /// List column bounds (points): `max` caps the automatic 38% width; a dragged
    /// divider may widen the list to `dragMax` (still a compact-width column, so its
    /// rows keep their list layout) while the detail keeps ``detailMinimumWidth``.
    static let listColumn = (min: CGFloat(340), ideal: CGFloat(400), max: CGFloat(560), dragMax: CGFloat(680))
    /// UserDefaults key remembering a dragged list column width (HIG Split views ›
    /// macOS: "draggable dividers resize them"); absent or 0 means automatic.
    static let listWidthKey = "fst.mac.listColumnWidth"
    /// Points one accessibility increment/decrement moves the divider.
    static let dividerStep: CGFloat = 20
    /// Detail column minimum (points).
    static let detailMinimumWidth: CGFloat = 480

    /// Whether a destination shows two columns at a content width.
    ///
    /// - Parameters:
    ///   - width: Content width in points (0 before the first layout pass).
    ///   - hasListPage: Whether the destination's path has a list page (Songs, Full
    ///     Rankings, Rivals lists).
    ///   - emptyListCollapsed: The list produced no row to show beside it.
    /// - Returns: True for two columns.
    /// Widest page content, centred in its column (web `MaxWidth.card`, 1400 px; the
    /// Item Shop grid uses `MaxWidth.grid`, 2170 px).
    ///
    /// - Parameter route: The page's route, or nil for a destination root.
    /// - Parameter isShopRoot: Whether a destination root is the Item Shop.
    /// - Returns: The maximum content width in points.
    static func pageMaxWidth(for route: AppRoute?, isShopRoot: Bool = false) -> CGFloat {
        route == .shop || (route == nil && isShopRoot) ? 2170 : 1400
    }

    /// List column width for a content width: 38% within ``listColumn`` bounds.
    ///
    /// - Parameter width: Content width in points.
    /// - Returns: The list column width.
    static func listWidth(forContentWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.38, listColumn.min), listColumn.max)
    }

    /// List column width honouring a width the person set by dragging the divider,
    /// clamped so the divider stays visible: the list keeps ``listColumn`` `min`…
    /// `dragMax` and the detail at least ``detailMinimumWidth`` (HIG Split views ›
    /// macOS: "set reasonable minimum/maximum defaults so the divider stays visible").
    ///
    /// - Parameters:
    ///   - width: Content width in points.
    ///   - preferred: The remembered dragged width, or nil/≤ 0 for automatic.
    /// - Returns: The list column width.
    static func listWidth(forContentWidth width: CGFloat, preferred: CGFloat?) -> CGFloat {
        guard let preferred, preferred > 0 else { return listWidth(forContentWidth: width) }
        let range = listWidthRange(forContentWidth: width)
        return min(max(preferred, range.lowerBound), range.upperBound)
    }

    /// Widths a dragged divider may take at a content width.
    ///
    /// - Parameter width: Content width in points.
    /// - Returns: ``listColumn`` `min` up to `dragMax` or the width that leaves the
    ///   detail ``detailMinimumWidth`` beside the 1 pt divider, whichever is smaller.
    static func listWidthRange(forContentWidth width: CGFloat) -> ClosedRange<CGFloat> {
        listColumn.min...max(listColumn.min, min(listColumn.dragMax, width - detailMinimumWidth - 1))
    }

    /// Column width from which pages use their regular-width layouts (two card columns,
    /// readable-width forms). The web's detail-card grid switches to two 420 px columns
    /// at an 844 px container; 720 pt keeps two ≥ 344 pt cards beside 16 pt margins.
    static let regularMinimumWidth: CGFloat = 720

    /// Width class of a Mac column.
    ///
    /// - Parameter width: Column width in points.
    /// - Returns: Regular from ``regularMinimumWidth``, else compact.
    static func widthClass(forWidth width: CGFloat) -> WidthClass {
        width >= regularMinimumWidth ? .regular : .compact
    }

    static func showsSplit(width: CGFloat, hasListPage: Bool, emptyListCollapsed: Bool) -> Bool {
        hasListPage && !emptyListCollapsed && width >= splitMinimumWidth
    }
}

// MARK: - Navigation model

/// The Mac window's navigation state: sidebar selection, one path per destination,
/// modal presentations and the refresh generation. Shared by the window and the menu
/// bar commands (one primary window, HIG Windows).
@MainActor @Observable
final class MacNavigationModel {
    /// UserDefaults key restoring the last sidebar destination (HIG Launching:
    /// "Restore as much granular prior state as possible on restart").
    static let selectionKey = "fst.mac.destination"

    /// Selected sidebar destination.
    private(set) var selected: MacDestination
    /// One independent path per destination (the web keeps each section's history).
    var paths: [MacDestination: [AppRoute]] = [:]
    /// Destinations currently showing two columns (reported by the list/detail stack).
    var splitDestinations: Set<MacDestination> = []
    /// Incremented by View › Refresh (⌘R); the detail column is rebuilt and reloads.
    private(set) var refreshGeneration = 0
    /// Profile selection sheet.
    var profilePresented = false
    /// Global search sheet.
    var searchPresented = false
    /// Notifications sheet.
    var notificationsPresented = false
    /// Help › What's New replay.
    var whatsNewPresented = false
    /// Visible sidebar rows, kept current by the window.
    private(set) var visible: [MacDestination]

    @ObservationIgnored private let storage: UserDefaults?

    /// Create the model.
    ///
    /// - Parameters:
    ///   - storage: Where the selected destination persists; nil in tests.
    ///   - initial: A launch override (Debug deep link) that wins over storage.
    ///   - visible: Initially visible destinations.
    init(storage: UserDefaults?, initial: MacDestination? = nil, visible: [MacDestination]) {
        self.storage = storage
        self.visible = visible
        let stored = storage?.string(forKey: Self.selectionKey).flatMap(MacDestination.init(rawValue:))
        selected = MacSidebarPolicy.resolve(initial ?? stored ?? .songs, in: visible)
    }

    /// Path of the selected destination.
    var currentPath: [AppRoute] { paths[selected] ?? [] }

    /// What Edit › Copy copies when no text is focused: the selected row's (or shown
    /// page's) song title or player name (``MacCopyPolicy``).
    var selectionCopyText: String? {
        MacCopyPolicy.selectedRoute(
            path: currentPath, section: selected.section, split: splitDestinations.contains(selected)
        ).flatMap(MacCopyPolicy.text(for:))
    }

    /// Whether Go › Back (⌘[) can act.
    var canGoBack: Bool { backPath != nil }

    private var backPath: [AppRoute]? {
        MacSidebarPolicy.backPath(
            currentPath, section: selected.section, split: splitDestinations.contains(selected)
        )
    }

    /// Show a destination. Choosing the selected one again returns it to its root
    /// (web and iPhone tab semantics); leaving Statistics clears its history (web).
    ///
    /// - Parameter destination: Sidebar row, Go-menu item or shortcut target.
    func select(_ destination: MacDestination) {
        guard visible.contains(destination) else { return }
        if destination == selected {
            paths[destination] = []
        } else if selected == .statistics {
            paths[.statistics] = []
        }
        selected = destination
        storage?.set(destination.rawValue, forKey: Self.selectionKey)
    }

    /// Select the n-th visible destination (⌘1…⌘9).
    ///
    /// - Parameter number: 1-based row number.
    func selectShortcut(_ number: Int) {
        if let destination = MacSidebarPolicy.destination(forShortcut: number, in: visible) {
            select(destination)
        }
    }

    /// The toolbar profile button (avatar), issue #290: with a selected player it shows
    /// Statistics, their own profile (web `getProfileClickDestination`, the sidebar
    /// footer's name); without one it opens profile selection. Profile › Select/Switch
    /// Profile… (⇧⌘P) still always opens the sheet.
    ///
    /// - Parameter hasPlayer: Whether a player is selected.
    func pressProfileButton(hasPlayer: Bool) {
        if hasPlayer, visible.contains(.statistics) {
            select(.statistics)
        } else {
            profilePresented = true
        }
    }

    /// Push a route on the selected destination.
    ///
    /// - Parameter route: Route to open.
    func push(_ route: AppRoute) {
        paths[selected, default: []].append(route)
    }

    /// Go back one level in the selected destination (⌘[).
    func goBack() {
        if let backPath { paths[selected] = backPath }
    }

    /// Rebuild the detail column so its pages read again (⌘R).
    func refresh() {
        refreshGeneration += 1
    }

    /// Adopt a new visible set (profile selected/deselected, Item Shop hidden).
    ///
    /// Paths are kept; only a selection that disappeared moves, and a hidden Item Shop
    /// is removed from every path.
    ///
    /// - Parameter visible: Newly visible destinations.
    func update(visible newVisible: [MacDestination]) {
        visible = newVisible
        if !newVisible.contains(.shop) {
            for (destination, path) in paths {
                if let index = path.firstIndex(of: .shop) { paths[destination] = Array(path.prefix(index)) }
            }
        }
        let resolved = MacSidebarPolicy.resolve(selected, in: newVisible)
        if resolved != selected {
            if selected == .statistics { paths[.statistics] = [] }
            selected = resolved
        }
    }
}

// MARK: - Sheet size

extension View {
    /// A reasonable default size for a sheet on the Mac (HIG Sheets › macOS: "Present a
    /// sheet in a reasonable default size") with grouped forms (the Mac's default
    /// columns form style drops the sections' cards); a no-op elsewhere.
    ///
    /// - Parameters:
    ///   - width: Minimum and ideal width in points.
    ///   - height: Minimum and ideal height in points.
    /// - Returns: The sheet content.
    func macSheetFrame(width: CGFloat = 560, height: CGFloat = 640) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
            .formStyle(.grouped)
        #else
        self
        #endif
    }
}
