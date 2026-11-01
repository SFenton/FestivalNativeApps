#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Settings lane routes

/// The Settings, Licenses and settings topics lane's screens in the UIKit port (ports
/// `Features/Settings`, `FirstRun`, `WhatsNew` and `Notifications`).
///
/// Owned by the Settings lane: `.licenses`, `.settingsTopic`; root `.settings`. ``UKRouteDestination``
/// calls these.
@MainActor
enum UKSettingsRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil for a route of another lane.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        UKSettingsRegistration.install()
        switch route {
        case .licenses: return UKLicensesViewController(context: context)
        case let .settingsTopic(topic): return UKSettingsViewController(context: context, topic: topic)
        default: return nil
        }
    }

    /// The root controller of a section this lane owns.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The Settings page for `.settings`, else nil.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController? {
        UKSettingsRegistration.install()
        return section == .settings ? UKSettingsViewController(context: context) : nil
    }
}

// MARK: - Registration

/// What the Settings lane wires into the shell at launch: the Notifications and What's New sheet
/// factories (``UKShellSheets``) and the first-run and launch What's New hooks. Called from
/// ``UKApp/didFinishLaunching()``; idempotent.
@MainActor
enum UKSettingsRegistration {
    private static var installed = false

    /// Installs the lane's hooks once.
    static func install() {
        guard !installed else { return }
        installed = true
        UKShellSheets.notificationsFactory = { session, open in
            UKNotificationsViewController.makeSheet(session: session, openRoute: open)
        }
        UKShellSheets.whatsNewFactory = { session in UKWhatsNew.shellSheet(session) }
        UKFirstRunHook.install()
    }
}

// MARK: - First run hook

/// Shows each page's first-run carousel when the page appears, without any per-screen code
/// (the SwiftUI `.firstRun(page:session:)` modifier on every route and section root): the hook
/// watches view controllers appear and disappear, attaches a ``UKFirstRunPageWatcher`` to the ones
/// that are a first-run page (a section root, or a route with ``AppRoute/firstRunPage``), and starts
/// the launch What's New flow when the window root first appears.
@MainActor
enum UKFirstRunHook {
    private static var installed = false
    private static var launches: [ObjectIdentifier: UKWhatsNewLaunch] = [:]

    /// Swaps in the lifecycle observers once.
    static func install() {
        guard !installed else { return }
        installed = true
        swap(#selector(UIViewController.viewDidAppear(_:)), #selector(UIViewController.ukfrViewDidAppear(_:)))
        swap(#selector(UIViewController.viewDidDisappear(_:)), #selector(UIViewController.ukfrViewDidDisappear(_:)))
    }

    private static func swap(_ original: Selector, _ replacement: Selector) {
        guard let first = class_getInstanceMethod(UIViewController.self, original),
              let second = class_getInstanceMethod(UIViewController.self, replacement) else { return }
        method_exchangeImplementations(first, second)
    }

    /// The first-run page a controller shows, if any.
    static func page(of controller: UIViewController) -> FirstRunPageKey? {
        guard let stack = controller.ukSectionStack else { return nil }
        if let route = controller.ukRoute { return route.firstRunPage }
        guard controller.navigationController?.viewControllers.first === controller else { return nil }
        switch stack.section {
        case .songs: return .songs
        case .suggestions: return .suggestions
        case .leaderboards: return .leaderboards
        case .compete: return .compete
        case .rivals: return .rivals
        case .statistics: return .statistics
        case .shop: return .shop
        case .settings: return nil
        }
    }

    fileprivate static func appeared(_ controller: UIViewController) {
        if let shell = controller as? UKRootViewController {
            if launches[ObjectIdentifier(shell)] == nil {
                launches[ObjectIdentifier(shell)] = UKWhatsNewLaunch(session: shell.chromeSession, shell: shell)
            }
            return
        }
        guard let page = page(of: controller), let session = controller.ukShell?.chromeSession else { return }
        watcher(for: controller, page: page, session: session).appeared()
    }

    fileprivate static func disappeared(_ controller: UIViewController) {
        guard let watcher = objc_getAssociatedObject(controller, &watcherKey) as? UKFirstRunPageWatcher else { return }
        watcher.disappeared()
    }

    private static func watcher(for controller: UIViewController, page: FirstRunPageKey, session: FestivalSession) -> UKFirstRunPageWatcher {
        if let existing = objc_getAssociatedObject(controller, &watcherKey) as? UKFirstRunPageWatcher { return existing }
        let made = UKFirstRunPageWatcher(page: page, session: session, host: controller)
        objc_setAssociatedObject(controller, &watcherKey, made, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return made
    }
}

nonisolated(unsafe) private var watcherKey: UInt8 = 0

extension UIViewController {
    @objc fileprivate func ukfrViewDidAppear(_ animated: Bool) {
        // Exchanged with `viewDidAppear(_:)`: this calls the original.
        ukfrViewDidAppear(animated)
        MainActor.assumeIsolated { UKFirstRunHook.appeared(self) }
    }

    @objc fileprivate func ukfrViewDidDisappear(_ animated: Bool) {
        ukfrViewDidDisappear(animated)
        MainActor.assumeIsolated { UKFirstRunHook.disappeared(self) }
    }
}
#endif
