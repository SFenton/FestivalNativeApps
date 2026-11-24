#if os(iOS)
import FestivalCore
import UIKit

extension UIViewController {
    /// Presents `content` in a Festival sheet and refreshes this page's tools once it is dismissed.
    ///
    /// - Parameters:
    ///   - content: The sheet page.
    ///   - title: Inline title.
    ///   - closeIdentifier: Close button identifier.
    ///   - size: Sheet size.
    func ukPresentSongsSheet(
        _ content: UIViewController, title: String, closeIdentifier: String, size: FestivalSheetSize
    ) {
        let sheet = UKSheet.make(
            content, title: title, closeIdentifier: closeIdentifier, size: size,
            regularWidth: traitCollection.horizontalSizeClass == .regular
        )
        sheet.onDismiss = { [weak self] in self?.ukPageToolsDidChange() }
        present(sheet, animated: true)
    }
}
#endif
