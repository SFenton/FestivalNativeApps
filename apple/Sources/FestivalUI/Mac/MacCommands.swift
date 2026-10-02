#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Page commands

/// Page tools a focused page offers to the menu bar (HIG Toolbars › macOS: "Every
/// toolbar item must also be a menu-bar command"). Songs publishes Sort and Filter.
struct MacPageCommands: Equatable {
    /// Opens the page's Sort options, or nil when the page has none.
    var sort: (@MainActor () -> Void)?
    /// Opens the page's Filter options, or nil when unavailable.
    var filter: (@MainActor () -> Void)?
    /// Opens Find Rival (Rivals), or nil elsewhere.
    var findRival: (@MainActor () -> Void)?

    /// Always equal: the closures only flip the page's own presentation state.
    static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.sort == nil) == (rhs.sort == nil) && (lhs.filter == nil) == (rhs.filter == nil)
            && (lhs.findRival == nil) == (rhs.findRival == nil)
    }
}

private struct MacPageCommandsKey: FocusedValueKey {
    typealias Value = MacPageCommands
}

extension FocusedValues {
    /// Sort/Filter actions of the page in the key window.
    var macPageCommands: MacPageCommands? {
        get { self[MacPageCommandsKey.self] }
        set { self[MacPageCommandsKey.self] = newValue }
    }
}

extension View {
    /// Publish a page's Sort/Filter actions to View › Sort… / Filter… (macOS only).
    ///
    /// - Parameter commands: The page's actions.
    /// - Returns: The view.
    func macPageCommands(_ commands: MacPageCommands) -> some View {
        focusedSceneValue(\.macPageCommands, commands)
    }
}

// MARK: - Song commands

/// Song Detail's toolbar tools for the menu bar (HIG Toolbars › macOS: "Every toolbar
/// item must also be a menu-bar command"): Paths and the official Item Shop link.
/// A separate key from ``MacPageCommands`` because the Songs list beside the song
/// publishes Sort/Filter at the same time.
struct MacSongCommands: Equatable {
    /// The song shown (for menu titles and equality).
    var songId: String
    /// Opens the Paths sheet, or nil when the song has no path charts.
    var paths: (@MainActor () -> Void)?
    /// The official Item Shop page while the song is in the Shop.
    var shopURL: URL?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songId == rhs.songId && (lhs.paths == nil) == (rhs.paths == nil) && lhs.shopURL == rhs.shopURL
    }
}

private struct MacSongCommandsKey: FocusedValueKey {
    typealias Value = MacSongCommands
}

extension FocusedValues {
    /// Song Detail's tools in the key window.
    var macSongCommands: MacSongCommands? {
        get { self[MacSongCommandsKey.self] }
        set { self[MacSongCommandsKey.self] = newValue }
    }
}

extension View {
    /// Publish Song Detail's Paths/Item Shop tools to the Song menu (macOS only).
    ///
    /// - Parameter commands: The song's tools.
    /// - Returns: The view.
    func macSongCommands(_ commands: MacSongCommands) -> some View {
        focusedSceneValue(\.macSongCommands, commands)
    }
}

// MARK: - Menu bar

/// The Mac app's menu bar commands: File › Close, Edit › Search Festival, View
/// (sidebar, toolbar, Refresh, Full Screen, Sort/Filter), a Go menu (destinations
/// ⌘1…⌘9, Back ⌘[, Search ⌘K), a Song menu (Paths, Item Shop), Profile and Help.
/// Unavailable items are disabled, never hidden (HIG The menu bar).
public struct MacCommands: Commands {
    let model: MacAppModel
    @FocusedValue(\.macPageCommands) private var pageCommands
    @FocusedValue(\.macSongCommands) private var songCommands
    @FocusedValue(\.macRankBy) private var rankBy
    @FocusedValue(\.macQuickLinksPage) private var pageQuickLinks
    @FocusedValue(\.macQuickLinksList) private var listQuickLinks
    @FocusedValue(\.macListCommands) private var listCommands

    /// Create the commands.
    ///
    /// - Parameter model: The app model shared with the window.
    public init(model: MacAppModel) {
        self.model = model
    }

    private var navigation: MacNavigationModel { model.navigation }

    /// Whether a sheet covers the window (menu commands must not stack another one).
    private var sheetOpen: Bool {
        navigation.profilePresented || navigation.searchPresented
            || navigation.notificationsPresented || navigation.whatsNewPresented
    }

    public var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        // One primary window: no File › New Window (HIG Windows: "avoid it as default
        // behavior unless it makes sense for your app"). Close keeps ⌘W for the main
        // and Settings windows (HIG The menu bar › File menu: "Close").
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search Festival…") { navigation.searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(sheetOpen)
        }
        CommandGroup(before: .sidebar) {
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(sheetOpen)
            Divider()
            // The system full-screen experience (HIG Going full screen › macOS: "Use
            // the system full-screen experience … Prefer the window's Enter Full Screen
            // button, View menu item or Control-Command-F"); the title follows state.
            Button(model.isFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                NSApp.sendAction(#selector(NSWindow.toggleFullScreen(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
            Divider()
            Button("Sort…") { pageCommands?.sort?() }
                .disabled(pageCommands?.sort == nil || sheetOpen)
            Button("Filter…") { pageCommands?.filter?() }
                .disabled(pageCommands?.filter == nil || sheetOpen)
            rankByMenu
            Divider()
            // The standard "Scroll to selection" shortcut (HIG Keyboards: Command-J).
            Button("Scroll to Selection") { listCommands?.scrollToSelection() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(listCommands == nil || sheetOpen)
            Divider()
        }
        CommandMenu("Go") {
            Button("Back") { navigation.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!navigation.canGoBack || sheetOpen)
            Divider()
            ForEach(MacDestination.allCases) { destination in
                destinationButton(destination)
            }
            Divider()
            Button("Search…") { navigation.searchPresented = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(sheetOpen)
            Divider()
            quickLinksCommands
        }
        CommandMenu("Song") {
            Button("Paths…") { songCommands?.paths?() }
                .disabled(songCommands?.paths == nil || sheetOpen)
            Button("Open in Item Shop") {
                if let url = songCommands?.shopURL { NSWorkspace.shared.open(url) }
            }
            .disabled(songCommands?.shopURL == nil)
        }
        CommandMenu("Profile") {
            Button(model.session.selectedPlayer == nil ? "Select Profile…" : "Switch Profile…") {
                navigation.profilePresented = true
            }
            .keyboardShortcut("p", modifiers: [.shift, .command])
            .disabled(sheetOpen)
            Button("Deselect Profile") { model.session.deselectPlayer() }
                .disabled(model.session.selectedPlayer == nil)
            Divider()
            Button("Find Rival…") { pageCommands?.findRival?() }
                .disabled(pageCommands?.findRival == nil || sheetOpen)
            Button("Notifications") { navigation.notificationsPresented = true }
                .disabled(model.session.selectedPlayer == nil || sheetOpen)
        }
        CommandGroup(replacing: .help) {
            Button("Festival Score Tracker Website") {
                if let url = URL(string: "https://festivalscoretracker.com") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("What's New") { navigation.whatsNewPresented = true }
                .disabled(sheetOpen)
            Button("Licenses") { navigation.push(.licenses) }
                .disabled(sheetOpen)
        }
    }

    /// View › Rank By: the front rankings page's metrics with a checkmark on the one in
    /// effect (HIG Menus: "Consider a checkmark to show an attribute is in effect");
    /// the account metrics stay listed but disabled elsewhere, so the submenu keeps
    /// its items (HIG Menus: "Make sure a submenu remains available even when its
    /// items are unavailable").
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

    /// Go › Quick Links (the front page's sections, the active one checked) and Next /
    /// Previous Section (⌥⌘↓ / ⌥⌘↑; Command-J is the standard Scroll to Selection).
    /// The detail column's page wins over the list column's.
    @ViewBuilder private var quickLinksCommands: some View {
        let controller = (pageQuickLinks ?? listQuickLinks)?.controller
        let sections = controller?.isAvailable == true ? controller?.sections ?? [] : []
        let ids = sections.map(\.id)
        let next = MacQuickLinksCommand.neighbor(of: controller?.activeID, in: ids, offset: 1)
        let previous = MacQuickLinksCommand.neighbor(of: controller?.activeID, in: ids, offset: -1)
        Menu("Quick Links") {
            if sections.isEmpty {
                Button("No Sections") {}.disabled(true)
            } else {
                ForEach(sections) { section in
                    Toggle(section.title, isOn: Binding(
                        get: { controller?.activeID == section.id },
                        set: { _ in controller?.jump(to: section.id) }
                    ))
                }
            }
        }
        Button("Next Section") { if let next { controller?.jump(to: next) } }
            .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            .disabled(next == nil || sheetOpen)
        Button("Previous Section") { if let previous { controller?.jump(to: previous) } }
            .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            .disabled(previous == nil || sheetOpen)
    }

    /// A Go-menu item: every destination is listed (disabled when hidden), with ⌘n for
    /// the n-th visible sidebar row.
    @ViewBuilder private func destinationButton(_ destination: MacDestination) -> some View {
        let index = navigation.visible.firstIndex(of: destination)
        let button = Button(destination.title) { navigation.select(destination) }
            .disabled(index == nil || sheetOpen)
        if let index, index < 9 {
            button.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        } else {
            button
        }
    }
}
#endif
