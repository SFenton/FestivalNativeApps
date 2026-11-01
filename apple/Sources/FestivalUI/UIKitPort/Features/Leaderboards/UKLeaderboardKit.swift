#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Shared metrics

/// Metrics every leaderboard row shares (the SwiftUI `RankingRowLayout` and
/// `SongLeaderboardRowCard` constants).
enum UKLeaderboardMetrics {
    /// Spacing between a ranking row's columns.
    static let columnSpacing: CGFloat = 10
    /// Horizontal padding inside a row, also the group card's hairline inset.
    static let horizontalPadding: CGFloat = 14
    /// A rankings board's gap between two rows and above the pinned chrome.
    static let rowGap: CGFloat = 6
    /// Minimum height of a leaderboard row (web `entryRowHeight`).
    static var minHeight: CGFloat { LeaderboardRowMetrics.minHeight }
    /// Corner radius of a board's group card.
    static let cardRadius: CGFloat = FestivalGroupCardMetrics.cornerRadius
    /// Fill of the selected player's row (web `Colors.purpleHighlight`).
    static let playerFill = UIColor(red: 75 / 255, green: 15 / 255, blue: 99 / 255, alpha: 0.75)
    /// Border of the selected player's own card (web `Colors.purpleHighlightBorder`).
    static let playerBorder = UIColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 0.5)
}

// MARK: - Column slot

/// A column that keeps a fixed minimum width across rows (``LeaderboardColumnSlot``) with a
/// template that can change as the section's widest label changes; the content aligns to
/// the slot's leading or trailing edge.
final class UKColumnSlot: UIView {
    private let content: UIView
    private let style: UIFont.TextStyle
    private let monospacedBold: Bool
    private var widthConstraint: NSLayoutConstraint?
    private var floor: CGFloat = 0

    /// The widest string the column shows; nil lets the column shrink to its content.
    var template: String? { didSet { if template != oldValue { applyTemplate() } } }

    /// Creates a slot.
    ///
    /// - Parameters:
    ///   - content: The column's content.
    ///   - style: The text style the template is measured in.
    ///   - bold: Measure the template bold (rank and rating columns).
    ///   - minimumWidth: A width floor used while there is no template (the SwiftUI row's scaled 40 pt rank column).
    init(content: UIView, style: UIFont.TextStyle = .body, bold: Bool = true, minimumWidth: CGFloat = 0) {
        self.content = content
        self.style = style
        self.monospacedBold = bold
        self.floor = minimumWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKColumnSlot, _) in
            self.applyTemplate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-measures the template, e.g. after the minimum floor changed.
    func applyTemplate() {
        widthConstraint?.isActive = false
        widthConstraint = nil
        var width: CGFloat = 0
        if let template, !template.isEmpty, !UKFont.isAccessibilitySize(traitCollection) {
            let font = UKFont.font(style, weight: monospacedBold ? .bold : nil, monospacedDigit: true)
            width = ceil((template as NSString).size(withAttributes: [.font: font]).width)
        } else if template == nil, !UKFont.isAccessibilitySize(traitCollection) {
            width = UKFont.scaled(floor, relativeTo: .body, traits: traitCollection)
        }
        guard width > 0 else { return }
        widthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: width)
        widthConstraint?.isActive = true
    }
}

// MARK: - Small shared views

/// The in-card disclosure chevron (`chevron.forward`, footnote semibold, muted).
@MainActor
func ukRowChevron() -> UIImageView {
    let image = UIImageView(image: UIImage(
        systemName: "chevron.forward",
        withConfiguration: UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
    ))
    image.tintColor = BrandUIColors.textMuted
    image.contentMode = .scaleAspectFit
    image.isAccessibilityElement = false
    image.translatesAutoresizingMaskIntoConstraints = false
    image.setContentHuggingPriority(.required, for: .horizontal)
    image.setContentCompressionResistancePriority(.required, for: .horizontal)
    return image
}

/// A one-line label in the row text rules.
@MainActor
func ukRowLabel(
    _ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, monospaced: Bool = false,
    color: UIColor = BrandUIColors.textPrimary, lines: Int = 1, alignment: NSTextAlignment = .natural
) -> UKLabel {
    let label = UKLabel(nil, style: style, weight: weight, monospacedDigit: monospaced, color: color, lines: lines, alignment: alignment)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
}

/// A row content view that hosts a shared, init-configured row view (rebuilt on every
/// ``apply``), so the boards draw the shared Common row parts instead of a second copy.
class UKRowHostView: UIView {
    private var hosted: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the hosted view.
    ///
    /// - Parameter view: The shared row view.
    func host(_ view: UIView) {
        hosted?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosted = view
        isAccessibilityElement = false
        accessibilityElements = [view]
    }
}

/// A flexible holder for a row's name column: it takes the row's slack (no intrinsic
/// width of its own), and the marquee inside keeps its natural width up to the holder's
/// width, scrolling when it does not fit.
///
/// - Parameter marquee: The name marquee.
/// - Returns: The holder to put in the row's stack.
@MainActor
func ukNameHolder(_ marquee: UIView) -> UIView {
    let holder = UIView()
    holder.translatesAutoresizingMaskIntoConstraints = false
    marquee.translatesAutoresizingMaskIntoConstraints = false
    holder.addSubview(marquee)
    NSLayoutConstraint.activate([
        marquee.leadingAnchor.constraint(equalTo: holder.leadingAnchor), marquee.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        marquee.topAnchor.constraint(equalTo: holder.topAnchor), marquee.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
    ])
    let fill = marquee.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
    fill.priority = UILayoutPriority(1)
    fill.isActive = true
    holder.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    holder.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
    return holder
}

// MARK: - Row models

/// What a leaderboard cell shows: the row kind decides which content view the one
/// ``UKLeaderboardRowCell`` hosts.
struct UKLeaderboardRow {
    /// The content view a row needs.
    enum Kind: Hashable {
        case ranking, song, songBand, history
    }

    /// Selects the content view.
    var kind: Kind
    /// Creates a content view of this kind.
    var make: @MainActor () -> UIView
    /// Applies this row's values to a content view of its kind.
    var apply: @MainActor (UIView) -> Void
    /// The selected player's row: a flat purple band inside the group card.
    var isSelectedBand = false
    /// The content draws its own card (Score History's rows); the cell draws none.
    var bare = false
    /// Runs when the row is tapped or activated; nil for a read-only row.
    var onTap: (() -> Void)?
}

/// The one collection-view cell every leaderboard board uses: a segment of the board's
/// group card (``UKCardView`` with a ``FestivalGroupSegment``), a hairline above all but
/// the first row, the selected-player band, and the row's content view.
final class UKLeaderboardRowCell: UKSelfSizingCell {
    /// Reuse identifier.
    static let reuseIdentifier = "UKLeaderboardRowCell"

    private let card = UKCardView(cornerRadius: UKLeaderboardMetrics.cardRadius)
    private let band = UIView()
    private let hairline = UKHairlineView(leadingInset: UKLeaderboardMetrics.horizontalPadding)
    private var content: UIView?
    private var kind: UKLeaderboardRow.Kind?
    private var topInset: NSLayoutConstraint!
    private var pressedDim = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        card.clipsContent = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        band.backgroundColor = UKLeaderboardMetrics.playerFill
        band.translatesAutoresizingMaskIntoConstraints = false
        band.isHidden = true
        card.contentView.addSubview(band)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(hairline)
        topInset = band.topAnchor.constraint(equalTo: card.contentView.topAnchor)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            band.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor), band.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            topInset, band.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: card.contentView.topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
    }

    override var isHighlighted: Bool {
        didSet { content?.alpha = isHighlighted ? 0.55 : 1 }
    }

    /// Fills the cell.
    ///
    /// - Parameters:
    ///   - row: The row's model.
    ///   - segment: This row's place in its column's group card.
    func configure(_ row: UKLeaderboardRow, segment: FestivalGroupSegment) {
        card.segment = segment
        card.isHidden = row.bare
        hairline.isHidden = segment.isFirst || row.bare
        band.isHidden = !row.isSelectedBand
        if kind != row.kind || content == nil {
            content?.removeFromSuperview()
            let made = row.make()
            made.translatesAutoresizingMaskIntoConstraints = false
            card.contentView.addSubview(made)
            card.contentView.bringSubviewToFront(hairline)
            NSLayoutConstraint.activate([
                made.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
                made.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
                made.topAnchor.constraint(equalTo: card.contentView.topAnchor),
                made.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            ])
            content = made
            kind = row.kind
        }
        if let content { row.apply(content) }
        content?.alpha = 1
    }
}

// MARK: - Ranking row

/// One account- or band-rankings row (``AccountRankingRow``, ``BandRankingRow``): rank,
/// name, songs, accent-coloured value and a chevron on one line; stacked at accessibility
/// text sizes. One element for VoiceOver: a button when it opens something.
final class UKRankingRowView: UIView {
    /// What the row shows.
    struct Model {
        var rank: Int
        var name: String
        var songs: String
        var spokenSongs: String
        var rating: String
        var bayesian: String?
        var emphasized = false
        var showsChevron = false
        var columns: LeaderboardRowColumns?
        var identifier: String
        /// A link to a profile or band; false is a read-only row.
        var opensSomething = true
        /// The row's accessibility hint (anonymous rows: "Profile unavailable").
        var hint: String?
        /// Replaces the spoken label ("Your rank, 3rd. Name.").
        var spokenOverride: String?
    }

    private let rankLabel = ukRowLabel(.body, monospaced: true)
    private lazy var rankSlot = UKColumnSlot(content: rankLabel, minimumWidth: 40)
    private let nameMarquee = UKMarqueeLabel("")
    private let nameWrapping = UKLabel(nil, style: .body, lines: 0)
    private lazy var nameHolder = ukNameHolder(nameMarquee)
    private let songsLabel = ukRowLabel(.subheadline, monospaced: true, alignment: .right)
    private lazy var songsSlot = UKColumnSlot(content: songsLabel, style: .subheadline, bold: false)
    private let ratingLabel = ukRowLabel(.body, weight: .semibold, monospaced: true, color: UKAccentText.blue, alignment: .right)
    private let bayesianLabel = ukRowLabel(.caption1, monospaced: true, alignment: .right)
    private let ratingColumn = UIStackView()
    private lazy var ratingSlot = UKColumnSlot(content: ratingColumn)
    private let chevron = ukRowChevron()
    private let line = UIStackView()
    private let accessibilityLine = UIStackView()
    private let valuesLine = UIStackView()
    private var model: Model?
    private var isStacked: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        translatesAutoresizingMaskIntoConstraints = false
        ratingColumn.axis = .vertical
        ratingColumn.alignment = .trailing
        ratingColumn.addArrangedSubview(ratingLabel)
        ratingColumn.addArrangedSubview(bayesianLabel)
        ratingLabel.adjustsFontSizeToFitWidth = true
        ratingLabel.minimumScaleFactor = 0.5
        nameMarquee.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        nameWrapping.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        line.axis = .horizontal
        line.alignment = .center
        line.spacing = UKLeaderboardMetrics.columnSpacing
        accessibilityLine.axis = .vertical
        accessibilityLine.spacing = 4
        accessibilityLine.alignment = .fill
        valuesLine.axis = .horizontal
        valuesLine.alignment = .firstBaseline
        valuesLine.spacing = 8
        for stack in [line, accessibilityLine] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UKLeaderboardMetrics.horizontalPadding),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UKLeaderboardMetrics.horizontalPadding),
            line.topAnchor.constraint(equalTo: topAnchor, constant: 8), line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            accessibilityLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UKLeaderboardMetrics.horizontalPadding),
            accessibilityLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UKLeaderboardMetrics.horizontalPadding),
            accessibilityLine.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            accessibilityLine.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardMetrics.minHeight),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKRankingRowView, _) in
            if let model = self.model { self.apply(model) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityActivate() -> Bool {
        guard model?.opensSomething == true else { return false }
        return super.accessibilityActivate()
    }

    /// Fills the row.
    ///
    /// - Parameter model: The row's values.
    func apply(_ model: Model) {
        self.model = model
        let stacked = UKFont.isAccessibilitySize(traitCollection)
        let hidesSongs = model.columns?.showsSongs == false && !stacked
        rankLabel.text = "#\(model.rank.formatted())"
        nameMarquee.text = model.name
        nameMarquee.font = UKFont.font(.body, weight: model.emphasized ? .bold : nil)
        nameWrapping.text = model.name
        nameWrapping.font = UKFont.font(.body, weight: model.emphasized ? .bold : nil)
        songsLabel.text = model.songs
        songsLabel.font = UKFont.font(.subheadline, weight: model.emphasized ? .bold : nil, monospacedDigit: true)
        ratingLabel.text = model.rating
        ratingLabel.font = UKFont.font(.body, weight: model.emphasized ? .bold : .semibold, monospacedDigit: true)
        bayesianLabel.text = model.bayesian
        bayesianLabel.isHidden = model.bayesian == nil
        rankSlot.template = model.columns?.rankLabel
        songsSlot.template = model.columns?.songsLabel
        ratingSlot.template = model.columns?.ratingLabel
        arrange(stacked: stacked, model: model, hidesSongs: hidesSongs)
        // Accessibility.
        accessibilityIdentifier = model.identifier
        accessibilityTraits = model.opensSomething ? .button : .staticText
        let shownSongs = hidesSongs ? nil : model.spokenSongs
        accessibilityLabel = model.spokenOverride ?? [
            "#\(model.rank.formatted())", model.name, shownSongs, model.rating, model.bayesian,
        ].compactMap { $0 }.joined(separator: ", ")
        accessibilityValue = hidesSongs ? model.spokenSongs : nil
        accessibilityHint = model.hint
    }

    private func arrange(stacked: Bool, model: Model, hidesSongs: Bool) {
        line.isHidden = stacked
        accessibilityLine.isHidden = !stacked
        line.arrangedSubviews.forEach { line.removeArrangedSubview($0); $0.removeFromSuperview() }
        accessibilityLine.arrangedSubviews.forEach { accessibilityLine.removeArrangedSubview($0); $0.removeFromSuperview() }
        valuesLine.arrangedSubviews.forEach { valuesLine.removeArrangedSubview($0); $0.removeFromSuperview() }
        nameHolder.removeFromSuperview()
        nameWrapping.removeFromSuperview()
        if stacked {
            let head = UIStackView(arrangedSubviews: [rankSlot, nameWrapping])
            head.axis = .horizontal
            head.alignment = .firstBaseline
            head.spacing = 8
            valuesLine.addArrangedSubview(songsSlot)
            valuesLine.addArrangedSubview(UIView())
            valuesLine.addArrangedSubview(ratingSlot)
            accessibilityLine.addArrangedSubview(head)
            accessibilityLine.addArrangedSubview(valuesLine)
            // The AX row has no template columns: the slots shrink to their content.
        } else {
            line.addArrangedSubview(rankSlot)
            line.addArrangedSubview(nameHolder)
            if !hidesSongs { line.addArrangedSubview(songsSlot) }
            line.addArrangedSubview(ratingSlot)
            if model.showsChevron {
                chevron.isHidden = false
                line.addArrangedSubview(chevron)
            } else if model.columns != nil {
                chevron.isHidden = true
                line.addArrangedSubview(chevron)
            }
        }
        rankSlot.applyTemplate()
        songsSlot.applyTemplate()
        ratingSlot.applyTemplate()
    }
}
#endif
