#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Chrome actions

extension UKRootViewController: UKChromeActions {
    func chromeOpenDrawer() { openDrawer() }
    func chromeOpenNotifications() { presentNotifications(revealsRouteWithDismissal: !floatsPageTools) }
    func chromePressProfile() { pressProfileButton() }
    var chromeSession: FestivalSession { session }
    var chromeLayout: DeviceLayout { layout }
    /// The bell and profile share one glass pill where page tools float above the iPhone
    /// tab bar (issue #632).
    var chromeInAccountPill: Bool { floatsPageTools }
}

// MARK: - Installing and refreshing

nonisolated(unsafe) private var accountOnlyKey: UInt8 = 0
nonisolated(unsafe) private var pinnedRailItemsKey: UInt8 = 0

extension UKRootViewController {
    /// Whether page tools float above the tab bar in this window.
    var floatsPageTools: Bool {
        UKFloatingPageToolsView.floats(in: layout, flyout: presentation.navigation == .flyout)
    }

    /// The page on top of the selected section's frontmost pane.
    var frontPage: UIViewController? {
        guard !searchActive, let stack = stacks[selected] else { return nil }
        if stack.isDetailOpen, let top = stack.trailing?.topViewController { return top }
        return stack.leading.topViewController
    }

    /// The tools a page offers, in row order.
    func tools(of page: UIViewController?) -> [UKPageTool] {
        ((page as? UKPageToolsProviding)?.ukPageTools ?? []).sorted { $0.order < $1.order }
    }

    private func barTools(of page: UIViewController) -> [UIBarButtonItem] {
        let provider = page as? UKPageToolsProviding
        let floating = floatsPageTools && !(provider?.ukToolsStayInBar ?? false)
        let pinned = provider?.ukPinnedBarItems ?? []
        let vertical = layout.sectionChrome.isVerticalBar
        placeLeadingRailItems(vertical ? pinned : [], on: page)
        return (vertical ? [] : pinned) + (floating ? [] : tools(of: page).map(\.item))
    }

    /// Rail actions supplement native Back or follow an explicit split Back/Close.
    private func placeLeadingRailItems(_ items: [UIBarButtonItem], on page: UIViewController) {
        let bar = page.navigationItem
        let previous = objc_getAssociatedObject(bar, &pinnedRailItemsKey) as? [UIBarButtonItem] ?? []
        guard !items.isEmpty || !previous.isEmpty else { return }
        let leading = (bar.leftBarButtonItems ?? []).filter { item in !previous.contains { $0 === item } }
        if leading.isEmpty { bar.leftItemsSupplementBackButton = !items.isEmpty }
        bar.leftBarButtonItems = leading + items
        objc_setAssociatedObject(bar, &pinnedRailItemsKey, items.isEmpty ? nil : items, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Floats the front page's tools above the tab bar, or clears the row.
    func updateFloatingTools() {
        guard isViewLoaded else { return }
        #if DEBUG
        if let mirror = pageMenuMirror {
            if drawer == nil { view.bringSubviewToFront(mirror) }
            mirror.update(self)
        }
        #endif
        placeFloatingToolsInSelectedStack()
        let floats = floatsPageTools
        let page = frontPage
        let tools = floats && !((page as? UKPageToolsProviding)?.ukToolsStayInBar ?? false) ? tools(of: page) : []
        let covered = searchActive || presentedViewController != nil || drawer != nil
        floatingTools.update(tools: tools, scope: page, covered: covered)
        floatingTools.isHidden = !floats || tools.isEmpty
        // Each page with tools reserves the row, so its last row scrolls clear (issue #678).
        for (section, stack) in stacks {
            let reserve: CGFloat = floats && section == selected && !tools.isEmpty ? FloatingPageToolsFit.reservedHeight : 0
            if stack.additionalSafeAreaInsets.bottom != reserve { stack.additionalSafeAreaInsets.bottom = reserve }
        }
    }

    /// Keeps the floating tools in the active tab's content, before the system tab bar
    /// in accessibility order. UIKit can temporarily detach the tab during an identity
    /// change, so the constraints must live with the tool's host, not span to the shell.
    func placeFloatingToolsInSelectedStack() {
        let root: UIView = view
        let stack = floatsPageTools && !searchActive ? stacks[selected]?.viewIfLoaded : nil
        let host = stack.flatMap { $0.isDescendant(of: root) ? $0 : nil } ?? root
        guard floatingTools.superview !== host else { return }
        NSLayoutConstraint.deactivate(floatingConstraints)
        host.addSubview(floatingTools)
        let bottom = floatingTools.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        floatingBottom = bottom
        floatingConstraints = [
            floatingTools.trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -FloatingPageToolsFit.margin),
            floatingTools.leadingAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.leadingAnchor, constant: FloatingPageToolsFit.margin),
            bottom,
        ]
        positionFloatingTools()
        NSLayoutConstraint.activate(floatingConstraints)
    }

    /// Keeps the row above the tab bar, which is measured expanded so the buttons stay put
    /// while scrolling minimizes the bar.
    func positionFloatingTools() {
        guard let host = floatingTools.superview else { return }
        let bar = max(tabs.tabBar.frame.height, 0)
        let inset = tabs.selectedViewController?.view.safeAreaInsets.bottom ?? 0
        expandedBarInset = max(expandedBarInset, inset - (stacks[selected]?.additionalSafeAreaInsets.bottom ?? 0))
        let height = max(bar, expandedBarInset)
        let y = view.bounds.maxY - max(height, view.safeAreaInsets.bottom)
        let constant = view.convert(CGPoint(x: view.bounds.midX, y: y), to: host).y - host.bounds.maxY
        if floatingBottom?.constant != constant { floatingBottom?.constant = constant }
    }

    /// The drawer button, page tools and account group on a section root.
    ///
    /// - Parameter controller: The section root screen.
    func installRootChrome(on controller: UIViewController) {
        let provider = controller as? UKPageToolsProviding
        UKRootChrome.install(
            on: controller, actions: self, drawer: true,
            pageItems: barTools(of: controller),
            showsNotifications: provider?.ukShowsNotifications ?? true
        )
        chromeControllers.add(controller)
    }

    /// The account group (and the page's tools) on a pushed page.
    ///
    /// - Parameter controller: The page.
    func installAccountChrome(on controller: UIViewController) {
        let provider = controller as? UKPageToolsProviding
        let showsAccount = controller.ukSplitPane != .trailing || controller.ukSectionStack?.showsAccountInTrailingPane == true
        UKRootChrome.install(
            on: controller, actions: self, drawer: false,
            pageItems: barTools(of: controller),
            showsAccount: showsAccount,
            showsNotifications: provider?.ukShowsNotifications ?? true
        )
        objc_setAssociatedObject(controller, &accountOnlyKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        chromeControllers.add(controller)
    }

    /// Rebuilds every installed bar (a profile change, a fold, a new unread count).
    func refreshChrome() {
        for controller in chromeControllers.allObjects {
            if objc_getAssociatedObject(controller, &accountOnlyKey) as? Bool == true {
                installAccountChrome(on: controller)
            } else if controller === searchController, !tabsSearchAsTab {
                UKRootChrome.install(on: controller, actions: self, drawer: true)
            } else {
                installRootChrome(on: controller)
            }
        }
        updateFloatingTools()
    }

    /// Observation hook: re-installs the bars when the player, avatar or unread count change.
    func refreshChromeFromState() {
        _ = session.selectedPlayer?.displayName
        _ = session.notificationsCenter.unreadCount
        guard isViewLoaded else { return }
        refreshChrome()
    }

    /// The bell's refresh (`NotificationsButton`): the unread count follows the selection.
    func refreshNotifications() {
        _ = session.selectionRevision
        let enabled = UserDefaults.standard.object(forKey: ExperimentalRanks.storageKey) as? Bool
            ?? ExperimentalRanks.defaultValue
        let center = session.notificationsCenter
        let session = session
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            center.setExperimentalRanks(enabled)
            await center.refresh(session: session)
        }
    }

    // MARK: Drawer

    /// Opens the drawer (iPhone) or flyout (iPad regular width, Duo).
    ///
    /// - Parameter animated: Whether the open sequence runs.
    func openDrawer(animated: Bool) {
        if let closing = drawer {
            // Tapped again while it slides shut: reverse the close, as SwiftUI's drawer does.
            guard closing.isClosing else { return }
            closing.reopen()
            shellState.drawerPresented = true
            tabs.view.accessibilityElementsHidden = true
            edgeSwipe?.isEnabled = false
            return
        }
        let flyout = presentation.navigation == .flyout
        let reduce = UIAccessibility.isReduceMotionEnabled || UKSettings.bool("fst.accessibility.reduceMotion", default: false)
        let panel = UKDrawerViewController(
            session: session, layout: { [weak self] in self?.layout ?? .standardPhone }, visibleSections: sections,
            hideShop: UKSettings.bool("fst.settings.hideShop", default: false), selected: selected,
            topRoute: stacks[selected]?.topRoute, showsSearch: flyout, searchActive: searchActive,
            closesOnEscape: flyout || layout.pose != .standard,
            footerScrolls: flyout || layout.pose != .standard, slides: !reduce,
            onIntent: { [weak self] intent in self?.handleDrawer(intent) },
            onClose: { [weak self] in self?.dismissDrawer() },
            onDismissed: { [weak self] in self?.drawerDismissed() }
        )
        addChild(panel)
        panel.view.frame = view.bounds
        panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(panel.view)
        panel.didMove(toParent: self)
        drawer = panel
        shellState.drawerPresented = true
        // The page behind the open drawer leaves the accessibility tree.
        tabs.view.accessibilityElementsHidden = true
        updateFloatingTools()
        edgeSwipe?.isEnabled = false
        if animated { panel.animateIn() } else { panel.skipToOpen() }
    }

    /// Closes the drawer without choosing a destination (Close, scrim, Escape, VoiceOver
    /// escape): focus returns to the button that opened it.
    func dismissDrawer() {
        guard let panel = drawer else { return }
        panel.animateOut()
        shellState.drawerPresented = false
        tabs.view.accessibilityElementsHidden = false
    }

    private func drawerDismissed() {
        guard let panel = drawer else { return }
        panel.willMove(toParent: nil)
        panel.view.removeFromSuperview()
        panel.removeFromParent()
        drawer = nil
        updateFloatingTools()
        updateEdgeSwipe()
        accessoryFocusToken += 1
        let request = AccessibilityFocusRequest(
            target: .identifier("fst.shell.drawer.open", fallbackLabel: "More"), screenChanged: false,
            token: accessoryFocusToken
        )
        focusAnchor.handled = request
        focusAnchor.schedule(request, attempt: 0)
    }

    /// The drawer follows the selection while it is open.
    func drawerReload() {
        drawer?.update(
            selected: selected, topRoute: stacks[selected]?.topRoute, searchActive: searchActive,
            visibleSections: sections, hideShop: UKSettings.bool("fst.settings.hideShop", default: false)
        )
    }

    /// Carries out a drawer intent on the root-owned navigation state.
    ///
    /// - Parameter intent: Row chosen in the drawer.
    func handleDrawer(_ intent: DrawerIntent) {
        dismissDrawer()
        switch intent {
        case let .push(route):
            if searchActive { perform(.closeSearch) }
            stacks[selected]?.push(route)
        case let .select(section):
            if searchActive { perform(.closeSearch) }
            if selected != section { selectSection(section); syncAfterSelect() }
            stacks[section]?.popToRoot(animated: false)
        case .chooseProfile:
            presentProfile()
        case .deselectProfile:
            session.deselectPlayer()
        case .openSearch:
            perform(.openSearch)
        }
    }

    private func syncAfterSelect() {
        shellState.selectedSection = selected
        syncTabSelection()
    }
}
#endif
