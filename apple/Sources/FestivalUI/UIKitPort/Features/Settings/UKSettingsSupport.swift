#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Settings writes

/// Writes the `fst.*` settings every other page reads (`@AppStorage` in SwiftUI): the same
/// keys in the same representation, through `UserDefaults.standard`, so a switch in the port
/// changes the SwiftUI app's pages and the port's pages alike (``UKSettings`` is the read
/// side). Each write posts `UserDefaults.didChangeNotification`, which ``UKSettings/didChange``
/// observers follow.
@MainActor
enum UKSettingsStore {
    /// Writes a Boolean setting.
    ///
    /// - Parameters:
    ///   - value: The new value.
    ///   - key: The `fst.*` key.
    static func set(_ value: Bool, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }

    /// Writes a number setting.
    ///
    /// - Parameters:
    ///   - value: The new value.
    ///   - key: The `fst.*` key.
    static func set(_ value: Double, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }

    /// Writes a string setting.
    ///
    /// - Parameters:
    ///   - value: The new value.
    ///   - key: The `fst.*` key.
    static func set(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }

    /// A number setting, falling back to its default.
    ///
    /// - Parameters:
    ///   - key: The `fst.*` key.
    ///   - fallback: The value when nothing is stored.
    /// - Returns: The stored or default value.
    static func double(_ key: String, default fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    /// A string setting, falling back to its default.
    ///
    /// - Parameters:
    ///   - key: The `fst.*` key.
    ///   - fallback: The value when nothing is stored.
    /// - Returns: The stored or default value.
    static func string(_ key: String, default fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }
}

// MARK: - Scroll page

/// A Settings-lane page: a transparent scroll view over the shared background holding one
/// column of cards, 16 pt from the edges, 8 pt below the bar and 32 pt above the bottom, capped to
/// the readable 680 pt column centred on wide windows (`ReadableWidthContainer`).
@MainActor
class UKSettingsScrollPage: UIViewController, UKModalScrollProviding {
    /// Settings' readable column width (`ReadableWidthContainer.columnWidth`).
    static let columnWidth: CGFloat = 680
    /// Space between cards.
    static let cardSpacing: CGFloat = 28

    /// The page scroll view.
    let scrollView = UIScrollView()
    /// The vertical column of cards.
    let column = UIStackView()
    /// The context the page was created in.
    let context: UKContext

    var ukModalScrollView: UIScrollView? { scrollView }

    /// Creates the page.
    ///
    /// - Parameter context: The page's context.
    init(context: UKContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)
        column.axis = .vertical
        column.spacing = Self.cardSpacing
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(holder)
        holder.addSubview(column)
        let frame = scrollView.frameLayoutGuide
        let content = scrollView.contentLayoutGuide
        let fill = column.widthAnchor.constraint(equalTo: holder.widthAnchor, constant: -32)
        fill.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            holder.topAnchor.constraint(equalTo: content.topAnchor),
            holder.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            holder.widthAnchor.constraint(equalTo: frame.widthAnchor),
            column.topAnchor.constraint(equalTo: holder.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -32),
            column.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: Self.columnWidth),
            fill,
        ])
    }

    private var laidOutWidth: CGFloat = 0

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Wrapped text measures at the width the column settled on: lay out again when it moves.
        if Self.remeasureLabels(in: column) {
            column.setNeedsLayout()
            scrollView.setNeedsLayout()
        }
    }

    /// Gives every wrapping label the width it was laid out at as its wrap width, so its height
    /// follows the final column rather than the width of an earlier pass.
    ///
    /// - Parameter view: The root to walk.
    /// - Returns: Whether any label changed.
    @discardableResult
    static func remeasureLabels(in view: UIView) -> Bool {
        var changed = false
        if let label = view as? UILabel, label.numberOfLines != 1, label.bounds.width > 0,
           abs(label.preferredMaxLayoutWidth - label.bounds.width) > 0.5 {
            label.preferredMaxLayoutWidth = label.bounds.width
            label.invalidateIntrinsicContentSize()
            changed = true
        }
        for sub in view.subviews where Self.remeasureLabels(in: sub) { changed = true }
        return changed
    }

    /// Replaces the column's cards.
    ///
    /// - Parameter views: The cards in page order.
    func setCards(_ views: [UIView]) {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(column.addArrangedSubview)
    }
}

// MARK: - Labels

/// Title plus optional description, the web's setting-row layout (`SettingLabel`):
/// semibold body title, regular subheadline description, both white.
@MainActor
final class UKSettingLabel: UIStackView {
    private let titleLabel: UKLabel
    private let detailLabel: UKLabel?

    /// Creates a label.
    ///
    /// - Parameters:
    ///   - title: Title Case setting name.
    ///   - detail: Optional sentence-case explanation.
    init(_ title: String, detail: String? = nil) {
        titleLabel = UKLabel(title, style: .body, weight: .semibold)
        detailLabel = detail.map { UKLabel($0, style: .subheadline) }
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        alignment = .fill
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(titleLabel)
        if let detailLabel { addArrangedSubview(detailLabel) }
        for label in [titleLabel, detailLabel].compactMap({ $0 }) {
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the description.
    ///
    /// - Parameter text: The new text.
    func setDetail(_ text: String?) { detailLabel?.text = text }
}

// MARK: - Toggle row

/// A Settings switch whose whole row is its touch target (``SettingsRowToggleStyle``):
/// the title and description flip the switch too, the row is at least 44 pt tall, and it
/// reads as one switch with the row's label, value and hint. The row is the accessibility
/// element (a toggle button with value "1" or "0"); the system switch inside is decoration
/// that follows it.
@MainActor
final class UKSettingsToggleRow: UIView, UIGestureRecognizerDelegate {
    private let switchView = UISwitch()
    private let content = UKSettingLabel("")
    private let titleText: String
    private let detailText: String?
    private let key: String
    private let fallback: Bool
    private let inverted: Bool

    /// Called after the user flips the switch, with the new displayed value.
    var onChange: ((Bool) -> Void)?
    /// Whether the row accepts taps.
    var isRowEnabled = true {
        didSet {
            switchView.isEnabled = isRowEnabled
            content.alpha = isRowEnabled ? 1 : 0.4
            updateAccessibility()
        }
    }

    /// The displayed state.
    var isOn: Bool { switchView.isOn }

    /// Creates a row bound to a setting.
    ///
    /// - Parameters:
    ///   - title: Title Case name.
    ///   - detail: Optional description.
    ///   - key: The `fst.*` key it reads and writes.
    ///   - fallback: The key's registered default.
    ///   - inverted: Show the opposite of the stored value (Highlight Shop Items).
    ///   - accessibilityLabel: A label that replaces "title, detail".
    ///   - hint: The accessibility hint.
    ///   - identifier: The accessibility identifier.
    ///   - leading: A decorative view before the label (an instrument icon).
    init(
        title: String, detail: String? = nil, key: String, default fallback: Bool, inverted: Bool = false,
        accessibilityLabel: String? = nil, hint: String? = nil, identifier: String, leading: UIView? = nil
    ) {
        titleText = accessibilityLabel ?? (detail.map { "\(title), \($0)" } ?? title)
        detailText = detail
        self.key = key
        self.fallback = fallback
        self.inverted = inverted
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UKSettingLabel(title, detail: detail)
        let row = UIStackView(arrangedSubviews: (leading.map { [$0] } ?? []) + [label, switchView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = leading == nil ? 12 : 12
        row.translatesAutoresizingMaskIntoConstraints = false
        switchView.setContentHuggingPriority(.required, for: .horizontal)
        switchView.setContentCompressionResistancePriority(.required, for: .horizontal)
        switchView.isAccessibilityElement = false
        switchView.addAction(UIAction { [weak self] _ in self?.switchFlipped() }, for: .valueChanged)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        isAccessibilityElement = true
        accessibilityIdentifier = identifier
        accessibilityHint = hint
        accessibilityTraits = .toggleButton
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads the setting into the switch.
    func sync() {
        let stored = UKSettings.bool(key, default: fallback)
        let shown = inverted ? !stored : stored
        if switchView.isOn != shown { switchView.setOn(shown, animated: window != nil) }
        updateAccessibility()
    }

    private func switchFlipped() {
        UKSettingsStore.set(inverted ? !switchView.isOn : switchView.isOn, forKey: key)
        updateAccessibility()
        onChange?(switchView.isOn)
    }

    @objc private func rowTapped() {
        guard isRowEnabled else { return }
        switchView.setOn(!switchView.isOn, animated: true)
        switchFlipped()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UISwitch)
    }

    override func accessibilityActivate() -> Bool {
        guard isRowEnabled else { return false }
        rowTapped()
        return true
    }

    private func updateAccessibility() {
        accessibilityLabel = titleText
        accessibilityValue = switchView.isOn ? "1" : "0"
        accessibilityTraits = isRowEnabled ? .toggleButton : [.toggleButton, .notEnabled]
    }
}

// MARK: - Link rows

/// A standalone link row (``SettingsScreen``'s `chevronRow`): the section title and
/// description with a trailing chevron, no card, the whole row tappable. In a split it
/// shows the open state with an accent fill and bar.
@MainActor
final class UKSettingsLinkRow: UIControl {
    private let fill = UIView()
    private let bar = UIView()
    private var action: () -> Void

    /// Whether the row's route is open beside the list.
    var isOpen = false {
        didSet {
            fill.isHidden = !isOpen
            bar.isHidden = !isOpen
            accessibilityTraits = isOpen ? [.button, .selected] : .button
        }
    }

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: Title Case section title.
    ///   - subtitle: Sentence-case description, also the accessibility hint.
    ///   - label: Accessibility label.
    ///   - identifier: Accessibility identifier.
    ///   - inCard: Row sits in a card (label and description, no header styling).
    ///   - action: Runs when tapped.
    init(
        title: String, subtitle: String, label: String, identifier: String, inCard: Bool = false,
        action: @escaping () -> Void
    ) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = BrandUIColors.accentBlue.withAlphaComponent(0.22)
        fill.layer.cornerRadius = 12
        fill.layer.cornerCurve = .continuous
        fill.isHidden = true
        fill.isUserInteractionEnabled = false
        bar.backgroundColor = BrandUIColors.accentBlue
        bar.layer.cornerRadius = 1.5
        bar.isHidden = true
        bar.isUserInteractionEnabled = false
        let text: UIView = inCard ? UKSettingLabel(title, detail: subtitle) : UKSectionHeaderView(title, subtitle: subtitle)
        text.isUserInteractionEnabled = false
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [text, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = inCard ? 8 : 16
        row.isUserInteractionEnabled = false
        for view in [fill, bar, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset: CGFloat = inCard ? 0 : 4
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: leadingAnchor), fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor), fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.widthAnchor.constraint(equalToConstant: 3),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 8), bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + (inCard ? 0 : 4)),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: inCard ? 0 : 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: inCard ? 0 : -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityHint = subtitle
        accessibilityIdentifier = identifier
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in self?.action() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// A button row with a trailing accent "Show" word (What's New).
@MainActor
final class UKSettingsShowRow: UIControl {
    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: Setting title.
    ///   - detail: Description.
    ///   - action: Trailing word ("Show").
    ///   - hint: Accessibility hint.
    ///   - identifier: Accessibility identifier.
    ///   - onTap: Runs when tapped.
    init(title: String, detail: String, action: String, hint: String, identifier: String, onTap: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UKSettingLabel(title, detail: detail)
        label.isUserInteractionEnabled = false
        let word = UKLabel(action, style: .subheadline, weight: .semibold, color: BrandUIColors.accentBlue, lines: 1)
        word.setContentHuggingPriority(.required, for: .horizontal)
        word.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, word])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(detail), \(action)"
        accessibilityHint = hint
        accessibilityIdentifier = identifier
        accessibilityTraits = .button
        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

// MARK: - Buttons

/// Buttons in the Settings lane's styles.
@MainActor
enum UKSettingsButtons {
    /// A prominent filled button (`.borderedProminent` with `AccentText.prominentFill`).
    ///
    /// - Parameters:
    ///   - title: Label.
    ///   - font: Label font.
    ///   - fill: Fill override (the brand red of Reset).
    ///   - identifier: Accessibility identifier.
    ///   - verticalPadding: Padding above and below the label.
    ///   - action: Runs when tapped.
    /// - Returns: The button.
    static func prominent(
        _ title: String, font: UIFont, fill: UIColor? = nil, identifier: String, verticalPadding: CGFloat = 6,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        let colors = UKAccentText.prominentColors(increasedContrast: UKAccessibility.moreContrast)
        configuration.baseBackgroundColor = fill ?? colors.fill
        configuration.baseForegroundColor = fill == nil ? colors.label : BrandUIColors.textPrimary
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: verticalPadding, leading: 12, bottom: verticalPadding, trailing: 12)
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
}

// MARK: - Section card

/// A Settings section on the shared group card (``SettingsSectionCard`` over
/// ``FestivalGlassSection``): titled with its description above the card, or untitled with
/// only the description above (a topic page, whose pane title names it). Rows are separated
/// by inset hairlines; an accordion row (``UKSettingsAccordionRow``) joins the card only
/// while it is open, as ``FestivalAccordionContent`` does.
@MainActor
final class UKSettingsSection: UIView {
    /// The card; rows live in it.
    let card = UKCardView(cornerRadius: UKGroupSectionView.cornerRadius)
    private let rowStack = UIStackView()

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - title: Title Case section title.
    ///   - subtitle: Sentence-case description.
    ///   - titled: False on a topic page: no header, only the description.
    init(_ title: String, subtitle: String? = nil, titled: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .vertical
        card.embed(rowStack)
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        if titled {
            outer.addArrangedSubview(Self.inset(UKSectionHeaderView(title, subtitle: subtitle)))
        } else if let subtitle {
            outer.addArrangedSubview(Self.inset(UKLabel(subtitle, style: .subheadline)))
        }
        outer.addArrangedSubview(card)
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor), outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor), outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func inset(_ view: UIView) -> UIView {
        let holder = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 4),
            view.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -4),
            view.topAnchor.constraint(equalTo: holder.topAnchor), view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    /// Replaces the card's rows.
    ///
    /// - Parameter rows: Row views; an accordion row manages its own padding and hairline.
    func setRows(_ rows: [UIView]) {
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            if row is UKSettingsAccordionRow {
                rowStack.addArrangedSubview(row)
                continue
            }
            if index > 0 { rowStack.addArrangedSubview(UKHairlineView()) }
            rowStack.addArrangedSubview(UKGroupSectionView.paddedRow(row))
        }
    }
}

/// A block that joins its card only while open, in the shared accordion choreography
/// (pattern `accordion`): a hairline above the padded content.
@MainActor
final class UKSettingsAccordionRow: UIView {
    private let accordion: UKAccordionView<Bool>
    private let hairline = UKHairlineView()

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - isOpen: Whether it starts open.
    ///   - content: Builds the block.
    init(isOpen: Bool, content: @escaping () -> UIView) {
        accordion = UKAccordionView<Bool>(isOpen ? true : nil) { _ in UKGroupSectionView.paddedRow(content()) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [hairline, accordion])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hairline.isHidden = !isOpen
        accordion.onLayoutChange = { [weak self] in self?.hairline.isHidden = self?.accordion.state.shown == nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Opens or closes the block.
    ///
    /// - Parameter open: The wanted state.
    func follow(_ open: Bool) {
        if open { hairline.isHidden = false }
        accordion.follow(open ? true : nil)
    }
}
#endif
