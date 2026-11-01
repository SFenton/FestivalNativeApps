#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Root

/// A window's root in the UIKit port: the UIKit counterpart of ``FestivalRootView``.
///
/// Owns the shell: one ``UKSectionStack`` per section inside a `UITabBarController` (phone
/// tabs with the trailing Search tab; at regular iPad width the same controller with its bar
/// hidden and the drawer as the flyout), the hamburger drawer, the profile and notification
/// buttons, the Search tab, tab and section transitions (``RootTabTransition``), conditional
/// sections (``ShellPresentation``, ``FestivalTabPolicy``), launch overrides
/// (``FestivalLaunch``) and the published ``DeviceLayout`` / ``ShellPresentation`` in
/// ``UKShellState``. Pages reach it through ``UKNavigating``.
///
/// The class is split across extensions: ``UKRootViewController+Layout``,
/// ``UKRootViewController+Navigation``, ``UKRootViewController+Chrome`` and
/// ``UKRootViewController+Commands``.
final class UKRootViewController: UIViewController {
    // MARK: Inputs

    let launch: FestivalLaunch
    let shellState = UKShellState()
    let observations = UKObservationBag()

    // MARK: Structure

    let tabs = UITabBarController()
    var stacks: [FestivalSection: UKSectionStack] = [:]
    var sections: [FestivalSection] = []
    var searchModel = GlobalSearchModel()
    var searchController: UKGlobalSearchViewController?
    var searchNavigation: UINavigationController?
    var drawer: UKDrawerViewController?
    var edgeSwipe: UIScreenEdgePanGestureRecognizer?

    // MARK: State

    var selected: FestivalSection
    var searchActive = false
    var layout: DeviceLayout = .standardPhone
    var hingeState: HingeState?
    var appliedRegularSet: Bool?
    var presentation = ShellPresentation.resolve(layout: .standardPhone, usesSidebarShell: false)
    var applyingTabSelection = false
    var didApplyLaunch = false
    var windowRoute: FestivalWindowRoute?
    var windowRouteApplied = false
    var liveToken = UUID()
    var chromeControllers = NSHashTable<UIViewController>.weakObjects()
    var accessoryFocusToken = 0
    var pendingSheetRoute: AppRoute?
    var hingeInteractionInstalled = false
    /// The simulated Duo window readout (`UKDebugDuoWindowReadout`), Debug only.
    var duoReadout: UIView?
    var splitOpenSections: Set<FestivalSection> = []
    var refreshTask: Task<Void, Never>?
    var openingApplied = false
    let focusAnchor = AccessibilityFocusAnchor.AnchorView()
    var tabsHidden = false
    var searchTabRef: AnyObject?
    /// Each section's `UITab` (iOS 18+), kept across tab-set rebuilds: `UITab` caches the
    /// controller its provider returned, and handing a section's live stack to a second tab
    /// asserts in `-[UITab viewController]` (selecting a player rebuilt the set and crashed).
    var sectionTabs: [FestivalSection: AnyObject] = [:]
    let floatingTools = UKFloatingPageToolsView()
    var floatingBottom: NSLayoutConstraint?
    var expandedBarInset: CGFloat = 0
    var tabsSearchAsTab = false

    // MARK: Background lane

    /// The shared artwork backdrop, installed once under the shell (``UKBackgroundView``).
    lazy var background = UKBackgroundView(session: session)

    /// Creates a window's root.
    ///
    /// - Parameter windowRoute: The content an "Open in New Window" request opened this
    ///   window with, if any.
    init(windowRoute: FestivalWindowRoute? = nil) {
        launch = FestivalLaunch.resolve(windowRoute: windowRoute)
        selected = launch.selected
        self.windowRoute = windowRoute
        searchActive = launch.opensSearch
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The session every screen of this window reads.
    var session: FestivalSession { launch.session }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = BrandUIColors.appBackground
        addChild(tabs)
        tabs.view.frame = view.bounds
        tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabs.view.backgroundColor = .clear
        tabs.delegate = self
        focusAnchor.isUserInteractionEnabled = false
        focusAnchor.frame = .zero
        view.addSubview(focusAnchor)
        view.addSubview(tabs.view)
        background.install(in: view) // Background lane: the one shared backdrop, beneath the tabs.
        tabs.didMove(toParent: self)
        if #available(iOS 26.0, *) { tabs.tabBarMinimizeBehavior = .onScrollDown }
        floatingTools.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingTools)
        placeFloatingToolsBeforeTabBar()
        let bottom = floatingTools.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -90)
        floatingBottom = bottom
        NSLayoutConstraint.activate([
            floatingTools.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -FloatingPageToolsFit.margin),
            floatingTools.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: FloatingPageToolsFit.margin),
            bottom,
        ])
        installHingeInteraction()
        installEdgeSwipe()
        shellState.selectedSection = selected
        shellState.searchActive = searchActive
        refreshLayout(initial: true)
        rebuildSections()
        applyLaunchState()
        observations.observe { [weak self] in self?.sessionChanged() }
        observations.observe { [weak self] in self?.refreshChromeFromState() }
        observations.observe { [weak self] in self?.refreshNotifications() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: UKSettings.didChange, object: nil
        )
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneForeground), name: UIScene.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneBackground), name: UIScene.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneForeground), name: UIScene.didActivateNotification, object: nil)
        session.acquireLiveUpdates(liveToken)
        #if DEBUG
        installDebugDuoWindow()
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyOpeningSheets()
        Task { await applyWindowRoute() }
    }

    deinit {
        let token = liveToken
        let session = launch.session
        Task { @MainActor in session.releaseLiveUpdates(token) }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func sceneForeground() { session.acquireLiveUpdates(liveToken) }
    @objc private func sceneBackground() { session.releaseLiveUpdates(liveToken) }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeFloatingToolsBeforeTabBar()
        refreshLayout(initial: false)
        positionFloatingTools()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshLayout(initial: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refreshLayout(initial: false) }
    }

    // MARK: Launch

    /// Applies the launch overrides (`FST_DEBUG_TAB/ROUTE`): the selected section and each
    /// section's initial path.
    private func applyLaunchState() {
        guard !didApplyLaunch else { return }
        didApplyLaunch = true
        for (section, routes) in launch.paths {
            stackFor(section)?.setPath(routes, animated: false)
        }
        syncTabSelection()
        shellState.splitOpen = false
    }

    /// The sheets and drawer a launch asks to start with, once the window is on screen.
    private func applyOpeningSheets() {
        guard didApplyLaunch, !openingApplied else { return }
        openingApplied = true
        if launch.opensDrawer { openDrawer(animated: false) }
        if launch.opensProfileSheet { presentProfile() }
    }
}

#endif
