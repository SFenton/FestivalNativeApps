#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Sheet presenter

/// Tells the presenting page when its sheet is gone (a Close tap or a swipe down), so the shell
/// shows the floating page tools again: it hides them while a sheet is up and only re-reads a
/// page's tools when told they changed.
@MainActor
final class UKSongsSheetDismissObserver: NSObject, UIAdaptivePresentationControllerDelegate {
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onDismiss() }
}

extension UIViewController {
    /// Presents `content` in a Festival sheet and refreshes this page's tools once it is dismissed.
    ///
    /// - Parameters:
    ///   - content: The sheet page.
    ///   - title: Inline title.
    ///   - closeIdentifier: Close button identifier.
    ///   - size: Sheet size.
    ///   - keep: Receives the dismiss observer, which the caller must retain while the sheet is up.
    func ukPresentSongsSheet(
        _ content: UIViewController, title: String, closeIdentifier: String, size: FestivalSheetSize, keep: (UKSongsSheetDismissObserver) -> Void
    ) {
        let observer = UKSongsSheetDismissObserver { [weak self] in self?.ukPageToolsDidChange() }
        keep(observer)
        var sheet: UKSheetNavigationController?
        sheet = UKSheet.make(content, title: title, closeIdentifier: closeIdentifier, size: size, regularWidth: traitCollection.horizontalSizeClass == .regular) { [weak self] in
            sheet?.dismiss(animated: true) { self?.ukPageToolsDidChange() }
        }
        sheet?.presentationController?.delegate = observer
        if let sheet { present(sheet, animated: true) }
    }
}
#endif
