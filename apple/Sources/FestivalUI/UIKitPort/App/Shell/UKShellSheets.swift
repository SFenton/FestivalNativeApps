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
    static var notificationsFactory: ((FestivalSession, @escaping (AppRoute) -> Void) -> UKSheetNavigationController)?
    /// Builds the What's New sheet.
    static var whatsNewFactory: ((FestivalSession) -> UKSheetNavigationController)?

    /// The Notifications sheet content.
    ///
    /// - Parameters:
    ///   - session: The shared session.
    ///   - open: Opens a row's page on the current tab.
    /// - Returns: The sheet's root.
    static func notifications(_ session: FestivalSession, _ open: @escaping (AppRoute) -> Void) -> UKSheetNavigationController {
        notificationsFactory?(session, open) ?? placeholder("Notifications", session)
    }

    /// The What's New sheet content.
    ///
    /// - Parameter session: The shared session.
    /// - Returns: The sheet's root.
    static func whatsNew(_ session: FestivalSession) -> UKSheetNavigationController {
        whatsNewFactory?(session) ?? placeholder("What's New", session)
    }

    private static func placeholder(_ title: String, _ session: FestivalSession) -> UKSheetNavigationController {
        let page = UKPlaceholderViewController(title: title, context: UKContext(session: session))
        return UKSheet.make(page, title: title, closeIdentifier: "fst.sheet.close")
    }

    /// A sheet's native Close button (top-right).
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - controller: The sheet's page; the button dismisses it.
    /// - Returns: The bar item.
    static func closeItem(identifier: String, _ controller: UIViewController) -> UIBarButtonItem {
        let item = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak controller] _ in
            dismiss(controller)
        })
        item.accessibilityIdentifier = identifier
        item.accessibilityLabel = "Close"
        return item
    }

    /// Dismisses the outer task and its native search presentation.
    ///
    /// - Parameter controller: The sheet or one of its pages.
    static func dismiss(_ controller: UIViewController?) {
        let navigation = controller?.navigationController ?? controller
        if let sheet = navigation as? UKSheetNavigationController {
            sheet.dismissFromPresenter(animated: true)
        } else if let navigation {
            UKPresentationCoordinator.shared(for: navigation).dismiss(navigation)
        }
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
    ) -> UKSheetNavigationController {
        let model = GlobalSearchModel(targets: .profiles)
        let box = WeakBox()
        let page = UKGlobalSearchViewController(
            model: model, session: session, asTab: false, layout: layout,
            open: { route in
                open(route)
                UKShellSheets.dismiss(box.page)
            },
            dismiss: {}
        )
        box.page = page
        page.title = "Profiles"
        return UKSheet.make(page, title: "Profiles", closeIdentifier: "fst.profile.close")
    }
}
#endif
