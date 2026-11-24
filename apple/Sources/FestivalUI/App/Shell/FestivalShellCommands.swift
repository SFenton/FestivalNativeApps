import FestivalAppSupport

// MARK: - Shell commands

/// Destination order for the shell's menu and keyboard shortcuts.
struct FestivalShellCommands: Equatable {
    /// Every destination the Go menu lists for this shell, visible or not (HIG The menu
    /// bar: "Disable, don't hide, unavailable items; always show the same set").
    var destinations: [FestivalSection]
    /// Visible destinations in sidebar (or tab) order: the ⌘1…⌘9 order.
    var visible: [FestivalSection]
    /// The selected destination.
    var selected: FestivalSection
    /// Whether ⌘[ has a page to go back to.
    var canGoBack: Bool
    /// Whether a root sheet covers the window (menu commands must not stack another).
    var sheetOpen: Bool
    /// Whether a player is selected.
    var hasPlayer: Bool
    /// Select a destination (the current one pops to its root).
    var select: @MainActor (FestivalSection) -> Void
    /// Back in the frontmost column.
    var goBack: @MainActor () -> Void
    /// Open global search.
    var search: @MainActor () -> Void
    /// Refresh the frontmost refreshable page.
    var refresh: @MainActor () -> Void
    /// Open profile selection.
    var chooseProfile: @MainActor () -> Void
    /// Deselect the player.
    var deselectProfile: @MainActor () -> Void
    /// Open Notifications.
    var notifications: @MainActor () -> Void
    /// Open What's New.
    var whatsNew: @MainActor () -> Void
    /// Push Licenses on the current destination.
    var licenses: @MainActor () -> Void
    /// Open the navigation flyout (iPad regular width; nil where none is shown).
    var showNavigation: (@MainActor () -> Void)? = nil
    /// Close the open flyout, else the open trailing pane (Escape); nil when neither shows.
    var closeOverlay: (@MainActor () -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.destinations == rhs.destinations && lhs.visible == rhs.visible && lhs.selected == rhs.selected
            && lhs.canGoBack == rhs.canGoBack && lhs.sheetOpen == rhs.sheetOpen && lhs.hasPlayer == rhs.hasPlayer
            && (lhs.showNavigation == nil) == (rhs.showNavigation == nil)
            && (lhs.closeOverlay == nil) == (rhs.closeOverlay == nil)
    }

    /// The Go menu's destinations for a shell: the sidebar's full set (web sidebar
    /// order), or the phone tab slots for a compact window, plus anything visible that
    /// the fixed set lacks.
    ///
    /// - Parameters:
    ///   - sidebar: Whether the window shows the sidebar shell.
    ///   - visible: The visible destinations.
    /// - Returns: Ordered destinations.
    static func destinations(sidebar: Bool, visible: [FestivalSection]) -> [FestivalSection] {
        let fixed: [FestivalSection] = sidebar
            ? SidebarMenu.sections(profile: .player, hideShop: false)
            : [.songs, .suggestions, .compete, .leaderboards, .statistics, .settings]
        return fixed + visible.filter { !fixed.contains($0) }
    }

    /// The ⌘-digit for a destination: its 1-based position among the visible ones.
    ///
    /// - Parameter section: A Go-menu destination.
    /// - Returns: 1…9, or nil when hidden or past the ninth.
    func digit(for section: FestivalSection) -> Int? {
        guard let index = visible.firstIndex(of: section), index < 9 else { return nil }
        return index + 1
    }
}
