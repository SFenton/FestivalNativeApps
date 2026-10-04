import SwiftUI
import FestivalCore
import FestivalDesign
#if canImport(UIKit)
import UIKit
#endif

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

/// Environment action that pushes a route on the currently selected section's stack
/// (the root-owned path), for chrome presented above it such as the notifications sheet.
///
/// Equatable for the same reason as ``OpenProfileAction``.
struct PushRouteAction: Equatable {
    let handler: @MainActor (AppRoute) -> Void

    /// Push `route` on the current section's navigation stack.
    @MainActor func callAsFunction(_ route: AppRoute) { handler(route) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Opens the profile selection sheet owned by the root shell.
    @Entry var openProfile = OpenProfileAction(handler: {})
    /// The profile button (avatar) press: the selected player's Statistics page, or the
    /// profile selection sheet without a selection (``ProfileButtonAction``, issue #290).
    @Entry var profileButtonAction = ProfileButtonHandler(statisticsVisible: false, handler: {})
    /// Opens the hamburger drawer; nil where the platform shows a permanent sidebar.
    @Entry var openDrawer: OpenDrawerAction? = nil
    /// Pushes on the current section's stack; nil outside the root shell (hosted tests).
    @Entry var pushRoute: PushRouteAction? = nil
    /// The shared session, so pushed pages' shared chrome (the persistent avatar) can
    /// read the selected profile; nil outside the root shell.
    @Entry var festivalSession: FestivalSession? = nil
    /// True inside the macOS shell, which owns one set of global toolbar items (Search,
    /// bell, profile) for the whole window; pages then omit their own copies, since two
    /// columns would otherwise both contribute them to the unified toolbar.
    @Entry var shellOwnsGlobalToolbar = false
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
///
/// Global search is the Search tab (issue #92), so it is no longer a rail item. The
/// separate Search tab leaves the folded rail room for only two items plus "…" with a
/// profile selected (measured 2026-10-04): with Quick Links at `.high` too, the profile
/// moved into "…". So Quick Links keeps the default priority, like Sort and Filter, and
/// the badged bell and the profile identity stay visible (HIG Designing for iPhone Duo:
/// "Set visibility priority by group ... to preserve frequent actions ... and
/// status/badged items"). Horizontal bars show Quick Links regardless.
enum RootChromeRailItem: CaseIterable, Equatable {
    case drawer
    case quickLinks
    case bell
    case profile

    /// True when the system should keep this item visible ahead of same-bar
    /// items with standard priority once the vertical bar runs out of room.
    var staysVisibleAheadOfOthers: Bool {
        switch self {
        case .drawer, .quickLinks: false
        case .bell, .profile: true
        }
    }
}

// MARK: - Trailing glass groups

/// A trailing item in the persistent top bar (issue #92), leading to trailing.
enum RootChromeTrailingItem: Equatable {
    /// A page action (Songs Sort, Filter; Song Detail Item Shop, Paths…).
    case pageAction
    /// The page's Quick Links menu.
    case quickLinks
    /// The notifications bell (a profile is selected).
    case bell
    /// The profile button, always the trailing-most item.
    case profile
}

/// How the persistent top bar's trailing items split into Liquid Glass groups (iOS 26+).
///
/// Issue #92: two groups, page tools (page actions, then Quick Links) and account
/// (Notifications, Profile), separated by a toolbar spacer. HIG Toolbars "Item
/// groupings": "Trailing: important always-available items" and "generally use no more
/// than three groups". SwiftUI merges adjacent bar items into one capsule, so the page
/// tools share one capsule and the bell and profile share the other.
///
/// The iPhone Duo vertical bar gets no fixed spacer: HIG Designing for iPhone Duo, "Group
/// related items with `ToolbarItemGroup`/`UIBarButtonItemGroup`; system spacing adapts,
/// so don't add fixed spacing."
enum RootChromeTrailingGroups {
    /// Whether the account group (bell, profile) is separated from the page tools by a
    /// `ToolbarSpacer(.fixed)`.
    ///
    /// - Parameter chrome: Current section chrome.
    /// - Returns: False only in the system vertical bar.
    static func separatesAccount(chrome: DeviceLayout.SectionChrome) -> Bool {
        !chrome.isVerticalBar
    }

    /// The glass groups the trailing items form, leading to trailing.
    ///
    /// - Parameters:
    ///   - pageActions: Number of page actions (0 when the page has none or they are
    ///     folded into one menu, which then counts as one).
    ///   - showsQuickLinks: The page offers Quick Links.
    ///   - showsBell: The bell shows (a profile is selected and the page allows it).
    ///   - chrome: Current section chrome.
    /// - Returns: One array per glass group, in bar order. Never more than two groups.
    static func resolve(
        pageActions: Int, showsQuickLinks: Bool, showsBell: Bool,
        chrome: DeviceLayout.SectionChrome
    ) -> [[RootChromeTrailingItem]] {
        let tools = Array(repeating: RootChromeTrailingItem.pageAction, count: max(0, pageActions))
            + (showsQuickLinks ? [.quickLinks] : [])
        let account: [RootChromeTrailingItem] = (showsBell ? [.bell] : []) + [.profile]
        guard separatesAccount(chrome: chrome), !tools.isEmpty else {
            return tools.isEmpty ? [account] : [tools + account]
        }
        return [tools, account]
    }
}

#if os(iOS)
@available(iOS 27.0, *)
extension ToolbarContent {
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

/// The account group at the top-right: the notifications bell (a profile is selected),
/// then the profile button, always the trailing-most item (issue #92).
///
/// Pages with their own trailing actions list this **last** inside their `.toolbar`
/// and apply `.festivalProvidesRootTrailingItems()`, so the avatar stays rightmost.
/// Global search is the Search tab, not a bar button.
///
/// In horizontal bars a `ToolbarSpacer(.fixed)` separates this account group from the
/// page tools before it (Sort, Filter, Quick Links), so the bar shows two Liquid Glass
/// groups (``RootChromeTrailingGroups``); the Duo vertical bar relies on system spacing.
///
/// In the iPhone Duo vertical bar both items stay symbol items (see ``RootProfileButton``)
/// and carry `visibilityPriority(.high)` (iOS 27+), so page actions overflow into the
/// system `…` menu before them: the bell carries the unread badge and the profile item
/// is the only visible identity on every root.
struct FestivalRootTrailingItems: ToolbarContent {
    let session: FestivalSession
    var showsNotifications: Bool = true
    @Environment(\.profileButtonAction) private var profileButtonAction
    /// Notification rows open their destination on the current tab (issue #75).
    @Environment(\.pushRoute) private var pushRoute
    @Environment(\.deviceLayout) private var layout
    #if !os(iOS)
    @Environment(\.openGlobalSearch) private var openGlobalSearch
    @Environment(\.shellOwnsGlobalToolbar) private var shellOwnsGlobalToolbar
    #endif

    var body: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            if RootChromeTrailingGroups.separatesAccount(chrome: layout.sectionChrome) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }
        // Bell only with a selected profile (operator, 2026-09-28): notifications are per player.
        if showsNotifications && session.selectedPlayer != nil {
            if #available(iOS 27.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationsButton(session: session, pushRoute: pushRoute)
                }
                .railVisibilityPriority(.bell)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationsButton(session: session, pushRoute: pushRoute)
                }
            }
        }
        if #available(iOS 27.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                RootProfileButton(session: session) { profileButtonAction() }
            }
            .railVisibilityPriority(.profile)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                RootProfileButton(session: session) { profileButtonAction() }
            }
        }
        #else
        if !shellOwnsGlobalToolbar {
            if let openGlobalSearch {
                ToolbarItem(placement: .primaryAction) {
                    GlobalSearchButton { openGlobalSearch() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                RootProfileButton(session: session) { profileButtonAction() }
            }
        }
        #endif
    }
}

// MARK: - Page action placement

extension ToolbarItemPlacement {
    /// Placement for a page's own trailing actions (Filter, Paths, Item Shop, Quick Links…)
    /// on tab roots and pushed pages alike.
    ///
    /// iOS pins `.primaryAction` to the far trailing edge, after every `.topBarTrailing`
    /// item, whatever modifier added it. Page actions therefore use `.topBarTrailing`,
    /// before the shared bell and profile, and the pushed-page account group (bell,
    /// profile) uses `.primaryAction` (``PageTrailingItems``). Its outer modifier would
    /// otherwise lay it out *before* the page's own items, folding it into their glass
    /// group away from the corner (issue #85). Other platforms use `.primaryAction`.
    static var festivalPageAction: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
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

/// Bell badge copy for the unread-notification count (web `HeaderActions.tsx:68`).
enum NotificationBadge {
    /// Largest count shown verbatim; higher counts read "9+" like the web bell.
    static let cap = 9

    /// Badge text for the bell.
    ///
    /// - Parameter unreadCount: Rows in the sheet's "New" section.
    /// - Returns: The count, "9+" above ``cap``, or nil (no badge) when nothing is unread.
    static func text(unreadCount: Int) -> String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > cap ? "\(cap)+" : String(unreadCount)
    }

    /// VoiceOver label for the bell; it carries the exact count, not the capped badge.
    ///
    /// - Parameter unreadCount: Rows in the sheet's "New" section.
    /// - Returns: "Notifications, N unread", or "Notifications" when nothing is unread.
    static func accessibilityLabel(unreadCount: Int) -> String {
        unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications"
    }
}

/// Notifications bell (web `HeaderActions` bell): unread-count badge, opens the native sheet.
///
/// iOS 26+ uses the system toolbar-item badge, so the bar lays it out without clipping
/// (HIG Notifications: "Avoid custom images or components that mimic a badge"). Older
/// iOS has no toolbar badge API, so it falls back to a small numeric capsule.
///
/// Owned by the Notifications feature lane; see `Features/Notifications/NotificationsSheet.swift`.
struct NotificationsButton: View {
    let session: FestivalSession
    /// The root shell's push on the current tab; a tapped row's page opens there after
    /// the sheet closes. Nil outside the shell.
    var pushRoute: PushRouteAction?
    /// Opens a sheet owned by the presenter instead of this button's own (the macOS
    /// shell, whose View menu also opens it); nil presents locally.
    var open: (() -> Void)?
    @State private var presented = false
    private var center: NotificationsCenter { session.notificationsCenter }

    var body: some View {
        let badge = NotificationBadge.text(unreadCount: center.unreadCount)
        Button {
            if let open { open() } else { presented = true }
        } label: {
            Label("Notifications", systemImage: "bell")
        }
        .tint(BrandTokens.textPrimary)
        .modifier(NotificationBadgeModifier(text: badge))
        .accessibilityLabel(NotificationBadge.accessibilityLabel(unreadCount: center.unreadCount))
        // The system badge also publishes its count as the accessibility value, which stays
        // stale after the badge clears; the label alone announces "N unread".
        .accessibilityValue(Text(""))
        .accessibilityIdentifier("fst.shell.notifications")
        .task(id: session.selectionRevision) { await center.refresh(session: session) }
        .sheet(isPresented: $presented) {
            // Closure passed directly, like the profile sheet (environment trap).
            NotificationsSheet(session: session) { route in pushRoute?(route) }
                .festivalSheet(.large)
        }
    }
}

/// Puts the bell's unread count on the system toolbar-item badge (iOS 26+).
///
/// Before iOS 26 SwiftUI ignores `badge` outside lists and tab bars, so a small numeric
/// capsule stands in. Both are hidden from VoiceOver: the bell's label carries the count.
private struct NotificationBadgeModifier: ViewModifier {
    /// Badge text, or nil for no badge.
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.badge(text.map { Text($0) })
        } else {
            content.overlay(alignment: .topTrailing) {
                if let text {
                    Text(text)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(.red))
                        .fixedSize()
                        .offset(x: 8, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Top-right profile action: the selected player's initial, or an add-profile glyph.
///
/// In a system vertical bar (iPhone Duo) the selected player shows as the symbol
/// `person.crop.circle.fill` titled "Profile: <name>" instead of the monogram: a
/// custom-view item cannot go vertical, so the system would keep a horizontal top bar
/// just for it (`.agents/design/apple/duo.md`, B1). Horizontal bars keep the monogram.
///
/// Callers pass `\.profileButtonAction` (``ProfileButtonAction``): with a selected
/// player the button opens their Statistics page, not profile search (issue #290).
struct RootProfileButton: View {
    let session: FestivalSession
    let action: () -> Void
    @Environment(\.deviceLayout) private var layout
    @Environment(\.displayScale) private var displayScale

    /// VoiceOver hint describing where the button goes.
    ///
    /// - Parameter hasPlayer: Whether a player is selected.
    /// - Returns: "Opens your statistics" with a selection, else "Opens profile selection".
    static func accessibilityHint(hasPlayer: Bool) -> String {
        hasPlayer ? "Opens your statistics" : "Opens profile selection"
    }

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
                MonogramLabel(name: name, size: 30, scale: displayScale)
            case let .symbol(title):
                Label(title, systemImage: "person.crop.circle.fill")
            }
        }
        .tint(BrandTokens.textPrimary)
        .accessibilityLabel(session.selectedPlayer.map {
            "Profile: \($0.displayName)"
        } ?? "Choose Profile")
        .accessibilityHint(Self.accessibilityHint(hasPlayer: session.selectedPlayer != nil))
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

// MARK: - Monogram bar item

/// The selected player's monogram as a bar-button label (issue #15).
///
/// A custom view inside a toolbar item is hosted as-is: the system did not enlarge its
/// hit region, so the avatar only answered inside its 36 pt capsule while Search and the
/// bell beside it took taps 20 pt off-centre. Drawn as an image, the item is a standard
/// image bar button with the system hit region (HIG Toolbars: "Prefer standard buttons";
/// HIG Buttons: "the hit region is at least 44x44 pt"). Falls back to the view when the
/// image cannot be rendered and on platforms without UIKit.
struct MonogramLabel: View {
    let name: String
    let size: CGFloat
    let scale: CGFloat

    var body: some View {
        #if canImport(UIKit)
        if let image = MonogramImageCache.shared.image(name: name, size: size, scale: scale) {
            // Titled like the vertical-bar symbol item, for the overflow menu.
            Label {
                Text("Profile: \(name)")
            } icon: {
                Image(uiImage: image).renderingMode(.original)
            }
        } else {
            ProfileAvatar(name: name, size: size)
        }
        #else
        ProfileAvatar(name: name, size: size)
        #endif
    }
}

/// Everything that changes a rendered monogram's pixels.
///
/// The image depends only on the initial (``ProfileAvatar/initial(for:)``), so names
/// sharing an initial share one image and the cache stays tiny.
struct MonogramImageKey: Hashable {
    let initial: String
    let size: CGFloat
    let scale: CGFloat

    /// Create the key for a player.
    ///
    /// - Parameters:
    ///   - name: Player display name.
    ///   - size: Avatar diameter in points.
    ///   - scale: Display scale; values below 1 (an unset environment) render at 1x.
    init(name: String, size: CGFloat, scale: CGFloat) {
        initial = ProfileAvatar.initial(for: name)
        self.size = size
        self.scale = max(scale, 1)
    }
}

#if canImport(UIKit)
/// Rendered monogram images, so a profile switch or toolbar rebuild never re-renders one.
@MainActor
final class MonogramImageCache {
    /// The process-wide cache used by ``MonogramLabel``.
    static let shared = MonogramImageCache()

    private var images: [MonogramImageKey: UIImage] = [:]

    /// The monogram image for `name`, rendering it on first use.
    ///
    /// - Parameters:
    ///   - name: Player display name.
    ///   - size: Avatar diameter in points.
    ///   - scale: Display scale; the image is rendered at this scale.
    /// - Returns: An original-colour image `size` points square, or nil if rendering fails.
    func image(name: String, size: CGFloat, scale: CGFloat) -> UIImage? {
        let key = MonogramImageKey(name: name, size: size, scale: scale)
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content: ProfileAvatar(name: name, size: size))
        renderer.scale = key.scale
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) else { return nil }
        images[key] = image
        return image
    }
}
#endif
