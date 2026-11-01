#if os(iOS)
import FestivalCore
import FestivalDesign
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
    private let closeAction: (() -> Void)?
    private let sheetTitle: String?
    private var fades: [ObjectIdentifier: UKModalTopEdgeFade] = [:]
    private var backdrop: UIView?
    private var observer: UKAccessibilityObserver?
    private var registeredCoverage = false

    /// Creates the sheet's stack.
    ///
    /// - Parameters:
    ///   - root: The first page.
    ///   - title: Inline title, or nil for none.
    ///   - closeIdentifier: Accessibility identifier of the Close button.
    ///   - onClose: Replaces the default dismissal.
    init(root: UIViewController, title: String?, closeIdentifier: String, onClose: (() -> Void)? = nil) {
        self.closeIdentifier = closeIdentifier
        self.closeAction = onClose
        self.sheetTitle = title
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
        let close: UIBarButtonItem
        let action = UIAction { [weak self] _ in self?.close() }
        if #available(iOS 26.0, *) {
            close = UIBarButtonItem(systemItem: .close, primaryAction: action)
        } else {
            close = UIBarButtonItem(title: "Close", primaryAction: action)
            close.style = .done
        }
        close.accessibilityLabel = "Close"
        close.accessibilityIdentifier = closeIdentifier
        controller.navigationItem.rightBarButtonItem = close
    }

    private func close() {
        if let closeAction { closeAction() } else { dismiss(animated: true) }
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
        if !registeredCoverage {
            registeredCoverage = true
            FestivalSheetCoverage.shared.begin()
        }
        installFade(for: topViewController)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if registeredCoverage && (isBeingDismissed || presentingViewController == nil) {
            registeredCoverage = false
            FestivalSheetCoverage.shared.end()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fades.values.forEach { $0.layout() }
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if viewController !== viewControllers.first { viewController.navigationItem.largeTitleDisplayMode = .never }
        viewController.view.backgroundColor = viewController.view.backgroundColor ?? .clear
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        installFade(for: viewController)
    }

    private func installFade(for controller: UIViewController?) {
        guard let provider = controller as? any UKModalScrollProviding, let scroll = provider.ukModalScrollView,
              fades[ObjectIdentifier(provider)] == nil else { return }
        let fade = UKModalTopEdgeFade(maskedView: provider.view, scrollView: scroll)
        fades[ObjectIdentifier(provider)] = fade
        fade.layout()
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
        let navigation = UKSheetNavigationController(root: content, title: title, closeIdentifier: closeIdentifier, onClose: onClose)
        switch coverage {
        case .fullScreen:
            navigation.modalPresentationStyle = .fullScreen
            navigation.view.backgroundColor = BrandUIColors.cardBackground
        case .sheet:
            navigation.modalPresentationStyle = presentationStyle(sizing: sizing, regularWidth: regularWidth)
            if let sheet = navigation.sheetPresentationController {
                sheet.detents = size == .compact ? [.medium(), .large()] : [.large()]
                sheet.prefersGrabberVisible = size == .compact
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
        presenter.present(sheet, animated: true, completion: completion)
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
