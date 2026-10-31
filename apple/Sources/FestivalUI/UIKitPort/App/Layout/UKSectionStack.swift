#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Host

/// What a section stack asks of the shell that owns it.
@MainActor
protocol UKSectionStackHost: AnyObject {
    /// The window layout the shell last published.
    var stackLayout: DeviceLayout { get }
    /// The screen for a pushed route, created in the stack's section context.
    func stackMakeScreen(_ route: AppRoute, section: FestivalSection) -> UIViewController
    /// A page is about to show in one of the stack's navigation controllers.
    func stackWillShow(_ controller: UIViewController, in stack: UKSectionStack, navigation: UINavigationController)
    /// The stack's path changed through a system gesture, Back button or split reshape.
    func stackDidChangePath(_ stack: UKSectionStack)
}

// MARK: - Section stack

/// One section's navigation: a leading `UINavigationController` holding the section root
/// and every page pushed on it, and, in a landscape regular window while a list page is on
/// top, an on-demand split with a second `UINavigationController` for the open item
/// (``OnDemandSplitPolicy``). The UIKit counterpart of `OnDemandSplitStack`.
///
/// The section's `[AppRoute]` ``path`` is the one source of truth: pushes, pops and
/// window changes edit it, and ``reshape(animated:)`` lays the page controllers out as
/// one pushed stack or as `list + detail`, reusing a controller whenever its route is
/// still on the path, so rotating, folding or resizing never loses the open item or
/// reloads a page.
@MainActor
final class UKSectionStack: UIViewController, UINavigationControllerDelegate {
    /// The section this stack belongs to.
    let section: FestivalSection
    /// The leading (or only) navigation controller.
    let leading = UINavigationController()
    /// The trailing pane's navigation controller while the split shows it.
    private(set) var trailing: UINavigationController?
    /// The shell.
    unowned let host: any UKSectionStackHost
    /// Pane geometry while the split is laid out, nil for one full-width stack.
    private(set) var geometry: OnDemandSplitPolicy.Geometry?
    private var cut: OnDemandSplitPolicy.Cut?
    private var placeholder: UIViewController?
    private let divider = UIView()
    private var applyingPath = false
    /// Called when the trailing pane opens or closes (Escape and the menu bar's Close).
    var onSplitOpenChanged: ((Bool) -> Void)?
    private var reportedOpen = false

    /// Creates a stack.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - root: The section's root screen.
    ///   - host: The shell.
    init(section: FestivalSection, root: UIViewController, host: any UKSectionStackHost) {
        self.section = section
        self.host = host
        super.init(nibName: nil, bundle: nil)
        configure(leading)
        leading.setViewControllers([root], animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure(_ navigation: UINavigationController) {
        navigation.delegate = self
        navigation.navigationBar.prefersLargeTitles = true
        navigation.view.backgroundColor = .clear
        navigation.isNavigationBarHidden = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(leading)
        view.addSubview(leading.view)
        leading.didMove(toParent: self)
        divider.isUserInteractionEnabled = false
        divider.isAccessibilityElement = false
        divider.accessibilityIdentifier = "fst.split.divider"
        divider.isHidden = true
        view.addSubview(divider)
    }

    // MARK: Path

    /// The section root screen.
    var root: UIViewController? { leading.viewControllers.first }

    /// The routes on the stack, leading pane first.
    var path: [AppRoute] {
        leading.viewControllers.dropFirst().compactMap(\.ukRoute) + (trailing?.viewControllers.compactMap(\.ukRoute) ?? [])
    }

    /// The page on top of the stack, if any.
    var topRoute: AppRoute? { path.last }

    /// Replaces the path, reshaping the panes.
    ///
    /// - Parameters:
    ///   - newPath: The routes above the root.
    ///   - animated: Whether the change animates.
    func setPath(_ newPath: [AppRoute], animated: Bool) {
        reshape(path: newPath, animated: animated)
    }

    /// Pushes a route on the path (a detail route of a list page on top opens beside it).
    ///
    /// - Parameter route: The page to show.
    func push(_ route: AppRoute) {
        if geometry != nil || splitIsPossible {
            reshape(path: path + [route], animated: true)
        } else {
            leading.pushViewController(host.stackMakeScreen(route, section: section), animated: true)
            host.stackDidChangePath(self)
        }
    }

    /// Opens a list row's detail: replaces an open item beside the list, else pushes.
    ///
    /// - Parameter route: The detail route.
    func select(_ route: AppRoute) {
        if geometry != nil {
            reshape(path: OnDemandSplitPolicy.path(selecting: route, in: path, section: section), animated: true)
        } else {
            push(route)
        }
    }

    /// Pops the top page (closing the open item first in a split).
    func pop() {
        var current = path
        guard !current.isEmpty else { return }
        current.removeLast()
        reshape(path: current, animated: true)
    }

    /// Replaces the top page.
    ///
    /// - Parameter route: The page to show instead.
    func replaceTop(with route: AppRoute) {
        var current = path
        guard !current.isEmpty else { return push(route) }
        current[current.count - 1] = route
        reshape(path: current, animated: false)
    }

    /// Pops to the section root.
    func popToRoot(animated: Bool) {
        reshape(path: [], animated: animated)
    }

    /// Closes the open item beside the list page (Escape, the Close button).
    ///
    /// - Returns: Whether an item was open.
    @discardableResult
    func closeDetail() -> Bool {
        guard let list = OnDemandSplitPolicy.pathClosingDetail(path, section: section) else { return false }
        reshape(path: list, animated: true)
        return true
    }

    /// Whether the trailing pane shows an open item.
    var isDetailOpen: Bool { geometry != nil && (cut?.selection != nil) }

    // MARK: Shape

    private var rightToLeft: Bool { view.effectiveUserInterfaceLayoutDirection == .rightToLeft }

    /// The panes the window allows now, whatever page is on top.
    private var windowGeometry: OnDemandSplitPolicy.Geometry? {
        guard view.window != nil, view.bounds.width > 0 else { return nil }
        let frame = view.convert(view.bounds, to: nil)
        return OnDemandSplitPolicy.geometry(OnDemandSplitPolicy.uikitContext(
            layout: host.stackLayout, container: OnDemandSplitPolicy.horizontalSpan(of: frame),
            rightToLeft: rightToLeft
        ))
    }

    private var splitIsPossible: Bool { windowGeometry != nil }

    /// Recomputes the pane shape for the current window and path.
    ///
    /// - Parameters:
    ///   - path: The path to show; nil keeps the current one.
    ///   - animated: Whether the panes animate.
    func reshape(path newPath: [AppRoute]? = nil, animated: Bool) {
        guard !applyingPath else { return }
        applyingPath = true
        defer { applyingPath = false }
        let target = newPath ?? path
        var pool = Array(leading.viewControllers.dropFirst()) + (trailing?.viewControllers.filter { $0.ukRoute != nil } ?? [])
        func screen(_ route: AppRoute) -> UIViewController {
            if let index = pool.firstIndex(where: { $0.ukRoute == route }) { return pool.remove(at: index) }
            let made = host.stackMakeScreen(route, section: section)
            return made
        }
        let windowShape = windowGeometry
        let candidate = OnDemandSplitPolicy.cut(section: section, path: target).flatMap { $0.cover == .overList ? nil : $0 }
        let split = candidate != nil && windowShape != nil
        let content = OnDemandSplitPolicy.trailingContent(cut: candidate, allowsSplit: split)
        let wasSplit = geometry != nil
        let leadingRoutes: [AppRoute]
        let trailingRoutes: [AppRoute]
        if split, let candidate {
            leadingRoutes = candidate.list
            trailingRoutes = candidate.detail
        } else {
            leadingRoutes = target
            trailingRoutes = []
        }
        // Detach the pooled pages first: a controller has one parent.
        let leadingScreens = leadingRoutes.map(screen)
        let trailingScreens = trailingRoutes.map(screen)
        let rootScreen = leading.viewControllers.first
        let oldTrailing = trailing
        oldTrailing?.setViewControllers([], animated: false)
        let animateLeading = animated && !split && !wasSplit && leadingScreens.count != leading.viewControllers.count - 1
        leading.setViewControllers(([rootScreen].compactMap { $0 }) + leadingScreens, animated: animateLeading)
        var pane: UINavigationController?
        if split, content != .none {
            let navigation = oldTrailing ?? UINavigationController()
            if oldTrailing == nil { configure(navigation); navigation.navigationBar.prefersLargeTitles = true }
            var screens = trailingScreens
            switch content {
            case let .placeholder(info):
                let holder = placeholder ?? UKSplitPlaceholderViewController(info)
                placeholder = holder
                screens = [holder]
            default:
                placeholder = nil
            }
            navigation.setViewControllers(screens, animated: false)
            pane = navigation
        } else {
            placeholder = nil
        }
        cut = split ? candidate : nil
        geometry = split ? windowShape : nil
        attach(pane)
        applyFrames(animated: animated && (split != wasSplit || (cut?.cover != nil)))
        let open = isDetailOpen
        if open != reportedOpen {
            reportedOpen = open
            onSplitOpenChanged?(open)
        }
        host.stackDidChangePath(self)
    }

    private func attach(_ pane: UINavigationController?) {
        if trailing === pane { return }
        if let old = trailing {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        trailing = pane
        if let pane {
            addChild(pane)
            pane.view.accessibilityIdentifier = nil
            view.insertSubview(pane.view, belowSubview: divider)
            pane.didMove(toParent: self)
        }
    }

    private func applyFrames(animated: Bool) {
        let bounds = view.bounds
        let leadingFrame: CGRect
        var trailingFrame: CGRect?
        let rtl = rightToLeft
        if let geometry {
            let full = geometry.leadingWidth + geometry.dividerWidth + geometry.trailingWidth
            let covered = cut?.cover == .overSplit
            let lead = geometry.leadingWidth
            let leadRect = rtl
                ? CGRect(x: bounds.width - lead, y: 0, width: lead, height: bounds.height)
                : CGRect(x: 0, y: 0, width: lead, height: bounds.height)
            leadingFrame = leadRect
            let trailWidth = covered ? full : geometry.trailingWidth
            trailingFrame = rtl
                ? CGRect(x: 0, y: 0, width: trailWidth, height: bounds.height)
                : CGRect(x: bounds.width - trailWidth, y: 0, width: trailWidth, height: bounds.height)
        } else {
            leadingFrame = bounds
        }
        let apply = {
            self.leading.view.frame = leadingFrame
            if let trailingFrame { self.trailing?.view.frame = trailingFrame }
            self.leading.view.alpha = (self.cut?.cover ?? .none) == .overSplit ? 0 : 1
            self.leading.view.isUserInteractionEnabled = (self.cut?.cover ?? .none) != .overSplit
            self.leading.view.accessibilityElementsHidden = (self.cut?.cover ?? .none) == .overSplit
        }
        updateDivider()
        if animated {
            let reduce = UIAccessibility.isReduceMotionEnabled || UKSettings.bool("fst.accessibility.reduceMotion", default: false)
            if reduce {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut], animations: apply)
            } else {
                UIView.animate(
                    withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                    options: [], animations: apply
                )
            }
        } else {
            apply()
        }
    }

    private func updateDivider() {
        guard let geometry else {
            divider.isHidden = true
            return
        }
        let contrast = traitCollection.accessibilityContrast == .high
            || UKSettings.bool("fst.accessibility.moreContrast", default: false)
        divider.isHidden = false
        divider.backgroundColor = OnDemandSplitPolicy.drawsDividerLine(geometry, increasedContrast: contrast)
            ? UIColor.white.withAlphaComponent(0.16) : .clear
        let width = OnDemandSplitPolicy.midpointDividerWidth
        let band = geometry.dividerWidth
        let x = rightToLeft ? view.bounds.width - geometry.leadingWidth - band / 2 - width / 2
            : geometry.leadingWidth + band / 2 - width / 2
        divider.frame = CGRect(x: x, y: 0, width: width, height: view.bounds.height)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let shape = windowGeometry
        if shape != nil || geometry != nil {
            // A window change (rotation, fold, resize) may change what the width allows.
            if (shape != nil) != (geometry != nil) || (shape != nil && shape != geometry) {
                reshape(animated: false)
                return
            }
        }
        applyFrames(animated: false)
    }

    /// Re-evaluates the shape after the shell published a new layout.
    func layoutDidChange() {
        view.setNeedsLayout()
        if (windowGeometry != nil) != (geometry != nil) || windowGeometry != geometry { reshape(animated: false) }
    }

    // MARK: Navigation delegate

    func navigationController(
        _ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool
    ) {
        host.stackWillShow(viewController, in: self, navigation: navigationController)
        if navigationController === trailing { installTrailingChrome(on: viewController, navigation: navigationController) }
        if navigationController === leading { installLeadingChrome(on: viewController, navigation: navigationController) }
    }

    func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        guard !applyingPath else { return }
        if navigationController === leading, geometry != nil {
            // The leading pane popped (Back or edge swipe): its open item closes with it.
            let newList = Array(leading.viewControllers.dropFirst().compactMap(\.ukRoute))
            let next = OnDemandSplitPolicy.path(settingList: newList, in: path, section: section)
            if next != path { reshape(path: next, animated: false); return }
        }
        if navigationController === trailing, geometry != nil, let cut {
            let tail = Array(navigationController.viewControllers.compactMap(\.ukRoute).dropFirst())
            let next = OnDemandSplitPolicy.path(settingDetailTail: tail, in: path, section: section)
            if next != path || cut.detail.count != navigationController.viewControllers.count {
                reshape(path: next, animated: false); return
            }
        }
        host.stackDidChangePath(self)
    }

    /// The split's Close button on the open item's root.
    private func installTrailingChrome(on controller: UIViewController, navigation: UINavigationController) {
        guard controller === navigation.viewControllers.first, controller.ukRoute != nil, cut?.cover != .overSplit else { return }
        let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closePressed))
        close.accessibilityLabel = "Close"
        close.accessibilityIdentifier = "fst.split.close"
        close.title = "Close"
        close.largeContentSizeImage = nil
        controller.navigationItem.leftBarButtonItem = close
        controller.navigationItem.leftItemsSupplementBackButton = false
    }

    /// Back on the leading pane's list page closes the open item first (issue #347).
    private func installLeadingChrome(on controller: UIViewController, navigation: UINavigationController) {
        guard geometry != nil, cut?.selection != nil, controller === navigation.viewControllers.last,
              controller.ukRoute != nil else { return }
        let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(listBackPressed))
        back.accessibilityLabel = "Back"
        back.accessibilityIdentifier = "fst.split.list-back"
        controller.navigationItem.leftBarButtonItem = back
        controller.navigationItem.hidesBackButton = true
    }

    @objc private func closePressed() { closeDetail() }

    @objc private func listBackPressed() {
        if let next = OnDemandSplitPolicy.pathAfterListBack(path, section: section) { reshape(path: next, animated: true) }
    }
}

// MARK: - Placeholder

/// The trailing pane's centred placeholder while a list page has nothing open (Settings,
/// issue #371).
final class UKSplitPlaceholderViewController: UIViewController {
    private let info: OnDemandSplitPolicy.Placeholder

    /// Creates the placeholder.
    ///
    /// - Parameter info: Its title, symbol, subtitle and identifier.
    init(_ info: OnDemandSplitPolicy.Placeholder) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        navigationItem.largeTitleDisplayMode = .never
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: info.systemImage)
        configuration.text = info.title
        configuration.secondaryText = info.subtitle
        configuration.textProperties.color = BrandUIColors.textPrimary
        configuration.secondaryTextProperties.color = BrandUIColors.textSecondary
        configuration.imageProperties.tintColor = BrandUIColors.textSecondary
        contentUnavailableConfiguration = configuration
        view.accessibilityIdentifier = info.accessibilityIdentifier
        view.accessibilityElements = nil
    }
}
#endif
