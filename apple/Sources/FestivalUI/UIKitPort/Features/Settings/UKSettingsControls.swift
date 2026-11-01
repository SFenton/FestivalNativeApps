#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Value row

/// The read-only title/value row (pattern `settings-value-row`, ``SettingsValueRow``): the
/// value sits at the row's end while the title, a 12 pt gap and the value fit at their
/// natural widths, otherwise it stacks 4 pt under the title and supporting text (R1, R2).
/// The row is one non-interactive static-text element read title, supporting text, value (R3).
@MainActor
final class UKSettingsValueRow: UIView {
    private let titleLabel: UKLabel
    private let detailLabel: UKLabel?
    private let valueView: UIView
    private var inlineConstraints: [NSLayoutConstraint] = []
    private var stackedConstraints: [NSLayoutConstraint] = []
    private var inline = true

    /// Creates a row with a custom value view.
    ///
    /// - Parameters:
    ///   - title: Title Case row name.
    ///   - detail: Optional supporting text under the title.
    ///   - spokenValue: The value as VoiceOver reads it.
    ///   - identifier: The row's accessibility identifier.
    ///   - value: The trailing (or stacked) value view.
    init(_ title: String, detail: String? = nil, spokenValue: String, identifier: String, value: UIView) {
        titleLabel = UKLabel(title, style: .body, weight: .semibold)
        detailLabel = detail.map { UKLabel($0, style: .subheadline) }
        valueView = value
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        value.translatesAutoresizingMaskIntoConstraints = false
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [titleLabel, detailLabel, value].compactMap({ $0 }) { addSubview(view) }
        let spacing = SettingsValueRowLayout.stackSpacing
        let gap = SettingsValueRowLayout.inlineGap
        let lead = detailLabel ?? titleLabel
        // Inline: the title column (title, detail) leading, the value at the end, centred.
        inlineConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor, constant: -gap),
            value.trailingAnchor.constraint(equalTo: trailingAnchor),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: value.bottomAnchor),
            lead.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if let detailLabel {
            inlineConstraints += [
                detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: spacing),
                detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor, constant: -gap),
            ]
        }
        stackedConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor), titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            value.leadingAnchor.constraint(equalTo: leadingAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            value.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if let detailLabel {
            stackedConstraints += [
                detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: spacing),
                value.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: spacing),
            ]
        } else {
            stackedConstraints.append(value.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: spacing))
        }
        NSLayoutConstraint.activate(inlineConstraints)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = SettingsValueRowLayout.spokenLabel(title: title, detail: detail)
        accessibilityValue = spokenValue
        accessibilityIdentifier = identifier
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKSettingsValueRow, _) in
            self.setNeedsLayout()
        }
    }

    /// Creates a row whose value is plain text.
    ///
    /// - Parameters:
    ///   - title: Title Case row name.
    ///   - value: The displayed value.
    ///   - spokenValue: The value as VoiceOver reads it when it differs from the text.
    ///   - identifier: The row's accessibility identifier.
    convenience init(_ title: String, value: String, spokenValue: String? = nil, identifier: String) {
        self.init(
            title, spokenValue: spokenValue ?? value, identifier: identifier,
            value: UKLabel(value, style: .body, lines: 0, alignment: .right)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The value text of a plain-text row.
    var valueLabel: UILabel? { valueView as? UILabel }

    /// Replaces the value of a plain-text row and its spoken value.
    ///
    /// - Parameters:
    ///   - text: The displayed value.
    ///   - spoken: The spoken value, or nil to speak `text`.
    func setValue(_ text: String, spoken: String? = nil) {
        valueLabel?.text = text
        accessibilityValue = spoken ?? text
        setNeedsLayout()
    }

    /// Replaces the supporting text and the spoken value of a custom-value row.
    func setDetail(_ text: String?, spokenValue: String) {
        detailLabel?.text = text
        accessibilityLabel = SettingsValueRowLayout.spokenLabel(title: titleLabel.text ?? "", detail: text)
        accessibilityValue = spokenValue
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let titleWidth = titleLabel.attributedText.map { $0.size().width }
            ?? ((titleLabel.text ?? "") as NSString).size(withAttributes: [.font: titleLabel.font as Any]).width
        let valueWidth = valueView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let fits = SettingsValueRowLayout.fitsInline(titleWidth: ceil(titleWidth), valueWidth: valueWidth, available: bounds.width)
        guard fits != inline else { return }
        inline = fits
        NSLayoutConstraint.deactivate(fits ? stackedConstraints : inlineConstraints)
        NSLayoutConstraint.activate(fits ? inlineConstraints : stackedConstraints)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }
}

// MARK: - Choice row

/// A single-choice setting shown as an inline accordion (``SettingsChoiceRow``): the
/// collapsed row shows the title, description and current value; expanding reveals one
/// checkmark row per option, and choosing writes in place.
@MainActor
final class UKSettingsChoiceRow<Value: RawRepresentable & CaseIterable & Hashable>: UIView where Value.RawValue == String {
    private let header = UIControl()
    private let valueLabel = UKLabel(style: .body, lines: 0)
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var optionButtons: [UIButton] = []
    private let accordion: UKAccordionView<Bool>
    private let titleText: String
    private let detailText: String?
    private let label: (Value) -> String
    private let identifier: String
    private let key: String
    private let fallback: Value
    private var expanded = false

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: Title Case setting name; also the spoken label.
    ///   - detail: Optional description under the title.
    ///   - key: The `fst.*` key it reads and writes (the raw value).
    ///   - fallback: The registered default.
    ///   - label: Visible and spoken name for a choice.
    ///   - identifier: Identifier of the header; options append `.<raw value>`.
    init(
        title: String, detail: String?, key: String, default fallback: Value, label: @escaping (Value) -> String,
        identifier: String
    ) {
        self.titleText = title
        self.detailText = detail
        self.label = label
        self.identifier = identifier
        self.key = key
        self.fallback = fallback
        let options = UIStackView()
        accordion = UKAccordionView<Bool>(nil) { _ in options }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let body = options
        body.axis = .vertical
        body.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
        body.isLayoutMarginsRelativeArrangement = true
        for option in Value.allCases {
            let button = optionRow(option)
            optionButtons.append(button)
            body.addArrangedSubview(button)
        }
        let text = UKSettingLabel(title, detail: detail)
        text.isUserInteractionEnabled = false
        valueLabel.isUserInteractionEnabled = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [text, valueLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor), row.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            row.topAnchor.constraint(equalTo: header.topAnchor), row.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        header.isAccessibilityElement = true
        header.accessibilityTraits = .button
        header.accessibilityLabel = title
        header.accessibilityHint = detail ?? ""
        header.accessibilityIdentifier = identifier
        header.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [header, accordion])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var selection: Value {
        Value(rawValue: UKSettingsStore.string(key, default: fallback.rawValue)) ?? fallback
    }

    /// Reads the setting into the header and the option checkmarks.
    func sync() {
        let current = selection
        valueLabel.text = label(current)
        header.accessibilityValue = SettingsChoiceAccessibility.value(selected: label(current), isExpanded: expanded)
        for button in optionButtons {
            let isSelected = button.accessibilityIdentifier == "\(identifier).\(current.rawValue)"
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
            button.configuration?.image = isSelected ? UIImage(systemName: "checkmark") : nil
        }
    }

    private func toggle() {
        expanded.toggle()
        accordion.follow(expanded ? true : nil)
        let transform = expanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        if UKAccessibility.reduceMotion {
            chevron.transform = transform
        } else {
            UIView.animate(withDuration: AccordionChoreography.resizeDuration, delay: 0, options: .curveEaseInOut) {
                self.chevron.transform = transform
            }
        }
        sync()
    }

    private func optionRow(_ option: Value) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = label(option)
        configuration.baseForegroundColor = BrandUIColors.textPrimary
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.titleAlignment = .leading
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.font(.body)
            return attributes
        }
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in BrandUIColors.accentBlue }
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .fill
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.configurationUpdateHandler = nil
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.accessibilityLabel = label(option)
        button.accessibilityIdentifier = "\(identifier).\(option.rawValue)"
        button.addAction(UIAction { [weak self] _ in
            UKSettingsStore.set(option.rawValue, forKey: self?.key ?? "")
            self?.sync()
        }, for: .touchUpInside)
        return button
    }
}

// MARK: - Reorder list

/// An inline drag-to-reorder list inside a Settings card (``SettingsReorderList``): bordered
/// rows with a grip glyph and a semibold label, reordered by dragging the grip. Each row also
/// offers Move Up and Move Down accessibility actions and announces its position. The page
/// stops scrolling only while a row is lifted.
@MainActor
final class UKSettingsReorderList<Item: Hashable>: UIView {
    private let items: [Item]
    private let labelFor: (Item) -> String
    private let keyFor: (Item) -> String
    private let identifier: String
    private let onMove: ([Item]) -> Void
    private var rows: [UIView] = []
    private let rowStack = UIStackView()
    private var dragging: Int?
    private var dragStart: CGFloat = 0
    private let feedback = UISelectionFeedbackGenerator()
    private var lastDestination: Int?

    /// Creates the list.
    ///
    /// - Parameters:
    ///   - items: Rows in their current order.
    ///   - identifier: Accessibility identifier prefix for the list and its rows.
    ///   - label: Visible row title.
    ///   - key: Stable identifier suffix for a row.
    ///   - onMove: Receives the complete new order after a drag or accessibility move.
    init(
        items: [Item], identifier: String, label: @escaping (Item) -> String, key: @escaping (Item) -> String,
        onMove: @escaping ([Item]) -> Void
    ) {
        self.items = items
        self.identifier = identifier
        self.labelFor = label
        self.keyFor = key
        self.onMove = onMove
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = BrandUIColors.surfaceMuted.withAlphaComponent(0.35)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderColor = BrandUIColors.glassBorder.cgColor
        layer.borderWidth = 1
        rowStack.axis = .vertical
        rowStack.spacing = 0
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor), rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor), rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (index, item) in items.enumerated() {
            let row = makeRow(item, index: index)
            rows.append(row)
            if index > 0 { rowStack.addArrangedSubview(UKHairlineView()) }
            rowStack.addArrangedSubview(row)
        }
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = identifier
        accessibilityElements = rows
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The measured spacing between row tops (row height plus its hairline).
    private var rowPitch: CGFloat { (rows.first?.bounds.height ?? 48) + 1 }

    private func makeRow(_ item: Item, index: Int) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let grip = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        grip.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        grip.tintColor = BrandUIColors.textMuted
        grip.contentMode = .center
        grip.isUserInteractionEnabled = true
        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.tag = index
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        drag.minimumPressDuration = 0
        drag.allowableMovement = .greatestFiniteMagnitude
        grip.addGestureRecognizer(drag)
        let text = UKLabel(labelFor(item), style: .body, weight: .semibold)
        text.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(grip)
        row.addSubview(text)
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            grip.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 44), grip.heightAnchor.constraint(equalToConstant: 44),
            text.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        row.isAccessibilityElement = true
        row.accessibilityTraits = .staticText
        row.accessibilityLabel = labelFor(item)
        row.accessibilityValue = "\(index + 1) of \(items.count)"
        row.accessibilityHint = "Drag the handle to reorder, or use the Move actions."
        row.accessibilityIdentifier = "\(identifier).\(keyFor(item))"
        row.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move Up") { [weak self] _ in self?.move(from: index, to: index - 1) ?? false },
            UIAccessibilityCustomAction(name: "Move Down") { [weak self] _ in self?.move(from: index, to: index + 1) ?? false },
        ]
        return row
    }

    private func move(from: Int, to: Int) -> Bool {
        guard items.indices.contains(to) else { return false }
        onMove(SettingsReorder.moved(items, from: from, to: to))
        return true
    }

    private func destination(from index: Int, translation: CGFloat) -> Int {
        SettingsReorder.destination(from: index, translation: translation, rowHeight: rowPitch, count: items.count)
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let grip = gesture.view else { return }
        let index = grip.tag
        let y = gesture.location(in: window).y
        switch gesture.state {
        case .began:
            dragging = index
            dragStart = y
            lastDestination = index
            superview?.bringSubviewToFront(self)
            rows[index].superview?.bringSubviewToFront(rows[index])
            feedback.prepare()
            UIView.animate(withDuration: UKAccessibility.reduceMotion ? 0 : 0.15) {
                self.rows[index].backgroundColor = BrandUIColors.surfaceFrosted
                self.rows[index].transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
                self.rows[index].layer.shadowColor = UIColor.black.cgColor
                self.rows[index].layer.shadowOpacity = 0.4
                self.rows[index].layer.shadowRadius = 8
                self.rows[index].layer.shadowOffset = CGSize(width: 0, height: 4)
            }
            setPageScrolling(false)
        case .changed:
            guard let from = dragging else { return }
            let translation = y - dragStart
            let to = destination(from: from, translation: translation)
            rows[from].transform = CGAffineTransform(translationX: 0, y: translation).scaledBy(x: 1.02, y: 1.02)
            for (position, row) in rows.enumerated() where position != from {
                var offset: CGFloat = 0
                if from < to, position > from, position <= to { offset = -rowPitch }
                if from > to, position < from, position >= to { offset = rowPitch }
                if row.transform.ty != offset {
                    UIView.animate(withDuration: UKAccessibility.reduceMotion ? 0 : 0.15, delay: 0, options: .curveEaseOut) {
                        row.transform = CGAffineTransform(translationX: 0, y: offset)
                    }
                }
            }
            if lastDestination != to {
                lastDestination = to
                feedback.selectionChanged()
            }
        case .ended, .cancelled, .failed:
            guard let from = dragging else { return }
            let to = gesture.state == .ended ? destination(from: from, translation: y - dragStart) : from
            dragging = nil
            setPageScrolling(true)
            if to != from {
                UIView.performWithoutAnimation {
                    rows.forEach { $0.transform = .identity }
                }
                onMove(SettingsReorder.moved(items, from: from, to: to))
            } else {
                UIView.animate(withDuration: UKAccessibility.reduceMotion ? 0 : 0.15) {
                    self.rows.forEach {
                        $0.transform = .identity
                        $0.backgroundColor = nil
                        $0.layer.shadowOpacity = 0
                    }
                }
            }
        default: break
        }
    }

    private func setPageScrolling(_ enabled: Bool) {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView {
                scroll.isScrollEnabled = enabled
                return
            }
            view = current.superview
        }
    }
}

// MARK: - Leeway block

/// The Maximum Score Leeway block under Filter Invalid Scores: a title, an example sentence
/// and a slider over ``InvalidScoreFilter/range``.
@MainActor
final class UKSettingsLeewayBlock: UIStackView {
    private let titleLabel = UKLabel(style: .body, weight: .semibold)
    private let detailLabel = UKLabel(style: .footnote)
    private let slider = UISlider()
    private static let key = "fst.settings.leeway"

    /// Creates the block.
    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = Float(InvalidScoreFilter.range.lowerBound)
        slider.maximumValue = Float(InvalidScoreFilter.range.upperBound)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.accessibilityLabel = "Max Score Leeway"
        slider.accessibilityIdentifier = "fst.settings.leeway"
        slider.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        slider.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        for view in [titleLabel, detailLabel, slider] { addArrangedSubview(view) }
        sync()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads the stored leeway into the slider and texts.
    func sync() {
        let leeway = UKSettingsStore.double(Self.key, default: 1)
        if abs(Double(slider.value) - leeway) > 0.0001 { slider.value = Float(leeway) }
        let text = ScoreFormatting.leeway(leeway)
        titleLabel.text = "Maximum Score Leeway: \(text)"
        let ceiling = InvalidScoreFilter.ceiling(maxScore: InvalidScoreFilter.exampleMaxScore, leeway: leeway).formatted()
        detailLabel.text = "A CHOpt path with a max score of 100k and \(text) leeway accepts scores up to \(ceiling) as valid."
        slider.accessibilityValue = text
    }

    private func changed() {
        UKSettingsStore.set(InvalidScoreFilter.normalized(Double(slider.value)), forKey: Self.key)
        sync()
    }
}
#endif
