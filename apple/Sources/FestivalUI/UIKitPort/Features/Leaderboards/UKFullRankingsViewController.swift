#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Full Rankings

/// `/leaderboards/all` (ports ``FullRankingsScreen``): paginated global rankings for one
/// instrument (or a within-group combo) and metric, 25 rows a page, the selected player's
/// row pinned above the pager on every page, instrument and Rank By page tools.
@MainActor
final class UKFullRankingsViewController: UIViewController, UKPageToolsProviding {
    private struct BoardSummary: Equatable {
        let totalAccounts: Int
        let totalPages: Int
    }

    private struct RequestKey: Hashable {
        let instrument: Instrument
        let rankBy: RankingMetric
        let page: Int
    }

    /// Rows per page (web `PAGE_SIZE`).
    static let pageSize = FullRankingsScreen.pageSize

    private let context: UKContext
    private var session: FestivalSession { context.session }
    private let combo: RankingCombo?
    private var instrument: Instrument
    private var selectedRankBy: RankingMetric
    private var page: Int
    private var state: RankLoadState<RankingsPayload> = .loading
    private var board: BoardSummary?
    private var spotlightState: RankLoadState<PlayerInstrumentRankingPayload> = .loading
    private var shownEntries: [AccountRankingEntry]?
    private var titleHidden = false
    private var focusPending: Bool
    private var loadTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?
    private let boardView: UKBoardView
    private lazy var background = UKBackgroundRegistration(session: session, mode: .carousel)
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var titleSlot: UKPinnedTitleSlot!
    private var titleView: UIView?
    private var titleKey: String?
    private var lastSelectedID: String??
    private var lastFitKey = ""
    private var selectedRowHeight: CGFloat = 0
    private var pager: UKRankingsPagerView?

    /// Creates the screen for an instrument's board.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - instrument: Chart being ranked.
    ///   - rankBy: Ranking metric raw value.
    ///   - page: 1-based page to open on.
    ///   - focusSelected: Bring the selected player's row into view once shown.
    convenience init(context: UKContext, instrument: Instrument, rankBy: String, page: Int, focusSelected: Bool) {
        self.init(
            context: context, combo: nil, instrument: instrument, rankBy: rankBy, page: page, focusSelected: focusSelected
        )
    }

    /// Creates the screen for a combo's board (issue #602).
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - combo: The within-group combo being ranked.
    ///   - rankBy: Ranking metric raw value.
    ///   - page: 1-based page to open on.
    ///   - focusSelected: Bring the selected player's row into view once shown.
    convenience init(context: UKContext, combo: RankingCombo, rankBy: String, page: Int, focusSelected: Bool) {
        self.init(
            context: context, combo: combo, instrument: combo.instruments.first ?? .lead, rankBy: rankBy, page: page,
            focusSelected: focusSelected
        )
    }

    private init(context: UKContext, combo: RankingCombo?, instrument: Instrument, rankBy: String, page: Int, focusSelected: Bool) {
        self.context = context
        self.combo = combo
        self.instrument = instrument
        selectedRankBy = RankingMetric(rawValue: rankBy) ?? .totalscore
        self.page = max(1, page)
        focusPending = focusSelected
        boardView = UKBoardView(
            gateKey: RequestKey(instrument: instrument, rankBy: .totalscore, page: 1), isLoading: true,
            spinnerLabel: "Loading rankings", spinnerIdentifier: nil, retainsFrame: false
        )
        super.init(nibName: nil, bundle: nil)
        gateKeyInitialize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    private func gateKeyInitialize() {
        boardView.gate.update(key: requestKey, isLoading: true)
    }

    // MARK: Derived

    private var experimental: Bool { UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue) }
    private var rankBy: RankingMetric { selectedRankBy.coerced(experimentalRanks: experimental) }
    private var scope: RankingScope { combo.map(RankingScope.combo) ?? .instrument(instrument) }
    private var pageTitle: String { combo.map(FullRankingsScreen.title(for:)) ?? FullRankingsScreen.title(for: instrument) }
    private var requestKey: RequestKey { RequestKey(instrument: instrument, rankBy: rankBy, page: page) }

    private var visibleInstruments: [Instrument] {
        let shown = UKSettings.visibleInstruments()
        return Instrument.allCases.filter { shown.contains($0) || $0 == instrument }
    }

    private var showsPinnedTitle: Bool {
        switch state {
        case .loaded: titleHidden
        case .failed: true
        case .loading: titleHidden || board == nil
        }
    }

    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    // MARK: Lifecycle

    override func loadView() { view = boardView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        ukInstallAccountItems()
        ukSetPageTitle(pageTitle, mode: .inline)
        titleSlot = UKPinnedTitleSlot(item: navigationItem)
        boardView.columnsProvider = { [weak self] width in
            guard let self else { return 1 }
            return WideColumns.count(layout: ukLayout, size: CGSize(width: width, height: boardView.bounds.height), subPage: ukIsSplitSubPage)
        }
        boardView.onScroll = { [weak self] scroll in self?.scrolled(scroll) }
        boardView.onLayout = { [weak self] in self?.layoutChanged() }
        boardView.rowsInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: UKLeaderboardMetrics.rowGap, trailing: 16)
        boardView.headInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
        boardView.tailInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: UKLeaderboardMetrics.rowGap, trailing: 16)
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        observations.observe { [weak self] in
            guard let self else { return }
            let id = session.selectedPlayer?.accountId
            selectedPlayerChanged(id)
        }
        lastRankBy = rankBy
        startLoad()
        startSpotlight()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.viewWillAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
    }

    // MARK: Page tools

    private var instrumentItem: UIBarButtonItem?
    private var rankByItem: UIBarButtonItem?

    var ukPageTools: [UKPageTool] {
        var tools: [UKPageTool] = []
        if combo == nil {
            let item = UKBoardMenus.instrumentItem(
                selected: instrument, choices: visibleInstruments, identifier: "fst.full-rankings.instrument-menu"
            ) { [weak self] chart in self?.select(instrument: chart) }
            tools.append(UKPageTool(order: PageToolOrder.primary, item: item))
        }
        if experimental {
            let item = UKBoardMenus.rankByItem(selection: selectedRankBy, experimental: experimental) { [weak self] metric in
                self?.select(rankBy: metric)
            }
            tools.append(UKPageTool(order: PageToolOrder.secondary, item: item))
        }
        return tools
    }

    // MARK: Selection

    private var lastRankBy: RankingMetric?

    private func select(instrument chart: Instrument) {
        guard chart != instrument else { return }
        instrument = chart
        resetBoard()
        titleKey = nil
        ukPageToolsDidChange()
        startLoad()
        startSpotlight()
    }

    private func select(rankBy metric: RankingMetric) {
        guard metric != selectedRankBy else { return }
        selectedRankBy = metric
        rankByChanged()
    }

    private func rankByChanged() {
        guard lastRankBy != rankBy else { return }
        lastRankBy = rankBy
        resetBoard()
        ukPageToolsDidChange()
        startLoad()
        if combo != nil { startSpotlight() }
    }

    private var lastToolsKey = ""

    private func settingsChanged() {
        rankByChanged()
        let key = "\(experimental)|\(visibleInstruments.map(\.rawValue))"
        if key != lastToolsKey {
            lastToolsKey = key
            ukPageToolsDidChange()
        }
    }

    private func resetBoard() {
        page = 1
        focusPending = false
        board = nil
        shownEntries = nil
        titleHidden = false
    }

    private func go(to destination: Int) {
        guard destination != page else { return }
        page = destination
        startLoad()
    }

    private func selectedPlayerChanged(_ id: String?) {
        guard lastSelectedID != .some(id) else { return }
        let first = lastSelectedID == nil
        lastSelectedID = .some(id)
        if !first {
            startSpotlight()
            render()
        }
    }

    // MARK: Loading

    private func startLoad() {
        loadTask?.cancel()
        let requested = requestKey
        state = .loading
        boardView.gate.update(key: requested, isLoading: true)
        render()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.rankings(
                    scope: scope, rankBy: requested.rankBy, page: requested.page, pageSize: Self.pageSize
                )
                try Task.checkCancellation()
                guard requested == requestKey else { return }
                let corrected = min(max(1, requested.page), max(1, payload.rankings.pageCount))
                if corrected != requested.page {
                    page = corrected
                    startLoad()
                    return
                }
                board = BoardSummary(totalAccounts: payload.rankings.totalAccounts, totalPages: payload.rankings.pageCount)
                shownEntries = payload.rankings.entries
                state = .loaded(payload)
                boardView.gate.update(key: requested, isLoading: false)
                render()
                revealFocusIfNeeded(payload)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard requested == requestKey else { return }
                state = .failed(ServiceIssue(error))
                boardView.gate.update(key: requested, isLoading: false)
                render()
            }
        }
    }

    private func startSpotlight() {
        spotlightTask?.cancel()
        guard let accountId = session.selectedPlayer?.accountId else {
            spotlightState = .loading
            return
        }
        spotlightState = .loading
        spotlightTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.playerRanking(scope: scope, accountId: accountId, rankBy: rankBy)
                try Task.checkCancellation()
                spotlightState = .loaded(payload)
            } catch is CancellationError {
                return
            } catch {
                spotlightState = .failed(ServiceIssue(error))
            }
            render()
        }
    }

    private func revealFocusIfNeeded(_ payload: RankingsPayload) {
        guard focusPending else { return }
        let entries = payload.rankings.entries
        guard let target = entries.firstIndex(where: { isSelectedAccount($0.accountId) }) else {
            focusPending = false
            return
        }
        let id = entries[WideColumns.rowStart(of: target, columns: boardView.columns)].id
        Task { [weak self] in
            let animates = SelectedRowReveal.loadFadesPlay && !UKAccessibility.reduceMotion
            try? await Task.sleep(for: SelectedRowReveal.wait(staggerIndex: BoardCardEntrance.index, animates: animates))
            guard let self, !Task.isCancelled else { return }
            boardView.scrollToRow(id, animated: !UKAccessibility.reduceMotion)
            focusPending = false
        }
    }

    // MARK: Spotlight

    private func spotlightPlacement(entries: [AccountRankingEntry]) -> RankingSpotlightPlacement? {
        guard let accountId = session.selectedPlayer?.accountId else { return nil }
        let source: RankingSpotlightSource = {
            switch spotlightState {
            case .loading: return .notLoaded
            case let .loaded(payload): return payload.ranking.map { .available($0.entry) } ?? .unranked
            case .failed: return .notLoaded
            }
        }()
        return RankingSpotlight.pinnedFooter(selectedAccountId: accountId, visibleEntries: entries, source: source)
    }

    private func footerEntries(_ entries: [AccountRankingEntry]) -> [AccountRankingEntry] {
        var rows = entries
        if case let .footer(entry) = spotlightPlacement(entries: entries) { rows.append(entry) }
        return rows
    }

    private func fittedColumns() -> LeaderboardRowColumns? {
        guard let shownEntries else { return nil }
        let rows = footerEntries(shownEntries)
        let names = rows.map { RankingRowName(name: AccountRankingRow.displayName($0), emphasized: isSelectedAccount($0.accountId)) }
        return UKRankingRowModels.fittingSongs(
            LeaderboardRowColumns.rankings(rows, metric: rankBy), names: names, sectionWidth: boardView.bounds.width,
            rowInset: 32, pageColumns: boardView.columns, traits: traitCollection
        )
    }

    private func showsFooter(_ placement: RankingSpotlightPlacement?) -> Bool {
        switch placement {
        case .pending, .unranked, .footer: true
        case .some(.none), .inline, nil: false
        }
    }

    // MARK: Render

    private func layoutChanged() {
        let key = "\(Int(boardView.bounds.width))|\(boardView.columns)|\(traitCollection.preferredContentSizeCategory.rawValue)"
        guard key != lastFitKey else { return }
        lastFitKey = key
        if boardView.bounds.width > 0 { render() }
    }

    private func scrolled(_ scroll: UIScrollView) {
        guard case .loaded = state, let frame = boardView.headFrame("title") else { return }
        let maxY = frame.maxY - (scroll.contentOffset.y + scroll.adjustedContentInset.top)
        let hidden = SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: maxY)
        if hidden != titleHidden {
            titleHidden = hidden
            updatePinnedTitle()
        }
    }

    private func updatePinnedTitle() {
        guard InstrumentPageTitleToolbarItem.pinsTitle(in: ukWindowLayout.sectionChrome) else { return }
        let key = "\(combo == nil ? instrument.rawValue : "combo")|\(pageTitle)"
        if key != titleKey {
            titleKey = key
            titleSlot.setTitle(UKInstrumentPageTitleView(
                instrument: combo == nil ? instrument : nil, title: pageTitle, style: .pinned, identifier: "fst.full-rankings.pinned-title"
            ))
        }
        titleSlot.setShown(showsPinnedTitle, animated: true)
    }

    private func render() {
        guard isViewLoaded else { return }
        ukSetPageTitle(pageTitle, mode: .inline)
        updatePinnedTitle()
        let columns = fittedColumns()
        let metric = rankBy
        var heads: [(id: String, view: UIView)] = []
        var rows: [(id: String, row: UKLeaderboardRow)] = []
        var tails: [(id: String, view: UIView)] = []
        var statusView: UIView?
        switch state {
        case .loading:
            break
        case let .failed(issue):
            statusView = UKServiceStatusView(issue, title: "Rankings unavailable") { [weak self] in self?.startLoad() }
        case let .loaded(payload):
            let entries = payload.rankings.entries
            if titleView == nil || titleKey2 != "\(scope.id)|\(pageTitle)" {
                titleKey2 = "\(scope.id)|\(pageTitle)"
                titleView = UKInstrumentPageTitleView(
                    instruments: scope.instruments, title: pageTitle, style: .header, identifier: "fst.full-rankings.title"
                )
            }
            if let titleView {
                heads.append(("title", ukPadded(titleView, UIEdgeInsets(top: 0, left: 0, bottom: UKLeaderboardMetrics.rowGap, right: 0))))
            }
            if let board {
                let count = UKRankingsCountHeader(
                    text: RankingsCountText.rankedPlayers(board.totalAccounts), identifier: "fst.full-rankings.ranked-count"
                )
                heads.append(("count", ukPadded(count, UIEdgeInsets(top: 0, left: 0, bottom: UKLeaderboardMetrics.rowGap, right: 0))))
            }
            if entries.isEmpty {
                let empty = UKEmptyStateView("No ranked players yet", placement: .inline, identifier: "fst.full-rankings.empty")
                heads.append(("empty", ukPadded(empty, UIEdgeInsets(top: 0, left: 0, bottom: UKLeaderboardMetrics.rowGap, right: 0))))
            }
            for entry in entries {
                let model = UKRankingRowModels.account(
                    entry: entry, metric: metric, isSelected: isSelectedAccount(entry.accountId), columns: columns
                )
                let route = AccountRankingRow.route(entry)
                rows.append((entry.id, UKRankingRowModels.row(
                    model, selectedBand: isSelectedAccount(entry.accountId),
                    onTap: entry.hasAccount ? { [weak self] in self?.context.navigator?.selectDetail(route) } : nil
                )))
            }
        }
        // Footer and pager.
        let placement = shownEntries.flatMap { spotlightPlacement(entries: $0) }
        let footer = (shownEntries != nil && showsFooter(placement)) ? makeFooter(columns: columns) : nil
        let pinned = footer.map { pins($0) } ?? true
        if let footer, !pinned { tails.append(("footer", footer)) }
        boardView.setContent(headViews: heads, rowItems: rows, tailViews: tails)
        applyStatus(statusView)
        applyChrome(footer: pinned ? footer : nil)
    }

    private var titleKey2: String?
    private var statusHost: UIView?

    private func applyStatus(_ status: UIView?) {
        statusHost?.removeFromSuperview()
        statusHost = status
        guard let status else { return }
        status.translatesAutoresizingMaskIntoConstraints = false
        boardView.gate.contentView.addSubview(status)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: boardView.gate.contentView.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: boardView.gate.contentView.trailingAnchor),
            status.topAnchor.constraint(equalTo: boardView.gate.contentView.safeAreaLayoutGuide.topAnchor),
            status.bottomAnchor.constraint(equalTo: boardView.gate.contentView.bottomAnchor),
        ])
    }

    private func pins(_ footer: UIView) -> Bool {
        let width = max(1, boardView.bounds.width - 32)
        let height = UKSelfSizing.fittingHeight(of: footer, width: width)
        selectedRowHeight = height
        return SelectedRowPinning.pins(
            isAccessibilitySize: UKFont.isAccessibilitySize(traitCollection),
            rowHeight: Double(height), boardHeight: Double(boardView.bounds.height)
        )
    }

    private func makeFooter(columns: LeaderboardRowColumns?) -> UIView? {
        guard let entries = shownEntries, let placement = spotlightPlacement(entries: entries) else { return nil }
        let footer = UKPinnedFooterView()
        switch placement {
        case .none, .inline:
            return nil
        case .pending:
            if case let .failed(issue) = spotlightState {
                let inline = UKServiceStatusInlineView(issue, scope: "full-rankings.spotlight") { [weak self] in self?.startSpotlight() }
                footer.setMessage(ukPadded(inline, UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)), plated: true)
            } else {
                footer.setMessage(ukSpotlightLoadingRow(identifier: "fst.full-rankings.spotlight-footer.loading"), plated: false)
            }
        case .unranked:
            footer.setMessage(
                ukCardMessage("You're not yet ranked on \(scope.label).", identifier: "fst.full-rankings.spotlight-footer.unranked"),
                plated: true
            )
        case let .footer(entry):
            let metric = rankBy
            let rank = entry.rank(for: metric)
            let loadedRows: [String]? = if case let .loaded(payload) = state { payload.rankings.entries.map(\.accountId) } else { nil }
            let isVisible = LeaderboardPaging.isSelectedOnPage(
                accountId: entry.accountId, rank: rank, page: page, pageSize: Self.pageSize, entries: loadedRows
            )
            let action = SelectedRowAction.footer(rank: rank, isVisible: isVisible, pageSize: Self.pageSize)
            let row = UKRankingRowView()
            row.apply(UKRankingRowModels.account(entry: entry, metric: metric, isSelected: true, columns: columns, opensProfile: false))
            switch action {
            case .openProfile:
                footer.setButton(
                    row: row, containerIdentifier: "fst.full-rankings.spotlight-footer", buttonIdentifier: "fst.full-rankings.spotlight-open",
                    label: action.footerLabel(for: .player, rank: rank)
                )
                footer.onTap = { [weak self] in self?.context.navigator?.push(.statistics) }
            case let .jump(destination):
                footer.setButton(
                    row: row, containerIdentifier: "fst.full-rankings.spotlight-footer", buttonIdentifier: "fst.full-rankings.spotlight-jump",
                    label: action.footerLabel(for: .player, rank: rank)
                )
                footer.onTap = { [weak self] in
                    self?.focusPending = true
                    self?.go(to: destination)
                }
            }
        }
        return footer
    }

    private func applyChrome(footer: UIView?) {
        let chrome = boardView.chrome
        chrome.arrangedSubviews.forEach { chrome.removeArrangedSubview($0); $0.removeFromSuperview() }
        let hasFooter = footer != nil
        let spacing = PinnedChromeSpacing.resolve(
            rowGap: Double(UKLeaderboardMetrics.rowGap), rowBottomInset: Double(UKLeaderboardMetrics.rowGap), edgePadding: 8,
            hasFooter: hasFooter, hasPager: board != nil
        )
        if let footer {
            chrome.addArrangedSubview(ukPadded(footer, UIEdgeInsets(top: spacing.footerTop, left: 16, bottom: spacing.footerBottom, right: 16)))
        }
        if let board {
            let pager = self.pager ?? UKRankingsPagerView(idPrefix: "fst.full-rankings")
            self.pager = pager
            pager.onChange = { [weak self] destination in self?.go(to: destination) }
            pager.show(RankingsPagerState(page: page, totalPages: board.totalPages))
            chrome.addArrangedSubview(ukPadded(pager, UIEdgeInsets(top: spacing.pagerTop, left: 16, bottom: 8, right: 16)))
        }
        chrome.accessibilityElements = chrome.arrangedSubviews
    }
}

#endif
