#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Section header

/// White, Title Case section title shared by every page, sheet and drawer
/// (``FestivalSectionHeader``): a headline with the heading trait and an optional
/// subheadline. Hinge-side placement (section-headers R10) is the hosting layout's job.
final class UKSectionHeaderView: UIView {
    private let titleLabel = UKLabel(style: .headline).asHeader()
    private let subtitleLabel = UKLabel(style: .subheadline)

    /// Creates a section header.
    ///
    /// - Parameters:
    ///   - title: Title Case heading text.
    ///   - subtitle: Optional supporting line (white).
    init(_ title: String, subtitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the texts.
    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
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
    /// - Parameter leadingInset: Distance from the leading edge.
    init(leadingInset: CGFloat = 0) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        let line = UIView()
        line.backgroundColor = BrandUIColors.glassBorder
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
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
    /// Corner radius of the card (the Rivals and Settings group card).
    static let cornerRadius = FestivalGroupCardMetrics.cornerRadius
    /// Minimum height of a padded row.
    static let minimumRowHeight: CGFloat = 44

    /// The card; rows and the action live in it.
    let card: UKCardView
    private let rowStack = UIStackView()
    private let actionHolder = UIView()
    private let rowStyle: FestivalGroupRows
    private let headerView: UKSectionHeaderView?

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - title: Title Case header, or nil for an untitled card.
    ///   - subtitle: Optional description under the title.
    ///   - rows: ``FestivalGroupRows/padded`` or ``FestivalGroupRows/flush(separatorInset:)``.
    init(_ title: String? = nil, subtitle: String? = nil, rows: FestivalGroupRows = .padded) {
        rowStyle = rows
        card = UKCardView(cornerRadius: Self.cornerRadius)
        headerView = title.map { UKSectionHeaderView($0, subtitle: subtitle) }
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
        card.embed(cardContent)
        if case .flush = rows { card.clipsContent = true }
        let outer = UIStackView(arrangedSubviews: [headerView.map { Self.inset($0, horizontal: 4) }, card].compactMap { $0 })
        outer.axis = .vertical
        outer.spacing = 8
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

    /// Replaces the card's rows; each becomes one row with a hairline above all but the
    /// first. Padded rows get the 44 pt minimum height and 16 x 6 pt padding.
    ///
    /// - Parameter rows: The row views.
    func setRows(_ rows: [UIView]) {
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in rows.enumerated() {
            if index > 0 { rowStack.addArrangedSubview(UKHairlineView(leadingInset: rowStyle.separatorInset)) }
            switch rowStyle {
            case .padded: rowStack.addArrangedSubview(Self.paddedRow(row))
            case .flush: rowStack.addArrangedSubview(row)
            }
        }
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

    /// Wraps a row in ``FestivalRowPadding``'s frame (44 pt minimum, 16 x 6 pt padding).
    ///
    /// - Parameter row: The row content.
    /// - Returns: The padded row.
    static func paddedRow(_ row: UIView) -> UIView {
        let holder = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: holder.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -6),
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumRowHeight),
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
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
