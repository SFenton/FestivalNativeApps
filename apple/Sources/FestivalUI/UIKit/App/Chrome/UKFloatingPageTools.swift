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
/// A tool with a ``UKPageToolSheet`` (Quick Links) opens that compact sheet, as the SwiftUI
/// floating tool does; any other tool's menu opens inline from its circle.
@MainActor
final class UKFloatingPageToolsView: UIView {
    private final class ToolButton: UIButton {
        var item: UIBarButtonItem?
        var glyph: UIView? {
            didSet {
                guard oldValue !== glyph else { return }
                oldValue?.removeFromSuperview()
                guard let glyph else { return }
                glyph.translatesAutoresizingMaskIntoConstraints = false
                glyph.isUserInteractionEnabled = false
                glyph.accessibilityElementsHidden = true
                addSubview(glyph)
                NSLayoutConstraint.activate([
                    glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
                    glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }
        }

        /// Match the SwiftUI floating row's capped body symbols, not the button's default scaling.
        func updateSymbolSize() {
            guard var configuration else { return }
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: UKFloatingPageToolsView.symbolPointSize(for: traitCollection)
            )
            self.configuration = configuration
        }
    }

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

    /// Returns the body symbol size for a fixed floating circle, capped at standard XXXL.
    ///
    /// - Parameter traits: The tool's current traits.
    static func symbolPointSize(for traits: UITraitCollection) -> CGFloat {
        let sizingTraits = traits.preferredContentSizeCategory.isAccessibilityCategory
            ? UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge) : traits
        return UIFont.preferredFont(forTextStyle: .body, compatibleWith: sizingTraits).pointSize
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
                let button = Self.button(for: tool, presenter: { [weak self] in self?.presenter() })
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
                guard let button = view as? ToolButton else { continue }
                Self.refresh(button, from: tool)
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

    /// A tool's identity across rebuilt bar items: its identifier and whether it opens a
    /// sheet or a menu. (A sheet reads its choices when it opens, so a kept button stays current.)
    private static func key(for tool: UKPageTool) -> String {
        let id = tool.item.accessibilityIdentifier ?? "\(ObjectIdentifier(tool.item).hashValue)"
        return "\(id)#\(tool.sheet != nil)#\(tool.item.menu != nil)"
    }

    /// Carry a rebuilt item's look, spoken name and value, and menu onto its existing button.
    /// The menu is replaced only when its rows changed: swapping an equal menu while it opens
    /// crashed the context menu's row list (Full Rankings' instrument menu).
    private static func refresh(_ button: ToolButton, from tool: UKPageTool) {
        let item = tool.item
        let tint = item.tintColor ?? BrandUIColors.textPrimary
        if var configuration = button.configuration,
           button.item == nil || button.largeContentImage !== item.image || button.glyph !== tool.floatingGlyph
            || configuration.baseForegroundColor != tint {
            configuration.image = tool.floatingGlyph == nil ? item.image?.withTintColor(tint, renderingMode: .alwaysOriginal) : nil
            configuration.baseForegroundColor = tint
            button.configuration = configuration
        }
        button.item = item
        button.glyph = tool.floatingGlyph
        button.accessibilityLabel = item.accessibilityLabel ?? item.title
        button.accessibilityValue = item.accessibilityValue
        button.accessibilityHint = item.accessibilityHint
        button.accessibilityTraits = item.accessibilityTraits.contains(.link) ? .link : .button
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

    /// The controller that presents a tool's sheet: the shell, found through the responder chain.
    private func presenter() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller.ukShell ?? controller }
            responder = current.next
        }
        return nil
    }

    /// One glass circle for a page tool's bar item.
    private static func button(for tool: UKPageTool, presenter: @escaping () -> UIViewController?) -> UIButton {
        let item = tool.item
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
            configuration.cornerStyle = .capsule
        }
        configuration.contentInsets = .zero
        let button = ToolButton(configuration: configuration)
        button.accessibilityIdentifier = item.accessibilityIdentifier
        button.showsLargeContentViewer = true
        button.updateSymbolSize()
        button.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (tool: ToolButton, _) in
            tool.updateSymbolSize()
        }
        if let sheet = tool.sheet {
            button.addAction(UIAction { _ in
                if let presenter = presenter() { UKPageToolMenuViewController.present(sheet, from: presenter) }
            }, for: .touchUpInside)
        } else if let menu = item.menu {
            button.menu = menu
            button.showsMenuAsPrimaryAction = true
            // A menu opened from the bottom bar otherwise lists its rows bottom-up.
            button.preferredMenuElementOrder = item.preferredMenuElementOrder
        } else {
            button.addAction(UIAction { [weak button] _ in
                guard let item = button?.item else { return }
                if let action = item.primaryAction {
                    action.performWithSender(item, target: nil)
                } else if let selector = item.action {
                    UIApplication.shared.sendAction(selector, to: item.target, from: item, for: nil)
                }
            }, for: .touchUpInside)
        }
        refresh(button, from: tool)
        button.widthAnchor.constraint(equalToConstant: FloatingPageToolsFit.slot).isActive = true
        button.heightAnchor.constraint(equalToConstant: FloatingPageToolsFit.slot).isActive = true
        return button
    }
}
#endif
