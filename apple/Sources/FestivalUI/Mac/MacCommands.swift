import SwiftUI
import FestivalCore
#if os(macOS)
import AppKit
#endif

// MARK: - Page commands

private struct MacPageCommandsKey: FocusedValueKey {
    typealias Value = PageMenuCommands
}

extension FocusedValues {
    /// Sort/Filter actions of the page in the key window.
    var macPageCommands: PageMenuCommands? {
        get { self[MacPageCommandsKey.self] }
        set { self[MacPageCommandsKey.self] = newValue }
    }
}

extension View {
    /// Publish a page's Sort/Filter actions to View › Sort… / Filter… (the macOS and
    /// iPadOS menu bar; a no-op on iPhone).
    ///
    /// - Parameter commands: The page's actions.
    /// - Returns: The view.
    func macPageCommands(_ commands: PageMenuCommands) -> some View {
        #if os(macOS)
        focusedSceneValue(\.macPageCommands, commands)
        #else
        modifier(MenuBarTopPagePublisher(keyPath: \.macPageCommands, value: commands))
        #endif
    }
}

// MARK: - Song commands

private struct MacSongCommandsKey: FocusedValueKey {
    typealias Value = SongMenuCommands
}

extension FocusedValues {
    /// Song Detail's tools in the key window.
    var macSongCommands: SongMenuCommands? {
        get { self[MacSongCommandsKey.self] }
        set { self[MacSongCommandsKey.self] = newValue }
    }
}

extension View {
    /// Publish Song Detail's Paths/Item Shop tools to the Song menu (the macOS and
    /// iPadOS menu bar; a no-op on iPhone).
    ///
    /// - Parameter commands: The song's tools.
    /// - Returns: The view.
    func macSongCommands(_ commands: SongMenuCommands) -> some View {
        #if os(macOS)
        focusedSceneValue(\.macSongCommands, commands)
        #else
        modifier(MenuBarTopPagePublisher(keyPath: \.macSongCommands, value: commands))
        #endif
    }
}

// MARK: - Profile page commands

private struct MacProfilePageCommandsKey: FocusedValueKey {
    typealias Value = ProfilePageMenuCommands
}

extension FocusedValues {
    /// The player or rival page's Profile-menu actions in the key window.
    var macProfilePageCommands: ProfilePageMenuCommands? {
        get { self[MacProfilePageCommandsKey.self] }
        set { self[MacProfilePageCommandsKey.self] = newValue }
    }
}

extension View {
    /// Publish a player or rival page's toolbar actions to the Profile menu (the macOS
    /// and iPadOS menu bar; a no-op on iPhone).
    ///
    /// - Parameter commands: The page's actions.
    /// - Returns: The view.
    func macProfilePageCommands(_ commands: ProfilePageMenuCommands) -> some View {
        #if os(macOS)
        focusedSceneValue(\.macProfilePageCommands, commands)
        #else
        modifier(MenuBarTopPagePublisher(keyPath: \.macProfilePageCommands, value: commands))
        #endif
    }
}

// MARK: - Menu bar

#if os(macOS)

/// The Mac app's menu bar commands: File › Close, Edit › Search Festival, View
/// (sidebar, toolbar, Refresh, Full Screen, Sort/Filter, Rank By, Instrument, Band
/// Size, as List/as Grid), a Go menu (destinations ⌘1…⌘9, Back ⌘[, Search ⌘K), a Song
/// menu (Paths, Item Shop), Profile (with the shown player's Select/Switch and View
/// Rival's Profile) and Help. Every page toolbar item has a command here (HIG Toolbars
/// › macOS: "Every toolbar item must also be a menu-bar command").
/// Unavailable items are disabled, never hidden (HIG The menu bar).
public struct MacCommands: Commands {
    let model: MacAppModel
    @FocusedValue(\.macPageCommands) private var pageCommands
    @FocusedValue(\.macSongCommands) private var songCommands
    @FocusedValue(\.macProfilePageCommands) private var profilePageCommands
    @FocusedValue(\.macRankBy) private var rankBy
    /// Settings › Experimental Ranks: View › Rank By lists Total Score alone while off.
    @AppStorage(ExperimentalRanks.storageKey) private var experimentalRanks = ExperimentalRanks.defaultValue
    @FocusedValue(\.macInstrument) private var instrument
    @FocusedValue(\.macBandSize) private var bandSize
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

    /// The front page's values for the shared page-tool menu items.
    private var pageTools: PageToolMenuState {
        PageToolMenuState(
            page: pageCommands, rankBy: rankBy, instrument: instrument, bandSize: bandSize,
            profile: profilePageCommands, experimentalRanks: experimentalRanks, blocked: sheetOpen
        )
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
            PageToolViewMenuItems(state: pageTools)
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
            PageToolProfileMenuItems(state: pageTools)
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

    /// Go › Quick Links (the front page's sections, the active one checked) and Next /
    /// Previous Section (⌥⌘↓ / ⌥⌘↑; Command-J is the standard Scroll to Selection).
    /// The detail column's page wins over the list column's.
    @ViewBuilder private var quickLinksCommands: some View {
        let controller = (pageQuickLinks ?? listQuickLinks)?.controller
        let sections = controller?.isAvailable == true ? controller?.sections ?? [] : []
        let ids = sections.map(\.id)
        let next = QuickLinksMenuCommand.neighbor(of: controller?.activeID, in: ids, offset: 1)
        let previous = QuickLinksMenuCommand.neighbor(of: controller?.activeID, in: ids, offset: -1)
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
