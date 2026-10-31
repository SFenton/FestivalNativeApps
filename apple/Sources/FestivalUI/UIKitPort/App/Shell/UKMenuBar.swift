#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Menu bar

/// The iPadOS menu bar: the UIKit counterpart of ``FestivalCommands``, built in the app
/// delegate's `buildMenu(with:)`. Items send ``UKShellCommands`` selectors down the
/// responder chain to the front window's ``UKRootViewController``, which enables or disables
/// them (HIG The menu bar: disable, don't hide). iPhone has no menu bar: its shortcuts are
/// the root's `keyCommands`.
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

        let find = UIKeyCommand(
            title: "Search Festival…", action: #selector(UKShellCommands.ukSearch), input: "f", modifierFlags: .command
        )
        builder.insertChild(UIMenu(options: .displayInline, children: [find]), atEndOfMenu: .edit)

        builder.insertSibling(goMenu(), afterMenu: .view)
        builder.insertSibling(profileMenu(), afterMenu: UIMenu.Identifier("com.festival.menu.go"))

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
        UIMenu(title: "Profile", identifier: UIMenu.Identifier("com.festival.menu.profile"), children: [
            UIKeyCommand(
                title: "Select Profile…", action: #selector(UKShellCommands.ukChooseProfile), input: "p",
                modifierFlags: [.shift, .command]
            ),
            UICommand(title: "Deselect Profile", action: #selector(UKShellCommands.ukDeselectProfile)),
            UICommand(title: "Notifications", action: #selector(UKShellCommands.ukNotifications)),
        ])
    }
}
#endif
