#if os(iOS)
import UIKit

// MARK: - Screen foundation

/// The explicit UIKit lifecycle seam used by Festival screens.
///
/// UIKit does not provide a safe application-wide lifecycle hook for every view controller.
/// Screens opt in by inheriting this class; the first-run coordinator receives only the
/// controller instances that actually become visible.
@MainActor
class UKScreenViewController: UIViewController {
    private weak var presentationCoordinator: UKPresentationCoordinator?
    private let paneFocusAnchor = AccessibilityFocusAnchor.AnchorView()
    private var pendingPaneFocus: AccessibilityFocusRequest?
    private var paneFocusToken = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        paneFocusAnchor.translatesAutoresizingMaskIntoConstraints = false
        paneFocusAnchor.isUserInteractionEnabled = false
        paneFocusAnchor.isAccessibilityElement = false
        view.addSubview(paneFocusAnchor)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            paneFocusAnchor.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            paneFocusAnchor.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            paneFocusAnchor.topAnchor.constraint(equalTo: guide.topAnchor),
            paneFocusAnchor.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationCoordinator = UKPresentationCoordinator.shared(for: self)
        UKFirstRunHook.pageDidAppear(self)
        UKMotionVisibility.changed()
        movePendingPaneFocus()
    }

    override func viewDidDisappear(_ animated: Bool) {
        if let viewIfLoaded { UKFadeIn.finishAnimations(in: viewIfLoaded) }
        super.viewDidDisappear(animated)
        presentationCoordinator?.cancelAutomatic(from: self)
        presentationCoordinator = nil
        pendingPaneFocus = nil
        UKFirstRunHook.pageDidDisappear(self)
        UKMotionVisibility.changed()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        movePendingPaneFocus()
    }

    /// Requests focus on the pane's actual heading after a user opens a different detail.
    func requestPaneFocus() {
        guard UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
                || AccessibilityFocusTrace.isEnabled else { return }
        paneFocusToken += 1
        pendingPaneFocus = AccessibilityFocusRequest(target: .topHeading, token: paneFocusToken)
        movePendingPaneFocus()
    }

    /// Retries a pending move when its native heading has actually laid out.
    func movePendingPaneFocus() {
        guard let request = pendingPaneFocus, let window = viewIfLoaded?.window else { return }
        let pane = navigationController?.viewIfLoaded
        let region = pane.map { $0.convert($0.bounds, to: window.screen.coordinateSpace) }
        if paneFocusAnchor.move(request, in: region) { pendingPaneFocus = nil }
    }
}
#endif
