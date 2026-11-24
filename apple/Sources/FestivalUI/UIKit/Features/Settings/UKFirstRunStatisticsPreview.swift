#if os(iOS)
import FestivalCore
import UIKit

/// Statistics illustrations made from native cards, tiles, header, and percentile table.
/// Samples do not depend on the selected player and never open a link.
final class UKFirstRunStatisticsPreview: UIView {
    private let grid: UKStatGridView?
    private let pulseGroup: UKFirstRunPulseGroup?

    /// The preview content that enters before the narration, if any.
    let entranceContent: UIView?

    /// Creates one of the Statistics guide's native previews.
    ///
    /// - Parameters:
    ///   - slideID: The slide's registered catalogue identifier.
    ///   - layout: The current device layout for the stat columns.
    init?(slideID: String, layout: @escaping () -> DeviceLayout) {
        let content: UIView
        switch slideID {
        case "statistics-select-profile":
            let select = Self.makeSelectButton()
            let card = UKCardView(cornerRadius: 16)
            let name = UKLabel(FirstRunDemoPool.rankings[0].name, style: .title2, weight: .bold)
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            select.setContentCompressionResistancePriority(.required, for: .horizontal)
            let stack = UIStackView(arrangedSubviews: [name, UIView(), select])
            stack.alignment = .center
            stack.spacing = 12
            card.contentView.ukPin(stack, insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
            grid = nil
            content = card
            entranceContent = nil
            pulseGroup = UKFirstRunPulseGroup(targets: [select], shape: .capsule)
        case "statistics-drill-down":
            let grid = UKStatGridView(tiles: FirstRunStatisticsSamples.drillDown, scope: "first-run", layoutProvider: layout)
            self.grid = grid
            content = grid
            entranceContent = nil
            pulseGroup = UKFirstRunPulseGroup(
                targets: grid.tileViews, shape: .roundedRect(cornerRadius: UKStatTileView.cornerRadius)
            )
        case "statistics-overview":
            let grid = UKStatGridView(tiles: FirstRunStatisticsSamples.overview, scope: "first-run", layoutProvider: layout)
            self.grid = grid
            content = grid
            entranceContent = nil
            pulseGroup = nil
        case "statistics-instrument-breakdown":
            let header = UKProfileInstrumentHeader(.lead)
            let grid = UKStatGridView(tiles: FirstRunStatisticsSamples.instrument, scope: "first-run", layoutProvider: layout)
            let stack = UIStackView(arrangedSubviews: [header, grid])
            stack.axis = .vertical
            stack.spacing = 10
            self.grid = grid
            content = stack
            entranceContent = header
            pulseGroup = nil
        case "statistics-percentiles":
            let table = UKPlayerPercentileTableCardView(
                buckets: FirstRunDemoPool.percentileBuckets.map {
                    PlayerPercentileBucket(topPercent: $0.percent, count: $0.count)
                },
                instrument: .lead, linkFilter: { $0 }, onSelect: { _ in }
            )
            self.grid = nil
            content = table
            entranceContent = table
            pulseGroup = nil
        default:
            return nil
        }
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        if bounds.width > 0 { grid?.prepare(width: bounds.width) }
        super.layoutSubviews()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        pulseGroup?.updatePulse()
    }

    /// - Parameter active: Whether this illustration is on the current slide.
    func setActive(_ active: Bool) { pulseGroup?.setActive(active) }

    /// Creates the same prominent Select treatment as the profile header, without a route.
    private static func makeSelectButton() -> UIButton {
        let button = UIButton(configuration: .filled())
        button.configurationUpdateHandler = { button in
            let traits = button.traitCollection
            let colors = UKAccentText.prominentColors(
                increasedContrast: UKAccessibility.moreContrast || UKAccessibility.systemIncreasedContrast(traits)
            )
            var configuration = UIButton.Configuration.filled()
            var title = AttributedString(ProfileIdentityAction.select.shortTitle)
            title.font = UKFont.font(.body, weight: .semibold)
            configuration.attributedTitle = title
            configuration.baseBackgroundColor = colors.fill
            configuration.baseForegroundColor = colors.label
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
            button.configuration = configuration
        }
        button.registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self]) {
            (button: UIButton, _) in button.setNeedsUpdateConfiguration()
        }
        button.setNeedsUpdateConfiguration()
        return button
    }
}
#endif
