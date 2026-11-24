#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Actions

/// What the shell's bar buttons do; the shell implements it.
@MainActor
protocol UKChromeActions: AnyObject {
    /// The hamburger button.
    func chromeOpenDrawer()
    /// The bell.
    func chromeOpenNotifications()
    /// The profile avatar (``ProfileButtonAction``).
    func chromePressProfile()
    /// The session whose profile and notifications the bar shows.
    var chromeSession: FestivalSession { get }
    /// The window layout (vertical bar or horizontal bar).
    var chromeLayout: DeviceLayout { get }
    /// The bell and profile share one glass pill (page tools float above the tab bar).
    var chromeInAccountPill: Bool { get }
}

// MARK: - Bar items

/// Builds the shell's bar items: the hamburger button (leading), then the notifications
/// bell and the profile button (trailing, avatar rightmost). The UIKit counterpart of
/// `FestivalRootChrome`, `FestivalRootTrailingItems`, `DrawerButton`,
/// `NotificationsButton` and `RootProfileButton`; identifiers, labels and hints are the
/// SwiftUI ones.
@MainActor
enum UKRootChrome {
    // MARK: Drawer button

    /// The hamburger button that opens the drawer.
    ///
    /// - Parameter actions: The shell.
    /// - Returns: The leading bar item.
    static func drawerItem(actions: any UKChromeActions) -> UIBarButtonItem {
        let image = UIImage(systemName: "line.3.horizontal")
        let action = UIAction(title: "Menu", image: image) { [weak actions] _ in
            actions?.chromeOpenDrawer()
        }
        let item = UIBarButtonItem(image: image, primaryAction: action)
        item.menuRepresentation = action
        item.tintColor = BrandUIColors.textPrimary
        item.accessibilityLabel = "Open Navigation"
        item.accessibilityIdentifier = "fst.shell.drawer.open"
        return item
    }

    // MARK: Account group

    /// The bell (with a selected player) and the profile button, bell first.
    ///
    /// - Parameters:
    ///   - actions: The shell.
    ///   - showsNotifications: Whether the page offers the bell.
    ///   - isRoot: Whether to prioritize the account group over page tools on the vertical rail.
    /// - Returns: The trailing items in bar order (leading to trailing).
    private static func accountItems(
        actions: any UKChromeActions, showsNotifications: Bool, isRoot: Bool
    ) -> [UIBarButtonItem] {
        let session = actions.chromeSession
        let layout = actions.chromeLayout
        var items: [UIBarButtonItem] = []
        if showsNotifications, session.selectedPlayer != nil {
            let bell = bellItem(actions: actions)
            if isRoot { applyRailPriority(.bell, to: bell, chrome: layout.sectionChrome) }
            items.append(bell)
        }
        let profile = profileItem(actions: actions)
        if isRoot { applyRailPriority(.profile, to: profile, chrome: layout.sectionChrome) }
        items.append(profile)
        // `rightBarButtonItems` lays out trailing-most first.
        return items
    }

    /// The notifications bell.
    ///
    /// - Parameter actions: The shell.
    /// - Returns: The bar item with its unread badge.
    static func bellItem(actions: any UKChromeActions) -> UIBarButtonItem {
        let count = actions.chromeSession.notificationsCenter.unreadCount
        let image = UIImage(systemName: "bell")
        let action = UIAction(title: "Notifications", image: image) { [weak actions] _ in
            actions?.chromeOpenNotifications()
        }
        let item = UIBarButtonItem(image: image, primaryAction: action)
        item.menuRepresentation = action
        item.tintColor = BrandUIColors.textPrimary
        item.accessibilityLabel = NotificationBadge.accessibilityLabel(unreadCount: count)
        item.accessibilityValue = ""
        item.accessibilityIdentifier = "fst.shell.notifications"
        let text = NotificationBadge.text(unreadCount: count)
        if #available(iOS 26.0, *) {
            item.badge = text.map { UIBarButtonItem.Badge.string($0) }
        }
        return item
    }

    /// The profile button: the selected player's monogram, the add-profile glyph, or the
    /// titled symbol in a system vertical bar.
    ///
    /// - Parameter actions: The shell.
    /// - Returns: The bar item.
    static func profileItem(actions: any UKChromeActions) -> UIBarButtonItem {
        let session = actions.chromeSession
        let layout = actions.chromeLayout
        let scale = UIScreen.main.scale
        let presentation = RootProfileButton.Presentation.resolve(
            displayName: session.selectedPlayer?.displayName, chrome: layout.sectionChrome
        )
        let action = UIAction { [weak actions] _ in actions?.chromePressProfile() }
        let item: UIBarButtonItem
        switch presentation {
        case .choose:
            action.title = "Choose Profile"
            item = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"), primaryAction: action)
        case let .monogram(name):
            let metrics = RootProfileButton.MonogramMetrics.current(inAccountPill: actions.chromeInAccountPill)
            action.title = "Profile: \(name)"
            item = UIBarButtonItem(
                image: UKMonogram.image(
                    name: name, size: metrics.diameter, scale: scale, outlined: metrics.outlined,
                    overhang: metrics.overhang
                ), primaryAction: action
            )
        case let .symbol(title):
            action.title = title
            item = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle.fill"), primaryAction: action)
        }
        item.tintColor = BrandUIColors.textPrimary
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = {
                if case .monogram = presentation, !actions.chromeInAccountPill { return true }
                return false
            }()
        }
        item.accessibilityLabel = session.selectedPlayer.map { "Profile: \($0.displayName)" } ?? "Choose Profile"
        item.accessibilityHint = RootProfileButton.accessibilityHint(hasPlayer: session.selectedPlayer != nil)
        item.accessibilityIdentifier = "fst.shell.profile"
        item.largeContentSizeImage = UIImage(systemName: "person.crop.circle")
        // Without an explicit menu action, the Duo's More menu names the symbol "account".
        action.image = layout.sectionChrome.isVerticalBar ? item.image : item.largeContentSizeImage
        item.menuRepresentation = action
        return item
    }

    /// Preserves the account items ahead of standard-priority actions on the Duo rail.
    static func applyRailPriority(
        _ role: RootChromeRailItem, to item: UIBarButtonItem, chrome: DeviceLayout.SectionChrome
    ) {
        if #available(iOS 27.0, *), chrome.isVerticalBar, role.staysVisibleAheadOfOthers {
            item.visibilityPriority = .high
        }
    }

    // MARK: Installing

    /// Puts the shell's items on a page's navigation item.
    ///
    /// - Parameters:
    ///   - controller: The page (a section root, or any page that shows the account group).
    ///   - actions: The shell.
    ///   - drawer: Whether the page also gets the hamburger button (section roots).
    ///   - pageItems: The page's own trailing actions, listed before the account group.
    ///   - showsAccount: Whether this bar owns the window's account group.
    ///   - showsNotifications: Whether that group includes the bell.
    static func install(
        on controller: UIViewController, actions: any UKChromeActions, drawer: Bool, pageItems: [UIBarButtonItem] = [],
        showsAccount: Bool = true, showsNotifications: Bool = true
    ) {
        let item = controller.navigationItem
        if drawer {
            let button = drawerItem(actions: actions)
            let layout = actions.chromeLayout
            // UIKit reserves the leading slot before considering trailing priorities.
            if layout.pose == .folded, layout.orientation == .portrait, layout.sectionChrome.isVerticalBar,
               showsAccount, showsNotifications, actions.chromeSession.selectedPlayer != nil {
                item.leftBarButtonItem = nil
                let menu = UIBarButtonItemGroup(barButtonItems: [button], representativeItem: nil)
                menu.menuRepresentation = button.menuRepresentation
                item.centerItemGroups = [menu]
            } else {
                item.centerItemGroups = []
                item.leftBarButtonItem = button
            }
        }
        // Bar order leading→trailing is [page tools][space][bell][profile]; UIKit's
        // `rightBarButtonItems` lists trailing-most first.
        var ordered = pageItems
        if showsAccount {
            if #available(iOS 26.0, *), !pageItems.isEmpty,
               RootChromeTrailingGroups.separatesAccount(chrome: actions.chromeLayout.sectionChrome) {
                ordered.append(.fixedSpace())
            }
            ordered += accountItems(actions: actions, showsNotifications: showsNotifications, isRoot: drawer)
        }
        item.rightBarButtonItems = ordered.reversed()
    }
}
#endif
