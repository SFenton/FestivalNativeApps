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
    private var lastSortKey = ""

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

    override var rowGap: CGFloat { 6 }
    override var rowInset: CGFloat { 3 }
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
        boardView.rowsInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 3, trailing: 16)
        boardView.gate.update(key: 0, isLoading: false)
        view.accessibilityIdentifier = nil
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
final class UKPlayerHistorySortViewController: UIViewController, UKModalScrollProviding {
    private var mode: PlayerScoreSortMode
    private var ascending: Bool
    private let onApply: (PlayerScoreSortMode, Bool) -> Void
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var modeButtons: [PlayerScoreSortMode: UIControl] = [:]
    private var checks: [PlayerScoreSortMode: UIImageView] = [:]
    private let direction = UISegmentedControl(items: ["Ascending", "Descending"])
    private let detail = UKLabel(nil, style: .footnote)

    var ukModalScrollView: UIScrollView? { scroll }

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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 24, right: 16)
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        // Mode.
        stack.addArrangedSubview(UKSectionHeaderView("Mode", subtitle: "Choose which property to sort your score history by."))
        let section = UKGroupSectionView(nil, rows: .flush(separatorInset: 16))
        section.card.accessibilityContainerType = .semanticGroup
        section.card.accessibilityIdentifier = "fst.history.sort.mode"
        section.setRows(PlayerScoreSortMode.allCases.map { choice in
            let control = UIControl()
            let label = UKLabel(choice.label)
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = BrandUIColors.accentBlue
            check.setContentHuggingPriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [label, check])
            row.axis = .horizontal
            row.isUserInteractionEnabled = false
            control.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -16),
                row.topAnchor.constraint(equalTo: control.topAnchor, constant: 12), row.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -12),
                control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])
            control.isAccessibilityElement = true
            control.accessibilityLabel = choice.label
            control.accessibilityTraits = [.button]
            control.accessibilityIdentifier = "fst.history.sort.mode.\(choice.rawValue)"
            control.addAction(UIAction { [weak self] _ in
                self?.mode = choice
                self?.changed()
            }, for: .primaryActionTriggered)
            modeButtons[choice] = control
            checks[choice] = check
            return control
        })
        stack.addArrangedSubview(section)
        // Direction.
        stack.addArrangedSubview(UKSectionHeaderView("Sort Direction"))
        direction.accessibilityIdentifier = "fst.history.sort.direction"
        direction.addAction(UIAction { [weak self] _ in
            self?.ascending = self?.direction.selectedSegmentIndex == 0
            self?.changed()
        }, for: .valueChanged)
        stack.addArrangedSubview(direction)
        stack.addArrangedSubview(detail)
        // Reset.
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Reset Sort Settings"
        configuration.baseForegroundColor = BrandUIColors.statusRed
        let reset = UIButton(configuration: configuration)
        reset.accessibilityIdentifier = "fst.history.sort.reset"
        reset.addAction(UIAction { [weak self] _ in
            self?.mode = PlayerScoreHistorySort.defaultMode
            self?.ascending = PlayerScoreHistorySort.defaultAscending
            self?.changed()
        }, for: .primaryActionTriggered)
        stack.addArrangedSubview(reset)
        refresh()
    }

    private func changed() {
        refresh()
        onApply(mode, ascending)
    }

    private func refresh() {
        for (choice, check) in checks { check.isHidden = choice != mode }
        for (choice, control) in modeButtons { control.accessibilityTraits = choice == mode ? [.button, .selected] : [.button] }
        direction.selectedSegmentIndex = ascending ? 0 : 1
        detail.text = ascending ? "Oldest first, low to high" : "Newest first, high to low"
    }
}
#endif
