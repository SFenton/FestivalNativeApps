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

    var body: some View {
        switch route {
        case let .songDetail(song):
            SongDetailScreen(song: song, session: session, visibleInstruments: visibleInstruments)
        case let .songLeaderboard(song, instrument, page):
            SoloLeaderboardScreen(
                song: song, instrument: instrument, session: session,
                initialPage: page, path: $path
            )
        case let .songBandLeaderboard(song, bandType):
            SongBandLeaderboardScreen(session: session, song: song, bandType: bandType)
        case let .playerHistory(song, instrument):
            PlayerHistoryScreen(session: session, song: song, instrument: instrument)
        case let .player(accountId, displayName):
            PlayerProfileScreen(session: session, accountId: accountId, displayName: displayName)
        case let .playerBands(accountId, displayName):
            PlayerBandsScreen(session: session, accountId: accountId, displayName: displayName)
        case .bands:
            BandsScreen(session: session)
        case let .band(bandId, name, bandType, teamKey):
            BandDetailScreen(
                session: session, bandId: bandId, name: name,
                bandType: bandType, teamKey: teamKey
            )
        case .leaderboards:
            LeaderboardsScreen(session: session)
        case let .fullRankings(instrument, rankBy):
            FullRankingsScreen(session: session, instrument: instrument, rankBy: rankBy)
        case let .bandRankings(bandType):
            BandRankingsScreen(session: session, bandType: bandType)
        case .rivals:
            RivalsScreen(session: session)
        case let .allRivals(category):
            AllRivalsScreen(session: session, category: category)
        case let .rivalDetail(rivalId, name):
            RivalDetailScreen(session: session, rivalId: rivalId, name: name)
        case let .rivalry(rivalId, mode, name):
            RivalryScreen(session: session, rivalId: rivalId, mode: mode, name: name)
        case .statistics:
            StatisticsScreen(session: session)
        case .suggestions:
            SuggestionsScreen(session: session)
        case .compete:
            CompeteScreen(session: session)
        case .shop:
            ShopScreen(session: session, isVisible: isVisible && path.last == .shop)
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
    let root: Root

    /// Create a tab stack.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - path: This tab's navigation path.
    ///   - isVisible: Whether this tab is currently selected.
    ///   - root: Tab root screen.
    init(
        session: FestivalSession, visibleInstruments: Set<Instrument>,
        path: Binding<[AppRoute]>, isVisible: Bool, @ViewBuilder root: () -> Root
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _path = path
        self.isVisible = isVisible
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root.navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(
                    route: route, session: session, visibleInstruments: visibleInstruments,
                    path: $path, isVisible: isVisible
                )
            }
        }
    }
}
