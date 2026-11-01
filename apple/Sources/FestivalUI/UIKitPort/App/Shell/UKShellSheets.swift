#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Sheet factories

/// The root sheets the shell presents but other lanes own: Notifications (the bell) and
/// What's New (Help menu). The Settings lane assigns its factories at launch; until it does,
/// a placeholder shows.
@MainActor
enum UKShellSheets {
    /// Builds the Notifications sheet; the closure opens a tapped row's page on the
    /// current tab once the sheet has closed.
    static var notificationsFactory: ((FestivalSession, @escaping (AppRoute) -> Void) -> UIViewController)?
    /// Builds the What's New sheet.
    static var whatsNewFactory: ((FestivalSession) -> UIViewController)?

    /// The Notifications sheet content.
    ///
    /// - Parameters:
    ///   - session: The shared session.
    ///   - open: Opens a row's page on the current tab.
    /// - Returns: The sheet's root.
    static func notifications(_ session: FestivalSession, _ open: @escaping (AppRoute) -> Void) -> UIViewController {
        notificationsFactory?(session, open) ?? placeholder("Notifications", session)
    }

    /// The What's New sheet content.
    ///
    /// - Parameter session: The shared session.
    /// - Returns: The sheet's root.
    static func whatsNew(_ session: FestivalSession) -> UIViewController {
        whatsNewFactory?(session) ?? placeholder("What's New", session)
    }

    private static func placeholder(_ title: String, _ session: FestivalSession) -> UIViewController {
        let page = UKPlaceholderViewController(title: title, context: UKContext(session: session))
        page.navigationItem.largeTitleDisplayMode = .never
        page.navigationItem.rightBarButtonItem = closeItem(identifier: "fst.sheet.close", page)
        return UINavigationController(rootViewController: page)
    }

    /// A sheet's native Close button (top-right).
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - controller: The sheet's page; the button dismisses it.
    /// - Returns: The bar item.
    static func closeItem(identifier: String, _ controller: UIViewController) -> UIBarButtonItem {
        let item = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak controller] _ in
            // From the presenter, so an active search controller does not swallow the close.
            let sheet = controller?.navigationController ?? controller
            sheet?.presentingViewController?.dismiss(animated: true)
        })
        item.accessibilityIdentifier = identifier
        item.accessibilityLabel = "Close"
        return item
    }
}

/// A weak reference a closure can capture before its page exists.
@MainActor
private final class WeakBox {
    weak var page: UIViewController?
}

// MARK: - Profile selection

/// The Profiles sheet: search for a player or band to select or open (UIKit counterpart of
/// ``ProfileSelectionSheet``), reusing the global search page with the profile targets.
@MainActor
enum UKProfileSelection {
    /// Builds the sheet.
    ///
    /// - Parameters:
    ///   - session: The shared session.
    ///   - layout: The window layout.
    ///   - open: The chosen route, pushed on the presenting tab once the sheet has gone.
    /// - Returns: The sheet's navigation controller.
    static func make(
        session: FestivalSession, layout: @escaping () -> DeviceLayout, open: @escaping (AppRoute) -> Void
    ) -> UINavigationController {
        let model = GlobalSearchModel(targets: .profiles)
        let box = WeakBox()
        let page = UKGlobalSearchViewController(
            model: model, session: session, asTab: false, layout: layout,
            open: { route in
                open(route)
                // Dismiss from the sheet's presenter: while the field is active the page is
                // presenting its search controller, and `dismiss` on the page closes only that.
                let sheet = box.page?.navigationController ?? box.page
                sheet?.presentingViewController?.dismiss(animated: true)
            },
            dismiss: {}
        )
        box.page = page
        page.title = "Profiles"
        page.loadViewIfNeeded()
        page.navigationItem.largeTitleDisplayMode = .never
        page.navigationItem.rightBarButtonItem = UKShellSheets.closeItem(identifier: "fst.profile.close", page)
        return UINavigationController(rootViewController: page)
    }
}
#endif
