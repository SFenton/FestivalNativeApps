#if os(iOS)
import FestivalAppSupport
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Tab bar delegate

extension UKRootViewController: UITabBarControllerDelegate {
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        // A re-tap on the selected section's tab pops it to its root (web tab semantics), and
        // stops there: letting the selection through re-runs `selectSection`, whose second,
        // unanimated pop lands mid-transition and leaves the old page on screen. Compare by
        // section, not object: `selectedTab` need not be the instance passed here.
        if !applyingTabSelection, !searchActive,
           let section = sections.first(where: { "fst.tab.\($0.rawValue)" == tab.identifier }),
           section == selected, tab.identifier == tabBarController.selectedTab?.identifier {
            stacks[section]?.popToRoot(animated: true)
            return false
        }
        return true
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard !applyingTabSelection else { return }
        let next: RootTab
        if selectedTab === searchTabRef {
            next = .search
        } else if let section = sections.first(where: { "fst.tab.\($0.rawValue)" == selectedTab.identifier }) {
            next = .section(section)
        } else {
            return
        }
        applyTransition(RootTabTransition.choose(next, selected: selected, searchActive: searchActive), fromTabBar: true)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard #unavailable(iOS 18.0), !applyingTabSelection else { return }
        let next: RootTab
        if viewController === searchNavigation {
            next = .search
        } else if let stack = viewController as? UKSectionStack {
            next = .section(stack.section)
        } else {
            return
        }
        applyTransition(RootTabTransition.choose(next, selected: selected, searchActive: searchActive), fromTabBar: true)
    }
}

// MARK: - Transitions

extension UKRootViewController {
    /// Carries out a tab, search or sidebar transition (the programmatic entry point).
    ///
    /// - Parameter transition: What changed (``RootTabTransition``).
    func perform(_ transition: RootTabTransition) {
        applyTransition(transition, fromTabBar: false)
    }

    private func applyTransition(_ transition: RootTabTransition, fromTabBar: Bool) {
        switch transition {
        case .none:
            break
        case .openSearch:
            searchActive = true
        case .closeSearch:
            searchActive = false
        case let .select(section):
            searchActive = false
            selectSection(section)
        case let .push(route):
            searchActive = false
            stacks[selected]?.push(route)
        }
        shellState.searchActive = searchActive
        shellState.selectedSection = selected
        syncTabSelection()
        updateFloatingTools()
        updateEdgeSwipe()
        drawerReload()
    }

    /// Changes the root section with web tab semantics.
    ///
    /// - Parameter next: Section chosen by a tab, flyout row or drawer item.
    func selectSection(_ next: FestivalSection) {
        guard stackFor(next) != nil else { return }
        if next == selected {
            stacks[next]?.popToRoot(animated: false)
        } else if FestivalTabPolicy.resetsPathOnLeave(selected) {
            stacks[selected]?.popToRoot(animated: false)
        }
        selected = next
        shellState.selectedSection = next
        publishSplitSelection()
    }

    /// Publishes the active split's exact selection, including in-place replacements.
    func publishSplitSelection() {
        let selection = stacks[selected]?.openDetailRoute
        if shellState.splitSelection != selection { shellState.splitSelection = selection }
    }

    /// The profile button: the selected player's Statistics, or profile search.
    func pressProfileButton() {
        let statisticsVisible = sections.contains(.statistics)
        switch ProfileButtonAction.resolve(
            selectedPlayer: session.selectedPlayer, statisticsVisible: statisticsVisible, selected: selected,
            searchActive: searchActive, topRoute: stacks[selected]?.topRoute
        ) {
        case .chooseProfile: presentProfile()
        case let .navigate(transition): perform(transition)
        }
    }

    /// Go back one page in the selected section (⌘[): the open item first, then the page.
    func goBack() {
        guard let stack = stacks[selected], !searchActive else { return }
        if stack.isDetailOpen, let next = OnDemandSplitPolicy.pathAfterListBack(stack.path, section: selected) {
            stack.setPath(next, animated: true)
        } else {
            stack.pop()
        }
    }

    /// Reacts to a changed selected profile or catalogue-independent session state.
    func sessionChanged() {
        let player = session.selectedPlayer
        _ = player?.accountId
        guard isViewLoaded else { return }
        rebuildSections()
        if player == nil && !FestivalLaunch.keepsProfileRoutes {
            // Profile-only pages disappear without a player (`ProfileRoutePolicy`).
            for stack in stacks.values {
                let resolved = ProfileRoutePolicy.resolve(stack.path, hasPlayer: false)
                if resolved != stack.path { stack.setPath(resolved, animated: false) }
            }
        }
        drawerReload()
    }

    /// Settings changes (Hide Item Shop, instrument toggles) that change the section set.
    @objc func settingsChanged() {
        rebuildSections()
        if UKSettings.bool("fst.settings.hideShop", default: false) {
            for (section, stack) in stacks {
                guard let index = stack.path.firstIndex(of: .shop) else { continue }
                stack.setPath(Array(stack.path.prefix(index)), animated: false)
                if section == .songs, let songs = stack.root as? UKSongsViewController {
                    songs.showNavigationNotice(ShopScreen.hiddenNavigationNotice)
                }
            }
        }
    }

    /// Opens the content an "Open in New Window" request carried (a song needs the catalogue).
    func applyWindowRoute() async {
        guard !windowRouteApplied, case let .song(songId)? = windowRoute else { return }
        windowRouteApplied = true
        guard let payload = try? await session.catalog(),
              let song = payload.catalog.songs.first(where: { $0.songId == songId }) else { return }
        stacks[.songs]?.setPath([.songDetail(song)], animated: false)
        if selected != .songs { perform(.select(.songs)) }
    }
}

// MARK: - UKNavigating

extension UKRootViewController: UKNavigating {
    func push(_ route: AppRoute) {
        if searchActive { searchActive = false; syncTabSelection() }
        stacks[selected]?.push(route)
    }

    func pop() { stacks[selected]?.pop() }

    func replaceTop(with route: AppRoute) { stacks[selected]?.replaceTop(with: route) }

    func select(_ section: FestivalSection) {
        perform(RootTabTransition.choose(.section(section), selected: selected, searchActive: searchActive))
    }

    func openDrawer() { openDrawer(animated: true) }

    func presentProfile() {
        let stack = stacks[selected]
        let sheet = UKProfileSelection.make(session: session, layout: { [weak self] in self?.layout ?? .standardPhone }) {
            [weak stack] route in
            guard let stack else { return }
            stack.setPath(stack.path + [route], animated: false)
        }
        presentSheet(sheet, detents: nil)
    }

    func selectDetail(_ route: AppRoute) { stacks[selected]?.select(route) }

    @discardableResult func closeDetail() -> Bool { stacks[selected]?.closeDetail() ?? false }

    func openSearch() { perform(.openSearch) }

    func presentNotifications() { presentNotifications(revealsRouteWithDismissal: false) }

    /// Opens the shell's Notifications modal.
    ///
    /// - Parameter revealsRouteWithDismissal: True for the standalone bell, which reveals the destination
    ///   as it closes. The horizontal account pill and menu commands push after dismissal.
    func presentNotifications(revealsRouteWithDismissal: Bool) {
        let stack = stacks[selected]
        let page = UKShellSheets.notifications(session) { [weak stack] route, sheet in
            guard let stack, let presenter = sheet.presentingViewController, !sheet.isBeingDismissed else { return }
            if revealsRouteWithDismissal {
                stack.setPath(stack.path + [route], animated: false)
                presenter.dismiss(animated: true)
            } else {
                presenter.dismiss(animated: true) { [weak stack] in stack?.push(route) }
            }
        }
        presentSheet(page, detents: [.large()])
    }

    /// Presents a sheet over the window.
    ///
    /// - Parameters:
    ///   - controller: The sheet's root.
    ///   - detents: Sheet detents; nil is the large sheet (`festivalSheet()`).
    func presentSheet(_ controller: UIViewController, detents: [UISheetPresentationController.Detent]?) {
        let top = presentedViewController ?? self
        if top is UIAlertController { return }
        let navigation = controller as? UINavigationController ?? UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        navigation.overrideUserInterfaceStyle = .dark
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = detents ?? [.large()]
            sheet.prefersGrabberVisible = false
        }
        shellState.drawerPresented = shellState.drawerPresented
        top.present(navigation, animated: true)
    }
}

// MARK: - Section stack host

extension UKRootViewController: UKSectionStackHost {
    var stackLayout: DeviceLayout { layout }

    func stackMakeScreen(_ route: AppRoute, section: FestivalSection) -> UIViewController {
        let screen = UKRouteDestination.make(route, context: context(for: section))
        return screen
    }

    func stackWillShow(_ controller: UIViewController, in stack: UKSectionStack, navigation: UINavigationController) {
        let isRoot = controller === stack.leading.viewControllers.first && navigation === stack.leading
        if isRoot, controller.ukRoute == nil {
            installRootChrome(on: controller)
        }
        if stack.section == selected { updateEdgeSwipe() }
    }

    func stackDidChangePath(_ stack: UKSectionStack) {
        if stack.section == selected {
            publishSplitSelection()
            updateEdgeSwipe()
            drawerReload()
        }
        refreshChrome()
    }
}

// MARK: - Navigation controller delegate (flyout Search page)

extension UKRootViewController: UINavigationControllerDelegate {}
#endif
