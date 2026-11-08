#if os(iOS)
import UIKit

extension UIAlertController {
    /// Creates a native action whose callback runs after the alert actually dismisses.
    ///
    /// - Parameters:
    ///   - title: The native action title.
    ///   - style: Default, cancel or destructive behavior.
    ///   - handler: The owning task's action after native dismissal.
    /// - Returns: An action to add with UIKit's standard API.
    @MainActor
    func ukAction(title: String, style: UIAlertAction.Style, handler: (() -> Void)? = nil) -> UIAlertAction {
        UIAlertAction(title: title, style: style) { [weak self] _ in
            guard let self else {
                handler?()
                return
            }
            UKPresentationCoordinator.shared(for: self).dismiss(self, completion: handler)
        }
    }
}
#endif
