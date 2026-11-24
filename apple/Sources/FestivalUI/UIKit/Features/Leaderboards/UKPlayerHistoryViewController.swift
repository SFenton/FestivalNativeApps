#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Score History

/// `/songs/:songId/:instrument/history` (ports ``PlayerHistoryScreen``): every tracked
/// score of the selected player on one song and instrument under the song header, sortable
/// through the Sort page tool; the best score purple wherever the sort puts it.
@MainActor
final class UKPlayerHistoryViewController: UKSongBoardViewController {
    private let instrument: Instrument
    private var state: PlayerHistoryScreen.LoadState = .loading
    private var sortMode = PlayerScoreHistorySort.defaultMode
    private var sortAscending = PlayerScoreHistorySort.defaultAscending
    private var loadTask: Task<Void, Never>?
    private var lastKey: String?
    private let observations = UKObservationBag()

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - song: Song whose history to show.
    ///   - instrument: Chart whose history to show.
    init(context: UKContext, song: Song, instrument: Instrument) {
        self.instrument = instrument
        super.init(
            context: context, song: song, idPrefix: "fst.history", spinnerLabel: "Loading Score History",
            spinnerIdentifier: "fst.history.gate", initiallyLoading: false
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var rowInset: CGFloat { PlayerHistoryScreen.rowVerticalInset }
    override var boardTitle: String { caption }
    override var captionText: String? { caption }
    override var captionTitle: String { instrument.label }
    override var captionInstrument: Instrument? { instrument }
    private var caption: String { "\(instrument.label) · Score History" }

    private var requestKey: String? {
        session.selectedPlayer.map { "\($0.accountId)|\(session.publicationRevision)" }
    }

    private var entries: [ScoreHistoryEntry]? {
        guard session.selectedPlayer != nil, case let .loaded(payload) = state, payload.state == .available else { return nil }
        return payload.entries(songId: song.songId, instrument: instrument)
    }

    private var sortAvailable: Bool { !(entries ?? []).isEmpty }

    // MARK: Lifecycle

    override func boardDidLoad() {
        boardView.separateCards = true
        boardView.rowSpacing = 2 * rowInset
        boardView.columnsProvider = nil
        boardView.gate.update(key: 0, isLoading: false)
        boardView.collectionView.accessibilityIdentifier = idPrefix
        updatePinnedTitle()
        observations.observe { [weak self] in
            guard let self else { return }
            let key = requestKey
            _ = session.publicationRevision
            if isViewLoaded, key != lastKey {
                lastKey = key
                if key != nil { startLoad() } else { state = .loading; render() }
            }
        }
        lastKey = requestKey
        if requestKey != nil { startLoad() } else { render() }
    }

    override func layoutKeyChanged() { render() }

    override var ukPageTools: [UKPageTool] {
        guard sortAvailable else { return [] }
        let item = UIBarButtonItem(title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: UIAction { [weak self] _ in
            self?.presentSort()
        })
        item.accessibilityIdentifier = "fst.history.sort.open"
        item.accessibilityLabel = "Sort"
        item.accessibilityValue = PlayerScoreHistorySort.spokenValue(mode: sortMode, ascending: sortAscending)
        item.tintColor = PlayerScoreHistorySort.isCustomized(mode: sortMode, ascending: sortAscending) ? BrandUIColors.gold : BrandUIColors.accentBlue
        return [UKPageTool(order: PageToolOrder.primary, item: item)]
    }

    // MARK: Sort

    private func presentSort() {
        let sheet = UKPlayerHistorySortViewController(mode: sortMode, ascending: sortAscending) { [weak self] mode, ascending in
            guard let self else { return }
            sortMode = mode
            sortAscending = ascending
            ukPageToolsDidChange()
            render()
            boardView.scrollToTop(animated: !UKAccessibility.reduceMotion)
        }
        UKSheet.present(sheet, from: self, title: "Sort Player Scores", closeIdentifier: "fst.history.sort.close", size: .compact)
    }

    // MARK: Loading

    private func startLoad() {
        guard let accountId = session.selectedPlayer?.accountId else { return }
        loadTask?.cancel()
        let requested = requestKey
        state = .loading
        render()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.songHistory(accountId: accountId, songId: song.songId)
                try Task.checkCancellation()
                guard requested == requestKey else { return }
                state = .loaded(payload)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard requested == requestKey else { return }
                state = .failed(ServiceIssue(error))
            }
            ukPageToolsDidChange()
            render()
        }
    }

    // MARK: Render

    private func button(_ title: String, identifier: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        let colors = UKAccentText.prominentColors(increasedContrast: UKAccessibility.moreContrast)
        configuration.title = title
        configuration.baseBackgroundColor = colors.fill
        configuration.baseForegroundColor = colors.label
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    private func message() -> UIView {
        if session.selectedPlayer == nil {
            return UKEmptyStateView(
                "No Profile Selected", systemImage: "person.crop.circle", subtitle: "Select a player to view score history.",
                identifier: "fst.history.no-player",
                actions: [button("Choose Profile", identifier: "fst.history.choose-profile") { [weak self] in self?.context.navigator?.presentProfile() }]
            )
        }
        switch state {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading Score History", placement: .fill)
            loading.accessibilityIdentifier = "fst.history.loading"
            return loading
        case let .failed(issue):
            let status = UKServiceStatusView(issue, title: "History Unavailable") { [weak self] in self?.startLoad() }
            status.accessibilityIdentifier = "fst.history.error"
            return status
        case let .loaded(payload):
            switch payload.state {
            case .unregistered:
                // Unavailable, not empty: keeps its failure title and Retry (R1, R8).
                let status = UKServiceStatusView(
                    .other(message: "Score history is only available for registered users."), title: "History Unavailable",
                    systemImage: "clock.badge.xmark"
                ) { [weak self] in self?.startLoad() }
                status.accessibilityIdentifier = "fst.history.unregistered"
                return status
            case .syncing:
                let status = UKServiceStatusView(
                    .other(message: "Score history is still syncing for this player. Check back soon."), title: "History Is Syncing"
                ) { [weak self] in self?.startLoad() }
                status.accessibilityIdentifier = "fst.history.syncing"
                return status
            case .available:
                return UKEmptyStateView(
                    "No Score History", systemImage: "clock.arrow.circlepath", subtitle: "No score history for this instrument.",
                    identifier: "fst.history.empty"
                )
            }
        }
    }

    private func render() {
        guard isViewLoaded else { return }
        updatePinnedTitle()
        var heads: [(id: String, view: UIView)] = []
        var rows: [(id: String, row: UKLeaderboardRow)] = []
        heads.append(("header", makeHeader(
            instrument: instrument, text: caption, identifier: "fst.history.header", boardIdentifier: "fst.history.board-title",
            subtitle: "Score History"
        )))
        if let entries, !entries.isEmpty {
            let sorted = PlayerScoreHistorySort.sorted(entries, mode: sortMode, ascending: sortAscending)
            let best = PlayerScoreHistorySort.highScoreIndex(in: sorted)
            let seasonColumn = ScoreRowSeasonPolicy.showsColumn(.historyList, width: Double(boardView.bounds.width))
            let columns = LeaderboardRowColumns.scoreHistory(entries.map(\.newScore))
            for (index, entry) in sorted.enumerated() {
                let model = UKBoardScoreHistoryRowView.Model(
                    entry: entry, isBest: index == best, seasonColumn: seasonColumn, currentSeason: session.catalogCurrentSeason,
                    columns: columns, identifier: "fst.history.row.\(index)"
                )
                rows.append(("row\(index)", UKLeaderboardRow(
                    kind: .history, make: { UKBoardScoreHistoryRowView() }, apply: { ($0 as? UKBoardScoreHistoryRowView)?.apply(model) },
                    isSelectedBand: false, bare: true, onTap: nil
                )))
            }
        } else {
            let holder = UIView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            let content = message()
            content.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: holder.leadingAnchor), content.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                content.topAnchor.constraint(equalTo: holder.topAnchor), content.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                holder.heightAnchor.constraint(greaterThanOrEqualToConstant: max(1, boardView.bounds.height - 200)),
            ])
            heads.append(("message", holder))
        }
        boardView.setContent(headViews: heads, rowItems: rows)
        boardView.chrome.arrangedSubviews.forEach { boardView.chrome.removeArrangedSubview($0); $0.removeFromSuperview() }
    }
}

// MARK: - Sort sheet

/// Score History's sort choices (``PlayerHistorySortSheet``): Date, Score, Accuracy or
/// Season, ascending or descending, applied as they are made, with a red reset.
final class UKPlayerHistorySortViewController: UKFormViewController {
    private var mode: PlayerScoreSortMode
    private var ascending: Bool
    private let onApply: (PlayerScoreSortMode, Bool) -> Void

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    ///   - onApply: Called on every change.
    init(mode: PlayerScoreSortMode, ascending: Bool, onApply: @escaping (PlayerScoreSortMode, Bool) -> Void) {
        self.mode = mode
        self.ascending = ascending
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func build() {
        let modes = PlayerScoreSortMode.allCases.map { choice in
            radioRow(choice.label, identifier: "fst.history.sort.mode.\(choice.rawValue)", selected: { [unowned self] in
                mode == choice
            }) { [unowned self] in
                mode = choice
                onApply(mode, ascending)
            }
        }
        addSection(
            "Mode", subtitle: "Choose which property to sort your score history by.",
            titleIdentifier: "fst.history.sort.mode", rows: modes
        )
        let direction = UKSortDirectionControl(
            ascending: ascending, identifier: "fst.history.sort.direction",
            ascendingDetail: "Oldest first, low to high", descendingDetail: "Newest first, high to low"
        )
        direction.onChange = { [unowned self] value in
            ascending = value
            onApply(mode, ascending)
        }
        addSection("Sort Direction", rows: [direction])
        let reset = buttonRow("Reset Sort Settings", color: Self.destructive, identifier: "fst.history.sort.reset") { [unowned self] in
            mode = PlayerScoreHistorySort.defaultMode
            ascending = PlayerScoreHistorySort.defaultAscending
            direction.ascending = ascending
            onApply(mode, ascending)
        }
        addSection(rows: [reset])
    }
}
#endif
