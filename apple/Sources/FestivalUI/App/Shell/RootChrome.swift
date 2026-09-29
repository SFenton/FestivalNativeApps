import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Shell environment actions

/// Environment action that opens the profile selection sheet from anywhere
/// (e.g. an in-page "Choose Profile" empty-state button).
///
/// `FestivalRootView` installs the real handler; the default is a no-op so hosted
/// previews and tests can render screens without the shell.
///
/// Always equal: the root re-creates the closure on every body pass (for example when
/// a pop writes the path back) and closures never compare equal, so without this every
/// view reading the action is invalidated after each navigation. The handler only
/// flips root-owned `@State`, so any instance behaves identically.
struct OpenProfileAction: Equatable {
    let handler: @MainActor () -> Void

    /// Present profile selection.
    @MainActor func callAsFunction() { handler() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// Environment action that opens the leading navigation drawer.
///
/// Equatable for the same reason as ``OpenProfileAction``.
struct OpenDrawerAction: Equatable {
    let handler: @MainActor () -> Void

    /// Slide the drawer in.
    @MainActor func callAsFunction() { handler() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Opens the profile selection sheet owned by the root shell.
    @Entry var openProfile = OpenProfileAction(handler: {})
    /// Opens the hamburger drawer; nil where the platform shows a permanent sidebar.
    @Entry var openDrawer: OpenDrawerAction? = nil
}

// MARK: - Rail overflow ranking

/// Rail overflow ranking for the shared tab-root chrome (operator decision,
/// 2026-09-28): folded iPhone Duo with a profile selected only fits **two** root
/// toolbar items plus the system "…" overflow in the vertical bar (5 tabs leave
/// little room). Bell and Profile (``FestivalRootTrailingItems``) stay visible;
/// the hamburger drawer button (``DrawerButton``) overflows into "…" as "Menu".
/// Giving the hamburger `.high` priority too instead pushed the profile avatar
/// into "…" — the wrong tradeoff, since the selected profile's identity is the
/// more useful item to keep visible at a glance
/// (`.agents/design/apple/duo.md` "Toolbar rules"). Anonymous sessions (3 tabs)
/// have enough room that every item stays visible regardless of this ranking.
///
/// `FestivalRootChrome`/`FestivalRootTrailingItems` apply this as the real
/// `visibilityPriority`, so ``RootChromeRailPriorityTests`` pins the decision
/// against a regression, not just a comment.
enum RootChromeRailItem: CaseIterable, Equatable {
    case drawer
    case bell
    case profile

    /// True when the system should keep this item visible ahead of same-bar
    /// items with standard priority once the vertical bar runs out of room.
    var staysVisibleAheadOfOthers: Bool {
        switch self {
        case .drawer: false
        case .bell, .profile: true
        }
    }
}

#if os(iOS)
@available(iOS 27.0, *)
private extension ToolbarContent {
    /// Applies ``RootChromeRailItem``'s ranking as the real `visibilityPriority`.
    ///
    /// - Parameter item: Which rail item this toolbar item represents.
    /// - Returns: The toolbar content with the matching system priority.
    @ToolbarContentBuilder
    func railVisibilityPriority(_ item: RootChromeRailItem) -> some ToolbarContent {
        if item.staysVisibleAheadOfOthers {
            visibilityPriority(.high)
        } else {
            visibilityPriority(.automatic)
        }
    }
}
#endif

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
    ///   - providesTrailingItems: Whether the page ends its own toolbar with
    ///     `FestivalRootTrailingItems`. Pass it whenever the caller knows: the fallback
    ///     (nil) reads `FestivalRootTrailingProvidedKey`, which arrives one update late,
    ///     so the first pass briefly adds a second bell/avatar and re-lays out the toolbar
    ///     (costly in the iPhone Duo rail, where every item change animates).
    /// - Returns: The page with shared chrome attached.
    func festivalRootChrome(
        session: FestivalSession, showsNotifications: Bool = true, providesTrailingItems: Bool? = nil
    ) -> some View {
        modifier(FestivalRootChrome(
            session: session, showsNotifications: showsNotifications,
            declaredProvidesTrailing: providesTrailingItems
        ))
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
    /// Synchronous declaration from the caller; nil falls back to the preference.
    var declaredProvidesTrailing: Bool?
    @Environment(\.openDrawer) private var openDrawer
    @State private var reportedProvidesTrailing = false

    /// Whether the page supplies the bell/avatar itself. A declared value never changes
    /// between updates, so the toolbar's structure stays stable across push and pop.
    private var pageProvidesTrailing: Bool { declaredProvidesTrailing ?? reportedProvidesTrailing }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FestivalRootTrailingProvidedKey.self) { provided in
                guard declaredProvidesTrailing == nil else { return }
                reportedProvidesTrailing = provided
            }
            .toolbar {
                #if os(iOS)
                if let openDrawer {
                    if #available(iOS 27.0, *) {
                        ToolbarItem(placement: .topBarLeading) {
                            DrawerButton { openDrawer() }
                        }
                        .railVisibilityPriority(.drawer)
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            DrawerButton { openDrawer() }
                        }
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
/// and carry `visibilityPriority(.high)` (iOS 27+), so page actions overflow into the
/// system `…` menu before them: the bell carries the unread badge and the profile item
/// is the only visible identity on every root.
struct FestivalRootTrailingItems: ToolbarContent {
    let session: FestivalSession
    var showsNotifications: Bool = true
    @Environment(\.openProfile) private var openProfile
    /// Global search: a header button on every layout (operator, 2026-09-28).
    @Environment(\.openGlobalSearch) private var openGlobalSearch

    var body: some ToolbarContent {
        #if os(iOS)
        if let openGlobalSearch {
            // Global search before the bell/avatar capsule (web header order).
            ToolbarItem(placement: .topBarTrailing) {
                GlobalSearchButton { openGlobalSearch() }
            }
        }
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        // Bell only with a selected profile (operator, 2026-09-28): notifications are per player.
        if showsNotifications && session.selectedPlayer != nil {
            if #available(iOS 27.0, *) {
                ToolbarItem(placement: .topBarTrailing) { NotificationsButton(session: session) }
                    .railVisibilityPriority(.bell)
            } else {
                ToolbarItem(placement: .topBarTrailing) { NotificationsButton(session: session) }
            }
        }
        if #available(iOS 27.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                RootProfileButton(session: session) { openProfile() }
            }
            .railVisibilityPriority(.profile)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                RootProfileButton(session: session) { openProfile() }
            }
        }
        #else
        if let openGlobalSearch {
            ToolbarItem(placement: .primaryAction) {
                GlobalSearchButton { openGlobalSearch() }
            }
        }
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

// MARK: - Vertical-bar page actions

/// A page action mirrored into the system vertical bar (the iPhone Duo "rail").
///
/// In horizontal bars this adds nothing: the page keeps its in-content button. In a
/// vertical bar the action also becomes a titled symbol item, so it sits in the rail
/// beside Back instead of only deep in the content (operator, 2026-09-28: Duo "Select
/// Profile" belongs in the rail). The in-page design stays with the page's lane; this
/// only owns rail placement.
struct VerticalBarActionItem: ToolbarContent {
    /// Title (overflow menu and VoiceOver).
    let title: String
    /// SF Symbol shown in the rail.
    let systemImage: String
    /// Accessibility identifier for UI tests.
    let identifier: String
    /// Performs the page's action.
    let action: () -> Void
    @Environment(\.deviceLayout) private var layout

    /// Leading group on iOS (after Back); primary action elsewhere.
    private static var placement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .primaryAction
        #endif
    }

    var body: some ToolbarContent {
        if layout.sectionChrome.isVerticalBar {
            // Its own group right after Back: sharing the trailing group with Quick Links
            // made the rail re-lay out the destination's items after a pop.
            ToolbarItem(placement: Self.placement) {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .tint(BrandTokens.textPrimary)
                .accessibilityIdentifier(identifier)
            }
        }
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
        // Bar buttons keep their size at large text (HIG); the Large Content Viewer
        // shows the name instead of the fixed-size monogram.
        .accessibilityShowsLargeContentViewer {
            Label(
                session.selectedPlayer?.displayName ?? "Choose Profile",
                systemImage: "person.crop.circle"
            )
        }
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
