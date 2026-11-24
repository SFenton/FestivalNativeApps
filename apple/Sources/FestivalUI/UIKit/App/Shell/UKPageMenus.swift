#if os(iOS)
import FestivalCore
import UIKit

/// The commands offered by the front page, independent of where its toolbar is placed.
@MainActor
protocol UKPageMenuProviding: UIViewController {
    /// Contributes the current page's commands to the window's menu state.
    func populatePageMenu(_ state: inout PageToolMenuState)
}

/// Native iPad page menus. The Debug mirror renders these same menu elements and actions
/// because the system menu bar isn't exposed to XCUITest.
@MainActor
enum UKPageMenus {
    /// Builds the page commands for View, in toolbar order.
    static func view(_ state: PageToolMenuState) -> [UIMenuElement] {
        [
            action("Sort…", blocked: state.blocked, perform: state.page?.sort),
            action("Filter…", blocked: state.blocked, perform: state.page?.filter),
            choices("Rank By", PageToolChoiceItems.rankBy(state), blocked: state.blocked),
            choices("Instrument", PageToolChoiceItems.instrument(state), blocked: state.blocked),
            choices("Band Size", PageToolChoiceItems.bandSize(state), blocked: state.blocked),
            UIMenu(options: .displayInline, children: layout(state)),
        ]
    }

    /// Builds the page commands for Profile.
    static func profile(_ state: PageToolMenuState) -> [UIMenuElement] {
        [
            action(ProfilePageMenuCommands.identityMenuTitle(for: state.profile?.identity),
                   blocked: state.blocked, perform: state.profile?.performIdentity),
            action("View Rival's Profile", blocked: state.blocked, perform: state.profile?.viewRivalProfile),
            action("Find Rival…", blocked: state.blocked, perform: state.page?.findRival),
        ]
    }

    /// Builds the Song menu, disabled when the front page is not Song Detail.
    static func song(_ state: PageToolMenuState) -> [UIMenuElement] {
        var shop: (@MainActor () -> Void)?
        if let url = state.song?.shopURL { shop = { UIApplication.shared.open(url) } }
        return [
            action("Paths…", blocked: state.blocked, perform: state.song?.paths),
            action("Open in Item Shop", blocked: state.blocked, perform: shop),
        ]
    }

    private static func layout(_ state: PageToolMenuState) -> [UIAction] {
        let layout = state.page?.layout
        return [false, true].map { grid in
            action(grid ? "as Grid" : "as List", blocked: state.blocked, checked: layout?.isGrid == grid,
                   perform: layout.map { choice in { choice.select(grid) } })
        }
    }

    private static func choices(_ title: String, _ items: PageToolChoiceItems, blocked: Bool) -> UIMenu {
        let actions = items.choices.map { choice -> UIAction in
            var perform: (@MainActor () -> Void)?
            if let select = items.select { perform = { select(choice.id) } }
            return action(choice.label, blocked: blocked, checked: items.selected == choice.id, perform: perform)
        }
        return UIMenu(title: title, options: .singleSelection, children: actions)
    }

    private static func action(
        _ title: String, blocked: Bool, checked: Bool = false, perform: (@MainActor () -> Void)?
    ) -> UIAction {
        UIAction(
            title: title, identifier: UIAction.Identifier("com.festival.page-menu.\(title)"),
            attributes: blocked || perform == nil ? .disabled : [], state: checked ? .on : .off
        ) { _ in perform?() }
    }
}

extension UKRootViewController {
    /// Resolves commands from this window's frontmost pane, never from a cached page.
    var pageMenuState: PageToolMenuState {
        var state = PageToolMenuState(
            experimentalRanks: UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue),
            blocked: sheetOpen || frontPage?.presentedViewController != nil
        )
        (frontPage as? UKPageMenuProviding)?.populatePageMenu(&state)
        return state
    }
}

#if DEBUG
/// A Debug-only, accessible readout of the View and Profile menu commands.
@MainActor
final class UKPageMenuMirror: UIStackView {
    private var signature: [String] = []
    private var page: ObjectIdentifier?

    /// Updates the visible items when navigation, availability or checkmarks change.
    func update(_ root: UKRootViewController) {
        let state = root.pageMenuState
        let view = UKPageMenus.view(state)
        let profile = UKPageMenus.profile(state)
        let bandSize = view.compactMap { $0 as? UIMenu }.first { $0.title == "Band Size" }
        let elements = view.flatMap { element -> [UIMenuElement] in
            if let menu = element as? UIMenu, menu.options.contains(.displayInline) { return menu.children }
            return [element]
        } + (bandSize?.children ?? []) + profile
        let next = elements.map {
            let action = $0 as? UIAction
            return "\($0.title)|\(action?.attributes.rawValue ?? 0)|\(action?.state.rawValue ?? 0)"
        }
        let frontPage = root.frontPage.map(ObjectIdentifier.init)
        guard next != signature || page != frontPage else { return }
        signature = next
        page = frontPage
        for row in arrangedSubviews { row.removeFromSuperview() }
        for element in elements {
            let action = element as? UIAction
            let button = UIButton(type: .system, primaryAction: action)
            button.setTitle(element.title, for: .normal)
            button.accessibilityLabel = element.title
            button.isEnabled = action?.attributes.contains(.disabled) != true
            if ["as List", "as Grid", "Duos", "Trios", "Quads"].contains(element.title) {
                button.accessibilityValue = action?.state == .on ? "1" : "0"
            }
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            addArrangedSubview(button)
        }
    }

    /// Installs the Debug readout over this window, leaving normal launches untouched.
    static func install(on root: UKRootViewController) -> UKPageMenuMirror? {
        guard ProcessInfo.processInfo.environment["FST_DEBUG_MENU_BAR"] == "1",
              MenuBarCommandsSupport.isAvailable else { return nil }
        let mirror = UKPageMenuMirror()
        mirror.axis = .vertical
        mirror.backgroundColor = .secondarySystemBackground
        mirror.accessibilityIdentifier = "fst.menu-bar-mirror"
        mirror.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(mirror)
        let safe = root.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            mirror.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            mirror.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            mirror.widthAnchor.constraint(equalToConstant: 200),
        ])
        return mirror
    }
}
#endif
#endif
