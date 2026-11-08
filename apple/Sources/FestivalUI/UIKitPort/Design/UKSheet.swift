#if os(iOS)
import FestivalCore
import FestivalDesign
import FentonUIKit
import UIKit

// MARK: - Scroll provider

/// A sheet page that has a scroll view whose offset drives the top edge fade under the
/// modal header (``ModalTopEdgeFadeModifier``).
@MainActor
protocol UKModalScrollProviding: UIViewController {
    /// The page's main scroll view (a collection or table view is one), or nil.
    var ukModalScrollView: UIScrollView? { get }
}

// MARK: - Sheet navigation controller

/// The inside of a Festival sheet (``FestivalModal`` + ``View/festivalSheet(_:sizing:)``):
/// a navigation stack with a transparent bar, an inline title and a Close button
/// (the system close button on iOS 26, a "Close" text button before), dark appearance,
/// accent-blue tint, the sheet background (Liquid Glass on iOS 26; the frosted material
/// and `cardBackground` tint before it; opaque `cardBackground` under Reduce
/// Transparency or the in-app toggles) and the top edge fade under the header.
final class UKSheetNavigationController: UINavigationController, UINavigationControllerDelegate {
    private let closeIdentifier: String
    private var closeAction: (() -> Void)?
    private let sheetTitle: String?
    private let sizing: FestivalSheetSizing
    private var fades: [ObjectIdentifier: UKModalTopEdgeFade] = [:]
    private var backdrop: UIView?
    private var observer: UKAccessibilityObserver?
    private var registeredCoverage = false
    private var isPopping = false
    private var isClosing = false
    private var didNotifyDismissal = false
    var ukOnDismiss: (() -> Void)?
    private var ukDismissObservers: [() -> Void] = []

    /// Creates the sheet's stack.
    ///
    /// - Parameters:
    ///   - root: The first page.
    ///   - title: Inline title, or nil for none.
    ///   - closeIdentifier: Accessibility identifier of the Close button.
    ///   - onClose: Replaces the default dismissal.
    init(
        root: UIViewController, title: String?, closeIdentifier: String,
        sizing: FestivalSheetSizing = .automatic, onClose: (() -> Void)? = nil
    ) {
        self.closeIdentifier = closeIdentifier
        self.closeAction = onClose
        self.sheetTitle = title
        self.sizing = sizing
        super.init(rootViewController: root)
        delegate = self
        overrideUserInterfaceStyle = .dark
        view.tintColor = BrandUIColors.accentBlue
        configureBar(for: root)
        applyBackground()
        observer = UKAccessibilityObserver { [weak self] in self?.applyBackground() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Chrome

    private func configureBar(for controller: UIViewController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: BrandUIColors.textPrimary]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.prefersLargeTitles = false
        decorate(controller)
    }

    /// Gives a page the sheet's title mode and, on the first page, title and Close.
    private func decorate(_ controller: UIViewController) {
        controller.navigationItem.largeTitleDisplayMode = .never
        guard controller === viewControllers.first else { return }
        if let sheetTitle { controller.navigationItem.title = sheetTitle }
        let alreadyHasClose = (controller.navigationItem.leftBarButtonItems ?? [])
            .contains { $0.accessibilityIdentifier == closeIdentifier }
            || (controller.navigationItem.rightBarButtonItems ?? [])
            .contains { $0.accessibilityIdentifier == closeIdentifier }
        guard !alreadyHasClose else { return }
        let close: UIBarButtonItem
        let action = UIAction { [weak self] _ in self?.ukCloseFromChrome() }
        if #available(iOS 26.0, *) {
            close = UIBarButtonItem(systemItem: .close, primaryAction: action)
        } else {
            close = UIBarButtonItem(title: "Close", primaryAction: action)
            close.style = .done
        }
        close.accessibilityLabel = "Close"
        close.accessibilityIdentifier = closeIdentifier
        // UIKit lays out rightBarButtonItems from index zero at the trailing edge.
        // Keep Close there while preserving feature-owned actions beside it.
        let featureItems = (controller.navigationItem.rightBarButtonItems ?? [])
            .filter { $0.accessibilityIdentifier != closeIdentifier }
        controller.navigationItem.rightBarButtonItems = [close] + featureItems
    }

    /// Performs the shell's Close action, including stack-pop and app-owned close callbacks.
    func ukCloseFromChrome() {
        guard !isPopping, !isClosing else { return }
        if viewControllers.count > 1 {
            guard !isBeingPresented, !isBeingDismissed, transitionCoordinator == nil else { return }
            isPopping = true
            if popViewController(animated: true) == nil {
                isPopping = false
            }
            return
        }
        guard !isBeingPresented, !isBeingDismissed,
              !(presentedViewController is UIAlertController) else { return }
        if let closeAction {
            isClosing = true
            closeAction()
        } else {
            isClosing = true
            dismissFromPresenter(animated: true)
        }
    }

    /// Rearms an app-owned Close callback after it keeps an in-progress task open.
    func ukRearmClose() {
        isClosing = false
        UKMotionVisibility.changed()
    }

    /// Adds an observer for the sheet's actual native dismissal.
    func ukObserveDismissal(_ observer: @escaping () -> Void) {
        ukDismissObservers.append(observer)
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
            UIKeyCommand(input: ".", modifierFlags: .command, action: #selector(handleEscape)),
        ]
    }

    @objc private func handleEscape(_ command: UIKeyCommand) {
        ukCloseFromChrome()
    }

    override func accessibilityPerformEscape() -> Bool {
        ukCloseFromChrome()
        return true
    }

    /// Dismisses the complete modal presentation, including a feature-owned controller such as
    /// an active `UISearchController`.
    func dismissFromPresenter(animated: Bool, completion: (() -> Void)? = nil) {
        for controller in viewControllers {
            controller.navigationItem.searchController?.isActive = false
        }
        view.endEditing(true)
        let finish: () -> Void = { [weak self] in
            self?.finishDismissalIfNeeded()
            completion?()
        }
        if let presenter = presentingViewController {
            presenter.dismiss(animated: animated, completion: finish)
        } else {
            dismiss(animated: animated, completion: finish)
        }
    }

    // MARK: Background

    private func applyBackground() {
        backdrop?.removeFromSuperview()
        backdrop = nil
        view.backgroundColor = nil
        if UKAccessibility.lessTransparency || UKAccessibility.moreContrast || UKAccessibility.systemReduceTransparency {
            view.backgroundColor = BrandUIColors.cardBackground
        } else if !FestivalGlassSurface.glassAvailable {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            let tint = UIView()
            tint.backgroundColor = BrandUIColors.cardBackground.withAlphaComponent(FestivalSheetBackground.frostedTintOpacity)
            blur.contentView.addSubview(tint)
            tint.frame = blur.bounds
            tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.frame = view.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.isUserInteractionEnabled = false
            view.insertSubview(blur, at: 0)
            backdrop = blur
        }
    }

    // MARK: Lifecycle

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let root = viewControllers.first {
            root.loadViewIfNeeded()
            decorate(root)
        }
        if !registeredCoverage {
            registeredCoverage = true
            FestivalSheetCoverage.shared.begin()
        }
        installFade(for: topViewController)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if registeredCoverage && (isBeingDismissed || presentingViewController == nil) {
            finishDismissalIfNeeded()
        }
        pruneFades()
    }

    private func finishDismissalIfNeeded() {
        if registeredCoverage {
            registeredCoverage = false
            FestivalSheetCoverage.shared.end()
        }
        guard !didNotifyDismissal else { return }
        didNotifyDismissal = true
        closeAction = nil
        ukOnDismiss?()
        ukOnDismiss = nil
        let observers = ukDismissObservers
        ukDismissObservers.removeAll()
        observers.forEach { $0() }
    }

    /// Adapts only an automatic sheet to the presenter that owns its window.
    func ukAdaptPresentationStyle(regularWidth: Bool) {
        guard sizing == .automatic, presentingViewController == nil else { return }
        modalPresentationStyle = regularWidth ? .formSheet : .pageSheet
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fades.values.forEach { $0.layout() }
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if viewController !== viewControllers.first { viewController.navigationItem.largeTitleDisplayMode = .never }
        viewController.view.backgroundColor = viewController.view.backgroundColor ?? .clear
        if viewController === viewControllers.first {
            viewController.loadViewIfNeeded()
            decorate(viewController)
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        isPopping = false
        installFade(for: viewController)
        pruneFades()
    }

    private func installFade(for controller: UIViewController?) {
        guard let provider = controller as? any UKModalScrollProviding, let scroll = provider.ukModalScrollView,
              fades[ObjectIdentifier(provider)] == nil else { return }
        let fade = UKModalTopEdgeFade(maskedView: provider.view, scrollView: scroll)
        fades[ObjectIdentifier(provider)] = fade
        fade.layout()
    }

    private func pruneFades() {
        let liveControllers = Set(viewControllers.map { ObjectIdentifier($0) })
        let staleIdentifiers = fades.keys.filter { !liveControllers.contains($0) }
        for identifier in staleIdentifiers {
            fades[identifier]?.remove()
            fades.removeValue(forKey: identifier)
        }
    }
}

// MARK: - Presentation

/// Presents content in a Festival sheet or full-screen cover
/// (``FestivalSheetModifier``, ``FestivalModalPresentation``).
@MainActor
enum UKSheet {
    /// The sheet's navigation controller around `content`, configured but not presented.
    ///
    /// - Parameters:
    ///   - content: The page to show.
    ///   - title: Inline title, or nil.
    ///   - closeIdentifier: Close button identifier.
    ///   - size: `compact` (medium and large detents with a grabber) or `large`.
    ///   - sizing: Page / form sizing (iOS 18+; the Duo / iPad regular-width rule).
    ///   - regularWidth: Whether the window is regular width.
    ///   - coverage: `sheet`, or `fullScreen` (opaque card background).
    ///   - onClose: Replaces the default dismissal.
    /// - Returns: The controller to present.
    static func make(
        _ content: UIViewController, title: String?, closeIdentifier: String, size: FestivalSheetSize = .large,
        sizing: FestivalSheetSizing = .automatic, regularWidth: Bool = false,
        coverage: FestivalModalCoverage = .sheet, onClose: (() -> Void)? = nil
    ) -> UKSheetNavigationController {
        let navigation = UKSheetNavigationController(
            root: content, title: title, closeIdentifier: closeIdentifier, sizing: sizing, onClose: onClose
        )
        switch coverage {
        case .fullScreen:
            navigation.modalPresentationStyle = .fullScreen
            navigation.view.backgroundColor = BrandUIColors.cardBackground
        case .sheet:
            let usesSharedNativeSizing = sizing == .page || sizing == .regularPage
            if usesSharedNativeSizing {
                FentonSheetPresenter.configure(
                    navigation,
                    configuration: .init(
                        heightPolicy: size == .compact ? .mediumAndLarge : .large,
                        showsGrabber: size == .compact
                    )
                )
            } else {
                navigation.modalPresentationStyle = presentationStyle(sizing: sizing, regularWidth: regularWidth)
                if let sheet = navigation.sheetPresentationController {
                    sheet.detents = size == .compact ? [.medium(), .large()] : [.large()]
                    sheet.prefersGrabberVisible = size == .compact
                }
            }
            if let sheet = navigation.sheetPresentationController {
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            }
        }
        return navigation
    }

    /// Presents `content` in a sheet from `presenter`.
    ///
    /// - Parameters:
    ///   - content: The page to show.
    ///   - presenter: The controller to present from.
    ///   - title: Inline title, or nil.
    ///   - closeIdentifier: Close button identifier.
    ///   - size: `compact` or `large`.
    ///   - sizing: Page / form sizing.
    ///   - coverage: `sheet` or `fullScreen`.
    ///   - onClose: Replaces the default dismissal.
    ///   - completion: Called when the presentation finishes.
    /// - Returns: The presented sheet.
    @discardableResult
    static func present(
        _ content: UIViewController, from presenter: UIViewController, title: String?, closeIdentifier: String,
        size: FestivalSheetSize = .large, sizing: FestivalSheetSizing = .automatic,
        coverage: FestivalModalCoverage = .sheet, onClose: (() -> Void)? = nil, completion: (() -> Void)? = nil
    ) -> UKSheetNavigationController {
        let regular = presenter.traitCollection.horizontalSizeClass == .regular
        // The sheet's glass chrome takes its style from the window, which the app delegate
        // makes dark at launch; this covers a window created elsewhere (the Design gallery).
        presenter.view.window?.overrideUserInterfaceStyle = .dark
        let sheet = make(
            content, title: title, closeIdentifier: closeIdentifier, size: size, sizing: sizing,
            regularWidth: regular, coverage: coverage, onClose: onClose
        )
        _ = UKPresentationCoordinator.shared(for: presenter).presentIndependent(
            sheet, from: presenter, animated: true, completion: completion
        )
        return sheet
    }

    /// The presentation style for a sizing choice (`presentationSizing`): `.form` at regular
    /// width for `automatic`, `.page` for `page`, `.page` at regular width for `regularPage`.
    ///
    /// - Parameters:
    ///   - sizing: The sizing choice.
    ///   - regularWidth: Whether the window is regular width.
    static func presentationStyle(sizing: FestivalSheetSizing, regularWidth: Bool) -> UIModalPresentationStyle {
        switch sizing {
        case .page: .pageSheet
        case .automatic: regularWidth ? .formSheet : .pageSheet
        case .regularPage: .pageSheet
        }
    }
}

// MARK: - Pull down to dismiss

/// Dismisses a sheet when the user pulls its scroll view down past 80 pt and lets go
/// (``PullDownToDismiss``).
@MainActor
final class UKPullDownToDismiss {
    private var offsetObservation: NSKeyValueObservation?
    private var stateObservation: NSKeyValueObservation?
    private var maxPull: CGFloat = 0
    private var fired = false

    /// Starts watching.
    ///
    /// - Parameters:
    ///   - scrollView: The sheet's scroll view.
    ///   - action: Called once when the pull qualifies.
    init(scrollView: UIScrollView, action: @escaping @MainActor () -> Void) {
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            MainActor.assumeIsolated {
                self?.maxPull = max(self?.maxPull ?? 0, -(scroll.contentOffset.y + scroll.adjustedContentInset.top))
            }
        }
        stateObservation = scrollView.panGestureRecognizer.observe(\.state, options: [.new]) { [weak self] pan, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch pan.state {
                case .began: self.maxPull = 0
                case .ended, .cancelled:
                    if PullDownToDismiss.shouldDismiss(pull: self.maxPull), !self.fired {
                        self.fired = true
                        action()
                    }
                    self.maxPull = 0
                default: break
                }
            }
        }
    }
}
#endif
