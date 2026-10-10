import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Search drawer transition fill

/// Keeps a system navigation-bar drawer search field's capsule drawn at rest (issue #559)
/// and while its page is pushed or popped (issue #544).
///
/// At rest it installs the field's ``SearchFieldBacking`` (design layer,
/// ``SearchFieldBackingView``): regular Liquid Glass at every scroll position, or the
/// opaque fallback under Reduce Transparency or Increase Contrast, so the field no longer
/// switches from UIKit's flat top-edge fill to glass as the list scrolls. Only a field the
/// system placed in the drawer (`searchBarPlacement == .stacked`) gets one.
///
/// On iOS 26/27, a `.searchable` field in the navigation-bar drawer shows Liquid Glass
/// once the list scrolls under the bar. During a navigation push or pop, UIKit hides the
/// real search bar and slides a portal of it (`CAPortalLayer`) with the page. The portal
/// draws the field's icon and prompt but not its glass, so the field had no capsule for
/// the whole transition. The glass appeared about half a second after Back, and an edge
/// swipe showed no capsule at all. A plain SwiftUI `List` with the same drawer behaves the
/// same way. At the top of the list the field uses a flat fill, which the portal does draw.
///
/// While a push or pop of the field's own page is animating, and whenever the field shows
/// glass (a glass backing, or the system glass once content is scrolled under the bar),
/// this gives the field the system search-field fill,
/// `tertiarySystemFill`. Apple documents that fill for "input fields, search bars". The
/// portal can draw it, and the fill is removed when the transition finishes or is
/// cancelled, so the settled field keeps its glass. The modifier uses public UIKit API
/// only, and it does nothing on macOS.
struct SearchDrawerTransitionFill: ViewModifier {
    /// The field's resting backing (``FestivalGlassSettings/searchFieldBacking``).
    let backing: SearchFieldBacking
    /// Whether the page's content is scrolled under the navigation bar now (the state in
    /// which the system field draws glass).
    let isContentUnderBar: @MainActor () -> Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(
            SearchDrawerTransitionBridge(backing: backing, isContentUnderBar: isContentUnderBar)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        #else
        content
        #endif
    }

    /// Distance past the top a scroll view must move before content counts as under the bar.
    nonisolated static let underBarTolerance: CGFloat = 0.5

    /// Whether a scroll view's content sits under the bar above it.
    ///
    /// - Parameters:
    ///   - offsetY: The scroll view's vertical content offset.
    ///   - adjustedTopInset: Its adjusted top content inset (the bars above it).
    /// - Returns: True once the content has scrolled past its top edge.
    nonisolated static func isContentUnderBar(offsetY: CGFloat, adjustedTopInset: CGFloat) -> Bool {
        offsetY + adjustedTopInset > underBarTolerance
    }
}

#if os(iOS)
extension SearchDrawerTransitionFill {
    /// Whether a List's scroll view has content scrolled under its bar.
    ///
    /// A pop asks before the page is back in a window; the scroll view keeps its offset
    /// and insets while it is out of one.
    ///
    /// - Parameter scrollView: The List's located scroll view, or nil before it is found.
    /// - Returns: False until the scroll view is found.
    @MainActor
    static func isContentUnderBar(_ scrollView: UIScrollView?) -> Bool {
        guard let scrollView else { return false }
        return isContentUnderBar(
            offsetY: scrollView.contentOffset.y, adjustedTopInset: scrollView.adjustedContentInset.top
        )
    }
}

// MARK: - UIKit bridge

/// A zero-size child view controller of the page that hears the page's appearance
/// transitions, which start when a push or pop starts, interactive pops included.
private struct SearchDrawerTransitionBridge: UIViewControllerRepresentable {
    let backing: SearchFieldBacking
    let isContentUnderBar: @MainActor () -> Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.backing = backing
        controller.isContentUnderBar = isContentUnderBar
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isContentUnderBar = isContentUnderBar
        if controller.backing != backing {
            controller.backing = backing
            controller.installBacking()
        }
    }

    /// Backs the page's drawer field at rest and fills it for the length of a push or pop.
    final class Controller: UIViewController {
        var backing: SearchFieldBacking = .none
        var isContentUnderBar: (@MainActor () -> Bool)?
        /// The field filled for transitions still running, with how many are running.
        private weak var filledField: UISearchTextField?
        private var activeTransitions = 0

        override func loadView() {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            coverNavigationTransition(animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installBacking()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            coverNavigationTransition(animated: animated)
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            // A resized iPad window can move the field between the drawer and the toolbar.
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.installBacking() }
            }
        }

        /// Give the drawer field its resting backing, or remove it where the system placed
        /// the field outside the drawer.
        func installBacking() {
            guard #available(iOS 26.0, *), let navigation = navigationController,
                  let (item, field) = searchItem(in: navigation)
            else { return }
            guard !isTransitioning else { return }
            let placed: SearchFieldBacking = item.searchBarPlacement == .stacked ? backing : .none
            SearchFieldBackingView.apply(placed, to: field)
        }

        /// Whether a covered push or pop is still running.
        private var isTransitioning: Bool { activeTransitions > 0 }

        /// Fill the field if a push or pop of this page is starting while the content is
        /// under the bar; remove the fill when that transition ends or is cancelled.
        ///
        /// - Parameter animated: Whether the appearance change animates.
        private func coverNavigationTransition(animated: Bool) {
            guard animated, let navigation = navigationController,
                  let coordinator = navigation.transitionCoordinator,
                  Self.isNavigationTransition(coordinator, in: navigation),
                  let (_, field) = searchItem(in: navigation),
                  currentBacking(of: field).needsTransitionFill(contentUnderBar: isContentUnderBar?() == true)
            else { return }
            activeTransitions += 1
            filledField = field
            field.backgroundColor = .tertiarySystemFill
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.transitionEnded() }
            }
        }

        /// Remove the fill once no covered transition is still running.
        private func transitionEnded() {
            activeTransitions = max(0, activeTransitions - 1)
            guard activeTransitions == 0 else { return }
            if let field = filledField {
                // A backed field keeps its fill cleared so UIKit's top-edge fill can't tint it.
                field.backgroundColor = currentBacking(of: field) == .none ? nil : .clear
            }
            filledField = nil
            installBacking()
        }

        /// The backing a field draws now (none before iOS 26).
        private func currentBacking(of field: UISearchTextField) -> SearchFieldBacking {
            guard #available(iOS 26.0, *) else { return .none }
            return SearchFieldBackingView.backing(of: field)
        }

        /// Whether a transition moves between two pages of one navigation stack (not a tab
        /// switch or a modal presentation).
        ///
        /// - Parameters:
        ///   - coordinator: The running transition's coordinator.
        ///   - navigation: This page's navigation controller.
        /// - Returns: True for a push or pop within `navigation`.
        private static func isNavigationTransition(
            _ coordinator: UIViewControllerTransitionCoordinator, in navigation: UINavigationController
        ) -> Bool {
            guard let from = coordinator.viewController(forKey: .from),
                  let to = coordinator.viewController(forKey: .to)
            else { return false }
            return from.navigationController === navigation && to.navigationController === navigation
        }

        /// The drawer search field of this page and the navigation item that owns it: the
        /// item's search controller, as `.searchable` configures it.
        ///
        /// - Parameter navigation: This page's navigation controller.
        /// - Returns: The item and its search text field, or nil when the page has no search
        ///   controller.
        private func searchItem(
            in navigation: UINavigationController
        ) -> (UINavigationItem, UISearchTextField)? {
            var page: UIViewController = self
            while let parent = page.parent, parent !== navigation {
                if let field = parent.navigationItem.searchController?.searchBar.searchTextField {
                    return (parent.navigationItem, field)
                }
                page = parent
            }
            guard let field = page.navigationItem.searchController?.searchBar.searchTextField
            else { return nil }
            return (page.navigationItem, field)
        }
    }
}
#endif
