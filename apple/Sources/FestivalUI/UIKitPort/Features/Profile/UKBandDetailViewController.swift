#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Band detail

/// `/bands/:bandId`: one band's page, matching the web client's `BandPage`
/// (``BandDetailScreen``): the member names as the large title with a "type • N appearances"
/// line under it, then Members, Band Summary and Band Statistics stat cards, the Band Rank
/// History chart, and Five Best / Five Worst Songs.
///
/// Every read is the same pure `GET /api/rankings/bands/{bandType}` board the Band Rankings
/// page uses, filtered to one `teamKey`, plus its `/history` and `/songs` sub-routes: never
/// `/api/bands/{bandId}` or the bare team route, whose handlers write on a GET (see
/// `.agents/platforms/service-safety.md`). A bare `bandId` cannot be resolved to a `bandType`
/// and `teamKey`, so without both this page shows an explicit "open from a band list" state
/// rather than guessing.
@MainActor
final class UKBandDetailViewController: UKProfileScrollViewController {
    // MARK: Inputs

    private let bandId: String
    private let name: String?
    private let bandType: BandType?
    private let teamKey: String?

    // MARK: State

    private var detailState: RankLoadState<BandDetail> = .loading
    private var totalRankedTeams: Int?
    private var historyState: RankLoadState<BandRankHistoryResponse> = .loading
    private var songsState: RankLoadState<BandSongExtremesResponse> = .loading
    private var selectedRankBy: BandRankingMetric = .adjusted
    private var songsById: [String: Song] = [:]
    private var detailTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var songsTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var renderedExperimental: Bool?
    private var rankByItem: UIBarButtonItem?
    private var statisticsGrid: UKStatGridView?
    private let historyHost = UKProfileHost()
    private let songsHost = UKProfileHost()
    private let refresh = UIRefreshControl()

    private var experimentalRanks: Bool {
        UKProfileSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue)
    }

    // MARK: Init

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - bandId: Band identifier from the originating link.
    ///   - name: Band member roster label known from the originating link, if any.
    ///   - bandType: Band size, when the originating row already knew it.
    ///   - teamKey: Stable member-account-id roster key, when already known.
    init(context: UKContext, bandId: String, name: String?, bandType: String?, teamKey: String?) {
        self.bandId = bandId
        self.name = name
        self.bandType = bandType.flatMap(BandType.init(rawValue:))
        self.teamKey = teamKey
        super.init(context: context)
    }

    deinit {
        for task in [detailTask, historyTask, songsTask, lookupTask, settingsTask] { task?.cancel() }
    }

    // MARK: Derived

    private var isResolvable: Bool { bandType != nil && teamKey?.isEmpty == false }

    /// The metric in effect: Total Score while Settings › Experimental Ranks is off.
    private var rankBy: BandRankingMetric { selectedRankBy.coerced(experimentalRanks: experimentalRanks) }

    private var showsRankBy: Bool {
        guard experimentalRanks, isResolvable, case .loaded = detailState else { return false }
        return true
    }

    /// The loaded roster's names (web `formatBandTitle`), else the originating link's label.
    private var pageTitle: String {
        if case let .loaded(detail) = detailState {
            return BandPageFormatting.title(memberNames: detail.members.map(\.resolvedName))
        }
        return name.map { BandPageFormatting.title(memberNames: [$0]) } ?? "Band"
    }

    private var bestSongId: String? {
        if case let .loaded(extremes) = songsState { return extremes.best.first?.songId }
        return nil
    }

    private var hasNavigator: Bool { context.navigator != nil }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        installQuickLinks()
        refresh.addAction(UIAction { [weak self] _ in self?.pullToRefresh() }, for: .valueChanged)
        scrollView.refreshControl = refresh
        updateTitle()
        renderedExperimental = experimentalRanks
        settingsTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UKSettings.didChange) {
                self?.settingsChanged()
            }
        }
        render()
        if isResolvable {
            loadDetail()
            loadSongLookup()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UKRefreshCommands.shared.register(self) { [weak self] in await self?.refreshAll() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UKRefreshCommands.shared.unregister(self)
    }

    override var ukPageTools: [UKPageTool] {
        var tools = super.ukPageTools
        if showsRankBy, let rankByItem { tools.append(UKPageTool(order: PageToolOrder.primary, item: rankByItem)) }
        return tools
    }

    override var pageBarItems: [UIBarButtonItem] { [] }

    private func updateTitle() {
        ukSetPageTitle(pageTitle, mode: .large)
    }

    private func settingsChanged() {
        guard isViewLoaded, renderedExperimental != experimentalRanks else { return }
        renderedExperimental = experimentalRanks
        render()
    }

    // MARK: Render

    private func render() {
        guard isViewLoaded else { return }
        updateTitle()
        rebuildRankByItem()
        guard isResolvable else {
            let empty = UKEmptyStateView(
                "Band Not Available", systemImage: "person.3",
                subtitle: "Open this band from Player Bands, Band Rankings or a song's Band Scores to see its details.",
                identifier: "fst.band.unresolved"
            )
            empty.hingeProvider = hingeProvider
            showState(empty)
            pageToolsChanged()
            return
        }
        switch detailState {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading band", placement: .fill)
            loading.hingeProvider = hingeProvider
            showState(loading)
        case let .failed(issue):
            showState(UKServiceStatusView(issue, title: "Band unavailable") { [weak self] in self?.loadDetail() })
        case let .loaded(detail):
            renderLoaded(detail)
        }
        pageToolsChanged()
    }

    private func renderLoaded(_ detail: BandDetail) {
        var sections: [UIView] = []
        var anchors: [(QuickLinkSection, UIView)] = []
        if let bandType {
            let label = UKLabel(
                BandPageFormatting.subtitle(bandType: bandType, appearances: detail.songsPlayed), style: .subheadline, weight: .semibold
            )
            label.accessibilityIdentifier = "fst.band.subtitle"
            sections.append(UKProfileInset(label, horizontal: UKProfileMetrics.headerInset, bottom: -8))
        }
        let members = membersSection(detail)
        let summary = summarySection(detail)
        let statistics = statisticsSection(detail)
        let history = historySection(detail)
        let songs = songsSection(detail)
        sections += [members, summary, statistics, history, songs]
        anchors = [
            (QuickLinkSection(id: "members", title: "Members", icon: .system("person.3.fill")), members),
            (QuickLinkSection(id: "summary", title: "Summary", icon: .system("list.bullet")), summary),
            (QuickLinkSection(id: "statistics", title: "Statistics", icon: .system("chart.bar.fill")), statistics),
            (QuickLinkSection(id: "rank-history", title: "Rank History", icon: .system("chart.line.uptrend.xyaxis")), history),
            (QuickLinkSection(id: "songs", title: "Songs", icon: .system("music.note")), songs),
        ]
        setSections(sections, fadeIn: true)
        setQuickLinks(anchors)
        renderHistory()
        renderSongs()
    }

    private func heading(_ title: String, subtitle: String? = nil) -> UIView {
        UKProfileInset(UKSectionHeaderView(title, subtitle: subtitle), horizontal: UKProfileMetrics.headerInset)
    }

    private func layoutProvider() -> DeviceLayout { layout }

    // MARK: Members

    /// Web `MembersSection`: one card per member (name, instrument icons, chevron) opening
    /// the player's profile, in the web's auto-fit card grid.
    private func membersSection(_ detail: BandDetail) -> UIView {
        let grid = UKProfileColumnGrid(columns: .adaptive(minimum: BandMemberCard.minimumWidth), spacing: 8)
        grid.layoutProvider = { [weak self] in self?.layout ?? .standardPhone }
        grid.setCells(detail.members.map { member in
            UKBandMemberCardView(member: member) { [weak self] route in self?.context.navigator?.push(route) }
        })
        let section = UKProfileSection([heading("Members"), grid], spacing: 8)
        section.ukContain(identifier: "fst.band.members-section")
        return section
    }

    // MARK: Summary and statistics

    private func summarySection(_ detail: BandDetail) -> UIView {
        let grid = makeGrid(BandDetailScreen.summaryTiles(detail, bandType: bandType), scope: "summary")
        let section = UKProfileSection([heading("Band Summary"), grid], spacing: 8)
        section.ukContain(identifier: "fst.band.summary-section")
        return section
    }

    private func statisticsTiles(_ detail: BandDetail) -> [StatTile] {
        BandDetailScreen.statisticsTiles(
            detail, bandType: bandType, bestSongId: bestSongId, experimentalRanks: experimentalRanks,
            linkFilter: { [hasNavigator] link in hasNavigator ? link : nil }
        )
    }

    private func statisticsSection(_ detail: BandDetail) -> UIView {
        let grid = makeGrid(statisticsTiles(detail), scope: "statistics")
        statisticsGrid = grid
        let section = UKProfileSection([heading("Band Statistics"), grid], spacing: 8)
        section.ukContain(identifier: "fst.band.statistics-section")
        return section
    }

    private func makeGrid(_ tiles: [StatTile], scope: String) -> UKStatGridView {
        let grid = UKStatGridView(
            tiles: tiles, scope: scope, identifierPrefix: BandDetailScreen.statIdentifierPrefix,
            layoutProvider: { [weak self] in self?.layout ?? .standardPhone }
        )
        grid.onSelect = { [weak self] link in
            guard let self else { return }
            UKProfileLinks.follow(link, context: self.context)
        }
        return grid
    }

    // MARK: Rank history

    /// Web `BandRankHistoryChart`: the Player profile's rank-history chart plotting the Rank
    /// By metric, in its card with the 30-day hint and history status.
    private func historySection(_ detail: BandDetail) -> UIView {
        historyHost.subviews.forEach { $0.removeFromSuperview() }
        historyHost.translatesAutoresizingMaskIntoConstraints = false
        historyHost.ukContain(identifier: "fst.band.history-section")
        return historyHost
    }

    private func historySubtitle(_ history: BandRankHistoryResponse?) -> String {
        BandPageFormatting.historySubtitle(
            days: history?.days ?? BandPageFormatting.historyDays,
            status: history?.historyStatus, message: history?.historyMessage
        )
    }

    private var historyWidth: CGFloat { historyHost.width }

    private func renderHistory() {
        guard case .loaded = detailState else { return }
        historyHost.subviews.forEach { $0.removeFromSuperview() }
        let section: UKGroupSectionView
        switch historyState {
        case .loading:
            section = UKGroupSectionView("Band Rank History", subtitle: historySubtitle(nil))
            let loading = UKLoadingView(accessibilityLabel: "Loading band rank history")
            loading.heightAnchor.constraint(equalToConstant: RankHistoryCharts.plotHeight).isActive = true
            section.setRows([loading])
        case let .failed(issue):
            section = UKGroupSectionView("Band Rank History", subtitle: historySubtitle(nil))
            section.setRows([UKServiceStatusInlineView(issue, scope: "band.history") { [weak self] in self?.loadHistory() }])
        case let .loaded(history):
            let ranked = history.rankedChronological(for: rankBy)
            section = UKGroupSectionView("Band Rank History", subtitle: historySubtitle(history))
            if ranked.isEmpty {
                let note = UKFootnoteLabel("No band rank history yet.")
                note.accessibilityIdentifier = "fst.band.history-empty"
                section.setRows([note])
            } else {
                let chart = UKRankHistoryChartView(
                    points: RankHistoryCharts.points(ranked, metric: rankBy, totalRankedTeams: totalRankedTeams),
                    valueKind: .band(rankBy), title: "Band rank history", identifierPrefix: "fst.band.rank-history",
                    initialChartWidth: RankHistoryCharts.chartWidth(forCardWidth: historyWidth)
                )
                section.setRows([chart])
                chart.prepare(width: max(0, historyWidth - 32))
            }
        }
        historyHost.ukPin(section)
    }

    // MARK: Songs

    /// Web `BandSongsSection`: Five Best Songs then Five Worst Songs, each under its heading
    /// and description, one card per song opening Song Detail.
    private func songsSection(_ detail: BandDetail) -> UIView {
        songsHost.translatesAutoresizingMaskIntoConstraints = false
        songsHost.ukContain(identifier: "fst.band.songs-section")
        return songsHost
    }

    private func renderSongs() {
        guard case .loaded = detailState else { return }
        songsHost.subviews.forEach { $0.removeFromSuperview() }
        let stack = UKProfileSection([
            songList(
                "Five Best Songs", description: BandPageFormatting.bestSongsDescription(pageTitle),
                empty: "No ranked band songs yet.", id: "best", entries: \.best
            ),
            songList(
                "Five Worst Songs", description: BandPageFormatting.worstSongsDescription(pageTitle),
                empty: "No additional ranked band songs yet.", id: "worst", entries: \.worst
            ),
        ], spacing: 20)
        songsHost.ukPin(stack)
    }

    private func songList(
        _ heading: String, description: String, empty: String, id: String,
        entries: KeyPath<BandSongExtremesResponse, [BandSongPerformanceEntry]>
    ) -> UIView {
        var views: [UIView] = [self.heading(heading, subtitle: description)]
        switch songsState {
        case .loading:
            let section = UKGroupSectionView()
            section.setRows([UKLoadingView(accessibilityLabel: "Loading \(heading)")])
            views.append(section)
        case let .failed(issue):
            let section = UKGroupSectionView()
            section.setRows([UKServiceStatusInlineView(issue, scope: "band.songs.\(id)") { [weak self] in self?.loadSongs() }])
            views.append(section)
        case let .loaded(extremes):
            let rows = extremes[keyPath: entries]
            if rows.isEmpty {
                let section = UKGroupSectionView()
                let title = UKLabel(empty, style: .headline)
                let note = UKLabel(description, style: .footnote)
                let stack = UIStackView(arrangedSubviews: [title, note])
                stack.axis = .vertical
                stack.spacing = 4
                stack.isAccessibilityElement = true
                stack.accessibilityLabel = "\(empty), \(description)"
                stack.accessibilityIdentifier = "fst.band.\(id)-songs-empty"
                section.setRows([stack])
                views.append(section)
            } else {
                let list = UKProfileSection(rows.map { entry in
                    UKBandSongRowView(entry: entry, song: songsById[entry.songId], session: session, layoutProvider: { [weak self] in self?.layout ?? .standardPhone }) { [weak self] route in
                        self?.context.navigator?.push(route)
                    }
                }, spacing: 8)
                views.append(list)
                UKFadeIn.fadeIn(list)
            }
        }
        let section = UKProfileSection(views, spacing: 8)
        section.ukContain(identifier: "fst.band.\(id)-songs")
        return section
    }

    // MARK: Page tools

    private func rebuildRankByItem() {
        guard showsRankBy else {
            rankByItem = nil
            return
        }
        let current = rankBy
        let actions = BandRankingMetric.enabled(experimentalRanks: experimentalRanks).map { metric in
            let action = UIAction(title: metric.label, state: metric == current ? .on : .off) { [weak self] _ in
                guard let self, self.selectedRankBy != metric else { return }
                self.selectedRankBy = metric
                self.rebuildRankByItem()
                self.pageToolsChanged()
                self.loadHistory()
            }
            action.accessibilityIdentifier = "fst.band-rankings.rank-by.\(metric.rawValue)"
            return action
        }
        let item = UIBarButtonItem(title: current.label, image: UIImage(systemName: "arrow.up.arrow.down"), menu: UIMenu(title: "Rank By", options: .singleSelection, children: actions))
        item.tintColor = BrandUIColors.textPrimary
        item.accessibilityLabel = current.label
        item.accessibilityIdentifier = "fst.band-rankings.rank-by-menu"
        rankByItem = item
    }

    // MARK: Loading

    /// Load the band's ranking row, then its history and songs.
    ///
    /// - Parameter force: Reissue the read behind a spinner (pull-to-refresh).
    private func loadDetail(force: Bool = false) {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        detailTask?.cancel()
        if force || !loaded { detailState = .loading }
        if force { render() }
        detailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.readDetail(bandType: bandType, teamKey: teamKey)
        }
    }

    private var loaded: Bool {
        if case .loaded = detailState { return true }
        return false
    }

    private func readDetail(bandType: BandType, teamKey: String) async {
        do {
            let payload = try await session.bandProfile(bandType: bandType, teamKey: teamKey)
            try Task.checkCancellation()
            totalRankedTeams = payload.totalRankedTeams
            detailState = .loaded(payload.detail)
            render()
            loadHistory()
            loadSongs()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            detailState = .failed(ServiceIssue(error))
            render()
        }
    }

    private func loadHistory() {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        historyTask?.cancel()
        historyState = .loading
        renderHistory()
        historyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.readHistory(bandType: bandType, teamKey: teamKey)
        }
    }

    private func readHistory(bandType: BandType, teamKey: String) async {
        do {
            let payload = try await session.bandRankHistory(bandType: bandType, teamKey: teamKey)
            try Task.checkCancellation()
            historyState = .loaded(payload.response)
        } catch is CancellationError {
            return
        } catch {
            historyState = .failed(ServiceIssue(error))
        }
        renderHistory()
    }

    private func loadSongs() {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        songsTask?.cancel()
        songsState = .loading
        renderSongs()
        songsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.readSongs(bandType: bandType, teamKey: teamKey)
        }
    }

    private func readSongs(bandType: BandType, teamKey: String) async {
        do {
            let payload = try await session.bandSongExtremes(bandType: bandType, teamKey: teamKey)
            try Task.checkCancellation()
            songsState = .loaded(payload.response)
        } catch is CancellationError {
            return
        } catch {
            songsState = .failed(ServiceIssue(error))
        }
        renderSongs()
        if case let .loaded(detail) = detailState { statisticsGrid?.setTiles(statisticsTiles(detail)) }
    }

    /// Build the songId to catalogue lookup used to enrich Best/Worst Songs rows. Best-effort:
    /// a failed or not-yet-loaded catalogue leaves rows on the raw `songId` fallback.
    private func loadSongLookup() {
        lookupTask?.cancel()
        lookupTask = Task { @MainActor [weak self] in
            guard let self, let payload = try? await self.session.catalog() else { return }
            self.songsById = Dictionary(payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
            self.renderSongs()
        }
    }

    private func pullToRefresh() {
        Task { @MainActor [weak self] in
            await self?.refreshAll()
            self?.refresh.endRefreshing()
        }
    }

    private func refreshAll() async {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        detailState = .loading
        render()
        await readDetail(bandType: bandType, teamKey: teamKey)
    }
}

// MARK: - Member card

/// Web `BandMemberCard` (``BandMemberCard``): the member's name over their instrument icons
/// (32 pt) and a chevron, on the shared band-row card, opening their profile.
final class UKBandMemberCardView: UIControl {
    private let member: BandMember
    private let onOpen: (AppRoute) -> Void
    private var nameLabel: UKLabel?

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - member: The band member.
    ///   - onOpen: Opens the player's profile.
    init(member: BandMember, onOpen: @escaping (AppRoute) -> Void) {
        self.member = member
        self.onOpen = onOpen
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let card = UKCardView(cornerRadius: UKProfileMetrics.rowCornerRadius)
        card.isUserInteractionEnabled = false
        ukPin(card)
        let name = UKLabel(member.resolvedName, style: .body, weight: .bold, lines: 1)
        nameLabel = name
        var column: [UIView] = [name]
        if !member.chartedInstruments.isEmpty {
            let icons = UIStackView(arrangedSubviews: member.chartedInstruments.map {
                UKInstrumentIconView($0, size: 32, hidesFromAccessibility: true)
            })
            icons.spacing = 6
            let holder = UIStackView(arrangedSubviews: [icons, UIView()])
            column.append(holder)
        }
        let details = UIStackView(arrangedSubviews: column)
        details.axis = .vertical
        details.spacing = 8
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = BrandUIColors.textMuted
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [details, chevron])
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        ukPin(row, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardRowMetrics.minHeight).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = BandMemberCard.spokenLabel(member)
        accessibilityHint = "Opens player profile"
        accessibilityTraits = .button
        accessibilityIdentifier = "fst.band.member.\(member.accountId)"
        applyLineLimit()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKBandMemberCardView, _) in self.applyLineLimit() }
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onOpen(.player(accountId: self.member.accountId, displayName: self.member.displayName))
        }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyLineLimit() {
        nameLabel?.numberOfLines = UKFont.isAccessibilitySize(traitCollection) ? 0 : 1
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - Song row

/// Web `PlayerSongRow` in `BandSongsSection` (``BandSongRow``): album art, title,
/// "artist · year" and the percentile pill on its own Song row card, opening Song Detail.
/// The pill drops under the song on a compact width or at accessibility sizes.
final class UKBandSongRowView: UIControl {
    private let entry: BandSongPerformanceEntry
    private let song: Song?
    private let onOpen: (AppRoute) -> Void
    private let layoutProvider: () -> DeviceLayout
    private let syncGroup = UKMarqueeSyncGroup()
    private var content: UIView?

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - entry: Band song performance.
    ///   - song: The catalogue song, or nil before the catalogue answers or for an unknown id.
    ///   - session: Shared app session (artwork).
    ///   - layoutProvider: The window layout.
    ///   - onOpen: Opens Song Detail.
    init(
        entry: BandSongPerformanceEntry, song: Song?, session: FestivalSession,
        layoutProvider: @escaping () -> DeviceLayout, onOpen: @escaping (AppRoute) -> Void
    ) {
        self.entry = entry
        self.song = song
        self.onOpen = onOpen
        self.layoutProvider = layoutProvider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let card = UKCardView(cornerRadius: UKProfileMetrics.rowCornerRadius)
        card.isUserInteractionEnabled = false
        ukPin(card)
        build(session: session)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = BandSongRow.spokenLabel(entry, song: song)
        accessibilityIdentifier = "fst.band.song-row.\(entry.songId)"
        if let song {
            accessibilityTraits = .button
            accessibilityHint = "Opens the song"
            addAction(UIAction { [weak self] _ in self?.onOpen(.songDetail(song)) }, for: .touchUpInside)
        } else {
            isUserInteractionEnabled = false
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitHorizontalSizeClass.self]) { (self: UKBandSongRowView, _) in
            self.rebuild(session: session)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var twoRow: Bool {
        traitCollection.horizontalSizeClass != .regular || UKFont.isAccessibilitySize(traitCollection)
    }

    private func rebuild(session: FestivalSession) {
        content?.removeFromSuperview()
        build(session: session)
    }

    private func build(session: FestivalSession) {
        let art = UKArtworkTileView(size: 44)
        art.configure(raw: song?.albumArt, session: session)
        art.isAccessibilityElement = false
        let title = UKMarqueeLabel(BandSongRow.title(song), font: UKFont.font(.subheadline, weight: .semibold))
        title.syncGroup = syncGroup
        var texts: [UIView] = [title]
        if let subtitle = BandSongRow.subtitle(song) {
            let line = UKMarqueeLabel(subtitle, font: UKFont.font(.caption1))
            line.syncGroup = syncGroup
            texts.append(line)
        }
        let textStack = UIStackView(arrangedSubviews: texts)
        textStack.axis = .vertical
        textStack.spacing = 2
        let info = UIStackView(arrangedSubviews: [art, textStack])
        info.spacing = 12
        info.alignment = .center
        let badge = BandSongRow.percentileDisplay(entry).map { UKBandSongPercentileBadge(label: $0) }
        let stack: UIStackView
        if twoRow {
            // The pill sits trailing under the song.
            var rows: [UIView] = [info]
            if let badge { rows.append(UIStackView(arrangedSubviews: [UIView(), badge])) }
            stack = UIStackView(arrangedSubviews: rows)
            stack.axis = .vertical
            stack.alignment = .fill
            stack.spacing = 6
        } else {
            stack = UIStackView(arrangedSubviews: [info] + (badge.map { [$0] } ?? []))
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12
        }
        stack.isUserInteractionEnabled = false
        ukPin(stack, insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        content = stack
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

/// The band song row's percentile pill (``SongMetadataFieldView`` `.percentile`): callout bold
/// "Top N%", gold with a gold outline for a top-5% placement (italic for the top 1%).
final class UKBandSongPercentileBadge: UIView {
    /// Creates the pill.
    ///
    /// - Parameter label: The "Top N%" text.
    init(label text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let tier = SuggestionSongRowView.tier(text)
        let highlighted = tier != .ordinary
        let label = UKLabel(text, style: .callout, weight: .bold, color: highlighted ? BrandUIColors.gold : BrandUIColors.textPrimary, lines: 0, alignment: .center)
        if tier == .topOne { label.font = UKFont.font(.callout, weight: .bold, italic: true) }
        backgroundColor = highlighted ? BrandUIColors.cardBackground : BrandUIColors.surfaceMuted
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.borderWidth = highlighted ? 2 : 0
        layer.borderColor = BrandUIColors.goldStroke.cgColor
        ukPin(label, insets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4))
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
