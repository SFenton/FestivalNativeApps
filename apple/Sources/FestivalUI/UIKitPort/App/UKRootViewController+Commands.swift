#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Menu-bar and keyboard commands

/// The window's commands, sent through the responder chain from the iPadOS menu bar
/// (``UKMenuBar``) and from the hardware-keyboard shortcuts: the UIKit counterpart of
/// ``FestivalShellCommands`` and ``FestivalCommands``.
@MainActor
@objc protocol UKShellCommands {
    func ukSearch()
    func ukGoBack()
    func ukRefresh()
    func ukSelectDestination(_ sender: Any?)
    func ukChooseProfile()
    func ukDeselectProfile()
    func ukNotifications()
    func ukWhatsNew()
    func ukLicenses()
    func ukShowNavigation()
    func ukCloseOverlay()
    func ukAppSettings()
    func ukNextSection()
    func ukPreviousSection()
    func ukOpenWebsite()
    func ukPageMenuCommand(_ sender: Any?)
}

extension UKRootViewController: UKShellCommands {
    /// Whether a root sheet covers the window (menu commands must not stack another).
    var sheetOpen: Bool { presentedViewController != nil || drawer != nil }

    @objc func ukSearch() { openSearch() }
    @objc func ukGoBack() { goBack() }

    @objc func ukRefresh() {
        guard let action = UKRefreshCommands.shared.latest else { return }
        Task { @MainActor in await action() }
    }

    @objc func ukSelectDestination(_ sender: Any?) {
        guard let command = sender as? UICommand, let raw = command.propertyList as? String,
              let section = FestivalSection(rawValue: raw) else { return }
        select(section)
    }

    @objc func ukChooseProfile() { presentProfile() }
    @objc func ukDeselectProfile() { session.deselectPlayer() }
    @objc func ukNotifications() { presentNotifications() }
    @objc func ukWhatsNew() { presentSheet(UKShellSheets.whatsNew(session), detents: nil) }
    @objc func ukLicenses() { perform(.push(.licenses)) }
    @objc func ukShowNavigation() { if presentation.navigation == .flyout { openDrawer() } }
    @objc func ukAppSettings() { select(.settings) }

    @objc func ukCloseOverlay() {
        if sheetOpen, drawer != nil { dismissDrawer(); return }
        if !searchActive { closeDetail() }
    }

    @objc func ukOpenWebsite() {
        if let url = URL(string: "https://festivalscoretracker.com") { UIApplication.shared.open(url) }
    }

    @objc func ukNextSection() { jumpQuickLink(offset: 1) }
    @objc func ukPreviousSection() { jumpQuickLink(offset: -1) }

    /// Performs a page command published by the front top page.
    @objc func ukPageMenuCommand(_ sender: Any?) {
        guard let command = sender as? UICommand,
              let identifier = command.propertyList as? String,
              let page = frontPage as? UKPageToolsProviding,
              !sheetOpen else { return }
#if DEBUG
        debugLastMenuDispatch = "\(identifier):\(String(describing: type(of: page)))"
        if ProcessInfo.processInfo.environment["FST_DEBUG_MENU_TRACE"] == "1" {
            print("[FST_MENU_TRACE] dispatch id=\(identifier) page=\(String(describing: type(of: page)))")
        }
#endif
        findPageMenuCommand(identifier, in: page.ukPageMenuCommands)?.perform?()
    }

    private func jumpQuickLink(offset: Int) {
        guard let controller = UKQuickLinksRegistry.shared.front else { return }
        let ids = controller.sections.map(\.id)
        if let target = MacQuickLinksCommand.neighbor(of: controller.activeID, in: ids, offset: offset) {
            controller.jump(to: target)
        }
    }

    // MARK: Validation

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(ukSearch), #selector(ukRefresh), #selector(ukSelectDestination(_:)), #selector(ukAppSettings),
             #selector(ukWhatsNew), #selector(ukLicenses), #selector(ukChooseProfile):
            return !sheetOpen
        case #selector(ukGoBack):
            return !sheetOpen && !searchActive && !(stacks[selected]?.path.isEmpty ?? true)
        case #selector(ukDeselectProfile), #selector(ukNotifications):
            return !sheetOpen && session.selectedPlayer != nil
        case #selector(ukShowNavigation):
            return !sheetOpen && presentation.navigation == .flyout
        case #selector(ukCloseOverlay):
            return drawer != nil || (!sheetOpen && splitOpenSections.contains(selected) && !searchActive)
        case #selector(ukNextSection), #selector(ukPreviousSection):
            return !sheetOpen && (UKQuickLinksRegistry.shared.front?.isAvailable ?? false)
        case #selector(ukPageMenuCommand(_:)):
            guard !sheetOpen, let command = sender as? UICommand,
                  let identifier = command.propertyList as? String,
                  let page = frontPage as? UKPageToolsProviding else { return false }
            return findPageMenuCommand(identifier, in: page.ukPageMenuCommands)?.isEnabled == true
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        if command.action == #selector(ukSelectDestination(_:)),
           let raw = command.propertyList as? String, let section = FestivalSection(rawValue: raw) {
            command.attributes = sheetOpen || !sections.contains(section) ? .disabled : []
        }
        if command.action == #selector(ukPageMenuCommand(_:)),
           let identifier = command.propertyList as? String,
           let page = frontPage as? UKPageToolsProviding,
           let source = findPageMenuCommand(identifier, in: page.ukPageMenuCommands) {
           command.attributes = sheetOpen || !source.isEnabled ? .disabled : []
           command.state = source.state
        } else if command.action == #selector(ukPageMenuCommand(_:)) {
            command.attributes = .disabled
        }
    }

    // MARK: Hardware keyboard (phones; the iPad menu bar carries these instead)

    override var keyCommands: [UIKeyCommand]? {
        guard !MenuBarCommandsSupport.isAvailable else { return [] }
        var commands: [UIKeyCommand] = [
            Self.command("Search", "f", #selector(ukSearch)),
            Self.command("Search", "k", #selector(ukSearch)),
            Self.command("Back", "[", #selector(ukGoBack)),
            Self.command("Refresh", "r", #selector(ukRefresh)),
        ]
        for (index, section) in sections.prefix(9).enumerated() {
            commands.append(UIKeyCommand(
                title: section.title, image: nil, action: #selector(ukSelectDestination(_:)), input: String(index + 1),
                modifierFlags: .command, propertyList: section.rawValue
            ))
        }
        return commands
    }

    private static func command(_ title: String, _ key: String, _ action: Selector) -> UIKeyCommand {
        UIKeyCommand(title: title, action: action, input: key, modifierFlags: .command)
    }

    private func findPageMenuCommand(
        _ identifier: String, in commands: [UKPageMenuCommand]
    ) -> UKPageMenuCommand? {
        for command in commands {
            if command.identifier == identifier { return command }
            if let match = findPageMenuCommand(identifier, in: command.children) { return match }
        }
        return nil
    }
}

// MARK: - Refresh commands

/// The pull-to-refresh actions of the pages on screen, so ⌘R can run the frontmost page's
/// refresh: the UIKit counterpart of ``RefreshCommandRegistry``. A refreshable page
/// registers its action in `viewDidAppear` and unregisters in `viewDidDisappear`.
@MainActor
final class UKRefreshCommands {
    /// The window-wide registry.
    static let shared = UKRefreshCommands()

    private var entries: [(owner: ObjectIdentifier, action: @MainActor () async -> Void)] = []

    /// Records (or moves to the front) a page's refresh.
    ///
    /// - Parameters:
    ///   - owner: The registering page.
    ///   - action: Its refresh.
    func register(_ owner: AnyObject, action: @escaping @MainActor () async -> Void) {
        let id = ObjectIdentifier(owner)
        entries.removeAll { $0.owner == id }
        entries.append((id, action))
    }

    /// Forgets a page that left the screen.
    ///
    /// - Parameter owner: The registering page.
    func unregister(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        entries.removeAll { $0.owner == id }
    }

    /// The most recently shown page's refresh.
    var latest: (@MainActor () async -> Void)? { entries.last?.action }
}
#endif
