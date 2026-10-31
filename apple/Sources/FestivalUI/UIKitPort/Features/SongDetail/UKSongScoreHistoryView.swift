#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

/// The selected player's score history on the song page (``SongScoreHistorySection``): an
/// instrument selector (graph look, shown even for one instrument), the paged accuracy and
/// score chart, the best five scores in one group card, and "View All Scores" when there
/// are more, which opens the separate Score History page.
///
/// Choosing another instrument fades the chart and list out, swaps them and fades back in
/// (`ScoreHistorySwap`), holding the card's height meanwhile; Reduce Motion swaps at once.
final class UKSongScoreHistoryView: UIView {
    /// Section identifier (Quick Links anchor).
    static let anchor = SongScoreHistorySection.anchor

    private let song: Song
    private let entries: [ScoreHistoryEntry]
    private let available: [Instrument]
    private let context: UKContext
    private let currentSeason: Int?
    private let viewportWidth: CGFloat
    private let section: UKGroupSectionView
    private let graphRow = UIView()
    private let chartHolder = UIView()
    private let selector: UKInstrumentSelectorView
    private var displayed: Instrument
    private var chartWidth: CGFloat = 0
    private var swap: Task<Void, Never>?
    private var heightPin: NSLayoutConstraint?
    private var listViews: [UIView] = []
    private var actionView: UIView?
    private var renderedChartWidth: CGFloat = 0

    /// The instrument the selector last chose, kept by the page across rebuilds.
    private(set) var chosen: Instrument

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - song: The song (the View All Scores route).
    ///   - entries: The selected player's history rows for this song.
    ///   - pool: Visible charted instruments in display order (the selector's pool).
    ///   - preferred: The instrument chosen before, if any.
    ///   - currentSeason: The catalogue's current season.
    ///   - viewportWidth: The page width (the season column from 520 pt).
    ///   - context: The page's context.
    init(
        song: Song, entries: [ScoreHistoryEntry], pool: [Instrument], preferred: Instrument?, currentSeason: Int?,
        viewportWidth: CGFloat, context: UKContext
    ) {
        self.song = song
        self.entries = entries
        self.context = context
        self.currentSeason = currentSeason
        self.viewportWidth = viewportWidth
        available = SongScoreHistoryModel.instruments(with: entries, in: pool)
        let shown = SongScoreHistoryModel.resolvedInstrument(preferred: preferred, available: available) ?? .lead
        displayed = shown
        chosen = shown
        selector = UKInstrumentSelectorView(
            instruments: available, selected: shown, required: true, look: .graph, keyboardIcon: song.usesKeyboardIcon,
            identifier: "fst.song-detail.history.instrument"
        )
        section = UKGroupSectionView("Score History", subtitle: "Select a bar to see more score details.", rows: .flush(separatorInset: 14))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        section.translatesAutoresizingMaskIntoConstraints = false
        addSubview(section)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: leadingAnchor), section.trailingAnchor.constraint(equalTo: trailingAnchor),
            section.topAnchor.constraint(equalTo: topAnchor), section.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        chartHolder.translatesAutoresizingMaskIntoConstraints = false
        let column = UIStackView(arrangedSubviews: [selector, chartHolder])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        graphRow.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: graphRow.leadingAnchor, constant: 14), column.trailingAnchor.constraint(equalTo: graphRow.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: graphRow.topAnchor, constant: 14), column.bottomAnchor.constraint(equalTo: graphRow.bottomAnchor, constant: -14),
        ])
        selector.onSelect = { [weak self] in if let instrument = $0 { self?.choose(instrument) } }
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = Self.anchor
        render(for: shown)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { swap?.cancel() }

    /// The heading, for Quick Links' rotor.
    var headerElement: UIView { section }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = chartHolder.bounds.width.rounded()
        if width != renderedChartWidth, width > 0, swap == nil {
            renderedChartWidth = width
            render(for: displayed)
        }
    }

    // MARK: Rendering

    private func render(for instrument: Instrument) {
        let width = chartHolder.bounds.width.rounded()
        let rows = SongScoreHistoryModel.chronological(entries, instrument: instrument)
        let list = SongScoreHistoryModel.bestFirst(rows, limit: SongScoreHistoryModel.listLimit)
        chartHolder.subviews.forEach { $0.removeFromSuperview() }
        let chart = UKScoreHistoryChartView(
            rows: rows, instrument: instrument, chartWidth: width,
            reservesPager: SongScoreHistoryModel.reservesPager(entries, instruments: available, chartWidth: Double(width)),
            currentSeason: currentSeason
        )
        chartHolder.addSubview(chart)
        NSLayoutConstraint.activate([
            chart.leadingAnchor.constraint(equalTo: chartHolder.leadingAnchor), chart.trailingAnchor.constraint(equalTo: chartHolder.trailingAnchor),
            chart.topAnchor.constraint(equalTo: chartHolder.topAnchor), chart.bottomAnchor.constraint(equalTo: chartHolder.bottomAnchor),
        ])
        let template = LeaderboardRowColumns.scoreHistory(rows.map(\.newScore)).scoreLabel
        let showsSeason = ScoreRowSeasonPolicy.showsColumn(.historyList, width: Double(viewportWidth))
        listViews = list.enumerated().map { index, entry in
            UKScoreHistoryRowView(
                entry: entry, isBest: index == 0, seasonColumn: showsSeason, currentSeason: currentSeason, grouped: true, scoreTemplate: template
            ).identified("fst.song-detail.history.row.\(index)")
        }
        section.setRows([graphRow] + listViews)
        if rows.count > SongScoreHistoryModel.listLimit {
            let action = UKPurpleActionButton(
                title: "View All Scores", card: "\(instrument.label) Score History", identifier: "fst.song-detail.history.view-all"
            ) { [weak self] in
                guard let self else { return }
                self.context.navigator?.selectDetail(.playerHistory(self.song, self.displayed))
            }
            actionView = action
            section.setAction(action)
        } else {
            actionView = nil
            section.setAction(nil)
        }
    }

    private var fadingViews: [UIView] { [chartHolder] + listViews + (actionView.map { [$0] } ?? []) }

    // MARK: Instrument swap

    private func choose(_ target: Instrument) {
        chosen = target
        switch ScoreHistorySwap.plan(displayed: displayed, target: target, reduceMotion: UKAccessibility.reduceMotion) {
        case .none:
            return
        case .settle:
            swap?.cancel()
            swap = nil
            UIView.animate(withDuration: ScoreHistorySwap.fadeInSeconds, delay: 0, options: .curveEaseOut) { self.fadingViews.forEach { $0.alpha = 1 } }
            releasePin()
        case .instant:
            swap?.cancel()
            swap = nil
            displayed = target
            render(for: target)
            fadingViews.forEach { $0.alpha = 1 }
            releasePin()
        case .fade:
            swap?.cancel()
            pinHeight()
            swap = Task { @MainActor [weak self] in
                guard let self else { return }
                UIView.animate(withDuration: ScoreHistorySwap.fadeOutSeconds, delay: 0, options: .curveEaseIn) { self.fadingViews.forEach { $0.alpha = 0 } }
                try? await Task.sleep(for: .seconds(ScoreHistorySwap.fadeOutSeconds))
                guard !Task.isCancelled else { return }
                self.displayed = target
                self.render(for: target)
                self.fadingViews.forEach { $0.alpha = 0 }
                await Task.yield()
                guard !Task.isCancelled else { return }
                UIView.animate(withDuration: ScoreHistorySwap.fadeInSeconds, delay: 0, options: .curveEaseOut) { self.fadingViews.forEach { $0.alpha = 1 } }
                try? await Task.sleep(for: .seconds(ScoreHistorySwap.fadeInSeconds))
                guard !Task.isCancelled else { return }
                UIView.animate(withDuration: ScoreHistorySwap.fadeInSeconds, delay: 0, options: .curveEaseOut) {
                    self.releasePin()
                    self.layoutIfNeeded()
                }
                self.swap = nil
            }
        }
    }

    /// Holds the graph row at its current height for the swap, so the card keeps its size.
    private func pinHeight() {
        guard heightPin == nil, graphRow.bounds.height > 0 else { return }
        let pin = graphRow.heightAnchor.constraint(greaterThanOrEqualToConstant: graphRow.bounds.height)
        pin.isActive = true
        heightPin = pin
    }

    private func releasePin() {
        heightPin?.isActive = false
        heightPin = nil
    }
}
#endif
