#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Menu bar

/// The iPadOS menu bar. Shell commands use the responder chain; deferred page commands
/// read the key window when the menu opens. Unavailable commands stay listed.
@MainActor
enum UKMenuBar {
    /// Adds the app's menus to the system menu bar.
    ///
    /// - Parameter builder: The menu builder from `UIApplicationDelegate.buildMenu(with:)`.
    static func build(with builder: any UIMenuBuilder) {
        guard builder.system == .main, MenuBarCommandsSupport.isAvailable else { return }
        let show = UIKeyCommand(
            title: "Show Navigation", action: #selector(UKShellCommands.ukShowNavigation), input: "s",
            modifierFlags: [.control, .command]
        )
        let close = UIKeyCommand(
            title: "Close", action: #selector(UKShellCommands.ukCloseOverlay), input: UIKeyCommand.inputEscape
        )
        let refresh = UIKeyCommand(
            title: "Refresh", action: #selector(UKShellCommands.ukRefresh), input: "r", modifierFlags: .command
        )
        builder.insertChild(UIMenu(options: .displayInline, children: [show, close, refresh]), atStartOfMenu: .view)
        if #available(iOS 26, *) {
            builder.insertChild(UIMenu(options: .displayInline, children: [PageMenu.view.deferred]), atEndOfMenu: .view)
        }

        let find = UIKeyCommand(
            title: "Search Festival…", action: #selector(UKShellCommands.ukSearch), input: "f", modifierFlags: .command
        )
        builder.insertChild(UIMenu(options: .displayInline, children: [find]), atEndOfMenu: .edit)

        builder.insertSibling(goMenu(), afterMenu: .view)
        builder.insertSibling(profileMenu(), afterMenu: UIMenu.Identifier("com.festival.menu.go"))
        if #available(iOS 26, *) {
            builder.insertSibling(
                UIMenu(title: "Song", identifier: UIMenu.Identifier("com.festival.menu.song"), children: [PageMenu.song.deferred]),
                beforeMenu: UIMenu.Identifier("com.festival.menu.profile")
            )
        }

        let settings = UICommand(title: "App Settings…", action: #selector(UKShellCommands.ukAppSettings))
        builder.insertChild(UIMenu(options: .displayInline, children: [settings]), atEndOfMenu: .application)

        let site = UICommand(title: "Festival Score Tracker Website", action: #selector(UKShellCommands.ukOpenWebsite))
        let whatsNew = UICommand(title: "What's New", action: #selector(UKShellCommands.ukWhatsNew))
        let licenses = UICommand(title: "Licenses", action: #selector(UKShellCommands.ukLicenses))
        builder.replaceChildren(ofMenu: .help) { _ in [site, whatsNew, licenses] }
    }

    private static func goMenu() -> UIMenu {
        var children: [UIMenuElement] = [
            UIKeyCommand(title: "Back", action: #selector(UKShellCommands.ukGoBack), input: "[", modifierFlags: .command),
        ]
        let destinations = FestivalShellCommands.destinations(sidebar: true, visible: [])
        var digit = 1
        var items: [UIMenuElement] = []
        for destination in destinations {
            let command: UICommand
            if digit <= 9 {
                command = UIKeyCommand(
                    title: destination.title, image: nil, action: #selector(UKShellCommands.ukSelectDestination(_:)),
                    input: String(digit), modifierFlags: .command, propertyList: destination.rawValue
                )
            } else {
                command = UICommand(
                    title: destination.title, image: nil, action: #selector(UKShellCommands.ukSelectDestination(_:)),
                    propertyList: destination.rawValue
                )
            }
            digit += 1
            items.append(command)
        }
        children.append(UIMenu(options: .displayInline, children: items))
        children.append(UIMenu(options: .displayInline, children: [
            UIKeyCommand(title: "Search…", action: #selector(UKShellCommands.ukSearch), input: "k", modifierFlags: .command),
        ]))
        children.append(UIMenu(options: .displayInline, children: [
            UIKeyCommand(
                title: "Next Section", action: #selector(UKShellCommands.ukNextSection), input: UIKeyCommand.inputDownArrow,
                modifierFlags: [.alternate, .command]
            ),
            UIKeyCommand(
                title: "Previous Section", action: #selector(UKShellCommands.ukPreviousSection), input: UIKeyCommand.inputUpArrow,
                modifierFlags: [.alternate, .command]
            ),
        ]))
        return UIMenu(title: "Go", identifier: UIMenu.Identifier("com.festival.menu.go"), children: children)
    }

    private static func profileMenu() -> UIMenu {
        var items: [UIMenuElement] = [
            UIKeyCommand(
                title: "Select Profile…", action: #selector(UKShellCommands.ukChooseProfile), input: "p",
                modifierFlags: [.shift, .command]
            ),
            UICommand(title: "Deselect Profile", action: #selector(UKShellCommands.ukDeselectProfile)),
        ]
        if #available(iOS 26, *) { items.append(PageMenu.profile.deferred) }
        items.append(UICommand(title: "Notifications", action: #selector(UKShellCommands.ukNotifications)))
        return UIMenu(title: "Profile", identifier: UIMenu.Identifier("com.festival.menu.profile"), children: items)
    }

    /// Resolve page tools through the focused window's responder chain.
    @available(iOS 26, *)
    @MainActor
    enum PageMenu: String {
        case view, song, profile

        var deferred: UIDeferredMenuElement {
            .usingFocus(identifier: .init("com.festival.page-menu.\(rawValue)"), shouldCacheItems: false)
        }

        init?(identifier: UIDeferredMenuElement.Identifier) {
            let prefix = "com.festival.page-menu."
            guard identifier.rawValue.hasPrefix(prefix) else { return nil }
            self.init(rawValue: String(identifier.rawValue.dropFirst(prefix.count)))
        }

        func items(_ state: PageToolMenuState) -> [UIMenuElement] {
            switch self {
            case .view: UKPageMenus.view(state)
            case .song: UKPageMenus.song(state)
            case .profile: UKPageMenus.profile(state)
            }
        }
    }
}
#endif
