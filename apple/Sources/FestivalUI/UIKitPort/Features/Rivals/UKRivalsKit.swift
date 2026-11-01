#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Visible instruments

/// The Settings-visible charts in the source's stable nine-instrument order, as
/// ``VisibleInstrumentsReader`` lists them for the SwiftUI Rivals and Compete pages.
@MainActor
enum UKRivalsInstruments {
    /// Saved-visible charts in the source order.
    ///
    /// - Returns: The instruments whose `fst.settings.show*` switch is on.
    static func visible() -> [Instrument] {
        let order: [Instrument] = [
            .lead, .bass, .drums, .vocals, .proLead, .proBass, .karaoke, .proCymbals, .proDrums,
        ]
        let visible = UKSettings.visibleInstruments()
        return order.filter(visible.contains)
    }
}

// MARK: - Prominent button

/// The filled capsule button of the empty states (`festivalProminentButton`): white on the
/// readable accent blue, or the dark page colour on white under Increase Contrast, 44 pt
/// tall at least.
final class UKProminentButton: UIButton {
    private let title: String
    private var observer: UKAccessibilityObserver?

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - title: Title Case label.
    ///   - identifier: Accessibility identifier.
    ///   - onTap: Called when pressed.
    init(title: String, identifier: String? = nil, onTap: @escaping () -> Void) {
        self.title = title
        super.init(frame: .zero)
        accessibilityIdentifier = identifier
        translatesAutoresizingMaskIntoConstraints = false
        addAction(UIAction { _ in onTap() }, for: .primaryActionTriggered)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        apply()
        observer = UKAccessibilityObserver { [weak self] in self?.apply() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKProminentButton, _) in self.apply() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply() {
        let colors = UKAccentText.prominentColors(
            increasedContrast: UKAccessibility.moreContrast || UKAccessibility.systemIncreasedContrast(traitCollection)
        )
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = colors.fill
        configuration.baseForegroundColor = colors.label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        var text = AttributedString(title)
        text.font = UKFont.font(.body, weight: .semibold)
        configuration.attributedTitle = text
        self.configuration = configuration
        titleLabel?.adjustsFontForContentSizeCategory = true
    }
}

// MARK: - Status pill

/// The red or green capsule every Rivals card draws its standing in (``RivalStatusPill``):
/// the text always carries the meaning, red text uses the lighter readable red.
final class UKRivalStatusPill: UIView {
    private let label = UILabel()

    /// Creates a pill.
    ///
    /// - Parameters:
    ///   - text: Visible label.
    ///   - tint: Status tint for the fill, stroke and (readable) text.
    ///   - singleLine: Keep the label on one line (the song rows' pills outside accessibility sizes).
    init(_ text: String, tint: UIColor, singleLine: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = UKFont.font(.caption2, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Self.readable(tint)
        label.numberOfLines = singleLine ? 1 : 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        backgroundColor = tint.withAlphaComponent(0.16)
        layer.borderColor = tint.withAlphaComponent(0.4).cgColor
        layer.borderWidth = 1
        layer.cornerCurve = .continuous
        isAccessibilityElement = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    /// The readable text colour for a status tint: the lighter red for `statusRed`
    /// (``RivalStatusText/red``), else the tint.
    ///
    /// - Parameter tint: A status tint.
    /// - Returns: The text colour.
    static func readable(_ tint: UIColor) -> UIColor {
        tint == BrandUIColors.statusRed ? UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1) : tint
    }
}

/// Lays its arranged subviews out in a row when they fit the width and one per line when
/// they do not (`ViewThatFits(in: .horizontal)`), re-deciding whenever the width changes.
final class UKFittingStack: UIStackView {
    private var settledWidth: CGFloat = 0

    override func layoutSubviews() {
        let width = bounds.width
        if width > 0, width != settledWidth {
            settledWidth = width
            let natural = arrangedSubviews.map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width }
            let needed = natural.reduce(0, +) + spacing * CGFloat(max(0, natural.count - 1))
            let wanted: NSLayoutConstraint.Axis = needed <= width ? .horizontal : .vertical
            if wanted != axis {
                axis = wanted
                alignment = .leading
                spacing = wanted == .horizontal ? 6 : 4
            }
        }
        super.layoutSubviews()
    }
}

// MARK: - Rival row (hub, All Rivals)

/// One rival in a hub or All Rivals card (``RivalRowContent``): a direction dot, the name
/// as a marquee, the "N ahead" and "N behind" pills (stacked at accessibility sizes) and a
/// chevron. One button element with the combined label.
final class UKRivalRowView: UIControl {
    private let pills = UIStackView()
    private let pillSpacer = UIView()

    /// Called when the row is pressed.
    var onSelect: (() -> Void)?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - displayName: The rival's name, nil for "Unknown Player".
    ///   - behindCount: The wire `behindCount` (shown as the "ahead" pill).
    ///   - aheadCount: The wire `aheadCount` (shown as the "behind" pill).
    ///   - direction: Whether the rival is above or below the player.
    ///   - identifier: Accessibility identifier.
    init(displayName: String?, behindCount: Int, aheadCount: Int, direction: RivalDirection, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let copy = RivalRowCopy(name: displayName, behindCount: behindCount, aheadCount: aheadCount)
        let dot = UIView()
        dot.backgroundColor = direction == .below ? BrandUIColors.statusGreen : BrandUIColors.statusRed
        dot.layer.cornerRadius = 4
        dot.isUserInteractionEnabled = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        let name = UKMarqueeLabel(copy.name, font: UKFont.font(.body, weight: .semibold))
        name.isUserInteractionEnabled = false
        pills.addArrangedSubview(UKRivalStatusPill(copy.aheadPill, tint: BrandUIColors.statusGreen))
        pills.addArrangedSubview(UKRivalStatusPill(copy.behindPill, tint: BrandUIColors.statusRed))
        pills.addArrangedSubview(pillSpacer)
        pills.spacing = 6
        pills.alignment = .leading
        pills.isUserInteractionEnabled = false
        let column = UIStackView(arrangedSubviews: [name, pills])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = .fill
        column.isUserInteractionEnabled = false
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.caption1, weight: .semibold))
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [dot, column, chevron])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = copy.accessibilityLabel
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .touchUpInside)
        applyPillAxis()
        ukFlattenAccessibility()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKRivalRowView, _) in self.applyPillAxis() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    private func applyPillAxis() {
        let vertical = UKFont.isAccessibilitySize(traitCollection)
        pills.axis = vertical ? .vertical : .horizontal
        pillSpacer.isHidden = vertical
    }
}

// MARK: - Rival song row (Rival Detail, Rivalry)

/// One shared song compared between the player and a rival (``RivalSongRowContent``):
/// art above the instrument icon, the title and artist as marquees, both "#rank Name"
/// pills and the rank-delta badge. One element with the combined label; a button when the
/// song is in the catalogue.
final class UKRivalSongRowView: UIControl {
    /// Album art edge, the native song rows' 44 pt.
    static let artSize: CGFloat = 44

    /// Called when the row is pressed (only when the song is in the catalogue).
    var onSelect: (() -> Void)?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - song: The comparison.
    ///   - albumArt: Catalogue artwork path, nil for the placeholder.
    ///   - session: Session whose caches draw the art.
    ///   - playerName: The player's display name.
    ///   - rivalName: The rival's display name.
    ///   - opensSong: Whether the row opens the song.
    init(song: RivalSongComparison, albumArt: String?, session: FestivalSession, playerName: String, rivalName: String, opensSong: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let standing = RivalSongStanding(rankDelta: song.rankDelta)
        let art = UKArtworkTileView(size: Self.artSize)
        art.configure(raw: albumArt, session: session)
        let leading = UIStackView(arrangedSubviews: [art])
        leading.axis = .vertical
        leading.spacing = 6
        leading.alignment = .center
        if let instrument = Instrument(rawValue: song.instrument) {
            leading.addArrangedSubview(UKInstrumentIconView(instrument, size: 22, hidesFromAccessibility: true))
        }
        leading.widthAnchor.constraint(equalToConstant: Self.artSize).isActive = true
        let title = UKMarqueeLabel(song.title ?? song.songId, font: UKFont.font(.body, weight: .semibold))
        let column = UIStackView(arrangedSubviews: [title])
        column.axis = .vertical
        column.spacing = 4
        column.alignment = .fill
        if let artist = song.artist {
            column.addArrangedSubview(UKMarqueeLabel(artist, font: UKFont.font(.caption1)))
        }
        let accessibilitySize = UKFont.isAccessibilitySize(traitCollection)
        let player = UKRivalStatusPill(
            "#\(song.userRank) \(playerName)", tint: Self.tint(standing, player: true), singleLine: !accessibilitySize
        )
        let rival = UKRivalStatusPill(
            "#\(song.rivalRank) \(rivalName)", tint: Self.tint(standing, player: false), singleLine: !accessibilitySize
        )
        let pills = UKFittingStack(arrangedSubviews: [player, rival])
        pills.axis = accessibilitySize ? .vertical : .horizontal
        pills.spacing = accessibilitySize ? 4 : 6
        pills.alignment = .leading
        column.addArrangedSubview(pills)
        let row = UIStackView(arrangedSubviews: [leading, column, Self.deltaBadge(song.rankDelta)])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        leading.isUserInteractionEnabled = false
        column.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = RivalSongRowContent.accessibilityLabel(for: song, rivalName: rivalName)
        accessibilityTraits = opensSong ? .button : .staticText
        isEnabled = opensSong
        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .touchUpInside)
        ukFlattenAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    private static func tint(_ standing: RivalSongStanding, player: Bool) -> UIColor {
        switch (standing, player) {
        case (.playerAhead, true), (.rivalAhead, false): BrandUIColors.statusGreen
        case (.rivalAhead, true), (.playerAhead, false): BrandUIColors.statusRed
        case (.tied, _): BrandUIColors.textPrimary
        }
    }

    private static func deltaBadge(_ delta: Int) -> UIView {
        let color: UIColor = delta == 0 ? BrandUIColors.textPrimary : (delta > 0 ? BrandUIColors.statusGreen : BrandUIColors.statusRed)
        let readable = UKRivalStatusPill.readable(color)
        let symbol = UIImageView(image: UIImage(systemName: delta == 0 ? "equal" : (delta > 0 ? "arrow.up" : "arrow.down")))
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.caption1, weight: .bold))
        symbol.tintColor = readable
        symbol.contentMode = .scaleAspectFit
        let magnitude = UKLabel("\(abs(delta))", style: .caption2, weight: .semibold, color: readable, lines: 1, alignment: .center)
        let stack = UIStackView(arrangedSubviews: [symbol, magnitude])
        stack.axis = .vertical
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }
}

// MARK: - Instrument section header

/// The instrument icon and name drawn above the card it titles (``InstrumentSectionHeader``,
/// small size): a 36 pt icon beside a bold subheadline, or for a combo its icons in a row
/// above the label.
final class UKInstrumentSectionHeaderView: UIView {
    /// Creates a header.
    ///
    /// - Parameters:
    ///   - scope: The board: one instrument or a combo.
    ///   - title: Label override, defaulting to the scope's name.
    init(scope: RankingScope, title: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UKLabel(title ?? scope.label, style: .subheadline, weight: .bold).asHeader()
        let content: UIView
        switch scope {
        case let .instrument(instrument):
            let row = UIStackView(arrangedSubviews: [UKInstrumentIconView(instrument, size: 36, hidesFromAccessibility: true), label])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            content = row
        case let .combo(combo):
            let column = UIStackView(arrangedSubviews: [UKInstrumentIconRow(instruments: combo.instruments, side: 36), label])
            column.axis = .vertical
            column.spacing = 2
            column.alignment = .leading
            content = column
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Layout helpers

extension UIView {
    /// Makes every descendant a non-element, so a row that speaks one combined label leaves
    /// its inner labels and marquees out of the accessibility tree (and out of the audit).
    func ukFlattenAccessibility() {
        for child in subviews {
            child.isAccessibilityElement = false
            child.ukFlattenAccessibility()
        }
    }

    /// This view inside a holder with side padding, for stacking cards in a page column.
    ///
    /// - Parameter horizontal: Leading and trailing padding.
    /// - Returns: The holder.
    func ukPadded(horizontal: CGFloat = 16) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: horizontal),
            trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -horizontal),
            topAnchor.constraint(equalTo: holder.topAnchor), bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    /// Pins this view to all four edges of `other`.
    ///
    /// - Parameter other: The container (or its layout guide's owner).
    func ukPin(to other: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor), trailingAnchor.constraint(equalTo: other.trailingAnchor),
            topAnchor.constraint(equalTo: other.topAnchor), bottomAnchor.constraint(equalTo: other.bottomAnchor),
        ])
    }
}
#endif
