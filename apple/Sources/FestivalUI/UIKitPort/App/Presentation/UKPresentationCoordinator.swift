#if os(iOS)
import PhotosUI
import QuickLook
import UIKit

// MARK: - Presentation coordinator

/// The result of asking a window to present an independent task.
@MainActor
enum UKPresentationRequestResult: Equatable {
    /// The controller was admitted and is being presented.
    case presented
    /// An automatic request owns the single bounded waiting slot.
    case queued
    /// An explicit request was not admitted; the caller remains unchanged.
    case rejected
}

/// Coordinates one independent native presentation lifecycle per window.
///
/// Alerts, photo pickers, document pickers and Quick Look are related presentations owned by
/// the active task and may be presented above it. Independent tasks never nest. Automatic
/// requests have one bounded waiting slot so a first-run guide is not lost behind a user-owned
/// task; the weak presenter and deferred builder make a stale request disposable when its page leaves.
@MainActor
final class UKPresentationCoordinator: NSObject {
    private weak var activeController: UIViewController?
    private var pendingAutomatic: PendingAutomatic?
    private var isPresenting = false
    private var activeFinish: (() -> Void)?
    private var visibilityObserver: UKMotionVisibilityObserver?

    private struct PendingAutomatic {
        weak var presenter: UIViewController?
        let build: () -> UIViewController?
        let onDismiss: (() -> Void)?
    }

    private override init() {
        super.init()
        visibilityObserver = UKMotionVisibilityObserver { [weak self] in
            self?.drainAutomatic(for: nil)
        }
    }

    // MARK: Lookup

    private static var associationKey: UInt8 = 0

    /// Returns the coordinator for the presenter's window, or for the presenter before it has
    /// joined a window.
    static func shared(for presenter: UIViewController) -> UKPresentationCoordinator {
        let owner: AnyObject = presenter.viewIfLoaded?.window ?? presenter
        if let coordinator = objc_getAssociatedObject(owner, &associationKey) as? UKPresentationCoordinator {
            return coordinator
        }
        let coordinator = UKPresentationCoordinator()
        objc_setAssociatedObject(owner, &associationKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return coordinator
    }

    /// Whether an explicit task can be presented now.
    func canPresentIndependent(from presenter: UIViewController) -> Bool {
        pendingAutomatic == nil && isReadyForIndependent(from: presenter)
    }

    private func isReadyForIndependent(from presenter: UIViewController) -> Bool {
        guard activeController == nil, !isPresenting, isVisiblePresenter(presenter) else { return false }
        var current: UIViewController? = presenter
        while let controller = current {
            guard controller.presentedViewController == nil,
                  controller.presentingViewController == nil,
                  controller.transitionCoordinator == nil else { return false }
            current = controller.parent
        }
        return true
    }

    private func isVisiblePresenter(_ presenter: UIViewController) -> Bool {
        guard let view = presenter.viewIfLoaded,
              let window = view.window,
              window.windowScene?.activationState == .foregroundActive,
              !view.isHidden else { return false }
        var current = presenter
        while let parent = current.parent {
            if let navigation = parent as? UINavigationController,
               navigation.visibleViewController !== current { return false }
            if let tab = parent as? UITabBarController,
               tab.selectedViewController !== current { return false }
            if parent.viewIfLoaded?.isHidden == true { return false }
            current = parent
        }
        return current === window.rootViewController || current.presentingViewController != nil
    }

    /// Cancels an automatic request owned by a page that is no longer visible.
    func cancelAutomatic(from presenter: UIViewController) {
        guard pendingAutomatic?.presenter === presenter else { return }
        pendingAutomatic = nil
    }

    // MARK: Independent tasks

    /// Presents one independent task. A rejected request leaves the caller's state untouched.
    @discardableResult
    func presentIndependent(
        _ controller: UIViewController,
        from presenter: UIViewController,
        animated: Bool = true,
        onDismiss: (() -> Void)? = nil,
        completion: (() -> Void)? = nil
    ) -> UKPresentationRequestResult {
        guard !(controller is UIAlertController), canPresentIndependent(from: presenter) else { return .rejected }
        activeController = controller
        isPresenting = true
        installDismissObservation(on: controller, onDismiss: onDismiss)
        presenter.present(controller, animated: animated) { [weak self] in
            self?.isPresenting = false
            completion?()
            UKMotionVisibility.changed()
        }
        return .presented
    }

    /// Presents an automatic task now, or retains one bounded builder until the current
    /// independent task has completed its actual native dismissal.
    @discardableResult
    func presentAutomatic(
        from presenter: UIViewController,
        build: @escaping () -> UIViewController?,
        onDismiss: (() -> Void)? = nil
    ) -> UKPresentationRequestResult {
        guard isVisiblePresenter(presenter) else { return .rejected }
        if let pending = pendingAutomatic {
            if pending.presenter?.viewIfLoaded?.window != nil { return .rejected }
            pendingAutomatic = nil
        }
        if isReadyForIndependent(from: presenter) {
            guard let controller = build() else { return .rejected }
            return presentIndependent(controller, from: presenter, onDismiss: onDismiss)
        }
        pendingAutomatic = PendingAutomatic(presenter: presenter, build: build, onDismiss: onDismiss)
        armAutomaticReadiness(for: presenter)
        return .queued
    }

    /// Presents a related system controller above the active task.
    @discardableResult
    func presentRelated(
        _ controller: UIViewController,
        from presenter: UIViewController,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> Bool {
        guard isVisiblePresenter(presenter),
              presenter.presentedViewController == nil,
              presenter.transitionCoordinator == nil
        else { return false }
        presenter.present(controller, animated: animated) {
            completion?()
            UKMotionVisibility.changed()
        }
        installRelatedDismissObservation(on: controller) { [weak self, weak presenter] in
            UKMotionVisibility.changed()
            if let presenter { self?.drainAutomatic(for: presenter) }
        }
        return true
    }

    /// Dismisses a task through UIKit and waits for its native completion.
    func dismiss(
        _ controller: UIViewController,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        let finish = {
            completion?()
            if self.activeController === controller { self.activeFinish?() }
            UKMotionVisibility.changed()
        }
        if let sheet = controller as? UKSheetNavigationController {
            sheet.dismissFromPresenter(animated: animated, completion: finish)
        } else {
            controller.navigationItem.searchController?.isActive = false
            for page in (controller as? UINavigationController)?.viewControllers ?? [] {
                page.navigationItem.searchController?.isActive = false
            }
            controller.viewIfLoaded?.endEditing(true)
            let presenter = controller.presentingViewController ?? controller
            presenter.dismiss(animated: animated, completion: finish)
        }
    }

    // MARK: Dismissal

    private func installDismissObservation(
        on controller: UIViewController,
        onDismiss: (() -> Void)?
    ) {
        let finish = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.finishAfterNativeDismissal(controller, onDismiss: onDismiss)
        }
        activeFinish = finish
        if let sheet = controller as? UKSheetNavigationController {
            sheet.ukObserveDismissal(finish)
            installDismissDelegate(on: sheet, finish: finish)
        } else {
            installLifecycleProbe(on: controller, onDisappear: finish)
            installDismissDelegate(on: controller, finish: finish)
        }
    }

    private func installDismissDelegate(on controller: UIViewController, finish: @escaping () -> Void) {
        guard !(controller is UIAlertController) else { return }
        let presentationController = controller.presentationController
        let original = presentationController?.delegate
        let proxy = UKPresentationDelegateProxy(original: original, onDismiss: finish)
        objc_setAssociatedObject(controller, &dismissObserverKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let presentationController {
            presentationController.delegate = proxy
        } else {
            DispatchQueue.main.async { [weak controller, weak proxy] in
                controller?.presentationController?.delegate = proxy
            }
        }
    }

    private func installRelatedDismissObservation(
        on controller: UIViewController, onDismiss: @escaping () -> Void
    ) {
        guard !(controller is UIAlertController) else { return }
        let proxy = UKPresentationDelegateProxy(original: controller.presentationController?.delegate, onDismiss: onDismiss)
        if let presentationController = controller.presentationController {
            objc_setAssociatedObject(
                controller, &relatedDismissObserverKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            presentationController.delegate = proxy
        } else {
            objc_setAssociatedObject(
                controller, &relatedDismissObserverKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            DispatchQueue.main.async { [weak controller, weak proxy] in
                controller?.presentationController?.delegate = proxy
            }
        }
    }

    private func installLifecycleProbe(on controller: UIViewController, onDisappear: @escaping () -> Void) {
        guard !(controller is UIAlertController || controller is PHPickerViewController
                || controller is UIDocumentPickerViewController || controller is UIImagePickerController
                || controller is QLPreviewController) else { return }
        controller.loadViewIfNeeded()
        guard let view = controller.viewIfLoaded else { return }
        if let probe = objc_getAssociatedObject(view, &lifecycleProbeKey) as? UKPresentationLifecycleProbe {
            probe.add(onDisappear)
            return
        }
        let probe = UKPresentationLifecycleProbe(onDisappear: onDisappear)
        probe.frame = .zero
        probe.isHidden = true
        probe.isAccessibilityElement = false
        view.addSubview(probe)
        objc_setAssociatedObject(view, &lifecycleProbeKey, probe, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func armAutomaticReadiness(for presenter: UIViewController) {
        var current: UIViewController? = presenter
        var foreign: UIViewController?
        while let controller = current {
            if let presented = controller.presentedViewController {
                foreign = presented
                break
            }
            current = controller.parent
        }
        if let foreign {
            if !(foreign is UIAlertController) {
                installLifecycleProbe(on: foreign) { [weak self, weak presenter] in
                    guard let presenter else { return }
                    self?.drainAutomatic(for: presenter)
                }
            }
            if let transition = foreign.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { [weak self, weak presenter] _ in
                    guard let presenter else { return }
                    self?.drainAutomatic(for: presenter)
                }
            }
        } else if let transition = presenter.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self, weak presenter] _ in
                guard let presenter else { return }
                self?.drainAutomatic(for: presenter)
            }
        }
    }

    private func didDismiss(_ controller: UIViewController, onDismiss: (() -> Void)?) {
        guard activeController === controller else { return }
        activeController = nil
        isPresenting = false
        activeFinish = nil
        onDismiss?()
        UKMotionVisibility.changed()
        drainAutomatic(for: nil)
    }

    private func finishAfterNativeDismissal(_ controller: UIViewController, onDismiss: (() -> Void)?) {
        let finish = { [weak self, weak controller] in
            guard let self, let controller, controller.presentingViewController == nil else { return }
            self.didDismiss(controller, onDismiss: onDismiss)
        }
        if controller.presentingViewController == nil {
            finish()
        } else if let transition = controller.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { context in
                if !context.isCancelled { finish() }
            }
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }

    private func drainAutomatic(for presenter: UIViewController?) {
        guard let pending = pendingAutomatic else { return }
        guard let source = pending.presenter,
              source.viewIfLoaded?.window != nil
        else {
            pendingAutomatic = nil
            return
        }
        guard presenter == nil || presenter === source else { return }
        guard isReadyForIndependent(from: source) else {
            armAutomaticReadiness(for: source)
            return
        }
        pendingAutomatic = nil
        guard let controller = pending.build() else { return }
        let result = presentIndependent(controller, from: source, onDismiss: pending.onDismiss)
        if result == .rejected {
            pendingAutomatic = pending
            armAutomaticReadiness(for: source)
        }
    }
}

nonisolated(unsafe) private var dismissObserverKey: UInt8 = 0
nonisolated(unsafe) private var relatedDismissObserverKey: UInt8 = 0
nonisolated(unsafe) private var lifecycleProbeKey: UInt8 = 0

@MainActor
private final class UKPresentationLifecycleProbe: UIView {
    private var callbacks: [() -> Void]
    private var enteredWindow = false
    private var fired = false

    init(onDisappear: @escaping () -> Void) {
        callbacks = [onDisappear]
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func add(_ callback: @escaping () -> Void) {
        callbacks.append(callback)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            enteredWindow = true
            fired = false
        } else if enteredWindow, !fired {
            fired = true
            callbacks.forEach { $0() }
            callbacks.removeAll()
        }
    }
}

@MainActor
private final class UKPresentationDelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var original: UIAdaptivePresentationControllerDelegate?
    private let onDismiss: () -> Void

    init(original: UIAdaptivePresentationControllerDelegate?, onDismiss: @escaping () -> Void) {
        self.original = original
        self.onDismiss = onDismiss
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) == true)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        original?.presentationControllerShouldDismiss?(presentationController) ?? true
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerWillDismiss?(presentationController)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidDismiss?(presentationController)
        onDismiss()
    }
}
#endif
