#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Stat tile

/// One value-over-caption tile of a stat grid (``PlayerStatTileView``): its own material card,
/// a chevron on the trailing edge when it links somewhere, one accessibility element
/// (label, value, hint, button trait only when it links).
final class UKStatTileView: UIControl {
    /// Tile corner radius (``StatTileSurface/cornerRadius``).
    static let cornerRadius: CGFloat = 14

    private(set) var tile: StatTile
    private let scope: String
    private let identifierPrefix: String
    private let card = UKCardView(cornerRadius: UKStatTileView.cornerRadius)
    private let wash = UIView()
    private let valueLabel = UKLabel(style: .title3, weight: .bold, monospacedDigit: true, color: UKAccentText.blue, lines: 0, alignment: .center)
    private let captionLabel = UKLabel(style: .caption2, lines: 0, alignment: .center)
    private let starsHolder = UIView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private var content = UIStackView()
    private var sideInsets: [NSLayoutConstraint] = []
    /// Called with the tile's link when tapped.
    var onSelect: ((PlayerStatLink) -> Void)?

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - tile: The tile's content.
    ///   - scope: Identifier scope (`overview`, an instrument's raw value, `summary` ...).
    ///   - identifierPrefix: Identifier prefix (``PlayerStatTileView/playerIdentifierPrefix`` or Band Detail's).
    init(tile: StatTile, scope: String, identifierPrefix: String) {
        self.tile = tile
        self.scope = scope
        self.identifierPrefix = identifierPrefix
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        apply(tile)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKStatTileView, _) in self.applyMetrics() }
        addAction(UIAction { [weak self] _ in
            guard let self, let link = self.tile.link else { return }
            self.onSelect?(link)
        }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Build

    private func build() {
        card.isUserInteractionEnabled = false
        ukPin(card)
        wash.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        wash.alpha = 0
        wash.layer.cornerRadius = Self.cornerRadius
        wash.layer.cornerCurve = .continuous
        wash.isUserInteractionEnabled = false
        ukPin(wash)
        captionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let stars = UKStarRatingView(stars: 6, gold: true, size: 16)
        stars.isUserInteractionEnabled = false
        starsHolder.translatesAutoresizingMaskIntoConstraints = false
        starsHolder.addSubview(stars)
        NSLayoutConstraint.activate([
            stars.centerXAnchor.constraint(equalTo: starsHolder.centerXAnchor),
            stars.centerYAnchor.constraint(equalTo: starsHolder.centerYAnchor),
            starsHolder.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        content = UIStackView(arrangedSubviews: [valueLabel, starsHolder, captionLabel])
        content.axis = .vertical
        content.spacing = 2
        content.alignment = .fill
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        chevron.tintColor = BrandUIColors.textMuted
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.isUserInteractionEnabled = false
        chevron.isAccessibilityElement = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)
        let leading = content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22)
        let trailing = content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22)
        sideInsets = [leading, trailing]
        NSLayoutConstraint.activate([
            leading, trailing,
            content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        applyMetrics()
    }

    /// The chevron's side padding scales with the footnote text so it never sits on a
    /// wrapped value at AX5 (iPad audit capture, Lane A11Y3).
    private func applyMetrics() {
        let inset = UKFont.scaled(22, relativeTo: .footnote, traits: traitCollection)
        sideInsets[0].constant = inset
        sideInsets[1].constant = -inset
        // Wraps instead of shrinking (a shrinking label reads as fixed-size to the Dynamic Type
        // audit); the value still fits one line at ordinary sizes.
        valueLabel.numberOfLines = 2
    }

    // MARK: Content

    /// Shows new tile content in place (same identity, new value or link).
    ///
    /// - Parameter newTile: The updated tile.
    func apply(_ newTile: StatTile) {
        tile = newTile
        let showsStars = newTile.goldStars
        valueLabel.isHidden = showsStars
        starsHolder.isHidden = !showsStars
        if newTile.isPlaceholder {
            valueLabel.attributedText = NSAttributedString(string: newTile.value, attributes: [
                .foregroundColor: UIColor.clear,
                .backgroundColor: UIColor.white.withAlphaComponent(0.16),
            ])
        } else {
            valueLabel.attributedText = nil
            valueLabel.text = newTile.value
            valueLabel.textColor = newTile.isGold ? BrandUIColors.gold : UKAccentText.blue
        }
        captionLabel.text = newTile.label.uppercased()
        let links = newTile.link != nil
        chevron.isHidden = !links
        isEnabled = true
        isUserInteractionEnabled = links
        accessibilityLabel = newTile.label
        accessibilityValue = newTile.isPlaceholder ? "Loading" : (newTile.goldStars ? "5 gold stars" : newTile.value)
        accessibilityHint = newTile.link.map { PlayerStatTileView.hint(for: $0) }
        accessibilityTraits = links ? .button : []
        accessibilityIdentifier = "\(identifierPrefix).\(scope).\(newTile.id)"
    }

    override var isHighlighted: Bool {
        didSet {
            guard tile.link != nil, isHighlighted != oldValue else { return }
            let pressed = isHighlighted
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.wash.alpha = pressed ? 1 : 0
                self.transform = pressed ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            }
        }
    }
}

// MARK: - Stat grid

/// Stat tiles in an adaptive grid (``PlayerStatGrid``): two columns on iPhone, three or four
/// as the page widens, one at accessibility sizes in a narrow window; every tile in a row
/// as tall as the row.
final class UKStatGridView: UIView, UKWidthDependent {
    private let scope: String
    private let identifierPrefix: String
    private let grid: UKProfileColumnGrid
    private var tileViews: [UKStatTileView] = []
    private var accessible: Bool
    /// Follows a tapped tile's link.
    var onSelect: (PlayerStatLink) -> Void = { _ in } {
        didSet { tileViews.forEach { $0.onSelect = onSelect } }
    }

    /// Creates a grid.
    ///
    /// - Parameters:
    ///   - tiles: The tiles in display order.
    ///   - scope: Identifier scope.
    ///   - identifierPrefix: Identifier prefix.
    ///   - layoutProvider: The window layout (for the Duo fold).
    init(
        tiles: [StatTile], scope: String, identifierPrefix: String = PlayerStatTileView.playerIdentifierPrefix,
        layoutProvider: @escaping () -> DeviceLayout
    ) {
        self.scope = scope
        self.identifierPrefix = identifierPrefix
        let accessible = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        self.accessible = accessible
        grid = UKProfileColumnGrid(columns: Self.rule(accessible: accessible), spacing: CGFloat(StatGridColumns.spacing), stretchesCells: true)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        grid.layoutProvider = layoutProvider
        ukPin(grid)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKStatGridView, _) in
            self.accessible = UKFont.isAccessibilitySize(self.traitCollection)
            self.grid.columns = Self.rule(accessible: self.accessible)
        }
        setTiles(tiles)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func rule(accessible: Bool) -> UKProfileColumnGrid.Columns {
        .stat(
            minimumTile: accessible ? StatGridColumns.accessibilityMinimumTileWidth : StatGridColumns.minimumTileWidth,
            minimumColumns: accessible ? StatGridColumns.accessibilityMinimumColumns : StatGridColumns.minimumColumns
        )
    }

    /// Shows new tiles: in place when the tile ids are unchanged, else rebuilt.
    ///
    /// - Parameter tiles: The tiles in display order.
    func setTiles(_ tiles: [StatTile]) {
        if tiles.map(\.id) == tileViews.map(\.tile.id) {
            for (view, tile) in zip(tileViews, tiles) { view.apply(tile) }
            return
        }
        tileViews = tiles.map { tile in
            let view = UKStatTileView(tile: tile, scope: scope, identifierPrefix: identifierPrefix)
            view.onSelect = onSelect
            return view
        }
        grid.setCells(tileViews)
    }

    func prepare(width: CGFloat) { grid.prepare(width: width) }
}
#endif
