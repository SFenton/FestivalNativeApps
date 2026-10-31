#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Bottom search field

/// The iPhone Duo bottom search field: a full-width (or trailing-page) Liquid Glass capsule
/// above the keyboard, shared by Songs' Filter and the Search tab (issues #333, #349). The
/// UIKit counterpart of ``BottomSearchField``; placement comes from
/// ``BottomSearchFieldPlacement``.
///
/// Install it with ``install(in:layout:)``: it pins itself to the host's bottom safe area
/// and `keyboardLayoutGuide`, keeps its edges clear of the hinge and reports its top so a
/// list can fade rows above it.
@MainActor
final class UKBottomSearchField: UIView, UITextFieldDelegate {
    /// The text field.
    let field = UITextField()
    /// Called as the text changes.
    var onChange: ((String) -> Void)?
    /// Called when the keyboard's Search key is pressed.
    var onSubmit: (() -> Void)?
    /// Called when the field's top edge moves (host window coordinates).
    var onTopChange: ((CGFloat) -> Void)?

    private let glass: UIVisualEffectView
    private let clearButton = UIButton(type: .system)
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private weak var host: UIViewController?
    private var layoutProvider: (() -> DeviceLayout)?

    /// Creates a field.
    ///
    /// - Parameters:
    ///   - prompt: Placeholder text.
    ///   - label: Spoken name.
    ///   - identifier: Accessibility identifier of the text field.
    ///   - clearIdentifier: Accessibility identifier of the clear button.
    init(prompt: String, label: String, identifier: String, clearIdentifier: String) {
        if #available(iOS 26.0, *) {
            glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        } else {
            glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.clipsToBounds = true
        glass.layer.cornerCurve = .continuous
        addSubview(glass)
        icon.tintColor = BrandUIColors.textSecondary
        icon.isAccessibilityElement = false
        field.attributedPlaceholder = NSAttributedString(
            string: prompt, attributes: [.foregroundColor: BrandUIColors.textSecondary]
        )
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = BrandUIColors.textPrimary
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = self
        field.accessibilityLabel = label
        field.accessibilityIdentifier = identifier
        field.accessibilityTraits.insert(.searchField)
        field.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.clearButton.isHidden = (self.field.text ?? "").isEmpty
            self.onChange?(self.field.text ?? "")
        }, for: .editingChanged)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = BrandUIColors.textSecondary
        clearButton.accessibilityLabel = "Clear Search"
        clearButton.accessibilityIdentifier = clearIdentifier
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in
            self?.field.text = ""
            self?.clearButton.isHidden = true
            self?.onChange?("")
        }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [icon, field, clearButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            clearButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The current text.
    var text: String {
        get { field.text ?? "" }
        set {
            guard field.text != newValue else { return }
            field.text = newValue
            clearButton.isHidden = newValue.isEmpty
        }
    }

    /// Updates the placeholder when the scope changes.
    ///
    /// - Parameter prompt: Placeholder text.
    func setPrompt(_ prompt: String) {
        field.attributedPlaceholder = NSAttributedString(
            string: prompt, attributes: [.foregroundColor: BrandUIColors.textSecondary]
        )
    }

    /// Adds the field to a controller's view, pinned above the bottom safe area and the
    /// keyboard.
    ///
    /// - Parameters:
    ///   - controller: The host.
    ///   - layout: The current window layout.
    func install(in controller: UIViewController, layout: @escaping () -> DeviceLayout) {
        host = controller
        layoutProvider = layout
        let view = controller.view!
        view.addSubview(self)
        let leading = leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: BottomSearchFieldPlacement.margin)
        let trailing = trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -BottomSearchFieldPlacement.margin)
        let height = heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        self.leading = leading
        self.trailing = trailing
        self.height = height
        let bottom = bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -BottomSearchFieldPlacement.rowPadding)
        NSLayoutConstraint.activate([leading, trailing, height, bottom])
        refreshPlacement()
    }

    /// Re-reads the hinge and section chrome and moves the field's edges and height.
    func refreshPlacement() {
        guard let host, let layout = layoutProvider?() else { return }
        height?.constant = BottomSearchFieldPlacement.fieldHeight(for: layout.sectionChrome)
        let container = host.view.convert(host.view.bounds, to: nil)
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: container, hinge: BottomSearchFieldPlacement.pageHinge(for: layout),
            layoutDirection: host.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        )
        leading?.constant = padding.leading
        trailing?.constant = -padding.trailing
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #available(iOS 26.0, *) {
            glass.cornerConfiguration = .capsule()
        } else {
            glass.layer.cornerRadius = bounds.height / 2
        }
        onTopChange?(convert(bounds, to: nil).minY)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?()
        return true
    }
}
#endif
