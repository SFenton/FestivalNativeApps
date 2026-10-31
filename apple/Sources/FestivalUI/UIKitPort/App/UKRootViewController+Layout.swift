#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Layout publishing and section set

extension UKRootViewController {
    /// True for the wide shell: a regular-width iPad window (sections in the flyout).
    var usesSidebarShell: Bool {
        ShellPresentation.usesSidebarShell(
            supportsSidebar: FestivalLaunch.supportsSidebar,
            widthClass: traitCollection.horizontalSizeClass == .compact ? .compact : .regular
        )
    }

    /// Profile kind driving conditional tabs.
    var profileKind: FestivalProfileKind {
        session.selectedPlayer == nil && !FestivalLaunch.keepsProfileRoutes ? .none : .player
    }

    // MARK: Hinge

    /// Listens for the iPhone Duo hinge (iOS 27.1+): its status joins the layout signals.
    func installHingeInteraction() {
        guard !hingeInteractionInstalled else { return }
        hingeInteractionInstalled = true
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                let next: HingeState? = update.hinge.map { hinge in
                    switch hinge.status {
                    case .closed: .closed
                    case .fullyOpen: .fullyOpen
                    default: .partiallyOpen
                    }
                }
                if next != self.hingeState {
                    self.hingeState = next
                    self.refreshLayout(initial: false)
                }
            }
            view.addInteraction(interaction)
        }
    }

    // MARK: Layout

    /// Recomputes the ``DeviceLayout`` from the window's size, size classes, safe area,
    /// vertical bar, hinge and reserved regions, and publishes it with the resolved
    /// ``ShellPresentation`` into ``UKShellState``.
    ///
    /// - Parameter initial: True for the first pass in `viewDidLoad`.
    func refreshLayout(initial: Bool) {
        guard isViewLoaded, view.bounds.width > 0 else { return }
        var occlusions: [CGRect] = []
        var divisions: [CGRect] = []
        var hinges: [CGRect] = []
        var barLeading: Bool?
        if #available(iOS 27.1, *) {
            occlusions = view.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            divisions = view.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
            hinges = view.reservedRegions(kind: .division, options: [.includeInactive]).map(\.frame)
            switch traitCollection.verticalBarEdge {
            case .leading: barLeading = true
            case .trailing: barLeading = false
            default: barLeading = nil
            }
        }
        let signals = LayoutSignals(
            uikitSize: view.bounds.size,
            widthClass: traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
            heightClass: traitCollection.verticalSizeClass == .compact ? .compact : .regular,
            safeArea: windowSafeArea(), verticalBarIsLeading: barLeading, hinge: hingeState,
            occlusions: occlusions, divisions: divisions, hinges: hinges, usesSidebarShell: usesSidebarShell
        ).applyingDebugOverrides()
        let next = DeviceLayout.resolve(signals)
        if next != layout {
            layout = next
            shellState.layout = next
            layoutDidChange()
        } else if shellState.layout == nil {
            shellState.layout = next
        }
    }

    /// The window's safe area including the system vertical bar, which the root's own
    /// safe area omits: read from the frontmost page.
    private func windowSafeArea() -> UIEdgeInsets {
        var insets = view.safeAreaInsets
        if let page = tabs.selectedViewController?.view {
            insets.left = max(insets.left, page.safeAreaInsets.left)
            insets.right = max(insets.right, page.safeAreaInsets.right)
        }
        return insets
    }

    /// The layout changed (rotation, fold, resize, size-class change): re-resolve the section
    /// set and shell, then let every stack and the chrome follow.
    private func layoutDidChange() {
        let regular = ShellPresentation.resolve(layout: layout, usesSidebarShell: usesSidebarShell).usesRegularSectionSet
        if appliedRegularSet == nil {
            appliedRegularSet = regular
            rebuildSections()
        } else if appliedRegularSet != regular {
            // A change in the tab set lands one run-loop turn later, so it never shares an
            // update with the size-class change that caused it (`ShellPresentation.applying`).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.appliedRegularSet = regular
                self.rebuildSections()
            }
        } else {
            rebuildSections()
        }
        for stack in stacks.values { stack.layoutDidChange() }
        refreshChrome()
        searchController?.refreshFieldPlacement()
        updateEdgeSwipe()
        drawer?.view.setNeedsLayout()
    }

    // MARK: Section set

    /// Rebuilds the tab set when the selected profile, window or Settings change which
    /// sections show, keeping the stacks of sections that stay.
    func rebuildSections() {
        let resolved = ShellPresentation.resolve(layout: layout, usesSidebarShell: usesSidebarShell)
        let applied = ShellPresentation.applying(resolved, regularSet: appliedRegularSet)
        presentation = applied
        if shellState.presentation != applied { shellState.presentation = applied }
        let hideShop = UKSettings.bool("fst.settings.hideShop", default: false)
        let next = applied.sections(profile: profileKind, hideShop: hideShop)
        let flyout = applied.navigation == .flyout
        guard next != sections || tabsHidden != flyout || tabsSearchAsTab != !flyout else {
            return
        }
        // Keep the user on an equivalent section when the visible set changes.
        let paths = Dictionary(uniqueKeysWithValues: stacks.map { ($0.key, $0.value.path) })
        let adapted = FestivalTabPolicy.adapt(selected: selected, paths: paths, to: next)
        sections = next
        for section in next where stacks[section] == nil { _ = stackFor(section) }
        for (section, path) in adapted.paths where path != paths[section] { stacks[section]?.setPath(path, animated: false) }
        if adapted.selected != selected {
            selected = adapted.selected
            shellState.selectedSection = selected
        }
        installTabs(flyout: flyout)
        drawerReload()
    }

    /// The tab (or flyout) container for the section set.
    private func installTabs(flyout: Bool) {
        tabsHidden = flyout
        tabsSearchAsTab = !flyout
        let searchRoot = makeSearchNavigation(asTab: !flyout)
        if #available(iOS 18.0, *) {
            var items: [UITab] = sections.map { section in
                let tab = UITab(
                    title: section.title, image: UIImage(systemName: section.symbol),
                    identifier: "fst.tab.\(section.rawValue)"
                ) { [weak self] _ in self?.stacks[section] ?? UIViewController() }
                tab.preferredPlacement = .fixed
                return tab
            }
            let search = UISearchTab { _ in searchRoot }
            searchTabRef = search
            if #available(iOS 26.0, *) { search.automaticallyActivatesSearch = !flyout }
            items.append(search)
            tabs.mode = .tabBar
            tabs.tabs = items
            tabs.setTabBarHidden(flyout, animated: false)
        } else {
            let controllers: [UIViewController] = sections.compactMap { section in
                let stack = stacks[section]
                stack?.tabBarItem = UITabBarItem(title: section.title, image: UIImage(systemName: section.symbol), tag: 0)
                return stack
            }
            searchRoot.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 1)
            tabs.setViewControllers(controllers + [searchRoot], animated: false)
            tabs.tabBar.isHidden = flyout
        }
        syncTabSelection()
    }

    /// The Search tab's navigation controller around the shared global search page.
    private func makeSearchNavigation(asTab: Bool) -> UINavigationController {
        let page = UKGlobalSearchViewController(
            model: searchModel, session: session, asTab: asTab, layout: { [weak self] in self?.layout ?? .standardPhone },
            open: { [weak self] route in self?.perform(RootTabTransition.openResult(route)) },
            dismiss: { [weak self] in
                guard let self else { return }
                self.perform(RootTabTransition.dismissSearch(searchActive: self.searchActive))
            }
        )
        let navigation = UINavigationController(rootViewController: page)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.view.backgroundColor = .clear
        navigation.view.accessibilityIdentifier = "fst.nav.search"
        if !asTab { navigation.delegate = self }
        searchController = page
        searchNavigation = navigation
        if !asTab {
            // The flyout's Search page carries the account items like every other root.
            UKRootChrome.install(on: page, actions: self, drawer: true)
            chromeControllers.add(page)
        }
        return navigation
    }

    /// The stack for a section, created on first use.
    func stackFor(_ section: FestivalSection) -> UKSectionStack? {
        if let existing = stacks[section] { return existing }
        let root = UKRouteDestination.root(for: section, context: context(for: section))
        let stack = UKSectionStack(section: section, root: root, host: self)
        stack.onSplitOpenChanged = { [weak self] open in
            guard let self else { return }
            if open { self.splitOpenSections.insert(section) } else { self.splitOpenSections.remove(section) }
            self.shellState.splitOpen = self.splitOpenSections.contains(self.selected)
        }
        stacks[section] = stack
        return stack
    }

    /// The context a section's screens are created with.
    func context(for section: FestivalSection) -> UKContext {
        UKContext(session: session, navigator: self).with {
            $0.section = section
            $0.shell = shellState
        }
    }

    // MARK: Tab selection

    /// Makes the tab bar show what the shell state says (the selected section, or Search).
    func syncTabSelection() {
        guard !sections.isEmpty else { return }
        applyingTabSelection = true
        defer { applyingTabSelection = false }
        if #available(iOS 18.0, *) {
            let tab = searchActive
                ? searchTabRef as? UITab : tabs.tabs.first(where: { $0.identifier == "fst.tab.\(selected.rawValue)" })
            if let tab, tabs.selectedTab !== tab { tabs.selectedTab = tab }
        } else {
            if searchActive, let search = searchNavigation {
                tabs.selectedViewController = search
            } else if let stack = stacks[selected] {
                tabs.selectedViewController = stack
            }
        }
        searchController?.setSelected(searchActive)
    }

    // MARK: Edge swipe

    func installEdgeSwipe() {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwiped(_:)))
        gesture.edges = .left
        view.addGestureRecognizer(gesture)
        edgeSwipe = gesture
        updateEdgeSwipe()
    }

    /// Enables the flyout swipe at a section root (iPad flyout and the Duo).
    func updateEdgeSwipe() {
        let atRoot = searchActive || (stacks[selected]?.path.isEmpty ?? true)
        edgeSwipe?.isEnabled = drawer == nil && atRoot
            && (presentation.navigation == .flyout || layout.pose != .standard)
    }

    @objc private func edgeSwiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        if FlyoutEdgeSwipe.opens(startFromLeading: 0, translation: CGSize(width: translation.x, height: translation.y)) {
            openDrawer()
        }
    }
}

#endif
