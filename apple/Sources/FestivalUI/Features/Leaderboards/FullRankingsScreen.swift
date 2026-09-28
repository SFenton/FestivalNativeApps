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
                ProgressView("Loading rankings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ServiceUnavailableView(title: "Rankings unavailable", message: message) {
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
                            AccountRankingRow(entry: entry, metric: rankBy)
                                .listRowBackground(BrandTokens.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
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
            state = .failed(error.localizedDescription)
        }
    }
}
