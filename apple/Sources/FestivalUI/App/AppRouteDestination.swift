import SwiftUI
import FestivalCore

// MARK: - Route → screen

/// Maps every `AppRoute` to its feature screen. Registered once per tab stack.
struct AppRouteDestination: View {
    let route: AppRoute
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool

    /// Create the destination for one route.
    ///
    /// - Parameters:
    ///   - route: Route being displayed.
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - path: Owning tab's navigation path (for screens that pop or replace).
    ///   - isVisible: Whether the owning tab is on screen.
    init(
        route: AppRoute, session: FestivalSession, visibleInstruments: Set<Instrument>,
        path: Binding<[AppRoute]>, isVisible: Bool
    ) {
        self.route = route
        self.session = session
        self.visibleInstruments = visibleInstruments
        _path = path
        self.isVisible = isVisible
    }

    /// Selected account for selected-player-scoped routes (Rivals family), whose
    /// loads read `session.selectedPlayer` rather than a route argument.
    private var selectedAccountId: String? { session.selectedPlayer?.accountId }

    /// Per-entity identity rule (`.agents/platforms/apple/architecture.md`,
    /// "Per-entity screens"): every screen below that shows one account's data is
    /// keyed with `.id(...)` on that account, so its `@State` (phase, pages, pending
    /// dialogs) starts fresh when the account changes instead of drawing the
    /// previous account until its `task(id:)` reloads.
    var body: some View {
        switch route {
        case let .songDetail(song):
            SongDetailScreen(song: song, session: session, visibleInstruments: visibleInstruments)
                .firstRun(.songInfo, session: session)
        case let .songLeaderboard(song, instrument, page, focusSelected):
            SoloLeaderboardScreen(
                song: song, instrument: instrument, session: session,
                initialPage: page, path: $path, focusSelected: focusSelected
            )
        case let .songBandLeaderboard(song, bandType, page, focus):
            SongBandLeaderboardScreen(
                session: session, song: song, bandType: bandType, initialPage: page, focus: focus
            )
        case let .playerHistory(song, instrument):
            PlayerHistoryScreen(session: session, song: song, instrument: instrument)
                .firstRun(.playerHistory, session: session)
        case let .player(accountId, displayName):
            PlayerProfileScreen(session: session, accountId: accountId, displayName: displayName)
                .id(accountId)
        case let .playerBands(accountId, displayName):
            PlayerBandsScreen(session: session, accountId: accountId, displayName: displayName)
                .id(accountId)
        case .bands:
            BandsScreen(session: session)
        case let .band(bandId, name, bandType, teamKey):
            BandDetailScreen(
                session: session, bandId: bandId, name: name,
                bandType: bandType, teamKey: teamKey
            )
        case .leaderboards:
            LeaderboardsScreen(session: session)
                .firstRun(.leaderboards, session: session)
        case let .fullRankings(instrument, rankBy):
            FullRankingsScreen(session: session, instrument: instrument, rankBy: rankBy)
        case let .bandRankings(bandType):
            BandRankingsScreen(session: session, bandType: bandType)
        case .rivals:
            RivalsScreen(session: session)
                .firstRun(.rivals, session: session)
        case let .allRivals(scope):
            AllRivalsScreen(session: session, scope: scope)
                .id(selectedAccountId)
        case let .rivalDetail(rivalId, name, scope):
            RivalDetailScreen(session: session, rivalId: rivalId, name: name, scope: scope)
                .id(selectedAccountId)
        case let .rivalry(rivalId, mode, name, scope):
            RivalryScreen(session: session, rivalId: rivalId, mode: mode, name: name, scope: scope)
                .id(selectedAccountId)
        case .statistics:
            StatisticsScreen(session: session)
                .firstRun(.statistics, session: session)
        case .suggestions:
            SuggestionsScreen(session: session, visibleInstruments: visibleInstruments)
                .firstRun(.suggestions, session: session)
        case .compete:
            CompeteScreen(session: session)
                .firstRun(.compete, session: session)
        case .shop:
            ShopScreen(session: session, isVisible: isVisible && path.last == .shop)
                .firstRun(.shop, session: session)
        case .licenses:
            LicensesScreen(session: session)
        }
    }
}

// MARK: - Tab stack

/// One tab's `NavigationStack`, with every `AppRoute` destination registered.
struct FestivalTabStack<Root: View>: View {
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @Binding var path: [AppRoute]
    let isVisible: Bool
    /// The leading pane's context while the window allows an on-demand split
    /// (`OnDemandSplitStack`), applied to every page; nil on iPhone and in portrait.
    let paneContext: SplitPaneContext?
    let root: Root

    /// Create a tab stack.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - path: This tab's navigation path.
    ///   - isVisible: Whether this tab is currently selected.
    ///   - paneContext: Split pane context for every page, or nil.
    ///   - root: Tab root screen.
    init(
        session: FestivalSession, visibleInstruments: Set<Instrument>,
        path: Binding<[AppRoute]>, isVisible: Bool, paneContext: SplitPaneContext? = nil,
        @ViewBuilder root: () -> Root
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _path = path
        self.isVisible = isVisible
        self.paneContext = paneContext
        self.root = root()
    }

    /// Whether the trailing pane is open beside this stack (its top page is a list).
    private var isListPane: Bool { paneContext?.paneWidth != nil }

    var body: some View {
        NavigationStack(path: $path) {
            root
                // Each page's tools show in the iPhone tab-bar accessory only while it
                // is the front page (issue #92).
                .pageToolsScope()
                .modifier(TopEdgeScrim())
                .menuBarColumn(isTop: isVisible && path.isEmpty, isList: isListPane)
                .splitPaneContext(paneContext)
                .rootTabBarVisibility()
                .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(
                    route: route, session: session, visibleInstruments: visibleInstruments,
                    path: $path, isVisible: isVisible
                )
                // The bell and profile on every pushed page (issue #92).
                .pageTrailingItems()
                .pageToolsScope()
                .modifier(TopEdgeScrim())
                .menuBarColumn(isTop: isVisible && path.last == route, isList: isListPane)
                .splitPaneContext(paneContext)
                .rootTabBarVisibility()
            }
        }
    }
}

// MARK: - Menu-bar column context (iPad)

extension View {
    /// Tell an iOS page whether it is the top page of its column and whether that column
    /// is a split's list column, so only the front pages publish menu-bar commands
    /// (`MenuBarTopPagePublisher`; iOS navigation keeps covered pages and unselected
    /// tabs alive). The Mac sets the same values in `MacStack`.
    ///
    /// - Parameters:
    ///   - isTop: The page is visible and nothing is pushed over it.
    ///   - isList: The page is the list beside an open trailing pane.
    /// - Returns: The page with its menu-bar context.
    @ViewBuilder
    func menuBarColumn(isTop: Bool, isList: Bool = false) -> some View {
        #if os(iOS)
        environment(\.macPageIsTop, isTop).environment(\.macColumnIsList, isList)
        #else
        self
        #endif
    }
}
