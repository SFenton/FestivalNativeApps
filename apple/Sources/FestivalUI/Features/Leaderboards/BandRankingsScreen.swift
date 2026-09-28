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
    @Environment(\.deviceLayout) private var layout

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
        Group {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading rankings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(issue):
                ServiceStatusView(issue, title: "Rankings unavailable") {
                    Task { await load() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    List {
                        if payload.rankings.entries.isEmpty {
                            Text("No ranked \(bandType.label.lowercased()) yet.")
                                .foregroundStyle(BrandTokens.textSecondary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.rankings.entries) { entry in
                            BandRankingRow(entry: entry, metric: rankBy, bandType: bandType)
                                .listRowBackground(BrandTokens.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .rankingsListRailClearance(layout)
                    RankingsPagerView(
                        page: page, totalPages: payload.rankings.pageCount,
                        idPrefix: "fst.band-rankings"
                    ) { destination in
                        page = destination
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .festivalBackground(.carousel, session: session)
        .navigationTitle("\(bandType.label) Rankings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    bandTypeMenu
                    BandRankByMenu(selection: $rankBy)
                }
            }
            #if os(iOS)
            if case let .loaded(payload) = state {
                RankingsPagerToolbarContent(
                    page: page, totalPages: payload.rankings.pageCount,
                    idPrefix: "fst.band-rankings"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        .onChange(of: bandType) { _, _ in page = 1 }
        .onChange(of: rankBy) { _, _ in page = 1 }
        .task(id: requestKey) { await load() }
    }

    private var bandTypeMenu: some View {
        Menu {
            Picker("Band Size", selection: $bandType) {
                ForEach(BandType.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
        } label: {
            Image(systemName: "person.3.fill")
        }
        .accessibilityIdentifier("fst.band-rankings.band-type-menu")
        .accessibilityLabel("Band size: \(bandType.label)")
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
