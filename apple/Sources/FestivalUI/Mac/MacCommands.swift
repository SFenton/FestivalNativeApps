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

    /// Always equal: the closures only flip the page's own presentation state.
    static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.sort == nil) == (rhs.sort == nil) && (lhs.filter == nil) == (rhs.filter == nil)
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

// MARK: - Menu bar

/// The Mac app's menu bar commands: View (sidebar, toolbar, Refresh, Sort/Filter), a
/// Go menu (destinations ⌘1…⌘9, Back ⌘[, Search ⌘K), a Profile menu and Help.
/// Unavailable items are disabled, never hidden (HIG The menu bar).
public struct MacCommands: Commands {
    let model: MacAppModel
    @FocusedValue(\.macPageCommands) private var pageCommands

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
        // One primary window: no File › New Window.
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search Festival…") { navigation.searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(sheetOpen)
        }
        CommandGroup(before: .sidebar) {
            Button("Refresh") { navigation.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(sheetOpen)
            Divider()
            Button("Sort…") { pageCommands?.sort?() }
                .disabled(pageCommands?.sort == nil || sheetOpen)
            Button("Filter…") { pageCommands?.filter?() }
                .disabled(pageCommands?.filter == nil || sheetOpen)
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
