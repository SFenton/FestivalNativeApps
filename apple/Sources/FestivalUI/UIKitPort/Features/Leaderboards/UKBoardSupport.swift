#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Menus

/// The bar items the rankings and song boards offer (Instrument, Rank By, Band Size, Sort):
/// UIKit menus with the SwiftUI pickers' choices, identifiers and spoken values.
@MainActor
enum UKBoardMenus {
    /// An instrument's artwork redrawn at menu size in original colours.
    ///
    /// - Parameter instrument: The instrument.
    /// - Returns: The image, or nil when the asset is missing.
    static func menuIcon(_ instrument: Instrument, side: CGFloat = 20) -> UIImage? {
        guard let image = UKInstrumentIconView.image(for: instrument) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }.withRenderingMode(.alwaysOriginal)
    }

    /// The Instrument tool: a titled menu whose label carries the artwork.
    ///
    /// - Parameters:
    ///   - selected: The current chart.
    ///   - choices: The selectable charts.
    ///   - identifier: `fst.full-rankings.instrument-menu`.
    ///   - onSelect: Receives the picked chart.
    static func instrumentItem(
        selected: Instrument, choices: [Instrument], identifier: String, onSelect: @escaping (Instrument) -> Void
    ) -> UIBarButtonItem {
        let actions = choices.map { chart in
            let action = UIAction(title: chart.label, image: menuIcon(chart, side: 16), state: chart == selected ? .on : .off) { _ in
                onSelect(chart)
            }
            action.accessibilityIdentifier = "fst.full-rankings.instrument.\(chart.rawValue)"
            return action
        }
        let item = UIBarButtonItem(
            title: selected.label, image: menuIcon(selected), primaryAction: nil,
            menu: UIMenu(title: "Instrument", options: .singleSelection, children: actions)
        )
        item.accessibilityIdentifier = identifier
        item.accessibilityLabel = "Instrument"
        item.accessibilityValue = selected.label
        return item
    }

    /// The Rank By tool for account boards.
    ///
    /// - Parameters:
    ///   - selection: The current metric.
    ///   - experimental: Settings › Experimental Ranks is on.
    ///   - onSelect: Receives the picked metric.
    static func rankByItem(selection: RankingMetric, experimental: Bool, onSelect: @escaping (RankingMetric) -> Void) -> UIBarButtonItem {
        let actions = RankingMetric.enabled(experimentalRanks: experimental).map { metric in
            let action = UIAction(title: metric.label, state: metric == selection ? .on : .off) { _ in onSelect(metric) }
            action.accessibilityIdentifier = "fst.rankings.rank-by.\(metric.rawValue)"
            return action
        }
        let item = UIBarButtonItem(
            title: selection.label, image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: nil,
            menu: UIMenu(title: "Rank By", options: .singleSelection, children: actions)
        )
        item.accessibilityIdentifier = "fst.rankings.rank-by-menu"
        item.accessibilityLabel = "Rank By"
        item.accessibilityValue = selection.label
        return item
    }

    /// The Rank By tool for band boards (no Max Score).
    ///
    /// - Parameters:
    ///   - selection: The current metric.
    ///   - experimental: Settings › Experimental Ranks is on.
    ///   - onSelect: Receives the picked metric.
    static func bandRankByItem(
        selection: BandRankingMetric, experimental: Bool, onSelect: @escaping (BandRankingMetric) -> Void
    ) -> UIBarButtonItem {
        let actions = BandRankingMetric.enabled(experimentalRanks: experimental).map { metric in
            let action = UIAction(title: metric.label, state: metric == selection ? .on : .off) { _ in onSelect(metric) }
            action.accessibilityIdentifier = "fst.band-rankings.rank-by.\(metric.rawValue)"
            return action
        }
        let item = UIBarButtonItem(
            title: selection.label, image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: nil,
            menu: UIMenu(title: "Rank By", options: .singleSelection, children: actions)
        )
        item.accessibilityIdentifier = "fst.band-rankings.rank-by-menu"
        item.accessibilityLabel = "Rank By"
        item.accessibilityValue = selection.label
        return item
    }

    /// The Band Size menu (the floating bar's pill, the rail item and the song band board's tool).
    ///
    /// - Parameters:
    ///   - selected: The current size.
    ///   - idPrefix: Identifier prefix for the choices.
    ///   - onSelect: Receives the picked size.
    static func bandTypeMenu(selected: BandType, idPrefix: String, onSelect: @escaping (BandType) -> Void) -> UIMenu {
        let actions = BandType.allCases.map { size in
            let action = UIAction(title: size.label, state: size == selected ? .on : .off) { _ in onSelect(size) }
            action.accessibilityIdentifier = "\(idPrefix).\(size.rawValue)"
            return action
        }
        return UIMenu(title: "Band Size", options: .singleSelection, children: actions)
    }
}

// MARK: - Pinned bar title

/// The bar's principal title slot of a page with an in-page heading: the pinned title while
/// the heading is scrolled away, otherwise an empty, unspoken placeholder that keeps the
/// system title off the bar (issue #93).
@MainActor
final class UKPinnedTitleSlot {
    private weak var item: UINavigationItem?
    private let placeholder = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var title: UIView?
    private(set) var isShown = false

    /// Creates the slot.
    ///
    /// - Parameter item: The page's navigation item.
    init(item: UINavigationItem) {
        self.item = item
        placeholder.isAccessibilityElement = false
        placeholder.accessibilityElementsHidden = true
        item.titleView = placeholder
    }

    /// Sets the pinned title view (rebuilt when the text or instrument changes).
    ///
    /// - Parameter view: The compact title.
    func setTitle(_ view: UIView?) {
        title = view
        apply(animated: false)
    }

    /// Shows or hides the pinned title.
    ///
    /// - Parameters:
    ///   - shown: Whether the in-page heading has scrolled away.
    ///   - animated: Cross-fade.
    func setShown(_ shown: Bool, animated: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        apply(animated: animated && !UKAccessibility.reduceMotion)
    }

    private func apply(animated: Bool) {
        guard let item else { return }
        let target: UIView = (isShown ? title : nil) ?? placeholder
        guard item.titleView !== target else { return }
        if animated, let host = item.titleView {
            target.alpha = 0
            item.titleView = target
            UIView.animate(withDuration: 0.2) { target.alpha = 1 }
            _ = host
        } else {
            item.titleView = target
        }
    }
}

// MARK: - Layout helpers

extension UIViewController {
    /// Whether this page is in a split's trailing pane (never two columns there, pattern `wide-columns`).
    var ukIsSplitSubPage: Bool { ukSplitPane == .trailing }
}

/// Wraps a view with insets, for chrome rows.
///
/// - Parameters:
///   - view: The content.
///   - insets: Padding on each side.
/// - Returns: The padded container.
@MainActor
func ukPadded(_ view: UIView, _ insets: UIEdgeInsets) -> UIView {
    let holder = UIView()
    holder.translatesAutoresizingMaskIntoConstraints = false
    view.translatesAutoresizingMaskIntoConstraints = false
    holder.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: insets.left),
        view.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -insets.right),
        view.topAnchor.constraint(equalTo: holder.topAnchor, constant: insets.top),
        view.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -insets.bottom),
    ])
    return holder
}

// MARK: - Message views

/// "Loading your rank": the spotlight footer's spinner row at the row height.
///
/// - Parameter identifier: Accessibility identifier, or nil.
@MainActor
func ukSpotlightLoadingRow(identifier: String?) -> UIView {
    let loading = UKLoadingView(accessibilityLabel: "Loading your rank")
    let holder = UIView()
    holder.translatesAutoresizingMaskIntoConstraints = false
    loading.translatesAutoresizingMaskIntoConstraints = false
    holder.addSubview(loading)
    NSLayoutConstraint.activate([
        loading.centerXAnchor.constraint(equalTo: holder.centerXAnchor), loading.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        holder.heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardMetrics.minHeight),
    ])
    holder.isAccessibilityElement = true
    holder.accessibilityLabel = "Loading your rank"
    holder.accessibilityIdentifier = identifier
    return holder
}

/// A card-sized text message row (a card's empty and unranked states).
///
/// - Parameters:
///   - text: The message.
///   - identifier: Accessibility identifier.
@MainActor
func ukCardMessage(_ text: String, identifier: String? = nil) -> UIView {
    let label = UKLabel(text, style: .subheadline)
    label.isAccessibilityElement = true
    label.accessibilityIdentifier = identifier
    let holder = ukPadded(label, UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))
    holder.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return holder
}
#endif
