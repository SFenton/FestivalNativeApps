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
    private var didNotify = false

    init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { notifyDismissal() }

    /// Delivers the shared shell's dismissal notification once.
    func notifyDismissal() {
        guard !didNotify else { return }
        didNotify = true
        onDismiss()
    }
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
        let sheet = UKSheet.make(
            content, title: title, closeIdentifier: closeIdentifier, size: size,
            regularWidth: traitCollection.horizontalSizeClass == .regular
        )
        sheet.ukOnDismiss = { observer.notifyDismissal() }
        present(sheet, animated: true)
    }
}
#endif
