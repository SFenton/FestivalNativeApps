import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Shell commands

/// The root shell's actions for the iPadOS menu bar, published by each window's
/// `FestivalRootView` with `focusedSceneValue`, so a menu command always acts on the
/// window in front (each window keeps its own navigation;
/// `.agents/design/apple/ipados.md`, Menu bar and Multiwindow).
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

private struct FestivalShellCommandsKey: FocusedValueKey {
    typealias Value = FestivalShellCommands
}

extension FocusedValues {
    /// The front window's root shell actions.
    var festivalShellCommands: FestivalShellCommands? {
        get { self[FestivalShellCommandsKey.self] }
        set { self[FestivalShellCommandsKey.self] = newValue }
    }
}

#if os(iOS)
// MARK: - iPadOS menu bar

/// The iPadOS menu bar (and ⌘-hold shortcut overlay), mirroring the Mac's
/// ``MacCommands`` over the focused window's ``FestivalShellCommands`` and the page
/// values the Mac already publishes: Edit › Search Festival (⌘F); View › Refresh (⌘R),
/// Sort…, Filter…, Rank By ▸, Instrument ▸, sidebar; Go › Back (⌘[), destinations (⌘1…⌘9), Search
/// (⌘K), Next/Previous Section (⌥⌘↓/↑); Song › Paths…, Open in Item
/// Shop; Profile › Select/Switch (⇧⌘P), Deselect, Find Rival…, Notifications; Help.
/// Unavailable items are disabled, never hidden (HIG The menu bar). iPhone has no menu
/// bar: nothing is added there, so its own hidden shortcut buttons stay in charge.
public struct FestivalCommands: Commands {
    @FocusedValue(\.festivalShellCommands) private var shell
    @FocusedValue(\.macPageCommands) private var pageCommands
    @FocusedValue(\.macSongCommands) private var songCommands
    @FocusedValue(\.macRankBy) private var rankBy
    @FocusedValue(\.macInstrument) private var instrument
    @FocusedValue(\.macQuickLinksPage) private var pageQuickLinks
    @FocusedValue(\.macQuickLinksList) private var listQuickLinks

    /// Create the commands.
    public init() {}

    /// Whether a root sheet covers the front window, or no window is focused.
    private var blocked: Bool { shell?.sheetOpen ?? true }

    public var body: some Commands {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // No persistent sidebar on iPad (`split-view.md`): View › Show Navigation
            // opens the overlay flyout instead of the system sidebar toggle.
            CommandGroup(before: .toolbar) {
                Button("Show Navigation") { shell?.showNavigation?() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                    .disabled(blocked || shell?.showNavigation == nil)
                // Escape closes the flyout or the open trailing pane (split-view.md).
                // In-view Escape shortcuts never fired on iPad with the menu bar
                // (live, 2026-10-04), so the window's command carries it.
                Button("Close") { shell?.closeOverlay?() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(shell?.closeOverlay == nil)
            }
            // HIG The menu bar › iPadOS: "Reserve Settings for opening your app's page in
            // iPadOS Settings; put internal-preferences ... beneath it, in the same group."
            CommandGroup(after: .appSettings) {
                Button("App Settings…") { shell?.select(.settings) }
                    .disabled(blocked || shell?.visible.contains(.settings) != true)
            }
            CommandGroup(after: .textEditing) {
                Button("Search Festival…") { shell?.search() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(blocked)
            }
            CommandGroup(before: .sidebar) {
                Button("Refresh") { shell?.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(blocked)
                Divider()
                Button("Sort…") { pageCommands?.sort?() }
                    .disabled(pageCommands?.sort == nil || blocked)
                Button("Filter…") { pageCommands?.filter?() }
                    .disabled(pageCommands?.filter == nil || blocked)
                rankByMenu
                instrumentMenu
                Divider()
            }
            CommandMenu("Go") {
                Button("Back") { shell?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(shell?.canGoBack != true || blocked)
                Divider()
                ForEach(shell?.destinations ?? [.songs]) { destination in
                    destinationButton(destination)
                }
                Divider()
                Button("Search…") { shell?.search() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(blocked)
                Divider()
                quickLinksCommands
            }
            CommandMenu("Song") {
                Button("Paths…") { songCommands?.paths?() }
                    .disabled(songCommands?.paths == nil || blocked)
                Button("Open in Item Shop") {
                    if let url = songCommands?.shopURL { UIApplication.shared.open(url) }
                }
                .disabled(songCommands?.shopURL == nil)
            }
            CommandMenu("Profile") {
                Button(shell?.hasPlayer == true ? "Switch Profile…" : "Select Profile…") {
                    shell?.chooseProfile()
                }
                .keyboardShortcut("p", modifiers: [.shift, .command])
                .disabled(blocked)
                Button("Deselect Profile") { shell?.deselectProfile() }
                    .disabled(shell?.hasPlayer != true || blocked)
                Divider()
                Button("Find Rival…") { pageCommands?.findRival?() }
                    .disabled(pageCommands?.findRival == nil || blocked)
                Button("Notifications") { shell?.notifications() }
                    .disabled(shell?.hasPlayer != true || blocked)
            }
            CommandGroup(replacing: .help) {
                Button("Festival Score Tracker Website") {
                    if let url = URL(string: "https://festivalscoretracker.com") { UIApplication.shared.open(url) }
                }
                Divider()
                Button("What's New") { shell?.whatsNew() }
                    .disabled(blocked)
                Button("Licenses") { shell?.licenses() }
                    .disabled(blocked)
            }
        }
    }

    /// View › Rank By with a checkmark on the metric in effect; the account metrics stay
    /// listed but disabled elsewhere (HIG Menus: "Make sure a submenu remains available
    /// even when its items are unavailable").
    @ViewBuilder private var rankByMenu: some View {
        let options = rankBy?.options ?? MacRankByCommands.accountOptions
        Menu("Rank By") {
            ForEach(options) { option in
                Toggle(option.label, isOn: Binding(
                    get: { rankBy?.selected == option.id },
                    set: { isOn in if isOn { rankBy?.select(option.id) } }
                ))
                .disabled(rankBy == nil)
            }
        }
    }

    /// View › Instrument with a checkmark on the chart in effect (the front rankings
    /// page's toolbar instrument menu, issue #294); every chart stays listed but
    /// disabled elsewhere (HIG Menus: "Make sure a submenu remains available even when
    /// its items are unavailable").
    @ViewBuilder private var instrumentMenu: some View {
        let options = instrument?.options ?? MacInstrumentCommands.allOptions
        Menu("Instrument") {
            ForEach(options) { option in
                Toggle(option.label, isOn: Binding(
                    get: { instrument?.selected == option.id },
                    set: { isOn in if isOn { instrument?.select(option.id) } }
                ))
                .disabled(instrument == nil)
            }
        }
    }

    /// Go › Next / Previous Section over the front page's Quick Links (the detail page wins).
    @ViewBuilder private var quickLinksCommands: some View {
        let controller = (pageQuickLinks ?? listQuickLinks)?.controller
        let sections = controller?.isAvailable == true ? controller?.sections ?? [] : []
        // No per-section submenu: listing the front page's sections (Leaderboards, Song
        // Detail) left the whole iPadOS menu bar unresponsive in the flyout shell, with
        // static items or live toggles alike (live A/B, 2026-10-05: ⌘-digits ignored
        // with the list, fine without). The page's toolbar Quick Links menu lists them;
        // Next/Previous Section keep keyboard access and resolve the active section
        // when chosen.
        Button("Next Section") { jumpQuickLink(controller, offset: 1) }
            .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            .disabled(sections.isEmpty || blocked)
        Button("Previous Section") { jumpQuickLink(controller, offset: -1) }
            .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            .disabled(sections.isEmpty || blocked)
    }

    /// Jump to the section before or after the active one (nothing at either end).
    ///
    /// - Parameters:
    ///   - controller: The front page's Quick Links.
    ///   - offset: +1 for next, −1 for previous.
    private func jumpQuickLink(_ controller: QuickLinksController?, offset: Int) {
        guard let controller else { return }
        let ids = controller.sections.map(\.id)
        if let target = MacQuickLinksCommand.neighbor(of: controller.activeID, in: ids, offset: offset) {
            controller.jump(to: target)
        }
    }

    /// A Go-menu destination, ⌘n for the n-th visible one (HIG The menu bar › iPadOS:
    /// "Tab-style navigation: consider a View menu item per tab, and key bindings for
    /// each"; listed under Go like the Mac's).
    @ViewBuilder private func destinationButton(_ destination: FestivalSection) -> some View {
        let digit = shell?.digit(for: destination)
        let button = Button(destination.title) { shell?.select(destination) }
            .disabled(digit == nil && shell?.visible.contains(destination) != true || blocked)
        if let digit {
            button.keyboardShortcut(KeyEquivalent(Character(String(digit))), modifiers: .command)
        } else {
            button
        }
    }
}
#endif
