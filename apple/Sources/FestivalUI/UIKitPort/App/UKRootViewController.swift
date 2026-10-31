#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Root

/// A window's root in the UIKit port: the UIKit counterpart of ``FestivalRootView``.
///
/// Foundation version (orchestrator): the shared background colour, one
/// `UINavigationController` per visible section in a `UITabBarController`, launch
/// overrides from ``FestivalLaunch`` and the ``UKNavigating`` commands. The Shell lane
/// replaces the tab-only container with the full shell (drawer, iPad flyout, Search tab,
/// profile button, iPhone Duo layouts) behind the same type.
final class UKRootViewController: UIViewController, UKNavigating {
    private let launch: FestivalLaunch
    private let tabs = UITabBarController()
    private let shellState = UKShellState()
    private let observations = UKObservationBag()
    // MARK: Background lane
    private lazy var background = UKBackgroundView(session: session)
    private var stacks: [FestivalSection: UINavigationController] = [:]
    private var sections: [FestivalSection] = []

    /// Creates a window's root.
    ///
    /// - Parameter windowRoute: The content an "Open in New Window" request opened this
    ///   window with, if any.
    init(windowRoute: FestivalWindowRoute? = nil) {
        launch = FestivalLaunch.resolve(windowRoute: windowRoute)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The session every screen of this window reads.
    var session: FestivalSession { launch.session }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = BrandUIColors.appBackground
        addChild(tabs)
        tabs.view.frame = view.bounds
        tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabs.view.backgroundColor = .clear
        view.addSubview(tabs.view)
        background.install(in: view) // Background lane: the one shared backdrop, beneath the tabs.
        tabs.didMove(toParent: self)
        observations.observe { [weak self] in self?.rebuildSections() }
        if let selected = stacks[launch.selected] { tabs.selectedViewController = selected }
        for (section, routes) in launch.paths {
            guard let stack = stacks[section] else { continue }
            for route in routes {
                stack.pushViewController(UKRouteDestination.make(route, context: context(for: section)), animated: false)
            }
        }
    }

    // MARK: Sections

    /// The context a section's screens are created with.
    private func context(for section: FestivalSection) -> UKContext {
        UKContext(session: session, navigator: self).with {
            $0.section = section
            $0.shell = shellState
        }
    }

    /// Rebuilds the tab set when the selected profile changes which sections show
    /// (``ShellPresentation``), keeping the stacks of sections that stay.
    private func rebuildSections() {
        let profile: FestivalProfileKind =
            session.selectedPlayer == nil && !FestivalLaunch.keepsProfileRoutes ? .none : .player
        let presentation = ShellPresentation.resolve(layout: .standardPhone, usesSidebarShell: false)
        shellState.presentation = presentation
        let next = presentation.sections(
            profile: profile, hideShop: UKSettings.bool("fst.settings.hideShop", default: false)
        )
        guard next != sections else { return }
        sections = next
        let controllers = next.map { section -> UINavigationController in
            if let existing = stacks[section] { return existing }
            let root = UKRouteDestination.root(for: section, context: context(for: section))
            let stack = UINavigationController(rootViewController: root)
            stack.navigationBar.prefersLargeTitles = true
            stack.view.backgroundColor = .clear
            stack.tabBarItem = UITabBarItem(
                title: section.title, image: UIImage(systemName: section.symbol), tag: section.hashValue
            )
            stack.tabBarItem.accessibilityIdentifier = "fst.nav.\(section.rawValue)"
            stacks[section] = stack
            return stack
        }
        stacks = stacks.filter { next.contains($0.key) }
        tabs.setViewControllers(controllers, animated: false)
    }

    /// The section whose tab is selected.
    private var selectedSection: FestivalSection? {
        stacks.first { $0.value === tabs.selectedViewController }?.key
    }

    // MARK: UKNavigating

    func push(_ route: AppRoute) {
        guard let section = selectedSection, let stack = stacks[section] else { return }
        stack.pushViewController(UKRouteDestination.make(route, context: context(for: section)), animated: true)
    }

    func pop() {
        (tabs.selectedViewController as? UINavigationController)?.popViewController(animated: true)
    }

    func replaceTop(with route: AppRoute) {
        guard let section = selectedSection, let stack = stacks[section] else { return }
        var controllers = stack.viewControllers
        guard controllers.count > 1 else { return push(route) }
        controllers[controllers.count - 1] = UKRouteDestination.make(route, context: context(for: section))
        stack.setViewControllers(controllers, animated: false)
    }

    func select(_ section: FestivalSection) {
        guard let stack = stacks[section] else { return }
        if tabs.selectedViewController === stack {
            stack.popToRootViewController(animated: true)
        } else {
            tabs.selectedViewController = stack
        }
    }

    func openDrawer() {}

    func presentProfile() {}
}
#endif
