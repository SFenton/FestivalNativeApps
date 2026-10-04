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
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Coordinate space shared by the rows' fade mask and the pinned chrome.
    nonisolated private static let pageSpace = "fst.full-rankings.page"

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
    init(session: FestivalSession, instrument: Instrument, rankBy: String) {
        self.session = session
        _instrument = State(initialValue: instrument)
        _rankBy = State(initialValue: RankingMetric(rawValue: rankBy) ?? .totalscore)
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
        // Read here, not only inside the mask's lazy `GeometryReader`, so measuring the
        // pinned chrome always rebuilds the mask: otherwise the first page kept an
        // opaque mask, and rows showed behind the pager, until something else
        // re-rendered the page (issue #294).
        let chromeTop = bottomChromeTop
        // Instrument, metric and page changes fade the board out, show the spinner and
        // fade the new page in (web LoadGate, issue #71).
        FestivalReloadGate(key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading rankings") {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Rankings unavailable") {
                    Task { await load() }
                }
            case let .loaded(payload):
                ScrollView {
                    LazyVStack(spacing: 6) {
                        RankingsPageTitle(instrument: instrument, title: Self.title(for: instrument), style: .header)
                            .padding(.top, 8)
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
                        }
                        if payload.rankings.entries.isEmpty {
                            Text("No ranked players yet.")
                                .foregroundStyle(FestivalText.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(payload.rankings.entries) { entry in
                            AccountRankingRow(
                                entry: entry, metric: rankBy,
                                isSelected: isSelectedAccount(entry.accountId), glassSurface: true
                            )
                            .macKeyboardRow(entry.id)
                        }
                    }
                    .macKeyboardRows(AccountRankingRow.keyRows(payload.rankings.entries))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    // Each loaded page fades in once (web load-in), not per row on scroll.
                    .festivalFadeInOnAppear()
                }
                // The last row comes to rest above the fade, not inside it.
                .contentMargins(.bottom, ScrollEdgeFade.distance, for: .scrollContent)
                // Rows fade out over 36 pt above the pinned footer and pager and are not
                // drawn beneath them, exactly like Song Leaderboard (issue #294; web
                // `useScrollFade`, issue #93).
                .mask { bottomChromeFadeMask(chromeTop: chromeTop) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            rowInset: 32
        )
        .coordinateSpace(.named(Self.pageSpace))
        .festivalBackground(.carousel, session: session)
        .navigationTitle(Self.title(for: instrument))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsPinnedTitle)
        // Mac: View › Rank By and View › Instrument mirror the toolbar menus.
        .macRankByCommands($rankBy)
        .macInstrumentCommands(visibleInstruments, selection: $instrument)
        .toolbar {
            #if os(iOS)
            // The rail of the iPhone Duo vertical bar never draws a custom title view
            // (Song Detail, `/duo` D4), so the in-list title stays the only one there.
            if !layout.sectionChrome.isVerticalBar {
                ToolbarItem(placement: .principal) {
                    pinnedTitle
                }
            }
            #endif
            // The instrument and Rank By are two titled items in one group, so the Duo
            // rail can place both (`/duo` J1; HIG Designing for iPhone Duo: "Give every
            // non-text-only item a title and symbol"), and every other bar shows them
            // side by side now that the pager no longer carries the instrument pill.
            ToolbarItemGroup(placement: .festivalPageAction) {
                instrumentPicker
                RankByMenu(selection: $rankBy)
            }
            #if os(iOS)
            if let board {
                RankingsPagerToolbarContent(
                    page: page, totalPages: board.totalPages,
                    idPrefix: "fst.full-rankings"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        board = nil
        shownEntries = nil
    }

    // MARK: Title

    /// The bar's icon and title once the in-list title has scrolled away.
    ///
    /// Built only while shown: a hidden (opacity 0) copy was still audited, and its
    /// icon failed Dynamic Type on Song Leaderboard. Until then an empty, unspoken
    /// placeholder holds the slot, so the bar does not fall back to `navigationTitle`
    /// above the in-list title (issue #93).
    @ViewBuilder
    private var pinnedTitle: some View {
        if showsPinnedTitle {
            RankingsPageTitle(instrument: instrument, title: Self.title(for: instrument), style: .pinned)
                .frame(maxWidth: 260)
                .transition(.opacity)
        } else {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }

    // MARK: Pinned bottom chrome

    /// The player's footer and the shared pager, floating over the page background
    /// with no band behind them, exactly as on Song Leaderboard. Built from the last
    /// loaded page, so paging keeps both in place while only the rows reload.
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            if let shownEntries {
                spotlightFooter(entries: shownEntries)
            }
            if let board {
                RankingsPagerView(
                    page: page, totalPages: board.totalPages,
                    idPrefix: "fst.full-rankings"
                ) { destination in
                    page = destination
                }
            }
        }
        .onGeometryChange(for: CGFloat?.self) { proxy in
            proxy.size.height > 0 ? proxy.frame(in: .named(Self.pageSpace)).minY : nil
        } action: { top in
            bottomChromeTop = top
        }
    }

    /// Alpha mask for the rows: opaque, then a 36 pt fade ending at the pinned
    /// chrome's top edge, clear beneath it. Extends into the top safe area so rows
    /// still scroll under the navigation bar.
    ///
    /// - Parameter chromeTop: The chrome's measured top in ``pageSpace``; nil draws
    ///   every row.
    /// - Returns: The mask view.
    private func bottomChromeFadeMask(chromeTop: CGFloat?) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(Self.pageSpace))
            let stops = ScrollEdgeFade.bottom(
                height: Double(frame.height),
                obscured: chromeTop.map { Double(frame.maxY - $0) } ?? 0
            )
            if chromeTop == nil {
                Color.black
            } else {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: stops.fadeStart),
                        .init(color: .clear, location: stops.fadeEnd),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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

    /// Where the selected player's own row goes for the current page.
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
        return RankingSpotlight.placement(
            selectedAccountId: accountId, visibleEntries: entries, source: source
        )
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

    /// Show the selected player's own row below the current page when they are not
    /// visible on it, with a jump control that moves straight to their page — a
    /// native addition beyond the web client, whose equivalent footer
    /// (`FullRankingsPage.tsx:531-552`) only links to the player's profile, since a
    /// paginated native `List` can usefully re-page itself instead.
    ///
    /// - Parameter entries: Current page's loaded rows.
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
                    .festivalGlass(.card, cornerRadius: 12)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else {
                    // The footer row's height, so it does not jump when the rank arrives.
                    RankingSpotlightLoadingRow()
                        .frame(maxWidth: .infinity, minHeight: LeaderboardRowMetrics.minHeight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("fst.full-rankings.spotlight-footer.loading")
                }
            case .unranked:
                RankingSpotlightUnrankedRow(message: "You're not yet ranked on \(instrument.label).")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .festivalGlassCapsule(.card)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("fst.full-rankings.spotlight-footer.unranked")
            case let .footer(entry):
                HStack(spacing: 8) {
                    AccountRankingRow(entry: entry, metric: rankBy, isSelected: true, glassSurface: true)
                    Button {
                        page = LeaderboardPaging.page(forRank: entry.rank(for: rankBy), pageSize: 25)
                    } label: {
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(.title3)
                            .foregroundStyle(BrandTokens.accentPurple)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to your page")
                    .accessibilityIdentifier("fst.full-rankings.spotlight-jump")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fst.full-rankings.spotlight-footer")
            }
        }
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
    /// menu-sized image. Keeps `fst.full-rankings.instrument-menu`.
    private var instrumentPicker: some View {
        Menu {
            instrumentChoices
        } label: {
            Label {
                Text(instrument.label)
            } icon: {
                InstrumentIcon.menuImage(for: instrument, keyboard: false)
            }
        }
        .accessibilityIdentifier("fst.full-rankings.instrument-menu")
        .accessibilityLabel("Instrument")
        .accessibilityValue(instrument.label)
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

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.rankings(
                instrument: requested.instrument, rankBy: requested.rankBy,
                page: requested.page, pageSize: 25
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

// MARK: - Page title

/// A rankings page title with the instrument artwork to its left (issue #294): the
/// large heading at the top of the list, and the compact copy the bar shows once that
/// heading has scrolled under it.
///
/// The artwork is decorative (the title already names the instrument), so it is hidden
/// from VoiceOver, and it scales with the title's text style so it keeps matching the
/// text at every Dynamic Type size (HIG Icons: "Match icon weight to adjacent text").
/// The artwork's visible disc fills about 84% of its square, so a square slightly
/// taller than the font's point size reads as the same height as the capitals.
struct RankingsPageTitle: View {
    /// Where the title is drawn.
    enum Style {
        /// The page's large heading, first in the scrolling content.
        case header
        /// The navigation bar's principal title after the heading scrolls away.
        case pinned
    }

    let instrument: Instrument
    let title: String
    let style: Style
    @ScaledMetric(relativeTo: .largeTitle) private var headerIconSide: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var pinnedIconSide: CGFloat = 24

    var body: some View {
        HStack(spacing: style == .header ? 10 : 6) {
            InstrumentIcon(instrument, size: style == .header ? headerIconSide : pinnedIconSide)
                .fixedSize()
                .accessibilityHidden(true)
            switch style {
            case .header:
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .pinned:
                MarqueeText(title)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(style == .header ? "fst.full-rankings.title" : "fst.full-rankings.pinned-title")
    }
}
