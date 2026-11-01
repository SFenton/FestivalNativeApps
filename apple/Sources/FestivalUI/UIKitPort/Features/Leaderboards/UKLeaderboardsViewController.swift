#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Tappable row

/// A card row that opens something: its content view is the one VoiceOver element, the
/// control is the touch target. The selected player's row gets the flat purple band.
final class UKCardRowControl: UIControl {
    private let band = UIView()
    /// Called when tapped.
    var onTap: (() -> Void)?

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - content: The row content.
    ///   - selectedBand: Fill with the player's purple.
    ///   - onTap: The row's action; nil makes it read-only.
    init(content: UIView, selectedBand: Bool, onTap: (() -> Void)?) {
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        band.backgroundColor = UKLeaderboardMetrics.playerFill
        band.isHidden = !selectedBand
        band.isUserInteractionEnabled = false
        content.isUserInteractionEnabled = false
        for view in [band, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        isUserInteractionEnabled = onTap != nil
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .primaryActionTriggered)
        accessibilityElements = [content]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}

// MARK: - Leaderboards

/// `/leaderboards` (ports ``LeaderboardsScreen``): top-ten cards per Settings-visible
/// instrument, then every band size, each a group card of ranking rows with the selected
/// player's own row below the top ten and a "View all rankings" button ending the card; a
/// shared Rank By page tool and Quick Links. The page shows a spinner until every card's
/// read settles, then the cards fade in.
@MainActor
final class UKLeaderboardsViewController: UIViewController, UKPageToolsProviding {
    private let context: UKContext
    private var session: FestivalSession { context.session }
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private lazy var gate = UKReloadGate(
        key: "", isLoading: true, spinnerLabel: "Loading Leaderboards", spinnerIdentifier: "fst.leaderboards.loading"
    )
    private lazy var background = UKBackgroundRegistration(session: session, mode: .carousel)
    private let quickLinks: UKQuickLinks
    private var instrumentStates: [Instrument: RankLoadState<RankingsPayload>] = [:]
    private var bandStates: [BandType: RankLoadState<BandRankingsPayload>] = [:]
    private var spotlightStates: [Instrument: RankLoadState<PlayerInstrumentRankingPayload>] = [:]
    private var loadedKey: String?
    private var settledKey: String?
    private var loadTask: Task<Void, Never>?
    private var cards: [String: UIView] = [:]
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var lastSelectedID: String??
    private var lastLayoutKey = ""
    private var lastGateKey: String?

    /// Narrowest card the two-column grid may draw at the default text size.
    private static let minimumCardWidth = LeaderboardsScreen.minimumCardWidth

    /// Creates the screen.
    ///
    /// - Parameter context: The screen's context.
    init(context: UKContext) {
        self.context = context
        quickLinks = UKQuickLinks(
            controller: QuickLinksController(), title: "Leaderboards Quick Links", sections: []
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: Derived

    private var experimental: Bool { UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue) }
    private var rankBy: RankingMetric {
        RankingMetric.coerced(UserDefaults.standard.string(forKey: "fst.leaderboards.rankBy") ?? RankingMetric.totalscore.rawValue, experimentalRanks: experimental)
    }
    private var visibleInstruments: [Instrument] {
        let shown = UKSettings.visibleInstruments()
        return Instrument.allCases.filter(shown.contains)
    }
    private var reloadKey: String {
        "\(rankBy.rawValue)|\(visibleInstruments.map(\.rawValue).joined(separator: ","))|\(session.selectedPlayer?.accountId ?? "")"
    }
    private var quickLinkSections: [QuickLinkSection] {
        visibleInstruments.map { LeaderboardsScreen.quickLink(for: $0) } + BandType.allCases.map { LeaderboardsScreen.quickLink(for: $0) }
    }

    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        ukSetPageTitle("Leaderboards")
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.delegate = self
        scroll.backgroundColor = .clear
        content.axis = .vertical
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        scroll.addSubview(content)
        gate.contentView.addSubview(scroll)
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gate)
        NSLayoutConstraint.activate([
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor), gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gate.topAnchor.constraint(equalTo: view.topAnchor), gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: gate.contentView.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: gate.contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: gate.contentView.topAnchor), scroll.bottomAnchor.constraint(equalTo: gate.contentView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task { @MainActor in
                await self?.loadAll()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        scroll.refreshControl = refresh
        quickLinks.attach(to: scroll, rect: { [weak self] id in
            guard let self, let card = cards[id], card.window != nil else { return nil }
            return card.convert(card.bounds, to: scroll)
        }, element: { [weak self] id in self?.cards[id] })
        quickLinks.onToolChange = { [weak self] in self?.ukPageToolsDidChange() }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyMayHaveChanged() }
        }
        observations.observe { [weak self] in
            guard let self else { return }
            let id = session.selectedPlayer?.accountId
            guard lastSelectedID != .some(id) else { return }
            let first = lastSelectedID == nil
            lastSelectedID = .some(id)
            if !first { keyMayHaveChanged() }
        }
        quickLinks.controller.configure(title: "Leaderboards Quick Links", explicit: quickLinkSections)
        keyMayHaveChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.viewWillAppear()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        quickLinks.didAppear()
        UKRefreshCommands.shared.register(self) { [weak self] in await self?.loadAll() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
        quickLinks.willDisappear()
        UKRefreshCommands.shared.unregister(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let key = "\(Int(scroll.bounds.width))|\(traitCollection.preferredContentSizeCategory.rawValue)"
        if key != lastLayoutKey {
            lastLayoutKey = key
            renderCards()
        }
        quickLinks.scrollViewDidScroll()
    }

    // MARK: Tools

    var ukPageTools: [UKPageTool] {
        var tools: [UKPageTool] = []
        if experimental {
            let item = UKBoardMenus.rankByItem(selection: rankBy, experimental: experimental) { metric in
                UserDefaults.standard.set(metric.rawValue, forKey: "fst.leaderboards.rankBy")
            }
            tools.append(UKPageTool(order: PageToolOrder.primary, item: item))
        }
        if let quick = quickLinks.tool { tools.append(quick) }
        return tools
    }

    // MARK: Loading

    private func keyMayHaveChanged() {
        quickLinks.controller.configure(title: "Leaderboards Quick Links", explicit: quickLinkSections)
        ukPageToolsDidChange()
        let key = reloadKey
        guard key != lastGateKey else { return }
        lastGateKey = key
        gate.update(key: key, isLoading: settledKey != key)
        if loadedKey == key {
            settledKey = key
            gate.update(key: key, isLoading: false)
            renderCards()
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await loadAll()
            guard !Task.isCancelled, key == reloadKey else { return }
            settledKey = key
            if allCardsLoaded { loadedKey = key }
            gate.update(key: key, isLoading: false)
        }
    }

    private var allCardsLoaded: Bool {
        func loaded<P>(_ state: RankLoadState<P>?) -> Bool {
            if case .loaded? = state { return true }
            return false
        }
        return visibleInstruments.allSatisfy { loaded(instrumentStates[$0]) } && BandType.allCases.allSatisfy { loaded(bandStates[$0]) }
    }

    private func loadAll() async {
        let result = await LeaderboardsPreloader.load(
            session: session, instruments: visibleInstruments, rankBy: rankBy, bandMetric: rankBy.bandMetric
        )
        guard !Task.isCancelled else { return }
        instrumentStates = result.instruments
        bandStates = result.bands
        spotlightStates = result.spotlights
        renderCards()
    }

    private func loadInstrument(_ instrument: Instrument) async {
        instrumentStates[instrument] = .loading
        renderCards()
        do {
            let payload = try await session.rankings(instrument: instrument, rankBy: rankBy, page: 1, pageSize: 10)
            instrumentStates[instrument] = .loaded(payload)
            if let selected = session.selectedPlayer?.accountId,
               !payload.rankings.entries.contains(where: { $0.accountId.caseInsensitiveCompare(selected) == .orderedSame }) {
                await loadSpotlight(instrument)
            } else {
                spotlightStates[instrument] = nil
            }
        } catch {
            instrumentStates[instrument] = .failed(ServiceIssue(error))
        }
        renderCards()
    }

    private func loadSpotlight(_ instrument: Instrument) async {
        guard let accountId = session.selectedPlayer?.accountId else {
            spotlightStates[instrument] = nil
            return
        }
        spotlightStates[instrument] = .loading
        do {
            spotlightStates[instrument] = .loaded(try await session.playerInstrumentRanking(instrument: instrument, accountId: accountId))
        } catch {
            spotlightStates[instrument] = .failed(ServiceIssue(error))
        }
    }

    private func loadBand(_ bandType: BandType) async {
        bandStates[bandType] = .loading
        renderCards()
        do {
            bandStates[bandType] = .loaded(try await session.bandRankings(bandType: bandType, rankBy: rankBy.bandMetric, page: 1, pageSize: 10))
        } catch {
            bandStates[bandType] = .failed(ServiceIssue(error))
        }
        renderCards()
    }

    // MARK: Cards

    private var columnsCount: Int {
        LeaderboardsScreen.usesTwoColumns(
            widthClass: ukLayout.widthClass, contentWidth: scroll.bounds.width,
            minimumCardWidth: UKFont.scaled(Self.minimumCardWidth, relativeTo: .body, traits: traitCollection)
        ) ? 2 : 1
    }

    private func renderCards() {
        guard isViewLoaded, scroll.bounds.width > 0 else { return }
        let columns = columnsCount
        let cardWidth = columns == 2
            ? (scroll.bounds.width - 2 * LeaderboardsScreen.pagePadding - LeaderboardsScreen.cardSpacing) / 2
            : scroll.bounds.width - 2 * LeaderboardsScreen.pagePadding
        cards.removeAll()
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        var built: [UIView] = []
        for instrument in visibleInstruments { built.append(instrumentCard(instrument, width: cardWidth)) }
        for bandType in BandType.allCases { built.append(bandCard(bandType, width: cardWidth)) }
        if columns == 2 {
            for start in stride(from: 0, to: built.count, by: 2) {
                let pair = Array(built[start..<min(start + 2, built.count)])
                let row = UIStackView(arrangedSubviews: pair + (pair.count == 1 ? [UIView()] : []))
                row.axis = .horizontal
                row.spacing = LeaderboardsScreen.cardSpacing
                row.alignment = .top
                row.distribution = .fillEqually
                content.addArrangedSubview(row)
            }
        } else {
            built.forEach(content.addArrangedSubview)
        }
        quickLinks.scrollViewDidScroll()
    }

    private func cardHeader(_ title: String, instrument: Instrument?) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        if let instrument { stack.addArrangedSubview(UKInstrumentIconView(instrument, size: UKFont.scaled(36, relativeTo: .title3), hidesFromAccessibility: true)) }
        let label = UKLabel(title, style: .title3, weight: .bold).asHeader()
        label.isAccessibilityElement = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(UIView())
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return ukPadded(stack, UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0))
    }

    private func skeleton() -> [UIView] {
        (0..<5).map { _ in
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.alignment = .center
            for width: CGFloat in [28, 120] {
                let capsule = UIView()
                capsule.backgroundColor = BrandUIColors.surfaceMuted
                capsule.layer.cornerRadius = 7
                capsule.translatesAutoresizingMaskIntoConstraints = false
                capsule.widthAnchor.constraint(equalToConstant: width).isActive = true
                capsule.heightAnchor.constraint(equalToConstant: 14).isActive = true
                row.addArrangedSubview(capsule)
            }
            row.addArrangedSubview(UIView())
            let last = UIView()
            last.backgroundColor = BrandUIColors.surfaceMuted
            last.layer.cornerRadius = 7
            last.translatesAutoresizingMaskIntoConstraints = false
            last.widthAnchor.constraint(equalToConstant: 56).isActive = true
            last.heightAnchor.constraint(equalToConstant: 14).isActive = true
            row.addArrangedSubview(last)
            let holder = ukPadded(row, UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardMetrics.minHeight).isActive = true
            holder.isAccessibilityElement = false
            holder.accessibilityElementsHidden = true
            return holder
        }
    }

    private func finishCard(
        id: String, containerIdentifier: String, header: UIView, section: UKGroupSectionView
    ) -> UIView {
        let stack = UIStackView(arrangedSubviews: [header, section])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isAccessibilityElement = false
        stack.accessibilityContainerType = .semanticGroup
        stack.accessibilityIdentifier = containerIdentifier
        cards[id] = stack
        return stack
    }

    private func instrumentCard(_ instrument: Instrument, width: CGFloat) -> UIView {
        let state = instrumentStates[instrument] ?? .loading
        let section = UKGroupSectionView(nil, rows: .flush(separatorInset: UKLeaderboardMetrics.horizontalPadding))
        var rows: [UIView] = []
        var action: UIView?
        let metric = rankBy
        switch state {
        case .loading:
            rows = skeleton()
        case let .failed(issue):
            let inline = UKServiceStatusInlineView(issue, scope: "leaderboards.\(instrument.rawValue)") { [weak self] in
                Task { await self?.loadInstrument(instrument) }
            }
            rows = [ukPadded(inline, UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))]
        case let .loaded(payload):
            let entries = payload.rankings.entries
            let placement = spotlightPlacement(instrument: instrument, entries: entries)
            var footerEntry: AccountRankingEntry?
            if case let .footer(entry)? = placement { footerEntry = entry }
            let fitRows = entries + [footerEntry].compactMap { $0 }
            let columns = UKRankingRowModels.fittingSongs(
                fitRows.isEmpty ? nil : LeaderboardRowColumns.rankings(fitRows, metric: metric),
                names: fitRows.map { RankingRowName(name: AccountRankingRow.displayName($0), emphasized: isSelectedAccount($0.accountId)) },
                sectionWidth: width, rowInset: 0, pageColumns: 1, traits: traitCollection
            )
            if entries.isEmpty {
                rows = [ukCardMessage("No ranked \(instrument.label) players yet.")]
            } else {
                for entry in entries {
                    let selected = isSelectedAccount(entry.accountId)
                    let row = UKRankingRowView()
                    row.apply(UKRankingRowModels.account(entry: entry, metric: metric, isSelected: selected, columns: columns))
                    let route = AccountRankingRow.route(entry)
                    rows.append(UKCardRowControl(content: row, selectedBand: selected, onTap: entry.hasAccount ? { [weak self] in
                        self?.context.navigator?.selectDetail(route)
                    } : nil))
                }
                rows += spotlightRows(instrument: instrument, placement: placement, columns: columns)
                let route = AppRoute.fullRankings(instrument: instrument, rankBy: metric.rawValue)
                let button = UKBoardPurpleActionButton(
                    title: RankingsCountText.viewAllRankings(totalAccounts: payload.rankings.totalAccounts), card: instrument.label,
                    identifier: "fst.leaderboards.card.\(instrument.rawValue).view-all"
                )
                button.onTap = { [weak self] in self?.context.navigator?.selectDetail(route) }
                action = button
            }
        }
        section.setRows(rows)
        section.setAction(action)
        let quick = LeaderboardsScreen.quickLink(for: instrument)
        return finishCard(
            id: quick.id, containerIdentifier: "fst.leaderboards.card.\(instrument.rawValue)",
            header: cardHeader(instrument.label, instrument: instrument), section: section
        )
    }

    private func spotlightPlacement(instrument: Instrument, entries: [AccountRankingEntry]) -> RankingSpotlightPlacement? {
        guard let accountId = session.selectedPlayer?.accountId else { return nil }
        let source: RankingSpotlightSource = {
            switch spotlightStates[instrument] {
            case .none, .loading: return .notLoaded
            case let .loaded(payload): return payload.ranking.map { .available($0.entry) } ?? .unranked
            case .failed: return .notLoaded
            }
        }()
        return RankingSpotlight.placement(selectedAccountId: accountId, visibleEntries: entries, source: source)
    }

    private func spotlightRows(instrument: Instrument, placement: RankingSpotlightPlacement?, columns: LeaderboardRowColumns?) -> [UIView] {
        guard let placement else { return [] }
        switch placement {
        case .none, .inline:
            return []
        case .pending:
            if case let .failed(issue)? = spotlightStates[instrument] {
                let inline = UKServiceStatusInlineView(issue, scope: "leaderboards.spotlight.\(instrument.rawValue)") { [weak self] in
                    Task {
                        await self?.loadSpotlight(instrument)
                        self?.renderCards()
                    }
                }
                return [ukPadded(inline, UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))]
            }
            return [ukSpotlightLoadingRow(identifier: "fst.leaderboards.card.\(instrument.rawValue).spotlight.loading")]
        case .unranked:
            return [ukCardMessage("Not yet ranked on \(instrument.label).", identifier: "fst.leaderboards.card.\(instrument.rawValue).spotlight.unranked")]
        case let .footer(entry):
            var model = UKRankingRowModels.account(entry: entry, metric: rankBy, isSelected: true, columns: columns)
            model.identifier = "fst.leaderboards.card.\(instrument.rawValue).spotlight"
            let row = UKRankingRowView()
            row.apply(model)
            let route = AccountRankingRow.route(entry)
            return [UKCardRowControl(content: row, selectedBand: true, onTap: entry.hasAccount ? { [weak self] in
                self?.context.navigator?.selectDetail(route)
            } : nil)]
        }
    }

    private func bandCard(_ bandType: BandType, width: CGFloat) -> UIView {
        let metric = rankBy.bandMetric
        let state = bandStates[bandType] ?? .loading
        let section = UKGroupSectionView(nil, rows: .flush(separatorInset: UKLeaderboardMetrics.horizontalPadding))
        var rows: [UIView] = []
        var action: UIView?
        switch state {
        case .loading:
            rows = skeleton()
        case let .failed(issue):
            let inline = UKServiceStatusInlineView(issue, scope: "leaderboards.\(bandType.rawValue)") { [weak self] in
                Task { await self?.loadBand(bandType) }
            }
            rows = [ukPadded(inline, UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))]
        case let .loaded(payload):
            let entries = payload.rankings.entries
            if entries.isEmpty {
                rows = [ukCardMessage("No ranked \(bandType.label.lowercased()) yet.")]
            } else {
                let columns = UKRankingRowModels.fittingSongs(
                    LeaderboardRowColumns.bandRankings(entries, metric: metric),
                    names: entries.map { RankingRowName(name: $0.membersLabel) },
                    sectionWidth: width, rowInset: 0, pageColumns: 1, traits: traitCollection
                )
                for entry in entries {
                    let row = UKRankingRowView()
                    row.apply(UKRankingRowModels.band(entry: entry, metric: metric, columns: columns))
                    let route = BandRankingRow.route(entry, bandType: bandType)
                    rows.append(UKCardRowControl(content: row, selectedBand: false) { [weak self] in
                        self?.context.navigator?.selectDetail(route)
                    })
                }
                let button = UKBoardPurpleActionButton(
                    title: RankingsCountText.viewAllBandRankings(totalTeams: payload.rankings.totalTeams), card: bandType.label,
                    identifier: "fst.leaderboards.band-card.\(bandType.rawValue).view-all"
                )
                button.onTap = { [weak self] in self?.context.navigator?.selectDetail(.bandRankings(bandType: bandType.rawValue)) }
                action = button
            }
        }
        section.setRows(rows)
        section.setAction(action)
        return finishCard(
            id: LeaderboardsScreen.quickLink(for: bandType).id, containerIdentifier: "fst.leaderboards.band-card.\(bandType.rawValue)",
            header: cardHeader(bandType.label, instrument: nil), section: section
        )
    }
}

extension UKLeaderboardsViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) { quickLinks.scrollViewDidScroll() }
}
#endif
