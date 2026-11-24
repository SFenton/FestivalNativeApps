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
final class UKBottomSearchField: UIView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    /// The text field.
    var field: UITextField { textField }
    /// Called as the text changes.
    var onChange: ((String) -> Void)?
    /// Called when the keyboard's Search key is pressed.
    var onSubmit: (() -> Void)?
    /// Called when the field's top edge moves (host window coordinates).
    var onTopChange: ((CGFloat) -> Void)?

    /// `festivalGlassCapsule(.control, interactive: true)`, as the SwiftUI field.
    private let glass = UKGlassView(.control, capsule: true, interactive: true)
    private let textField = CapsuleTextField()
    private let clearButton = UIButton(type: .system)
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private var bottom: NSLayoutConstraint?
    private var contentTrailing: NSLayoutConstraint?
    private var clearWidth: NSLayoutConstraint?
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
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        icon.tintColor = BrandUIColors.textMuted
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        icon.adjustsImageSizeForAccessibilityContentSizeCategory = true
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        field.placeholder = prompt
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
        textField.capsule = self
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.refreshClearButton()
            self.onChange?(self.field.text ?? "")
        }, for: .editingChanged)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = BrandUIColors.textMuted
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.accessibilityLabel = "Clear Search"
        clearButton.accessibilityIdentifier = clearIdentifier
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in
            self?.text = ""
            self?.onChange?("")
        }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [icon, field, clearButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(stack)
        let contentTrailing = stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -12)
        self.contentTrailing = contentTrailing
        clearWidth = clearButton.widthAnchor.constraint(greaterThanOrEqualToConstant: GlobalSearchField.clearTarget)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 12),
            contentTrailing,
            clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: GlobalSearchField.clearTarget),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusField))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The current text.
    var text: String {
        get { field.text ?? "" }
        set {
            guard field.text != newValue else { return }
            field.text = newValue
            refreshClearButton()
        }
    }

    private func refreshClearButton() {
        let empty = text.isEmpty
        if empty { clearWidth?.isActive = false }
        clearButton.isHidden = empty
        if !empty { clearWidth?.isActive = true }
        contentTrailing?.constant = empty ? -12 : -4
    }

    /// Updates the placeholder when the scope changes.
    ///
    /// - Parameter prompt: Placeholder text.
    func setPrompt(_ prompt: String) {
        field.placeholder = prompt
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
        let safeArea = view.safeAreaLayoutGuide
        let leading = leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: BottomSearchFieldPlacement.margin)
        let trailing = trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -BottomSearchFieldPlacement.margin)
        let height = heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        self.leading = leading
        self.trailing = trailing
        self.height = height
        let bottom = bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -BottomSearchFieldPlacement.rowPadding)
        self.bottom = bottom
        NSLayoutConstraint.activate([leading, trailing, height, bottom])
        refreshPlacement()
    }

    /// Re-reads the hinge and section chrome and moves the field's edges and height.
    func refreshPlacement() {
        guard let host, let layout = layoutProvider?() else { return }
        let minimumHeight = BottomSearchFieldPlacement.fieldHeight(for: layout.sectionChrome)
        if height?.constant != minimumHeight { height?.constant = minimumHeight }
        let view = host.view!
        guard let window = view.window else { return }
        let container = view.convert(view.safeAreaLayoutGuide.layoutFrame, to: window)
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: container, hinge: BottomSearchFieldPlacement.pageHinge(for: layout),
            layoutDirection: view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        )
        if leading?.constant != padding.leading { leading?.constant = padding.leading }
        if trailing?.constant != -padding.trailing { trailing?.constant = -padding.trailing }
        let keyboard = view.convert(view.keyboardLayoutGuide.layoutFrame, to: window)
        let keyboardTop = keyboard.minY < container.maxY - 1 ? keyboard.minY : nil
        let bottomPadding = BottomSearchFieldPlacement.bottomPadding(
            chrome: layout.sectionChrome, rowBottom: keyboardTop ?? container.maxY,
            windowBottom: window.bounds.maxY, fieldHeight: max(bounds.height, minimumHeight), keyboardTop: keyboardTop
        )
        if bottom?.constant != -bottomPadding { bottom?.constant = -bottomPadding }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshPlacement()
        onTopChange?(convert(bounds, to: nil).minY)
    }

    @objc private func focusField() {
        field.becomeFirstResponder()
    }

    /// The empty field exposes the full capsule; entered text keeps its native editing bounds.
    private final class CapsuleTextField: UITextField {
        weak var capsule: UKBottomSearchField?

        override var accessibilityFrame: CGRect {
            get {
                guard text?.isEmpty != false, let capsule, capsule.window != nil else {
                    return super.accessibilityFrame
                }
                return UIAccessibility.convertToScreenCoordinates(capsule.bounds, in: capsule)
            }
            set { super.accessibilityFrame = newValue }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let view = target, view !== self {
            if view is UIControl { return false }
            target = view.superview
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?()
        return true
    }
}
#endif
