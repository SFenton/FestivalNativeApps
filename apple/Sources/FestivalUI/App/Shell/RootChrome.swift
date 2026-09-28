import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Shell environment actions

/// Environment action that opens the profile selection sheet from anywhere
/// (e.g. an in-page "Choose Profile" empty-state button).
///
/// `FestivalRootView` installs the real handler; the default is a no-op so hosted
/// previews and tests can render screens without the shell.
struct OpenProfileAction {
    let handler: @MainActor () -> Void

    /// Present profile selection.
    @MainActor func callAsFunction() { handler() }
}

/// Environment action that opens the leading navigation drawer.
struct OpenDrawerAction {
    let handler: @MainActor () -> Void

    /// Slide the drawer in.
    @MainActor func callAsFunction() { handler() }
}

extension EnvironmentValues {
    /// Opens the profile selection sheet owned by the root shell.
    @Entry var openProfile = OpenProfileAction(handler: {})
    /// Opens the hamburger drawer; nil where the platform shows a permanent sidebar.
    @Entry var openDrawer: OpenDrawerAction? = nil
}

// MARK: - Shared tab-root chrome

extension View {
    /// Standard chrome for every tab root: drawer button (leading) and profile
    /// button (trailing, top-right like the web header).
    ///
    /// Page-specific toolbar items (search, sort, filter) are added by the page
    /// itself with its own `.toolbar { … }`; this modifier owns only the shared
    /// items. The profile sheet and drawer are owned by `FestivalRootView` and reached
    /// through `\.openProfile` / `\.openDrawer`. Apply only on tab **roots**, never on
    /// pushed pages (they get the system back button instead). Owned by Lane A (Shell).
    ///
    /// - Parameters:
    ///   - session: Shared app session (drives the profile avatar).
    ///   - showsNotifications: Show the notifications bell beside the profile button.
    /// - Returns: The page with shared chrome attached.
    func festivalRootChrome(session: FestivalSession, showsNotifications: Bool = true) -> some View {
        modifier(FestivalRootChrome(session: session, showsNotifications: showsNotifications))
    }
}

/// Implementation of `festivalRootChrome(session:)`.
///
/// Toolbar items from an outer modifier are laid out *before* the page's own items,
/// so a page with trailing actions would push the profile avatar away from the
/// top-right corner. Such pages instead end their own `.toolbar` with
/// `FestivalRootTrailingItems(session:)` and mark themselves with
/// `.festivalProvidesRootTrailingItems()`; the chrome then only adds the drawer button.
struct FestivalRootChrome: ViewModifier {
    let session: FestivalSession
    let showsNotifications: Bool
    @Environment(\.openDrawer) private var openDrawer
    @State private var pageProvidesTrailing = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FestivalRootTrailingProvidedKey.self) { provided in
                pageProvidesTrailing = provided
            }
            .toolbar {
                #if os(iOS)
                if let openDrawer {
                    ToolbarItem(placement: .topBarLeading) {
                        DrawerButton { openDrawer() }
                    }
                }
                #endif
                if !pageProvidesTrailing {
                    FestivalRootTrailingItems(session: session, showsNotifications: showsNotifications)
                }
            }
    }
}

// MARK: - Shared trailing items

/// The notifications bell and profile avatar as one glass capsule at the top-right.
///
/// Pages with their own trailing actions list this **last** inside their `.toolbar`
/// and apply `.festivalProvidesRootTrailingItems()`, so the avatar stays rightmost.
///
/// In the iPhone Duo vertical bar both items stay symbol items (see ``RootProfileButton``)
/// and the bell carries `visibilityPriority(.high)` (iOS 27+) so it is the last page item
/// to overflow into the system `…` menu: it carries the unread badge.
struct FestivalRootTrailingItems: ToolbarContent {
    let session: FestivalSession
    var showsNotifications: Bool = true
    @Environment(\.openProfile) private var openProfile

    var body: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        if showsNotifications {
            if #available(iOS 27.0, *) {
                ToolbarItem(placement: .topBarTrailing) { NotificationsButton(session: session) }
                    .visibilityPriority(.high)
            } else {
                ToolbarItem(placement: .topBarTrailing) { NotificationsButton(session: session) }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            RootProfileButton(session: session) { openProfile() }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            RootProfileButton(session: session) { openProfile() }
        }
        #endif
    }
}

/// Set by pages that place `FestivalRootTrailingItems` in their own toolbar.
struct FestivalRootTrailingProvidedKey: PreferenceKey {
    static let defaultValue = false

    /// Any page in the subtree providing the items suppresses the chrome's copy.
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Declare that this tab root already ends its toolbar with `FestivalRootTrailingItems`.
    ///
    /// - Returns: The view, tagged so `festivalRootChrome` skips its own trailing items.
    func festivalProvidesRootTrailingItems() -> some View {
        preference(key: FestivalRootTrailingProvidedKey.self, value: true)
    }
}

// MARK: - Toolbar buttons

/// Hamburger button that opens the leading drawer (web `HamburgerButton`).
struct DrawerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Menu", systemImage: "line.3.horizontal")
        }
        .tint(BrandTokens.textPrimary)
        .accessibilityLabel("Open Navigation")
        .accessibilityIdentifier("fst.shell.drawer.open")
    }
}

/// Notifications bell (web `HeaderActions` bell): unread badge, opens the native sheet.
///
/// Owned by the Notifications feature lane; see `Features/Notifications/NotificationsSheet.swift`.
struct NotificationsButton: View {
    let session: FestivalSession
    @State private var presented = false
    private var center: NotificationsCenter { session.notificationsCenter }

    var body: some View {
        Button {
            presented = true
        } label: {
            Label("Notifications", systemImage: "bell")
        }
        .tint(BrandTokens.textPrimary)
        .accessibilityLabel(center.unreadCount > 0
            ? "Notifications, \(center.unreadCount) unread" : "Notifications")
        .accessibilityIdentifier("fst.shell.notifications")
        .overlay(alignment: .topTrailing) {
            if center.unreadCount > 0 {
                Circle()
                    .fill(BrandTokens.gold)
                    .frame(width: 9, height: 9)
                    .offset(x: 2, y: -1)
                    .accessibilityHidden(true)
            }
        }
        .task(id: session.selectionRevision) { await center.refresh(session: session) }
        .sheet(isPresented: $presented) {
            NotificationsSheet(session: session)
                .festivalSheet(.large)
        }
    }
}

/// Top-right profile action: the selected player's initial, or an add-profile glyph.
///
/// In a system vertical bar (iPhone Duo) the selected player shows as the symbol
/// `person.crop.circle.fill` titled "Profile: <name>" instead of the monogram: a
/// custom-view item cannot go vertical, so the system would keep a horizontal top bar
/// just for it (`.agents/design/apple/duo.md`, B1). Horizontal bars keep the monogram.
struct RootProfileButton: View {
    let session: FestivalSession
    let action: () -> Void
    @Environment(\.deviceLayout) private var layout

    /// How the profile action is drawn for a player and section chrome.
    enum Presentation: Equatable {
        /// Add-profile symbol (no selection).
        case choose
        /// Monogram avatar (horizontal bars).
        case monogram(String)
        /// Titled symbol item (system vertical bar).
        case symbol(title: String)

        /// Resolve the presentation.
        ///
        /// - Parameters:
        ///   - displayName: Selected player's name, or nil when anonymous.
        ///   - chrome: Current section chrome.
        /// - Returns: The presentation.
        static func resolve(displayName: String?, chrome: DeviceLayout.SectionChrome) -> Presentation {
            guard let displayName else { return .choose }
            if case .verticalBar = chrome { return .symbol(title: "Profile: \(displayName)") }
            return .monogram(displayName)
        }
    }

    var body: some View {
        Button(action: action) {
            switch Presentation.resolve(
                displayName: session.selectedPlayer?.displayName, chrome: layout.sectionChrome
            ) {
            case .choose:
                Label("Choose Profile", systemImage: "person.crop.circle")
            case let .monogram(name):
                ProfileAvatar(name: name, size: 30)
            case let .symbol(title):
                Label(title, systemImage: "person.crop.circle.fill")
            }
        }
        .tint(BrandTokens.textPrimary)
        .accessibilityLabel(session.selectedPlayer.map {
            "Profile: \($0.displayName)"
        } ?? "Choose Profile")
        .accessibilityHint("Opens profile selection")
        .accessibilityIdentifier("fst.shell.profile")
    }
}

// MARK: - Avatar

/// Circular monogram for a selected profile (players have no public avatar image).
struct ProfileAvatar: View {
    let name: String
    let size: CGFloat

    /// First letter or digit of the display name, upper-cased.
    nonisolated static func initial(for name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        Text(Self.initial(for: name))
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(BrandTokens.textPrimary)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [BrandTokens.accentBlue, BrandTokens.accentPurple],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(BrandTokens.glassBorder, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
