import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - FullRankingsScreen

/// `/leaderboards/all` — paginated global rankings for one instrument and metric
/// (`FortniteFestivalWeb/src/pages/leaderboards/FullRankingsPage.tsx`).
struct FullRankingsScreen: View {
    let session: FestivalSession
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true
    @State private var instrument: Instrument
    @State private var rankBy: RankingMetric
    @State private var page = 1
    @State private var state: RankLoadState<RankingsPayload> = .loading
    @State private var lastRequest: RequestKey?
    /// Ranked-account count and page count for the current instrument and metric,
    /// kept while another page loads so the pager and the ranked count don't
    /// flicker; cleared when the instrument or metric changes.
    @State private var board: BoardSummary?
    /// The selected player's own row on this instrument's board, independent of
    /// the current page — mirroring the web client's separate `playerRanking`
    /// query on `FullRankingsPage.tsx`.
    @State private var spotlightState: RankLoadState<PlayerInstrumentRankingPayload> = .loading
    /// The last loaded page's rows: keeps the pinned spotlight footer and the shared
    /// columns in place while the next page loads (Song Leaderboard, issue #93);
    /// cleared with ``board`` when the instrument or metric changes.
    @State private var shownEntries: [AccountRankingEntry]?
    /// The in-list title has scrolled under the bar: the bar shows the instrument icon
    /// and title instead (issue #294, like Song Leaderboard's pinned title).
    @State private var titleHidden = false
    /// Top edge of the pinned footer and pager in ``pageSpace``; nil without chrome.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade: the full 40 pt until the last row arrives
    /// above the chrome, then shrinking to nothing (Song Leaderboard, issue #293).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    /// The pinned footer jumped to the player's page, or the board was opened for their
    /// row: bring it into view once that page is shown (leaderboard-row R7, #318, #370).
    @State private var focusPending = false
    /// The rows' first-load fade window: a scroll rushes their stagger, rows the
    /// selected-row scroll realizes fade in with it, and once it closes recycled rows
    /// appear without a fade (load-transition R5, issue #323).
    @State private var fadeScope = FestivalFadeInScope()
    /// Counts the reload gate's reveals: each revealed page re-arms ``fadeScope`` (web
    /// `resetRush` on paginate).
    @State private var rowsReveal = 0
    /// Columns of rows: two on a full-width page in wide landscape, never on a split's
    /// sub-page (pattern `wide-columns`, issue #353).
    @State private var columns = 1
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    /// Coordinate space shared by the rows' fade mask and the pinned chrome.
    nonisolated private static let pageSpace = "fst.full-rankings.page"
    /// Space between two rows, and between the last row and the pinned chrome.
    nonisolated private static let rowGap: CGFloat = 6
    /// Rows per page (web `FullRankingsPage` `PAGE_SIZE`); a link that opens the board
    /// on the selected player's page counts pages with it.
    nonisolated static let pageSize = 25

    /// Identity of a pending selected-row reveal: re-runs when the request or the
    /// shown rows change.
    private struct FocusRequest: Equatable {
        let pending: Bool
        let rows: String?
    }

    private struct SpotlightKey: Equatable {
        let instrument: Instrument
        let accountId: String?
    }

    private var spotlightKey: SpotlightKey {
        SpotlightKey(instrument: instrument, accountId: session.selectedPlayer?.accountId)
    }

    /// Count facts that survive a page change.
    private struct BoardSummary: Equatable {
        let totalAccounts: Int
        let totalPages: Int
    }

    private struct RequestKey: Equatable {
        let instrument: Instrument
        let rankBy: RankingMetric
        let page: Int
    }

    private var requestKey: RequestKey {
        RequestKey(instrument: instrument, rankBy: rankBy, page: page)
    }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - instrument: Chart being ranked.
    ///   - rankBy: Ranking metric raw value (e.g. `adjusted`, `totalscore`).
    ///   - page: 1-based page to open on.
    ///   - focusSelected: Bring the selected player's row on that page into view once
    ///     it has appeared (web `navToPlayer`; a Compete preview's row, issue #370).
    init(
        session: FestivalSession, instrument: Instrument, rankBy: String,
        page: Int = 1, focusSelected: Bool = false
    ) {
        self.session = session
        _instrument = State(initialValue: instrument)
        _rankBy = State(initialValue: RankingMetric(rawValue: rankBy) ?? .totalscore)
        _page = State(initialValue: max(1, page))
        _focusPending = State(initialValue: focusSelected)
    }

    /// Mirror the tab root's Filter menu without depending on its own state; keep
    /// the currently displayed chart selectable even if it was just hidden.
    private var visibleInstruments: [Instrument] {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums),
            (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
            (.karaoke, showKaraoke), (.proCymbals, showProCymbals),
            (.proDrums, showProDrums),
        ]
        let shown = Set(preferences.compactMap { $0.1 ? $0.0 : nil })
        return Instrument.allCases.filter { shown.contains($0) || $0 == instrument }
    }

    /// The page title for a chart, e.g. "Lead Rankings": the navigation title (back
    /// menu, window title, VoiceOver) and the text beside the instrument icon.
    ///
    /// - Parameter instrument: Chart being ranked.
    /// - Returns: The localized-format title.
    static func title(for instrument: Instrument) -> String {
        "\(instrument.label) Rankings"
    }

    /// Whether the bar shows the pinned icon and title: once the in-list title has
    /// scrolled away, and while a new board has no in-list title yet (first load,
    /// instrument or metric switch, failure). A page change keeps the last decision so
    /// the bar doesn't flash the title while only the rows reload.
    private var showsPinnedTitle: Bool {
        switch state {
        case .loaded: titleHidden
        case .failed: true
        case .loading: titleHidden || board == nil
        }
    }

    var body: some View {
        // Read here, not only inside the reload gate's content or the mask's lazy
        // `GeometryReader`, so measuring the pinned chrome always rebuilds the mask:
        // otherwise the first page kept an opaque mask, and rows showed behind the
        // pager, until something else re-rendered the page (issues #294, #305).
        let chromeTop = bottomChromeTop
        // Instrument, metric and page changes fade the board out, show the spinner and
        // fade the new page in (web LoadGate, issue #71).
        FestivalReloadGate(
            key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading rankings",
            onReveal: { rowsReveal += 1 }
        ) {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Rankings unavailable") {
                    Task { await load() }
                }
            case let .loaded(payload):
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Self.rowGap) {
                        // The title and count fade in at once, like the web page header;
                        // the rows stagger beneath them.
                        InstrumentPageTitle(
                            instrument: instrument, title: Self.title(for: instrument), style: .header,
                            identifier: "fst.full-rankings.title"
                        )
                            .padding(.top, 8)
                            .festivalFadeInOnAppear()
                            .onGeometryChange(for: Bool.self) { proxy in
                                SongDetailPinnedTitlePolicy.isHeroHidden(
                                    titleMaxY: proxy.frame(in: .scrollView).maxY
                                )
                            } action: { hidden in
                                titleHidden = hidden
                            }
                        if let board {
                            RankingsCountHeader(
                                text: RankingsCountText.rankedPlayers(board.totalAccounts),
                                id: "fst.full-rankings.ranked-count"
                            )
                            .festivalFadeInOnAppear()
                        }
                        if payload.rankings.entries.isEmpty {
                            FestivalEmptyState(
                                "No ranked players yet", placement: .inline,
                                accessibilityIdentifier: "fst.full-rankings.empty"
                            )
                            .festivalFadeInOnAppear()
                        }
                        // Row-major pairs in wide landscape (wide-columns R2, #353).
                        ForEach(WideColumns.indexedRows(payload.rankings.entries, columns: columns)) { row in
                            WideColumnsRow(columns: columns, count: row.items.count) {
                                ForEach(row.indexed, id: \.item.id) { index, entry in
                                    AccountRankingRow(
                                        entry: entry, metric: rankBy,
                                        isSelected: isSelectedAccount(entry.accountId), cardSurface: true
                                    )
                                    .frame(maxWidth: .infinity)
                                    .macKeyboardRow(entry.id)
                                    // Web `PaginatedLeaderboard` row stagger; the page
                                    // scope decides whether it still fades (R5).
                                    .festivalFadeIn(staggerIndex: index)
                                }
                            }
                        }
                    }
                    .macKeyboardRows(AccountRankingRow.keyRows(payload.rankings.entries))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, Self.rowGap)
                }
                // One fade window per revealed page (web `resetRush` on paginate):
                // scrolling while the rows stagger in, or the selected-row scroll, fades
                // the rest in together (#323).
                .festivalScrollFadeInScope(fadeScope, resetKey: rowsReveal)
                // Rows fade out over up to 40 pt above the pinned footer and pager and
                // are not drawn beneath them, exactly like Song Leaderboard (issue #294;
                // web board `useScrollMask`, issues #93, #329). The fade shrinks away as the last row
                // arrives, so the list ends one row gap above the chrome with no
                // reserved margin (issue #293).
                .bottomChromeFade(
                    chromeTop: chromeTop, distance: $bottomFadeDistance, in: Self.pageSpace
                )
                // Jumped here from the pinned footer, or opened from a Compete preview's
                // row: scroll the player's row into view once the page is shown, as Song
                // Leaderboard does (R7, issues #318, #370).
                .task(id: FocusRequest(pending: focusPending, rows: rowsKey(payload))) {
                    guard focusPending else { return }
                    let entries = payload.rankings.entries
                    guard let targetIndex = entries.firstIndex(where: {
                        isSelectedAccount($0.accountId)
                    }) else {
                        focusPending = false
                        return
                    }
                    // After the row's own entrance (web `navToPlayer`, #323).
                    // A pair's identity is its first row's (wide-columns, #353).
                    if await SelectedRowReveal.reveal(
                        entries[WideColumns.rowStart(of: targetIndex, columns: columns)].id,
                        proxy: proxy, reduceMotion: reduceMotion,
                        staggerIndex: targetIndex, scope: fadeScope
                    ) {
                        focusPending = false
                    }
                }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wideColumnsCount($columns)
        // The shared Song Leaderboard pager and the player's footer, pinned outside the
        // reload gate so both stay put while only the rows fade (issue #294; a bottom
        // safe-area inset for the same tab-bar reason as `SoloLeaderboardScreen`).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        // `/duo` J2 (operator, 2026-10-02): a narrow board (folded Duo, a split column,
        // portrait iPhone) drops songs played/total on every row when it would truncate
        // a name, instead of cutting names to ~5 characters (the Compete cards' issue
        // #38 fit; rows are padded 16 pt per side).
        .leaderboardSectionColumns(
            pageColumns(shownEntries ?? []),
            hidingCrowdedSongsFor: pageNames(shownEntries ?? []),
            rowInset: 32, pageColumns: columns
        )
        .coordinateSpace(.named(Self.pageSpace))
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle(Self.title(for: instrument))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsPinnedTitle)
        // Mac: View › Rank By and View › Instrument mirror the toolbar menus.
        .macRankByCommands($rankBy)
        .macInstrumentCommands(visibleInstruments, selection: $instrument)
        .toolbar {
            #if os(iOS)
            // The iPhone Duo vertical bar minimizes its top bar on scroll, so a custom
            // title would leave when due; the system title stays there (R14).
            if !layout.sectionChrome.isVerticalBar {
                InstrumentPageTitleToolbarItem(
                    instrument: instrument, title: Self.title(for: instrument), isShown: showsPinnedTitle,
                    identifier: "fst.full-rankings.pinned-title"
                )
            }
            #endif
            // The instrument and Rank By are two titled items in one group, so the Duo
            // rail can place both (`/duo` J1; HIG Designing for iPhone Duo: "Give every
            // non-text-only item a title and symbol"), and every other bar shows them
            // side by side now that the pager no longer carries the instrument pill.
            // The iPhone tab-bar accessory takes both instead (issue #92).
            if layout.sectionChrome.isVerticalBar || pageTools == nil {
                ToolbarItemGroup(placement: .festivalPageAction) {
                    instrumentPicker
                    RankByMenu(selection: $rankBy)
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // iPhone tab-bar accessory (issue #92): Instrument, then Rank By.
        .festivalPageTool(
            token: InstrumentToolToken(selected: instrument, choices: visibleInstruments),
            order: PageToolOrder.primary
        ) {
            instrumentPicker
        }
        .festivalPageTool(token: rankBy, order: PageToolOrder.secondary) {
            RankByMenu(selection: $rankBy)
        }
        .onChange(of: instrument) { _, _ in
            resetBoard()
        }
        .onChange(of: rankBy) { _, _ in
            resetBoard()
        }
        .task(id: requestKey) { await load() }
        .task(id: spotlightKey) { await loadSpotlight() }
    }

    /// Start a new board on page 1 without the previous board's counts or rows.
    private func resetBoard() {
        page = 1
        focusPending = false
        board = nil
        shownEntries = nil
    }

    // MARK: Pinned bottom chrome

    /// The player's footer and the shared pager, floating over the page background
    /// with no band behind them, exactly as on Song Leaderboard. Built from the last
    /// loaded page, so paging keeps both in place while only the rows reload.
    private var bottomChrome: some View {
        let spacing = chromeSpacing
        return VStack(spacing: 0) {
            if let shownEntries {
                spotlightFooter(entries: shownEntries)
                    .padding(.top, spacing.footerTop)
                    .padding(.bottom, spacing.footerBottom)
            }
            if let board {
                RankingsPagerView(
                    page: page, totalPages: board.totalPages,
                    idPrefix: "fst.full-rankings", topPadding: spacing.pagerTop
                ) { destination in
                    page = destination
                }
            }
        }
        .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
    }

    /// Padding that rests the last row one row gap above the player's footer, or
    /// above the pager without a footer, and the footer one row gap above the pager,
    /// as on Song Leaderboard (issue #293).
    private var chromeSpacing: PinnedChromeSpacing {
        PinnedChromeSpacing.resolve(
            rowGap: Double(Self.rowGap), rowBottomInset: Double(Self.rowGap), edgePadding: 8,
            hasFooter: shownEntries.map { Self.showsFooter(spotlightPlacement(entries: $0)) } ?? false,
            hasPager: board != nil
        )
    }

    /// Whether a spotlight placement draws a row in the pinned footer.
    ///
    /// - Parameter placement: The selected player's placement, nil without one.
    /// - Returns: True for the pending, unranked and player footer rows.
    private static func showsFooter(_ placement: RankingSpotlightPlacement?) -> Bool {
        switch placement {
        case .pending, .unranked, .footer: return true
        case .some(.none), .inline, nil: return false
        }
    }

    // MARK: Selected-player spotlight

    /// Whether `accountId` is the currently selected player, matching case-insensitively.
    ///
    /// - Parameter accountId: Row's account id.
    /// - Returns: True only when a player is selected and it is this account.
    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    /// The selected player's pinned footer for the current page.
    ///
    /// - Parameter entries: Current page's loaded rows.
    /// - Returns: The spotlight placement, or nil without a selected player.
    private func spotlightPlacement(entries: [AccountRankingEntry]) -> RankingSpotlightPlacement? {
        guard let accountId = session.selectedPlayer?.accountId else { return nil }
        let source: RankingSpotlightSource = {
            switch spotlightState {
            case .loading: return .notLoaded
            case let .loaded(payload): return payload.ranking.map { .available($0.entry) } ?? .unranked
            case .failed: return .notLoaded
            }
        }()
        // Pinned on every page, the player's own page included (issue #318).
        return RankingSpotlight.pinnedFooter(
            selectedAccountId: accountId, visibleEntries: entries, source: source
        )
    }

    /// Identity of a loaded page's rows (page and first row), for the reveal task.
    ///
    /// - Parameter payload: The loaded page.
    /// - Returns: A key that changes when other rows are shown.
    private func rowsKey(_ payload: RankingsPayload) -> String {
        "\(page):\(payload.rankings.entries.first?.accountId ?? "")"
    }

    /// One rank and rating width for the page's rows and the pinned footer row (web
    /// `FullRankingsPage`'s shared `computeRankWidth`, operator batch 7.3, issue #37).
    ///
    /// - Parameter entries: Current page's loaded rows.
    /// - Returns: The page's fitted columns.
    private func pageColumns(_ entries: [AccountRankingEntry]) -> LeaderboardRowColumns {
        var rows = entries
        if case let .footer(entry) = spotlightPlacement(entries: entries) {
            rows.append(entry)
        }
        return .rankings(rows, metric: rankBy)
    }

    /// Every name the page draws (the pinned footer row included) for the songs fit.
    ///
    /// - Parameter entries: Current page's loaded rows.
    /// - Returns: The rows' names, bold for the selected player's.
    private func pageNames(_ entries: [AccountRankingEntry]) -> [RankingRowName] {
        var rows = entries
        if case let .footer(entry) = spotlightPlacement(entries: entries) {
            rows.append(entry)
        }
        return rows.map {
            RankingRowName(name: AccountRankingRow.displayName($0), emphasized: isSelectedAccount($0.accountId))
        }
    }

    /// The selected player's own row, pinned above the pager on every page, including
    /// the page whose rows already show it, as on Song Leaderboard (web
    /// `FullRankingsPage`'s player footer; leaderboard-row R5, issue #318).
    ///
    /// The row is drawn like the page's rows (same row component, highlight and
    /// columns). Tapping it follows the shared selected-row rule (R7,
    /// ``SelectedRowAction``): off this page it jumps to the player's page and brings
    /// their row into view; on it, it opens Statistics (web `getPlayerProfileRoute`).
    ///
    /// - Parameter entries: Last loaded page's rows.
    @ViewBuilder
    private func spotlightFooter(entries: [AccountRankingEntry]) -> some View {
        if let placement = spotlightPlacement(entries: entries) {
            switch placement {
            case .none, .inline:
                EmptyView()
            case .pending:
                if case let .failed(issue) = spotlightState {
                    ServiceStatusInline(issue, scope: "full-rankings.spotlight") {
                        Task { await loadSpotlight() }
                    }
                    .padding(12)
                    .festivalCard(cornerRadius: 12)
                    .padding(.horizontal, 16)
                } else {
                    // The footer row's height, so it does not jump when the rank arrives.
                    RankingSpotlightLoadingRow()
                        .frame(maxWidth: .infinity, minHeight: LeaderboardRowMetrics.minHeight)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("fst.full-rankings.spotlight-footer.loading")
                }
            case .unranked:
                RankingSpotlightUnrankedRow(message: "You're not yet ranked on \(instrument.label).")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .festivalCardCapsule()
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("fst.full-rankings.spotlight-footer.unranked")
            case let .footer(entry):
                selectedRowFooter(entry)
            }
        }
    }

    /// The pinned row as a button or link chosen by ``SelectedRowAction``.
    ///
    /// - Parameter entry: The selected player's row on this board.
    private func selectedRowFooter(_ entry: AccountRankingEntry) -> some View {
        let rank = entry.rank(for: rankBy)
        // While the next page loads, its rank decides, so the footer keeps its
        // place and action (issue #93).
        let loadedRows: [String]? = if case let .loaded(payload) = state {
            payload.rankings.entries.map(\.accountId)
        } else {
            nil
        }
        let isVisible = LeaderboardPaging.isSelectedOnPage(
            accountId: entry.accountId, rank: rank, page: page, pageSize: Self.pageSize, entries: loadedRows
        )
        let action = SelectedRowAction.footer(rank: rank, isVisible: isVisible, pageSize: Self.pageSize)
        let row = AccountRankingRow(
            entry: entry, metric: rankBy, isSelected: true, cardSurface: true, opensProfile: false
        )
        .modifier(PinnedFooterBacking())
        .contentShape(Rectangle())
        return Group {
            switch action {
            case .openProfile:
                NavigationLink(value: AppRoute.statistics) { row }
                    .accessibilityLabel(action.footerLabel(for: .player, rank: rank))
                    .accessibilityIdentifier("fst.full-rankings.spotlight-open")
            case let .jump(destination):
                Button {
                    focusPending = true
                    page = destination
                } label: {
                    row
                }
                .accessibilityLabel(action.footerLabel(for: .player, rank: rank))
                .accessibilityIdentifier("fst.full-rankings.spotlight-jump")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.full-rankings.spotlight-footer")
    }

    /// Read the selected player's own row on this instrument's board.
    private func loadSpotlight() async {
        guard let accountId = session.selectedPlayer?.accountId else { return }
        spotlightState = .loading
        do {
            let payload = try await session.playerInstrumentRanking(
                instrument: instrument, accountId: accountId
            )
            spotlightState = .loaded(payload)
        } catch {
            spotlightState = .failed(ServiceIssue(error))
        }
    }

    /// The instrument switcher: a system toolbar `Menu` (system hit target, overflow
    /// title and Duo rail placement) whose `Label` carries the artwork redrawn as a
    /// menu-sized image; in the iPhone tab-bar accessory it lists the same charts in
    /// a sheet (``PageToolMenu``, issue #92). Keeps `fst.full-rankings.instrument-menu`.
    private var instrumentPicker: some View {
        PageToolMenu("Instrument", choices: instrumentMenuChoices) {
            instrumentChoices
        } label: {
            Label {
                Text(instrument.label)
            } icon: {
                InstrumentIcon.menuImage(for: instrument, keyboard: false)
            }
        }
        .accessibilityIdentifier("fst.full-rankings.instrument-menu")
        .festivalBarItemAccessibility(label: "Instrument", value: instrument.label)
    }

    /// The visible charts as a picker, shared by the rail item and the pill.
    private var instrumentChoices: some View {
        Picker("Instrument", selection: $instrument) {
            ForEach(visibleInstruments) { chart in
                Label {
                    Text(chart.label)
                } icon: {
                    InstrumentIcon(chart, size: 16)
                }
                .tag(chart)
            }
        }
    }

    /// The visible charts for the inline-accessory sheet (``PageToolMenu``).
    private func instrumentMenuChoices() -> [PageToolMenuChoice] {
        visibleInstruments.map { chart in
            PageToolMenuChoice(
                id: "fst.full-rankings.instrument.\(chart.rawValue)",
                label: AnyView(Label {
                    Text(chart.label)
                } icon: {
                    InstrumentIcon(chart, size: 16)
                }),
                isSelected: chart == instrument,
                action: { instrument = chart }
            )
        }
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.rankings(
                instrument: requested.instrument, rankBy: requested.rankBy,
                page: requested.page, pageSize: Self.pageSize
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = min(max(1, requested.page), max(1, payload.rankings.pageCount))
            if corrected != requested.page {
                page = corrected
                return
            }
            board = BoardSummary(
                totalAccounts: payload.rankings.totalAccounts,
                totalPages: payload.rankings.pageCount
            )
            shownEntries = payload.rankings.entries
            state = .loaded(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard requested == requestKey else { return }
            state = .failed(ServiceIssue(error))
        }
    }
}

/// Everything the accessory's instrument tool displays: re-registers it when the
/// selection or the Settings-visible charts change (issue #92).
private struct InstrumentToolToken: Hashable {
    let selected: Instrument
    let choices: [Instrument]
}
