#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Section header

/// A section's in-list title (`SongsInlineSectionTitle`): a plain row that carries the jump
/// target; the floating bar draws the same name once it has passed (the mask hides this copy
/// above the bar's edge).
final class UKSongsSectionHeaderView: UICollectionReusableView {
    static let kind = "UKSongsSectionHeader"
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 2
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UKFont.font(.subheadline, weight: .bold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = BrandUIColors.textPrimary
        label.numberOfLines = 0
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the title.
    func configure(group: SongsListGroup) {
        label.text = group.label
        accessibilityLabel = group.spokenLabel ?? group.label
        accessibilityIdentifier = group.accessibilityID
        setNeedsLayout()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let text = label.sizeThatFits(CGSize(width: layoutAttributes.size.width - 40, height: .greatestFiniteMagnitude))
        attributes.size.height = ceil(text.height) + Self.topPadding + Self.bottomPadding
        return attributes
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 20, y: Self.topPadding, width: max(0, bounds.width - 40), height: max(0, bounds.height - Self.topPadding - Self.bottomPadding))
    }
}

// MARK: - Floating section bar

/// The current section's title, floating just below the navigation bar once the list has
/// scrolled (`SongsSectionBar`), with the incoming title pushing it out. No backing: the
/// rows fade out under its bottom edge (``UKPinnedHeaderEdgeFade``).
final class UKSongsSectionBar: UIView {
    private let current = UILabel()
    private let outgoing = UILabel()
    private let incoming = UILabel()
    /// The bar's own height.
    private(set) var barHeight: CGFloat = 0
    private var currentText = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        for label in [current, outgoing, incoming] {
            label.font = UKFont.font(.subheadline, weight: .bold)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = BrandUIColors.textPrimary
            label.numberOfLines = 1
            label.isHidden = true
            addSubview(label)
        }
        for label in [outgoing, incoming] { label.isAccessibilityElement = false }
        current.isAccessibilityElement = true
        current.accessibilityTraits = .header
        current.accessibilityIdentifier = "fst.songs.section-bar"
        isAccessibilityElement = false
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The bar's height for the current text size.
    static func height() -> CGFloat {
        ceil(UKFont.font(.subheadline, weight: .bold).lineHeight) + UKSongsSectionHeaderView.topPadding + UKSongsSectionHeaderView.bottomPadding
    }

    /// Shows the titles.
    ///
    /// - Parameters:
    ///   - current: The current title and its spoken form.
    ///   - currentY: Its top within the bar (0 at rest, negative while pushed).
    ///   - outgoing: The previous title, drawn only while it leaves.
    ///   - incoming: The next title and its top while it enters.
    func update(
        current: (label: String, spoken: String)?, currentY: CGFloat, outgoing: String?, outgoingY: CGFloat,
        incoming: String?, incomingY: CGFloat
    ) {
        barHeight = Self.height()
        guard let current else { isHidden = true; return }
        isHidden = false
        let width = bounds.width - 40
        self.current.text = current.label
        self.current.accessibilityLabel = current.spoken
        place(self.current, y: currentY, width: width)
        if let outgoing {
            self.outgoing.text = outgoing
            place(self.outgoing, y: outgoingY, width: width)
        } else {
            self.outgoing.isHidden = true
        }
        if let incoming {
            self.incoming.text = incoming
            place(self.incoming, y: incomingY, width: width)
        } else {
            self.incoming.isHidden = true
        }
    }

    private func place(_ label: UILabel, y: CGFloat, width: CGFloat) {
        label.isHidden = false
        label.frame = CGRect(x: 20, y: y + UKSongsSectionHeaderView.topPadding, width: max(0, width), height: ceil(label.font.lineHeight))
    }
}

// MARK: - Notice cell

/// A cell that shows one notice view above the rows (a banner, freshness notice or retry button).
final class UKSongsNoticeCell: UICollectionViewCell {
    private var hosted: UIView?

    /// Replaces the hosted view.
    func host(_ view: UIView) {
        hosted?.removeFromSuperview()
        hosted = view
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor), view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = UKSelfSizing.fittingHeight(of: contentView, width: layoutAttributes.size.width)
        return attributes
    }
}

/// A card-plated 44 pt text button (the Songs retry and reset buttons).
enum UKSongsButtons {
    /// Builds the button.
    ///
    /// - Parameters:
    ///   - title: Label.
    ///   - identifier: Accessibility identifier.
    ///   - action: Called on tap.
    static func plated(_ title: String, identifier: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = BrandUIColors.textPrimary
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        configuration.background.backgroundColor = BrandUIColors.cardBackground
        configuration.background.cornerRadius = 10
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UKFont.font(.body)
            return outgoing
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = identifier
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
}

// MARK: - A–Z scrubber

/// The trailing A–Z jump rail (``SongSectionIndexScrubber``): a capsule of letters that scrubs
/// the list under the finger, adjustable for VoiceOver.
final class UKSongSectionIndexView: UIView {
    private let card = UKCardView(cornerRadius: 11, capsule: true)
    private var labels: [UILabel] = []
    private var entries: [SongSectionIndexScrubber.Entry] = []
    private var sections: [SongSection] = []
    private var activeIndex = 0
    private var isActive = false
    private var touchIndex: Int?
    private let feedback = UISelectionFeedbackGenerator()
    private var labelHeight: CGFloat = SongSectionIndexScrubber.defaultLabelHeight
    /// Called with a section's id as the rail passes over it.
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = true
        addSubview(card)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(scrub(_:)))
        press.minimumPressDuration = 0
        addGestureRecognizer(press)
        isAccessibilityElement = true
        accessibilityLabel = "Jump to section"
        accessibilityIdentifier = "fst.songs.section-index"
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The rail's scale for a text size (Caption 2 grows to Accessibility 2).
    static func scale(for category: UIContentSizeCategory) -> CGFloat {
        let points: CGFloat
        switch category {
        case .extraSmall, .small, .medium, .large, .unspecified: points = 11
        case .extraLarge: points = 13
        case .extraExtraLarge: points = 15
        case .extraExtraExtraLarge: points = 17
        case .accessibilityMedium: points = 20
        default: points = 24
        }
        return points / 11
    }

    /// The rail's width for a text size.
    static func width(for category: UIContentSizeCategory) -> CGFloat {
        (SongSectionIndexScrubber.baseWidth * scale(for: category)).rounded()
    }

    /// Sets the sections and fits the rail to `availableHeight`.
    ///
    /// - Parameters:
    ///   - sections: The A–Z sections.
    ///   - availableHeight: The most height the rail may take.
    /// - Returns: The rail's size.
    @discardableResult
    func configure(sections: [SongSection], availableHeight: CGFloat) -> CGSize {
        self.sections = sections
        let category = traitCollection.preferredContentSizeCategory
        let scale = Self.scale(for: category)
        let font = UKFont.font(.caption2, weight: .semibold)
        let sized = UIFont(descriptor: font.fontDescriptor, size: 11 * scale)
        labelHeight = ceil(sized.lineHeight)
        let limit = SongSectionIndexScrubber.heightLimit(labelCount: sections.count, labelHeight: labelHeight, scale: scale)
            .map { min($0, availableHeight) } ?? availableHeight
        let capacity = SongSectionIndexScrubber.capacity(availableHeight: limit, labelHeight: labelHeight)
        entries = SongSectionIndexScrubber.entries(labels: sections.map(\.label), capacity: capacity)
        while labels.count < entries.count {
            let label = UILabel()
            label.textAlignment = .center
            label.isAccessibilityElement = false
            card.contentView.addSubview(label)
            labels.append(label)
        }
        for (index, label) in labels.enumerated() {
            label.isHidden = index >= entries.count
            guard index < entries.count else { continue }
            label.font = sized
            label.text = entries[index].label
        }
        let height = 2 * SongSectionIndexScrubber.labelInset + CGFloat(entries.count) * labelHeight
            + CGFloat(max(0, entries.count - 1)) * SongSectionIndexScrubber.labelSpacing
        let size = CGSize(width: Self.width(for: category), height: height)
        accessibilityValue = sections.indices.contains(activeIndex) ? sections[activeIndex].label : ""
        refreshColors()
        setNeedsLayout()
        return size
    }

    private func refreshColors() {
        for (index, label) in labels.enumerated() where index < entries.count {
            label.textColor = isActive && entries[index].sections.contains(activeIndex) ? BrandUIColors.gold : BrandUIColors.textPrimary
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = bounds
        var y = SongSectionIndexScrubber.labelInset
        for (index, label) in labels.enumerated() where index < entries.count {
            label.frame = CGRect(x: 0, y: y, width: bounds.width, height: labelHeight)
            y += labelHeight + SongSectionIndexScrubber.labelSpacing
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: 0).contains(point)
    }

    @objc private func scrub(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let y = gesture.location(in: self).y
            guard let index = SongSectionIndexScrubber.section(
                at: y, height: bounds.height, inset: SongSectionIndexScrubber.labelInset, entries: entries
            ), sections.indices.contains(index) else { return }
            isActive = true
            guard index != touchIndex else { return }
            touchIndex = index
            if index != activeIndex {
                activeIndex = index
                feedback.selectionChanged()
            }
            accessibilityValue = sections[index].label
            refreshColors()
            onSelect?(sections[index].id)
        default:
            isActive = false
            touchIndex = nil
            refreshColors()
        }
    }

    override func accessibilityIncrement() { move(by: 1) }
    override func accessibilityDecrement() { move(by: -1) }

    private func move(by delta: Int) {
        guard !sections.isEmpty else { return }
        let index = min(sections.count - 1, max(0, activeIndex + delta))
        activeIndex = index
        accessibilityValue = sections[index].label
        onSelect?(sections[index].id)
    }
}
#endif
