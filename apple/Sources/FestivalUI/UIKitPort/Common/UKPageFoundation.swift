#if os(iOS)
import FentonUIKit
import UIKit

// MARK: - Page foundation

/// Chooses which owner supplies the page viewport's safe-area and scroll insets.
enum UKPageViewportPolicy: Equatable {
    /// The page remains a full native viewport and UIKit supplies adjusted insets.
    case native
    /// The shared host supplies the safe-area rectangle and registered-scroll insets.
    case contained
}

/// The consumer-owned page adapter for the shared Fenton UIKit host.
///
/// The page keeps ownership of its controller, content view, route state, and
/// visual policy. ``FentonContentContainmentView`` owns only the page content
/// rectangle and the registered primary scroll view's inset lifecycle.
@MainActor
class UKPageViewController: UKScreenViewController {
    /// The app-owned content host.
    let pageContainment = FentonContentContainmentView()

    /// Persistent app-owned composition surface for pages with independent controls and results.
    private(set) lazy var pageBodyView = UIView()

    private(set) var registeredPageScrollView: UIScrollView?
    private(set) var pageViewportPolicy: UKPageViewportPolicy = .native
    private weak var installedPageContent: UIView?
    private var pageStateView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        pageContainment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageContainment)
        NSLayoutConstraint.activate([
            pageContainment.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageContainment.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageContainment.topAnchor.constraint(equalTo: view.topAnchor),
            pageContainment.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Installs one app-owned content view and, when supplied, its primary native scroll view.
    ///
    /// Native pages keep a full viewport and UIKit's automatic adjustment behavior. Contained
    /// pages opt into host-owned safe-area placement and explicit scroll registration.
    ///
    /// - Parameters:
    ///   - content: The page content view.
    ///   - scrollView: The page's primary ``UIScrollView``, if it has one.
    ///   - contentInsetsOverride: An explicit host-owned content rectangle, when needed by a
    ///     family-specific layout policy.
    func installPageContent(
        _ content: UIView,
        scrollView: UIScrollView? = nil,
        viewport: UKPageViewportPolicy = .native,
        contentInsetsOverride: UIEdgeInsets? = nil
    ) {
        pageViewportPolicy = viewport
        pageContainment.contentInsetsOverride = contentInsetsOverride ?? (viewport == .native ? .zero : nil)
        pageContainment.installContentView(content)
        installedPageContent = content
        setContentScrollView(scrollView)
        registerPageScrollView(viewport == .contained ? scrollView : nil)
    }

    /// Installs a persistent native canvas for controls, results and pinned page chrome.
    ///
    /// - Parameter scrollView: The primary scroller; UIKit retains automatic inset ownership.
    func installPageBody(scrollView: UIScrollView? = nil) {
        installPageContent(pageBodyView, scrollView: scrollView)
    }

    /// Registers the primary scroll view without replacing the page content.
    ///
    /// - Parameter scrollView: The native scroll view whose insets the host owns while present.
    func registerPageScrollView(_ scrollView: UIScrollView?) {
        pageContainment.unregisterMainScrollView()
        registeredPageScrollView = scrollView
        if let scrollView {
            pageContainment.registerMainScrollView(scrollView)
        }
    }

    /// Restores the registered scroll view's original adjustment behavior and insets.
    func unregisterPageScrollView() {
        pageContainment.unregisterMainScrollView()
        registeredPageScrollView = nil
    }

    /// Shows a consumer-owned state over the page without replacing its primary content view.
    ///
    /// A page may temporarily move its primary content into a loading gate. Before replacing
    /// any previous state, this method reclaims that content and recreates only its host
    /// constraints, preserving the scroll object, offset, and inset policy.
    func showPageState(_ state: UIView, edgeToEdge: Bool = false) {
        restorePageContentHierarchy()
        pageStateView?.removeFromSuperview()
        pageContainment.isHidden = true
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        if edgeToEdge {
            NSLayoutConstraint.activate([
                state.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                state.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                state.topAnchor.constraint(equalTo: view.topAnchor),
                state.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        } else {
            let guide = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                state.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                state.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                state.topAnchor.constraint(equalTo: guide.topAnchor),
                state.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            ])
        }
        pageStateView = state
    }

    /// Removes the page state and restores the primary content hierarchy.
    func clearPageState() {
        restorePageContentHierarchy()
        pageStateView?.removeFromSuperview()
        pageStateView = nil
        pageContainment.isHidden = false
    }

    /// Reclaims the installed page content only when a consumer moved it into another host.
    func restorePageContentHierarchy() {
        guard let content = installedPageContent,
              content.superview !== pageContainment.contentView else { return }
        let preservedOffset = (content as? UIScrollView)?.contentOffset
        let currentSuperview = content.superview
        var ancestors: [UIView] = []
        var cursor = currentSuperview
        while let view = cursor {
            ancestors.append(view)
            if view === pageContainment.contentView { break }
            cursor = view.superview
        }
        if !ancestors.contains(where: { $0 === pageContainment.contentView }) {
            ancestors.append(pageContainment.contentView)
        }
        let constraints = ancestors.flatMap { $0.constraints.filter { constraint in
            (constraint.firstItem as? UIView) === content || (constraint.secondItem as? UIView) === content
        } }
        NSLayoutConstraint.deactivate(constraints)
        content.removeFromSuperview()
        pageContainment.installContentView(content)
        pageContainment.setNeedsLayout()
        pageContainment.layoutIfNeeded()
        if let scroll = content as? UIScrollView, let preservedOffset {
            scroll.setContentOffset(preservedOffset, animated: false)
        }
    }
}
#endif
