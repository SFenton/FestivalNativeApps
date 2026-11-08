#if os(iOS)
import UIKit

/// One visibility policy for decorative motion, without per-frame polling.
@MainActor
enum UKMotionVisibility {
    static let didChange = Notification.Name("fst.uikit.motion-visibility")

    /// Reports whether a component is visible, active and not behind a presented task.
    ///
    /// - Parameter view: The component whose native animation would run.
    /// - Returns: False for hidden ancestors, inactive windows or covered content.
    static func permitsAnimation(in view: UIView) -> Bool {
        guard !UKAccessibility.reduceMotion, !DebugAnimationOverride.stillBackground,
              let window = view.window, window.windowScene?.activationState == .foregroundActive else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.isHidden { return false }
            ancestor = current.superview
        }
        var responder: UIResponder? = view
        var controller: UIViewController?
        while let current = responder {
            if let found = current as? UIViewController {
                controller = found
                break
            }
            responder = current.next
        }
        while let current = controller {
            if current.presentedViewController != nil { return false }
            controller = current.parent
        }
        return true
    }

    /// Publishes an actual presentation or page-visibility change after UIKit updates it.
    static func changed() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// Refreshes native animation state when the scene or presentation hierarchy changes.
@MainActor
final class UKMotionVisibilityObserver {
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    /// Subscribes without retaining the observed component.
    ///
    /// - Parameter onChange: A weakly capturing component refresh.
    init(_ onChange: @escaping @MainActor () -> Void) {
        var names = [
            UIScene.didActivateNotification, UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification, UKMotionVisibility.didChange,
        ]
        #if DEBUG
        names.append(.perfMarqueeRequestChanged)
        #endif
        tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
        }
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
#endif
