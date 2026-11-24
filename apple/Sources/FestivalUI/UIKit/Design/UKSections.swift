#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Section header

/// White, Title Case section title shared by every page, sheet and drawer
/// (``FestivalSectionHeader``): a headline with the heading trait and an optional
/// subheadline. A full-width header can keep its text on the leading side of the
/// active fold (section-headers R10) without making the header itself narrower.
final class UKSectionHeaderView: UIView, UKWidthDependent {
    private let hingeProvider: (() -> CGRect?)?
    private var textTrailing: NSLayoutConstraint?

    /// Creates a section header.
    ///
    /// - Parameters:
    ///   - title: Title Case heading text.
    ///   - subtitle: Optional supporting line (white).
    ///   - identifier: Optional test identifier for the heading itself.
    ///   - usesSwiftUILeading: Match the SwiftUI line spacing when the subtitle wraps.
    ///   - hingeProvider: Active fold in window coordinates for a full-width section.
    init(
        _ title: String, subtitle: String? = nil, identifier: String? = nil, usesSwiftUILeading: Bool = false,
        hingeProvider: (() -> CGRect?)? = nil
    ) {
        self.hingeProvider = hingeProvider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = UKLabel(title, style: .headline).asHeader()
        titleLabel.accessibilityIdentifier = identifier
        let subtitleLabel = UKLabel(subtitle, style: .subheadline, usesSwiftUILeading: usesSwiftUILeading)
        subtitleLabel.isHidden = subtitle == nil
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let trailing = stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        textTrailing = trailing
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), trailing,
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fit the text to its leading lane; the host calls this again for a hinge-only change.
    ///
    /// - Parameter width: The proposed full width before limiting the text.
    func prepare(width: CGFloat) {
        guard let hingeProvider, let textTrailing else { return }
        var inset: CGFloat = 0
        if let fold = hingeProvider(), window != nil, width > 0 {
            var frame = bounds
            frame.size.width = width
            let span = HorizontalSpan(convert(frame, to: nil))
            if let lane = HingeColumns.titleWidth(span: span, fold: fold) { inset = width - lane }
        }
        if textTrailing.constant != -inset { textTrailing.constant = -inset }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        prepare(width: bounds.width)
    }
}

// MARK: - View All

/// The trailing "View All" push beside a section title (``SectionViewAllLink``): a 44 x 44
/// pt accent-blue text button, "View All" spoken with what is listed.
final class UKViewAllButton: UIButton {
    /// Called when tapped.
    var onTap: (() -> Void)?

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - listName: What is listed, spoken after "View All" (e.g. "SFentonX's Bands").
    ///   - onTap: Called when tapped.
    init(identifier: String, listName: String, onTap: (() -> Void)? = nil) {
        self.onTap = onTap
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "View All"
        configuration.baseForegroundColor = BrandUIColors.accentBlue
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.font(.subheadline, weight: .semibold)
            return attributes
        }
        self.configuration = configuration
        titleLabel?.adjustsFontForContentSizeCategory = true
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = "View All \(listName)"
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Hairline

/// A 1 pt row separator in the glass border colour, inset from the leading edge
/// (`FestivalGlassSection`'s hairlines); hidden from accessibility.
final class UKHairlineView: UIView {
    /// Creates a hairline.
    ///
    /// - Parameters:
    ///   - leadingInset: Distance from the leading edge.
    ///   - trailingInset: Distance from the trailing edge.
    ///   - color: The separator color for its surface.
    init(leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, color: UIColor = BrandUIColors.glassBorder) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        let line = UIView()
        line.backgroundColor = color
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: FestivalLeadingHairline.height),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset),
            line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Group section

/// A titled group of rows on one material card (``FestivalGlassSection``): the header
/// sits outside the card, rows are separated by inset hairlines, and an optional action
/// ("View All") ends the card inside it, inset by ``FestivalGroupCardMetrics/actionInset``.
final class UKGroupSectionView: UIView {
    /// Page content uses the Festival card; sheet forms use the system grouped-list fill.
    enum Surface: Equatable {
        case content
        case form
    }

    /// Corner radius of the card (the Rivals and Settings group card).
    static let cornerRadius = FestivalGroupCardMetrics.cornerRadius
    /// Minimum height of a padded row.
    static let minimumRowHeight: CGFloat = 44

    private let rowStack = UIStackView()
    private let actionHolder = UIView()
    private let rowStyle: FestivalGroupRows
    private let surface: Surface
    private var onWidthChange: ((CGFloat, UITraitCollection) -> Void)?
    private var measuredWidth: CGFloat?
    private var measuredTextSize: UIContentSizeCategory?

    private static let formInset: CGFloat = 20
    private static let formDisclosureHeaderInset: CGFloat = 15
    /// The part of the native 15 pt text inset inside a form's 4 pt padded row.
    static let formTextPadding: CGFloat = 11

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - title: Title Case header, or nil for an untitled card.
    ///   - subtitle: Optional description under the title.
    ///   - rows: ``FestivalGroupRows/padded`` or ``FestivalGroupRows/flush(separatorInset:)``.
    ///   - surface: Grouped-list appearance in a modal form, material card on a page.
    ///   - formFill: A custom form fill matching a SwiftUI row background, if specified.
    convenience init(
        _ title: String? = nil, subtitle: String? = nil, rows: FestivalGroupRows = .padded,
        surface: Surface = .content, formFill: UIColor? = nil
    ) {
        self.init(header: title.map { UKSectionHeaderView($0, subtitle: subtitle) },
                  rows: rows, surface: surface, formFill: formFill)
    }

    /// Creates a section with a custom visible header (for example a field name and its hint).
    ///
    /// - Parameters:
    ///   - header: Header content, or nil for an untitled card.
    ///   - rows: The row padding and separator style.
    ///   - surface: Grouped-list appearance in a modal form, material card on a page.
    ///   - formFill: A custom form fill matching a SwiftUI row background, if specified.
    init(
        header: UIView?, rows: FestivalGroupRows = .padded, surface: Surface = .content, formFill: UIColor? = nil
    ) {
        rowStyle = rows
        self.surface = surface
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .vertical
        rowStack.spacing = 0
        actionHolder.isHidden = true
        actionHolder.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: FestivalGroupCardMetrics.actionInset,
            leading: FestivalGroupCardMetrics.actionInset,
            bottom: FestivalGroupCardMetrics.actionInset,
            trailing: FestivalGroupCardMetrics.actionInset
        )
        let cardContent = UIStackView(arrangedSubviews: [rowStack, actionHolder])
        cardContent.axis = .vertical
        let card: UIView
        switch surface {
        case .content:
            let material = UKCardView(cornerRadius: Self.cornerRadius)
            material.embed(cardContent)
            if case .flush = rows { material.clipsContent = true }
            card = material
        case .form:
            let group = Self.inset(cardContent, horizontal: 0)
            group.backgroundColor = formFill ?? .secondarySystemGroupedBackground
            group.layer.cornerCurve = .continuous
            if #available(iOS 26.0, *) {
                group.layer.cornerRadius = 26
            } else {
                group.layer.cornerRadius = 10
            }
            group.clipsToBounds = true
            card = group
        }
        let header = header.map { Self.inset($0, horizontal: surface == .form ? Self.formInset : 4) }
        let outer = UIStackView(arrangedSubviews: [header, card].compactMap { $0 })
        outer.axis = .vertical
        outer.spacing = surface == .form ? 10 : 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor), outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor), outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private static func inset(_ view: UIView, horizontal: CGFloat) -> UIView {
        let holder = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: horizontal),
            view.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -horizontal),
            view.topAnchor.constraint(equalTo: holder.topAnchor), view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reports the laid-out card width when it or the Dynamic Type category changes.
    ///
    /// - Parameter update: Updates rows in place with their new shared layout.
    func observeWidth(_ update: @escaping (CGFloat, UITraitCollection) -> Void) {
        if onWidthChange == nil {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKGroupSectionView, _) in
                self.setNeedsLayout()
            }
        }
        onWidthChange = update
        measuredWidth = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let onWidthChange, bounds.width > 0 else { return }
        let textSize = traitCollection.preferredContentSizeCategory
        guard measuredWidth != bounds.width || measuredTextSize != textSize else { return }
        measuredWidth = bounds.width
        measuredTextSize = textSize
        onWidthChange(bounds.width, traitCollection)
    }

    /// Replaces the card's rows; each becomes one row with a hairline above all but the
    /// first. Padded rows use the insets and minimum height of their surface.
    ///
    /// - Parameter rows: The row views.
    func setRows(_ rows: [UIView]) {
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if surface == .form, case .padded = rowStyle {
            Self.formRows(rows).forEach(rowStack.addArrangedSubview)
            return
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = surface == .form
                    ? UKHairlineView(leadingInset: Self.formInset, trailingInset: Self.formInset, color: .separator)
                    : UKHairlineView(leadingInset: rowStyle.separatorInset)
                rowStack.addArrangedSubview(separator)
            }
            switch rowStyle {
            case .padded: rowStack.addArrangedSubview(Self.paddedRow(row))
            case .flush: rowStack.addArrangedSubview(row)
            }
        }
    }

    /// Builds padded form rows with the dividers inside their height. Disclosure children
    /// start beneath a divider and indent their labels without shifting the trailing controls.
    ///
    /// - Parameters:
    ///   - rows: The form controls.
    ///   - disclosureBody: Whether the parent row already supplies the outer inset.
    ///   - startsWithSeparator: Whether a preceding sibling control needs a divider below it.
    /// - Returns: Views to arrange vertically in the card.
    static func formRows(_ rows: [UIView], disclosureBody: Bool = false, startsWithSeparator: Bool = false) -> [UIView] {
        let inset = disclosureBody ? 0 : formInset
        let indent = disclosureBody ? formInset : 0
        return rows.enumerated().map { index, row in
            let holder = formRow(row, horizontal: inset, leadingIndent: indent)
            func addSeparator(atTop: Bool) {
                let separator = UKHairlineView(
                    leadingInset: atTop ? inset : inset + indent, trailingInset: inset, color: .separator
                )
                separator.isUserInteractionEnabled = false
                holder.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                    separator.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                    atTop ? separator.topAnchor.constraint(equalTo: holder.topAnchor)
                        : separator.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                ])
            }
            if (disclosureBody || startsWithSeparator) && index == 0 { addSeparator(atTop: true) }
            if index < rows.count - 1 { addSeparator(atTop: false) }
            return holder
        }
    }

    /// Makes a grouped card containing a disclosure header and its inset choice rows.
    ///
    /// - Parameters:
    ///   - label: Visible and spoken header content.
    ///   - rows: The revealed form controls.
    ///   - expanded: Whether the group starts open.
    ///   - identifier: Accessibility identifier of the disclosure button.
    /// - Returns: The card and its disclosure, for callers with additional header actions.
    static func formDisclosure(
        label: UIView, rows: [UIView], expanded: Bool, identifier: String
    ) -> (card: UKGroupSectionView, group: UKDisclosureGroupView) {
        let body = UIStackView(arrangedSubviews: formRows(rows, disclosureBody: true))
        body.axis = .vertical
        let group = UKDisclosureGroupView(
            label: label, body: body, initiallyExpanded: expanded,
            identifier: identifier, headerVerticalInset: formDisclosureHeaderInset
        )
        let card = UKGroupSectionView(rows: .flush(separatorInset: 0), surface: .form)
        card.setRows([formRow(group, vertical: 0)])
        return (card, group)
    }

    /// The secondary heading used by a plain native Form section, rather than a Festival heading.
    static func formHeading(_ title: String) -> UKLabel {
        UKLabel(title, style: .headline, color: .secondaryLabel).asHeader()
    }

    /// A native Form footer aligns with the row content, not the outside of the card.
    static func formFooter(_ text: String) -> UIView {
        inset(UKLabel(text, style: .footnote, usesSwiftUILeading: true), horizontal: formInset)
    }

    /// Text inside a native Form card has a 15 pt inset above and below, including the row's 4 pt padding.
    ///
    /// - Parameters:
    ///   - text: The explanatory text.
    ///   - style: Footnote for supporting copy; body for a status message.
    /// - Returns: The note with its inner padding.
    static func formNote(_ text: String, style: UIFont.TextStyle = .footnote) -> UIView {
        paddedRow(
            UKLabel(text, style: style, usesSwiftUILeading: true),
            horizontal: 0, vertical: formTextPadding, minimumHeight: 0
        )
    }

    /// A footnote in a padded content card keeps the minimum on the text row,
    /// with the card's vertical insets outside it, as in ``FestivalRowPadding``.
    static func contentNote(_ text: String, identifier: String? = nil) -> UKFootnoteLabel {
        let label = UKFootnoteLabel(text)
        label.accessibilityIdentifier = identifier
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumRowHeight).isActive = true
        return label
    }

    /// Sets or removes the in-card action.
    ///
    /// - Parameter action: The "View All" button, or nil while the card shows no rows.
    func setAction(_ action: UIView?) {
        actionHolder.subviews.forEach { $0.removeFromSuperview() }
        actionHolder.isHidden = action == nil
        guard let action else { return }
        action.translatesAutoresizingMaskIntoConstraints = false
        actionHolder.addSubview(action)
        let guide = actionHolder.layoutMarginsGuide
        NSLayoutConstraint.activate([
            action.leadingAnchor.constraint(equalTo: guide.leadingAnchor), action.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            action.topAnchor.constraint(equalTo: guide.topAnchor), action.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }

    /// Gives a form row the system group's row height and insets.
    ///
    /// - Parameters:
    ///   - row: The row content.
    ///   - horizontal: Use zero inside an existing form row to avoid a second inset.
    ///   - vertical: Inset for a single-line control, or a larger one for a multiline editor.
    ///   - leadingIndent: Additional space for a nested row.
    /// - Returns: The padded form row.
    static func formRow(
        _ row: UIView, horizontal: CGFloat = formInset, vertical: CGFloat = 4, leadingIndent: CGFloat = 0
    ) -> UIView {
        paddedRow(row, horizontal: horizontal, vertical: vertical, minimumHeight: 52, leadingIndent: leadingIndent)
    }

    /// Wraps a row in the supported surface's padding (default: ``FestivalRowPadding``).
    ///
    /// - Parameters:
    ///   - row: The row content.
    ///   - horizontal: Inset on either side.
    ///   - vertical: Inset above and below.
    ///   - minimumHeight: Minimum height of the padded row.
    ///   - leadingIndent: Additional space on the leading edge.
    /// - Returns: The padded row.
    static func paddedRow(
        _ row: UIView, horizontal: CGFloat = 16, vertical: CGFloat = 6, minimumHeight: CGFloat = minimumRowHeight,
        leadingIndent: CGFloat = 0
    ) -> UIView {
        let holder = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: horizontal + leadingIndent),
            row.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -horizontal),
            row.topAnchor.constraint(equalTo: holder.topAnchor, constant: vertical),
            row.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -vertical),
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
        ])
        return holder
    }
}

// MARK: - Footnote

/// Supporting text under a card (``FestivalFootnote``): white footnote text.
final class UKFootnoteLabel: UILabel {
    /// Creates a footnote.
    ///
    /// - Parameter text: The string.
    init(_ text: String) {
        super.init(frame: .zero)
        self.text = text
        font = UKFont.font(.footnote)
        adjustsFontForContentSizeCategory = true
        textColor = BrandUIColors.textPrimary
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
        setContentCompressionResistancePriority(.required, for: .vertical)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A split pane can resize this label after its page's layout callback.
        updateWrappedHeight()
    }
}
#endif
