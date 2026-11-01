#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Wide-row profile panel

/// The right half of a wide Songs row (``SongProfilePanel``): one flat card per scored chart
/// of the selected player, or the selected band's one card, in equal-width columns.
///
/// Hidden from accessibility: the row lists each card as its own stop after the song
/// (`songs-profile-panel` R8), from ``cardFrames``.
final class UKSongProfilePanelView: UIView {
    private struct Card {
        let container: UIView
        let icon: UIView
        let flow: UKSongMetadataFlowView?
        let label: UILabel?
    }

    private let tiles: [SongProfilePanelTile]
    private let arrangement: SongProfilePanelPolicy.Arrangement
    private var cards: [Card] = []
    private(set) var cardFrames: [CGRect] = []
    private var plan: (width: CGFloat, frames: [CGRect], height: CGFloat)?
    private static let cardInsetH: CGFloat = 8
    private static let cardInsetV: CGFloat = 6
    private static let iconSide: CGFloat = 28

    /// Creates the panel.
    init(
        songId: String, tiles: [SongProfilePanelTile], arrangement: SongProfilePanelPolicy.Arrangement,
        keyboard: Bool, highContrast: Bool, traits: UITraitCollection
    ) {
        self.tiles = tiles
        self.arrangement = arrangement
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        for tile in tiles {
            let card = UIView()
            card.backgroundColor = BrandUIColors.surfaceMuted.withAlphaComponent(0.35)
            card.layer.cornerRadius = 8
            card.layer.cornerCurve = .continuous
            if highContrast {
                card.layer.borderWidth = 1
                card.layer.borderColor = BrandUIColors.textPrimary.cgColor
            }
            let icon: UIView
            switch tile.subject {
            case let .chart(chart):
                let view = UIImageView(image: UKInstrumentIconView.image(for: chart, keyboard: keyboard && (chart == .lead || chart == .proLead)))
                view.contentMode = .center
                view.preferredSymbolConfiguration = nil
                icon = view
            case let .band(type, _):
                let view = UIImageView(image: UIImage(systemName: type.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
                view.tintColor = BrandUIColors.textPrimary
                view.contentMode = .center
                icon = view
            }
            icon.isAccessibilityElement = false
            card.addSubview(icon)
            let fields = arrangement.dropsStars ? tile.fields.filter { $0.id != .stars } : tile.fields
            var flow: UKSongMetadataFlowView?
            var label: UILabel?
            if !fields.isEmpty {
                let view = UKSongMetadataFlowView(fields: fields, traits: traits, leading: true)
                card.addSubview(view)
                flow = view
            } else {
                let text = UILabel()
                text.font = UKFont.font(.subheadline, weight: .semibold)
                text.adjustsFontForContentSizeCategory = true
                text.textColor = BrandUIColors.textPrimary
                text.text = tile.label
                text.numberOfLines = 0
                card.addSubview(text)
                label = text
            }
            addSubview(card)
            cards.append(Card(container: card, icon: icon, flow: flow, label: label))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The panel's height at `width`.
    func height(forWidth width: CGFloat) -> CGFloat { layoutPlan(width: width).height }

    private func cardHeight(_ index: Int, width: CGFloat) -> CGFloat {
        let inner = max(0, width - 2 * Self.cardInsetH - Self.iconSide - 8)
        let content: CGFloat
        if let flow = cards[index].flow {
            content = flow.height(forWidth: inner)
        } else if let label = cards[index].label {
            content = max(Self.iconSide, ceil(label.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height))
        } else {
            content = 0
        }
        return max(Self.iconSide, content) + 2 * Self.cardInsetV
    }

    private func layoutPlan(width: CGFloat) -> (width: CGFloat, frames: [CGRect], height: CGFloat) {
        if let plan, plan.width == width { return plan }
        let columns = max(1, arrangement.columns)
        let spacing = SongProfilePanelPolicy.tileSpacing
        let cardWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var frames = [CGRect](repeating: .zero, count: cards.count)
        var y: CGFloat = 0
        var index = 0
        while index < cards.count {
            let line = index..<min(index + columns, cards.count)
            let lineHeight = line.map { cardHeight($0, width: cardWidth) }.max() ?? 0
            for (column, i) in line.enumerated() {
                frames[i] = CGRect(x: CGFloat(column) * (cardWidth + spacing), y: y, width: cardWidth, height: lineHeight)
            }
            y += lineHeight + spacing
            index += columns
        }
        let result = (width, frames, max(0, y - spacing))
        plan = result
        return result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let plan = layoutPlan(width: bounds.width)
        cardFrames = plan.frames
        for (card, frame) in zip(cards, plan.frames) {
            card.container.frame = frame
            card.icon.frame = CGRect(x: Self.cardInsetH, y: Self.cardInsetV, width: Self.iconSide, height: Self.iconSide)
            let x = Self.cardInsetH + Self.iconSide + 8
            let inner = CGRect(x: x, y: Self.cardInsetV, width: max(0, frame.width - x - Self.cardInsetH), height: frame.height - 2 * Self.cardInsetV)
            card.flow?.frame = inner
            card.label?.frame = inner
        }
    }
}

#endif
