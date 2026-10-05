import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandRankingsScreen

/// `/leaderboards/bands/:bandType` — paginated band rankings for one band size
/// (`FortniteFestivalWeb/src/pages/leaderboards/BandRankingsPage.tsx`).
struct BandRankingsScreen: View {
    let session: FestivalSession
    @State private var bandType: BandType
    @State private var rankBy: BandRankingMetric
    @State private var page = 1
    @State private var state: RankLoadState<BandRankingsPayload> = .loading
    /// Ranked-team count and page count for the current size and metric, kept
    /// across page loads (no pager/subtitle flicker); cleared on a size/metric change.
    @State private var board: BoardSummary?
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    /// Count facts that survive a page change.
    private struct BoardSummary: Equatable {
        let totalTeams: Int
        let totalPages: Int
    }

    private struct RequestKey: Equatable {
        let bandType: BandType
        let rankBy: BandRankingMetric
        let page: Int
    }

    private var requestKey: RequestKey {
        RequestKey(bandType: bandType, rankBy: rankBy, page: page)
    }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - bandType: Band size key (`Band_Duets`, `Band_Trios`, `Band_Quad`).
    init(session: FestivalSession, bandType: String) {
        self.session = session
        _bandType = State(initialValue: BandType(rawValue: bandType) ?? .duets)
        _rankBy = State(initialValue: .totalscore)
    }

    var body: some View {
        // Band size, metric and page changes fade the board out, show the spinner and
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
                        if let board {
                            RankingsCountHeader(
                                text: RankingsCountText.rankedBands(board.totalTeams),
                                id: "fst.band-rankings.ranked-count"
                            )
                        }
                        if payload.rankings.entries.isEmpty {
                            Text("No ranked \(bandType.label.lowercased()) yet.")
                                .foregroundStyle(FestivalText.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(payload.rankings.entries) { entry in
                            BandRankingRow(entry: entry, metric: rankBy, bandType: bandType, cardSurface: true)
                                .macKeyboardRow(entry.teamKey)
                        }
                    }
                    .macKeyboardRows(BandRankingRow.keyRows(payload.rankings.entries, bandType: bandType))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    // Each loaded page fades in once (web load-in), not per row on scroll.
                    .festivalFadeInOnAppear()
                }
                // One rank and rating width for the page (issue #37).
                .leaderboardSectionColumns(.bandRankings(payload.rankings.entries, metric: rankBy))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RankingsFloatingBar(
                pager: board.map { RankingsPagerState(page: page, totalPages: $0.totalPages) },
                idPrefix: "fst.band-rankings"
            ) { destination in
                page = destination
            } menu: { showsTitle in
                bandTypeMenu(showsTitle: showsTitle)
            }
        }
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle("\(bandType.label) Rankings")
        // Mac: View › Rank By mirrors the toolbar menu.
        .macRankByCommands($rankBy)
        .toolbar {
            if layout.sectionChrome.isVerticalBar {
                // `/duo` J1: band size and Rank By as two titled rail items, not one
                // custom `HStack` item that keeps a horizontal top bar.
                ToolbarItemGroup(placement: .festivalPageAction) {
                    bandTypeMenu(showsTitle: false)
                    BandRankByMenu(selection: $rankBy)
                }
            } else if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) {
                    HStack(spacing: 4) {
                        BandRankByMenu(selection: $rankBy)
                    }
                }
            }
            #if os(iOS)
            if let board {
                RankingsPagerToolbarContent(
                    page: page, totalPages: board.totalPages,
                    idPrefix: "fst.band-rankings"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        // iPhone tab-bar accessory (issue #92): Rank By.
        .festivalPageTool(token: rankBy, order: PageToolOrder.primary) {
            BandRankByMenu(selection: $rankBy)
        }
        .onChange(of: bandType) { _, _ in
            page = 1
            board = nil
        }
        .onChange(of: rankBy) { _, _ in
            page = 1
            board = nil
        }
        .task(id: requestKey) { await load() }
    }

    /// Band-size switcher: a material pill in the floating bar, or a titled toolbar
    /// item (`Label` with the band symbol) in the iPhone Duo rail (`/duo` J1).
    ///
    /// - Parameter showsTitle: Whether the pill shows the band size's name.
    /// - Returns: The native `Menu`, keeping `fst.band-rankings.band-type-menu`.
    @ViewBuilder
    private func bandTypeMenu(showsTitle: Bool) -> some View {
        if layout.sectionChrome.isVerticalBar {
            Menu {
                bandTypeChoices
            } label: {
                Label(bandType.label, systemImage: "person.3.fill")
            }
            .accessibilityIdentifier("fst.band-rankings.band-type-menu")
            .accessibilityLabel("Band size")
            .accessibilityValue(bandType.label)
        } else {
            Menu {
                bandTypeChoices
            } label: {
                RankingsSwitcherPillLabel(title: bandType.label, showsTitle: showsTitle) {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fst.band-rankings.band-type-menu")
            .accessibilityLabel("Band size")
            .accessibilityValue(bandType.label)
        }
    }

    /// Band sizes as a picker, shared by the rail item and the pill.
    private var bandTypeChoices: some View {
        Picker("Band Size", selection: $bandType) {
            ForEach(BandType.allCases) { size in
                Text(size.label).tag(size)
            }
        }
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let payload = try await session.bandRankings(
                bandType: requested.bandType, rankBy: requested.rankBy,
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
                totalTeams: payload.rankings.totalTeams,
                totalPages: payload.rankings.pageCount
            )
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
