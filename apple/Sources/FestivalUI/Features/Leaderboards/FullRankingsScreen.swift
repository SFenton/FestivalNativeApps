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
    /// The selected player's own row on this instrument's board, independent of
    /// the current page — mirroring the web client's separate `playerRanking`
    /// query on `FullRankingsPage.tsx`.
    @State private var spotlightState: RankLoadState<PlayerInstrumentRankingPayload> = .loading

    private struct SpotlightKey: Equatable {
        let instrument: Instrument
        let accountId: String?
    }

    private var spotlightKey: SpotlightKey {
        SpotlightKey(instrument: instrument, accountId: session.selectedPlayer?.accountId)
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
                            Text("No ranked players yet.")
                                .foregroundStyle(BrandTokens.textSecondary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.rankings.entries) { entry in
                            AccountRankingRow(
                                entry: entry, metric: rankBy,
                                isSelected: isSelectedAccount(entry.accountId)
                            )
                            .listRowBackground(BrandTokens.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    spotlightFooter(entries: payload.rankings.entries)
                    RankingsPagerView(
                        page: page, totalPages: payload.rankings.pageCount,
                        idPrefix: "fst.full-rankings"
                    ) { destination in
                        page = destination
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .festivalBackground(.carousel, session: session)
        .navigationTitle("\(instrument.label) Rankings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    instrumentMenu
                    RankByMenu(selection: $rankBy)
                }
            }
        }
        .onChange(of: instrument) { _, _ in page = 1 }
        .onChange(of: rankBy) { _, _ in page = 1 }
        .task(id: requestKey) { await load() }
        .task(id: spotlightKey) { await loadSpotlight() }
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

    /// Show the selected player's own row below the current page when they are not
    /// visible on it, with a jump control that moves straight to their page — a
    /// native addition beyond the web client, whose equivalent footer
    /// (`FullRankingsPage.tsx:531-552`) only links to the player's profile, since a
    /// paginated native `List` can usefully re-page itself instead.
    ///
    /// - Parameter entries: Current page's loaded rows.
    @ViewBuilder
    private func spotlightFooter(entries: [AccountRankingEntry]) -> some View {
        if let accountId = session.selectedPlayer?.accountId {
            let source: RankingSpotlightSource = {
                switch spotlightState {
                case .loading: return .notLoaded
                case let .loaded(payload): return payload.ranking.map { .available($0.entry) } ?? .unranked
                case .failed: return .notLoaded
                }
            }()
            switch RankingSpotlight.placement(
                selectedAccountId: accountId, visibleEntries: entries, source: source
            ) {
            case .none, .inline:
                EmptyView()
            case .pending:
                if case let .failed(issue) = spotlightState {
                    ServiceStatusInline(issue, scope: "full-rankings.spotlight") {
                        Task { await loadSpotlight() }
                    }
                    .padding(12)
                } else {
                    RankingSpotlightLoadingRow()
                        .padding(12)
                        .accessibilityIdentifier("fst.full-rankings.spotlight-footer.loading")
                }
            case .unranked:
                RankingSpotlightUnrankedRow(message: "You're not yet ranked on \(instrument.label).")
                    .padding(12)
                    .accessibilityIdentifier("fst.full-rankings.spotlight-footer.unranked")
            case let .footer(entry):
                HStack(spacing: 8) {
                    AccountRankingRow(entry: entry, metric: rankBy, isSelected: true)
                    Button {
                        page = LeaderboardPaging.page(forRank: entry.rank(for: rankBy), pageSize: 25)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(BrandTokens.accentPurple)
                    }
                    .accessibilityLabel("Jump to your page")
                    .accessibilityIdentifier("fst.full-rankings.spotlight-jump")
                }
                .padding(.horizontal, 12)
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

    private var instrumentMenu: some View {
        Menu {
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
        } label: {
            InstrumentIcon(instrument, size: 20)
        }
        .accessibilityIdentifier("fst.full-rankings.instrument-menu")
        .accessibilityLabel("Instrument: \(instrument.label)")
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
