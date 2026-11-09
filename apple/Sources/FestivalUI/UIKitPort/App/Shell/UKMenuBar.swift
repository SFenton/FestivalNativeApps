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
        builder.insertChild(pageToolsMenu(), atEndOfMenu: .view)
        builder.insertSibling(profilePageMenu(), afterMenu: UIMenu.Identifier("com.festival.menu.go"))

        let site = UICommand(title: "Festival Score Tracker Website", action: #selector(UKShellCommands.ukOpenWebsite))
        let whatsNew = UICommand(title: "What's New", action: #selector(UKShellCommands.ukWhatsNew))
        let licenses = UICommand(title: "Licenses", action: #selector(UKShellCommands.ukLicenses))
        builder.replaceChildren(ofMenu: .help) { _ in [site, whatsNew, licenses] }
    }

    private static func pageToolsMenu() -> UIMenu {
        let commands = frontPageCommands()
        let viewChildren: [UIMenuElement] = [
            command("Sort…", id: "sort", commands: commands),
            command("Filter…", id: "filter", commands: commands),
            submenu("Rank By", id: "rankBy", commands: commands, fallback: [
                ("Total Score", "rank.total"), ("Average Score", "rank.average")
            ]),
            submenu("Instrument", id: "instrument", commands: commands, fallback: [
                ("Vocals", "instrument.vocals"), ("Guitar", "instrument.guitar"),
                ("Bass", "instrument.bass"), ("Drums", "instrument.drums")
            ]),
            submenu("Band Size", id: "bandSize", commands: commands, fallback: BandType.allCases.map {
                ($0.label, "bandSize.\($0.rawValue)")
            }),
            command("as List", id: "asList", commands: commands),
            command("as Grid", id: "asGrid", commands: commands),
        ]
        return UIMenu(
            title: "Page Tools", identifier: UIMenu.Identifier("com.festival.menu.page-tools"),
            options: .displayInline, children: viewChildren
        )
    }

    private static func profilePageMenu() -> UIMenu {
        let commands = frontPageCommands()
        return UIMenu(title: "Profile", identifier: UIMenu.Identifier("com.festival.menu.page-profile"), children: [
            command("Select This Profile", id: "profile.identity", commands: commands),
            command("View Rival's Profile", id: "profile.rival", commands: commands),
            command("Find Rival…", id: "findRival", commands: commands),
        ])
    }

    private static func frontPageCommands() -> [String: UKPageMenuCommand] {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }),
              let root = window.rootViewController as? UKRootViewController,
              let page = root.frontPage as? UKPageToolsProviding else { return [:] }
        return flatten(page.ukPageMenuCommands)
    }

    private static func flatten(_ commands: [UKPageMenuCommand]) -> [String: UKPageMenuCommand] {
        var result: [String: UKPageMenuCommand] = [:]
        for command in commands {
            result[command.identifier] = command
            for child in flatten(command.children) { result[child.key] = child.value }
        }
        return result
    }

    private static func command(
        _ title: String, id: String, commands: [String: UKPageMenuCommand]
    ) -> UICommand {
        let source = commands[id]
        let result = UICommand(
            title: source?.title ?? title, action: #selector(UKShellCommands.ukPageMenuCommand(_:)),
            propertyList: id
        )
        result.state = source?.state ?? .off
        result.attributes = source?.isEnabled == true ? [] : .disabled
        return result
    }

    private static func submenu(
        _ title: String, id: String, commands: [String: UKPageMenuCommand],
        fallback: [(String, String)]
    ) -> UIMenu {
        let source = commands[id]
        let choices = source?.children.map { ($0.title, $0.identifier) } ?? fallback
        return UIMenu(
            title: title, identifier: UIMenu.Identifier("com.festival.menu.\(id)"),
            children: choices.map { command($0.0, id: $0.1, commands: commands) }
        )
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
