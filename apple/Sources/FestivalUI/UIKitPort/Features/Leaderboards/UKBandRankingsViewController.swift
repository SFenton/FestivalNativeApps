#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Band Rankings

/// `/leaderboards/bands/:bandType` (ports ``BandRankingsScreen``): paginated band rankings
/// for one band size, the floating pager bar with the band-size switcher below the rows,
/// and Rank By as a page tool.
@MainActor
final class UKBandRankingsViewController: UIViewController, UKPageToolsProviding {
    private struct BoardSummary: Equatable {
        let totalTeams: Int
        let totalPages: Int
    }

    private struct RequestKey: Hashable {
        let bandType: BandType
        let rankBy: BandRankingMetric
        let page: Int
    }

    private let context: UKContext
    private var session: FestivalSession { context.session }
    private var bandType: BandType
    private var selectedRankBy: BandRankingMetric
    private var page: Int
    private var state: RankLoadState<BandRankingsPayload> = .loading
    private var board: BoardSummary?
    private var loadTask: Task<Void, Never>?
    private let boardView: UKBoardView
    private lazy var background = UKBackgroundRegistration(session: session, mode: .carousel)
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var bar: UKRankingsFloatingBar?
    private var lastRankBy: BandRankingMetric?
    private var statusHost: UIView?
    private var lastFitKey = ""

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - bandType: Band size key (`Band_Duets`, `Band_Trios`, `Band_Quad`).
    ///   - rankBy: Initial metric's raw value; unknown values fall back to Total Score.
    ///   - page: Initial 1-based page.
    init(context: UKContext, bandType: String, rankBy: String, page: Int) {
        self.context = context
        self.bandType = BandType(rawValue: bandType) ?? .duets
        selectedRankBy = BandRankingMetric(rawValue: rankBy) ?? .totalscore
        self.page = max(1, page)
        boardView = UKBoardView(
            gateKey: RequestKey(bandType: BandType(rawValue: bandType) ?? .duets, rankBy: .totalscore, page: 1), isLoading: true,
            spinnerLabel: "Loading rankings", spinnerIdentifier: nil, retainsFrame: false
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    private var experimental: Bool { UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue) }
    private var rankBy: BandRankingMetric { selectedRankBy.coerced(experimentalRanks: experimental) }
    private var requestKey: RequestKey { RequestKey(bandType: bandType, rankBy: rankBy, page: page) }
    private var verticalBar: Bool { ukWindowLayout.sectionChrome.isVerticalBar }

    // MARK: Lifecycle

    override func loadView() { view = boardView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        ukInstallAccountItems()
        ukSetPageTitle("\(bandType.label) Rankings")
        boardView.columnsProvider = { [weak self] width in
            guard let self else { return 1 }
            return WideColumns.count(layout: ukLayout, size: CGSize(width: width, height: boardView.bounds.height), subPage: ukIsSplitSubPage)
        }
        boardView.rowsInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16)
        boardView.headInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
        boardView.onLayout = { [weak self] in
            guard let self else { return }
            let key = "\(Int(boardView.bounds.width))|\(boardView.columns)|\(verticalBar)"
            if key != lastFitKey {
                lastFitKey = key
                render()
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        lastRankBy = rankBy
        startLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.viewWillAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
    }

    // MARK: Tools

    var ukPageTools: [UKPageTool] {
        var tools: [UKPageTool] = []
        if verticalBar {
            let item = UIBarButtonItem(
                title: bandType.label, image: UIImage(systemName: "person.3.fill"), primaryAction: nil, menu: bandTypeMenu()
            )
            item.accessibilityIdentifier = "fst.band-rankings.band-type-menu"
            item.accessibilityLabel = "Band size"
            item.accessibilityValue = bandType.label
            tools.append(UKPageTool(order: PageToolOrder.primary, item: item))
        }
        if experimental {
            let item = UKBoardMenus.bandRankByItem(selection: selectedRankBy, experimental: experimental) { [weak self] metric in
                self?.select(rankBy: metric)
            }
            tools.append(UKPageTool(order: verticalBar ? PageToolOrder.secondary : PageToolOrder.primary, item: item))
        }
        return tools
    }

    private func bandTypeMenu() -> UIMenu {
        UKBoardMenus.bandTypeMenu(selected: bandType, idPrefix: "fst.band-rankings.band-type") { [weak self] size in
            self?.select(bandType: size)
        }
    }

    // MARK: Selection

    private func select(bandType size: BandType) {
        guard size != bandType else { return }
        bandType = size
        page = 1
        board = nil
        ukSetPageTitle("\(bandType.label) Rankings")
        ukPageToolsDidChange()
        startLoad()
    }

    private func select(rankBy metric: BandRankingMetric) {
        guard metric != selectedRankBy else { return }
        selectedRankBy = metric
        rankByChanged()
    }

    private func rankByChanged() {
        guard lastRankBy != rankBy else { return }
        lastRankBy = rankBy
        page = 1
        board = nil
        ukPageToolsDidChange()
        startLoad()
    }

    private var lastToolsKey = ""

    private func settingsChanged() {
        rankByChanged()
        let key = "\(experimental)"
        if key != lastToolsKey {
            lastToolsKey = key
            ukPageToolsDidChange()
        }
    }

    private func go(to destination: Int) {
        guard destination != page else { return }
        page = destination
        startLoad()
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
                let payload = try await session.bandRankings(
                    bandType: requested.bandType, rankBy: requested.rankBy, page: requested.page,
                    pageSize: PlayerStatLinks.bandRankingsPageSize
                )
                try Task.checkCancellation()
                guard requested == requestKey else { return }
                let corrected = min(max(1, requested.page), max(1, payload.rankings.pageCount))
                if corrected != requested.page {
                    page = corrected
                    startLoad()
                    return
                }
                board = BoardSummary(totalTeams: payload.rankings.totalTeams, totalPages: payload.rankings.pageCount)
                state = .loaded(payload)
                boardView.gate.update(key: requested, isLoading: false)
                render()
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

    // MARK: Render

    private func render() {
        guard isViewLoaded else { return }
        var heads: [(id: String, view: UIView)] = []
        var rows: [(id: String, row: UKLeaderboardRow)] = []
        var status: UIView?
        switch state {
        case .loading:
            break
        case let .failed(issue):
            status = UKServiceStatusView(issue, title: "Rankings unavailable") { [weak self] in self?.startLoad() }
        case let .loaded(payload):
            let entries = payload.rankings.entries
            let columns = entries.isEmpty ? nil : LeaderboardRowColumns.bandRankings(entries, metric: rankBy)
            if let board {
                let count = UKRankingsCountHeader(text: RankingsCountText.rankedBands(board.totalTeams), identifier: "fst.band-rankings.ranked-count")
                heads.append(("count", ukPadded(count, UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 0))))
            }
            if entries.isEmpty {
                let empty = UKEmptyStateView(
                    "No ranked \(bandType.label.lowercased()) yet", placement: .inline, identifier: "fst.band-rankings.empty"
                )
                heads.append(("empty", ukPadded(empty, UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 0))))
            }
            for entry in entries {
                let route = BandRankingRow.route(entry, bandType: bandType)
                let model = UKRankingRowModels.band(entry: entry, metric: rankBy, columns: columns)
                rows.append((entry.teamKey, UKRankingRowModels.row(model, selectedBand: false) { [weak self] in
                    self?.context.navigator?.selectDetail(route)
                }))
            }
        }
        boardView.setContent(headViews: heads, rowItems: rows)
        statusHost?.removeFromSuperview()
        statusHost = status
        if let status {
            status.translatesAutoresizingMaskIntoConstraints = false
            boardView.gate.contentView.addSubview(status)
            NSLayoutConstraint.activate([
                status.leadingAnchor.constraint(equalTo: boardView.gate.contentView.leadingAnchor),
                status.trailingAnchor.constraint(equalTo: boardView.gate.contentView.trailingAnchor),
                status.topAnchor.constraint(equalTo: boardView.gate.contentView.safeAreaLayoutGuide.topAnchor),
                status.bottomAnchor.constraint(equalTo: boardView.gate.contentView.bottomAnchor),
            ])
        }
        applyChrome()
    }

    private func applyChrome() {
        let chrome = boardView.chrome
        let bar = self.bar ?? UKRankingsFloatingBar(
            idPrefix: "fst.band-rankings", menuIdentifier: "fst.band-rankings.band-type-menu", menuIcon: "person.3.fill"
        )
        self.bar = bar
        bar.onChange = { [weak self] destination in self?.go(to: destination) }
        bar.show(
            state: board.map { RankingsPagerState(page: page, totalPages: $0.totalPages) },
            menu: bandTypeMenu(), menuTitle: bandType.label, verticalBar: verticalBar
        )
        if bar.superview == nil {
            chrome.addArrangedSubview(ukPadded(bar, UIEdgeInsets(top: 0, left: 16, bottom: 8, right: 16)))
        }
    }
}
#endif
