#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Card grid

/// Song Detail's preview cards in hinge-aware adaptive columns (``SongDetailCardGrid`` over
/// ``HingeEagerGrid``): as many columns of at least ``SongDetailCardColumns/minimumWidth``
/// as fit, at least one; in an iPhone Duo book pose the same count each side with the
/// gutter on the fold. Every card is built at once, rows are as tall as their tallest card
/// and cards start at the top of their row (a card whose height changes as its chart
/// loads grows its row through Auto Layout).
final class UKSongDetailCardGridView: UIView {
    private let cards: [UIView]
    private let rows = UIStackView()
    private let layoutProvider: () -> DeviceLayout
    private var signature: [CGFloat] = []

    /// Creates the grid.
    ///
    /// - Parameters:
    ///   - cards: The cards in reading order.
    ///   - layoutProvider: The window layout, for the fold.
    init(cards: [UIView], layoutProvider: @escaping () -> DeviceLayout) {
        self.cards = cards
        self.layoutProvider = layoutProvider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical
        rows.spacing = SongDetailCardColumns.rowSpacing
        rows.alignment = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor), rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor), rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let columns = Self.columns(width: bounds.width, in: self, layout: layoutProvider())
        let key = columns.flatMap { [$0.x, $0.width] }
        guard key != signature, bounds.width > 0 else { return }
        signature = key
        rebuild(columns)
    }

    /// Every column's leading x and width for a width (``HingeEagerGridLayout/columns(width:)``).
    ///
    /// - Parameters:
    ///   - width: The grid's width.
    ///   - view: The grid, to find the fold across it.
    ///   - layout: The window layout.
    /// - Returns: One (x, width) per column.
    static func columns(width: CGFloat, in view: UIView, layout: DeviceLayout) -> [(x: CGFloat, width: CGFloat)] {
        let spacing = SongDetailCardColumns.spacing
        let minimum = SongDetailCardColumns.minimumWidth
        if view.window != nil, let fold = layout.splitHinge,
           let band = HingeColumns.adaptiveBand(span: HorizontalSpan(view.convert(view.bounds, to: nil)), fold: fold, gutter: spacing, minimum: minimum),
           abs(band.width - width) < 0.5 {
            let spec = HingeColumns.spec(band: band, spacing: spacing, perSide: .fit(minimum: minimum))
            return Array(zip(spec.offsets, spec.widths)).map { (x: $0.0, width: $0.1) }
        }
        let count = HingeColumns.fitCount(width: width, minimum: minimum, spacing: spacing)
        let cell = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        return (0..<count).map { (x: CGFloat($0) * (cell + spacing), width: cell) }
    }

    private func rebuild(_ columns: [(x: CGFloat, width: CGFloat)]) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for start in stride(from: 0, to: cards.count, by: columns.count) {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            for (offset, card) in cards[start ..< min(start + columns.count, cards.count)].enumerated() {
                card.removeFromSuperview()
                card.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(card)
                NSLayoutConstraint.activate([
                    card.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: columns[offset].x),
                    card.widthAnchor.constraint(equalToConstant: columns[offset].width),
                    card.topAnchor.constraint(equalTo: row.topAnchor),
                    card.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
                ])
            }
            rows.addArrangedSubview(row)
        }
        // Reading order for VoiceOver is the cards' order, not their row positions.
        rows.accessibilityElements = cards
    }
}
#endif
