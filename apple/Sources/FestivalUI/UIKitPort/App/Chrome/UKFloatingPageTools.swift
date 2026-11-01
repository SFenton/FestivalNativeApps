#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Floating page tools

/// The front page's tools as individual 44 pt Liquid Glass circles, trailing-aligned above
/// the horizontal tab bar (iPhone, compact iPad windows, the iPhone Duo inner display in
/// portrait; issues #92, #632, #633): the UIKit counterpart of ``FloatingPageToolsBar``.
///
/// Elsewhere (the Duo vertical bar, the iPad flyout shell) pages keep their tools as
/// navigation-bar items. The row hides while Search or a root sheet covers the page, and
/// fades its tools with ``FloatingPageToolsMotion``.
///
/// A tool's menu opens inline from its circle (a deliberate simplification of the
/// SwiftUI compact sheet: UIKit menus open from a button reliably).
@MainActor
final class UKFloatingPageToolsView: UIView {
    private let stack = UIStackView()
    private var shownIDs: [String] = []
    private var revealedScopes = Set<ObjectIdentifier>()

    /// Creates the row.
    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityIdentifier = "fst.page-tools"
        accessibilityLabel = "Page Tools"
        shouldGroupAccessibilityChildren = true
        stack.axis = .horizontal
        stack.spacing = FloatingPageToolsFit.spacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: FloatingPageToolsFit.verticalPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -FloatingPageToolsFit.verticalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Button frames are in the stack's coordinates, which sit inset in this view.
        stack.arrangedSubviews.contains { stack.convert($0.frame, to: self).insetBy(dx: -4, dy: -4).contains(point) }
            && !isHidden && alpha > 0
    }

    /// Whether a window floats page tools (agent decision, issue #633).
    ///
    /// - Parameters:
    ///   - layout: The window layout.
    ///   - flyout: The iPad flyout shell (its pages keep navigation-bar items).
    /// - Returns: True for a horizontal tab bar.
    static func floats(in layout: DeviceLayout, flyout: Bool) -> Bool {
        !flyout && FloatingPageToolsHost.floatsPageTools(in: layout)
    }

    /// Shows the front page's tools.
    ///
    /// - Parameters:
    ///   - tools: The tools in row order.
    ///   - scope: The front page (a revisited page cross-fades instead of staggering).
    ///   - covered: A root sheet or Search covers the page.
    func update(tools: [UKPageTool], scope: AnyObject?, covered: Bool) {
        let reduce = UIAccessibility.isReduceMotionEnabled || UKSettings.bool("fst.accessibility.reduceMotion", default: false)
        let revealed = scope.map { revealedScopes.contains(ObjectIdentifier($0)) } ?? true
        let motion = FloatingPageToolsMotion.resolve(reduceMotion: reduce, revealed: revealed)
        // Pages build fresh bar items each time they are asked, so a tool is matched by its
        // identifier and kind, not its object: an equal row updates in place, which keeps an open
        // menu open (rebuilding the buttons closed it, the Full Rankings instrument switch).
        let ids = tools.map(Self.key(for:))
        if ids != shownIDs {
            shownIDs = ids
            let old = stack.arrangedSubviews
            old.forEach { $0.removeFromSuperview() }
            for (index, tool) in tools.enumerated() {
                let button = Self.button(for: tool.item)
                stack.addArrangedSubview(button)
                switch motion {
                case .none: break
                case .quick:
                    button.alpha = 0
                    UIView.animate(withDuration: FloatingPageToolsMotion.quickFade, delay: 0, options: .curveEaseOut) { button.alpha = 1 }
                case .staggered:
                    button.alpha = 0
                    button.transform = CGAffineTransform(translationX: 0, y: FloatingPageToolsMotion.rise)
                    UIView.animate(
                        withDuration: FloatingPageToolsMotion.fadeDuration,
                        delay: FloatingPageToolsMotion.staggerDelay(index: index, count: tools.count), options: .curveEaseOut
                    ) {
                        button.alpha = 1
                        button.transform = .identity
                    }
                }
            }
            if let scope, !tools.isEmpty { revealedScopes.insert(ObjectIdentifier(scope)) }
        } else {
            // The same items: carry their current spoken value and menu to the buttons (Quick
            // Links' active section, a menu's checked choice).
            for (view, tool) in zip(stack.arrangedSubviews, tools) {
                guard let button = view as? UIButton else { continue }
                Self.refresh(button, from: tool.item)
            }
        }
        isHidden = tools.isEmpty
        let target: CGFloat = covered ? 0 : 1
        if motion == .none {
            alpha = target
        } else {
            UIView.animate(withDuration: FloatingPageToolsMotion.quickFade) { self.alpha = target }
        }
        isUserInteractionEnabled = !covered
        accessibilityElementsHidden = covered || tools.isEmpty
    }

    /// A tool's identity across rebuilt bar items: its identifier and whether it is a menu.
    private static func key(for tool: UKPageTool) -> String {
        let id = tool.item.accessibilityIdentifier ?? "\(ObjectIdentifier(tool.item).hashValue)"
        return "\(id)#\(tool.item.menu != nil)"
    }

    /// Carry a rebuilt item's look, spoken name and value, and menu onto its existing button.
    /// The menu is replaced only when its rows changed: swapping an equal menu while it opens
    /// crashed the context menu's row list (Full Rankings' instrument menu).
    private static func refresh(_ button: UIButton, from item: UIBarButtonItem) {
        if button.configuration?.image !== item.image { button.configuration?.image = item.image }
        button.accessibilityLabel = item.accessibilityLabel ?? item.title
        button.accessibilityValue = item.accessibilityValue
        button.accessibilityHint = item.accessibilityHint
        button.largeContentTitle = item.accessibilityLabel ?? item.title
        button.largeContentImage = item.image
        guard let menu = item.menu, let current = button.menu else { return }
        if signature(of: current) != signature(of: menu) { button.menu = menu }
        button.preferredMenuElementOrder = item.preferredMenuElementOrder
    }

    /// A menu's rows as text (titles, checked state, identifiers, nesting), to tell an
    /// equal rebuilt menu from a changed one.
    private static func signature(of element: UIMenuElement) -> String {
        if let menu = element as? UIMenu {
            return "[\(menu.title)|\(menu.children.map(signature(of:)).joined(separator: ","))]"
        }
        if let action = element as? UIAction {
            return "\(action.title)/\(action.state.rawValue)/\(action.accessibilityIdentifier ?? "")"
        }
        return element.title
    }

    /// One glass circle for a page tool's bar item.
    private static func button(for item: UIBarButtonItem) -> UIButton {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
            configuration.cornerStyle = .capsule
        }
        configuration.image = item.image
        configuration.baseForegroundColor = BrandUIColors.textPrimary
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = item.accessibilityLabel ?? item.title
        button.accessibilityValue = item.accessibilityValue
        button.accessibilityHint = item.accessibilityHint
        button.accessibilityIdentifier = item.accessibilityIdentifier
        button.showsLargeContentViewer = true
        button.largeContentTitle = item.accessibilityLabel ?? item.title
        button.largeContentImage = item.image
        if let menu = item.menu {
            button.menu = menu
            button.showsMenuAsPrimaryAction = true
            // A menu opened from the bottom bar otherwise lists its rows bottom-up.
            button.preferredMenuElementOrder = item.preferredMenuElementOrder
        } else if let action = item.primaryAction {
            button.addAction(UIAction(title: action.title, image: action.image) { _ in
                action.performWithSender(item, target: nil)
            }, for: .touchUpInside)
        } else if let selector = item.action {
            let target = item.target
            button.addAction(UIAction { _ in
                UIApplication.shared.sendAction(selector, to: target, from: item, for: nil)
            }, for: .touchUpInside)
        }
        button.widthAnchor.constraint(equalToConstant: FloatingPageToolsFit.slot).isActive = true
        button.heightAnchor.constraint(equalToConstant: FloatingPageToolsFit.slot).isActive = true
        return button
    }
}
#endif
