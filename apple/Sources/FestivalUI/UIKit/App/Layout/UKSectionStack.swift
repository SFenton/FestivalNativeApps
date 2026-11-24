#if os(iOS)
import FestivalAppSupport
import FestivalCore
import FestivalDesign
import FentonAppleCore
import FentonUIKit
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
final class UKSectionStack: FentonCoverSplitViewController, UINavigationControllerDelegate {
    /// The section this stack belongs to.
    let section: FestivalSection
    /// The leading (or only) navigation controller.
    let leading: UINavigationController = FentonNavigationController()
    /// The trailing pane's navigation controller while the split shows it.
    var trailing: UINavigationController? { trailingController as? UINavigationController }
    /// The shell.
    unowned let host: any UKSectionStackHost
    /// Pane geometry while the split is laid out, nil for one full-width stack.
    private(set) var geometry: OnDemandSplitPolicy.Geometry?
    private var appliedWindowState = OnDemandSplitPolicy.WindowState(measured: false, allowsSplit: false)
    private var appliedWindowGeometry: OnDemandSplitPolicy.Geometry?
    private var windowChangePending = false
    private var cut: OnDemandSplitPolicy.Cut?
    private var placeholder: UIViewController?
    private var applyingPath = false
    private var accessibilityObserver: UKAccessibilityObserver?
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
        super.init(leading: leading)
        dividerAccessibilityIdentifier = "fst.split.divider"
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
        accessibilityObserver = UKAccessibilityObserver { [weak self] in self?.view.setNeedsLayout() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKSectionStack, _) in
            self.view.setNeedsLayout()
        }
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

    /// The selection associated with the trailing pane, even when a profile covers it.
    var openDetailRoute: AppRoute? { geometry == nil ? nil : cut?.selection }

    /// Whether the trailing pane shows an open item.
    var isDetailOpen: Bool { openDetailRoute != nil }

    /// The leading pane owns window-level controls until a profile covers it.
    var showsAccountInTrailingPane: Bool { cut?.cover == .overSplit }

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

    private var splitIsPossible: Bool { appliedWindowGeometry != nil }

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
        let windowShape = appliedWindowGeometry
        let candidate = OnDemandSplitPolicy.cut(section: section, path: target).flatMap { $0.cover == .overList ? nil : $0 }
        let split = candidate != nil && windowShape != nil
        let content = OnDemandSplitPolicy.trailingContent(cut: candidate, allowsSplit: split)
        let hadTrailingPane = trailing != nil
        let wasCovered = cut?.cover == .overSplit
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
        let targetLeading = [rootScreen].compactMap { $0 } + leadingScreens
        if oldTrailing?.viewControllers.contains(where: { targetLeading.contains($0) }) == true {
            for page in targetLeading where page.navigationItem.leftBarButtonItem?.accessibilityIdentifier == "fst.split.close" {
                page.navigationItem.leftBarButtonItem = nil
            }
            oldTrailing?.setViewControllers([], animated: false)
        }
        cut = split ? candidate : nil
        geometry = split ? windowShape : nil
        let animateLeading = animated && content == .none && !hadTrailingPane
            && targetLeading.count != leading.viewControllers.count
        if leading.viewControllers != targetLeading {
            leading.setViewControllers(targetLeading, animated: animateLeading)
        }
        var pane: UINavigationController?
        if split, content != .none {
            let navigation = oldTrailing ?? FentonNavigationController()
            if oldTrailing == nil {
                configure(navigation)
                navigation.view.accessibilityIdentifier = "fst.split.trailing"
            }
            var screens = trailingScreens
            switch content {
            case let .placeholder(info):
                let holder = placeholder ?? UKSplitPlaceholderViewController(info)
                placeholder = holder
                screens = [holder]
            default:
                placeholder = nil
            }
            let previous = navigation.viewControllers
            if previous != screens {
                let keepDetailRoot = previous.first?.ukRoute != nil && previous.first === screens.first
                navigation.setViewControllers(screens, animated: animated && keepDetailRoot && previous.count != screens.count)
            }
            pane = navigation
        } else {
            placeholder = nil
        }
        setTrailingController(pane)
        if let page = leading.topViewController { installLeadingChrome(on: page, navigation: leading) }
        if let pane, let page = pane.topViewController { installTrailingChrome(on: page, navigation: pane) }
        applyFrames(animated: animated && (hadTrailingPane != (pane != nil) || wasCovered != (cut?.cover == .overSplit)))
        let open = isDetailOpen
        if open != reportedOpen {
            reportedOpen = open
            onSplitOpenChanged?(open)
        }
        host.stackDidChangePath(self)
    }

    private func applyFrames(animated: Bool) {
        let panes = geometry.map {
            FentonSplitGeometry(leadingWidth: $0.leadingWidth, bandWidth: $0.dividerWidth,
                                trailingWidth: $0.trailingWidth, isHinge: $0.isHinge)
        }
        let contrast = UKAccessibility.systemIncreasedContrast(traitCollection) || UKAccessibility.moreContrast
        let close = trailing?.viewControllers.first?.navigationItem.leftBarButtonItem
        if close?.accessibilityIdentifier == "fst.split.close" {
            let tint = contrast ? BrandUIColors.textPrimary : BrandUIColors.accentBlue
            if close?.tintColor != tint { close?.tintColor = tint }
        }
        let drawsLine = geometry.map { OnDemandSplitPolicy.drawsDividerLine($0, increasedContrast: contrast) } ?? false
        let animate: ((@escaping () -> Void) -> Void)? = animated ? { apply in self.animatePaneChange(apply) } : nil
        layoutPanes(
            geometry: panes, coversLeading: cut?.cover == .overSplit,
            dividerColor: drawsLine ? UIColor.white.withAlphaComponent(0.16) : nil,
            animate: animate
        )
    }

    private func animatePaneChange(_ apply: @escaping () -> Void) {
        let reduce = UIAccessibility.isReduceMotionEnabled || UKSettings.bool("fst.accessibility.reduceMotion", default: false)
        if reduce {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut], animations: apply)
        } else {
            UIView.animate(
                withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                options: [], animations: apply
            )
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !applyWindowShape() { applyFrames(animated: false) }
        applyPageSafeAreas()
    }

    /// Removes the window rail inset that UIKit passes to pages at the divider.
    /// The scroll view and navigation contents still respect their own pane's safe area.
    private func applyPageSafeAreas() {
        let isSideBySide = trailing != nil && geometry != nil && cut?.cover != .overSplit
        let windowInsets = host.stackLayout.sectionChrome.isVerticalBar ? view.safeAreaInsets : .zero

        func update(_ navigation: UINavigationController, dividerAtRight: Bool) {
            guard let page = navigation.topViewController, let pageView = page.viewIfLoaded else { return }
            let current = page.additionalSafeAreaInsets
            let observed = pageView.safeAreaInsets
            let pane = navigation.view.safeAreaInsets
            var next = current
            next.left = isSideBySide && !dividerAtRight
                ? -min(windowInsets.left, max(0, observed.left - current.left - pane.left)) : 0
            next.right = isSideBySide && dividerAtRight
                ? -min(windowInsets.right, max(0, observed.right - current.right - pane.right)) : 0
            if next != current { page.additionalSafeAreaInsets = next }
        }

        update(leading, dividerAtRight: !rightToLeft)
        if let trailing { update(trailing, dividerAtRight: rightToLeft) }
    }

    /// Re-evaluates the shape after the shell published a new layout.
    func layoutDidChange() {
        let floats = ukShell?.floatsPageTools == true
        leading.topViewController?.ukRefreshPageTitlePlacement(floatsPageTools: floats)
        trailing?.topViewController?.ukRefreshPageTitlePlacement(floatsPageTools: floats)
        view.setNeedsLayout()
    }

    private func applyWindowShape(deferIfNeeded: Bool = true) -> Bool {
        guard !applyingPath, !windowChangePending else { return false }
        let shape = windowGeometry
        let next = OnDemandSplitPolicy.WindowState(
            measured: view.window != nil && view.bounds.width > 0, allowsSplit: shape != nil
        )
        if deferIfNeeded, OnDemandSplitPolicy.defersWindowChange(from: appliedWindowState, to: next) {
            windowChangePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.windowChangePending = false
                _ = self.applyWindowShape(deferIfNeeded: false)
            }
            return false
        }
        appliedWindowState = next
        guard appliedWindowGeometry != shape else { return false }
        appliedWindowGeometry = shape
        if let geometry, let shape, geometry.isHinge != shape.isHinge, let trailing, cut?.cover != .overSplit {
            // The hinge's UIKit transaction can animate pane bounds after AX has published the new frame.
            UIView.performWithoutAnimation {
                reshape(animated: false)
                applyPageSafeAreas()
                leading.view.layoutIfNeeded()
                trailing.view.layoutIfNeeded()
            }
        } else {
            reshape(animated: false)
        }
        return true
    }

    // MARK: Navigation delegate

    func navigationController(
        _ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool
    ) {
        viewController.ukRefreshPageTitlePlacement(floatsPageTools: ukShell?.floatsPageTools == true)
        host.stackWillShow(viewController, in: self, navigation: navigationController)
        if navigationController === trailing { installTrailingChrome(on: viewController, navigation: navigationController) }
        if navigationController === leading { installLeadingChrome(on: viewController, navigation: navigationController) }
    }

    func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        guard !applyingPath else { return }
        if navigationController === leading, let cut {
            // The leading pane popped (Back or edge swipe): its open item closes with it.
            let newList = Array(leading.viewControllers.dropFirst().compactMap(\.ukRoute))
            if newList != cut.list { reshape(path: newList, animated: false); return }
        }
        if navigationController === trailing, let cut {
            let detail = navigationController.viewControllers.compactMap(\.ukRoute)
            if detail != cut.detail { reshape(path: cut.list + detail, animated: animated); return }
        }
        host.stackDidChangePath(self)
    }

    /// The split's Close button on the open item's root.
    private func installTrailingChrome(on controller: UIViewController, navigation: UINavigationController) {
        guard controller === navigation.viewControllers.first, controller.ukRoute != nil else { return }
        guard controller.navigationItem.leftBarButtonItem?.accessibilityIdentifier != "fst.split.close" else { return }
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
        let item = controller.navigationItem
        let hasSplitBack = item.leftBarButtonItem?.accessibilityIdentifier == "fst.split.list-back"
        guard cut?.selection != nil, controller === navigation.viewControllers.last, controller.ukRoute != nil else {
            if hasSplitBack {
                item.leftBarButtonItem = nil
                item.hidesBackButton = false
            }
            return
        }
        guard !hasSplitBack else { return }
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
        let state = UKEmptyStateView(
            info.title, systemImage: info.systemImage, subtitle: info.subtitle, identifier: info.accessibilityIdentifier
        )
        view.addSubview(state)
        let region = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            state.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            state.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            state.topAnchor.constraint(equalTo: region.topAnchor),
            state.bottomAnchor.constraint(equalTo: region.bottomAnchor),
        ])
    }
}
#endif
