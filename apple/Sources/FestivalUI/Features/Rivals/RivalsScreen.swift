import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalsScreen

/// `/rivals` — selected player's rivals hub.
///
/// Ports the web's `RivalsPage`/`LeaderboardRivalsTab`: a Song/Leaderboard segmented
/// tab, one section per Settings-visible instrument, and a "View All" push to
/// `AllRivalsScreen`. The web additionally groups a "Common Rivals" section
/// (rivals shared across every visible instrument) and a settings-derived
/// multi-instrument "combo" scope (e.g. Guitar+Bass); this native pass covers the
/// per-instrument sections only — see `.agents/pages/rivals/ios.md` for the gap.
struct RivalsScreen: View {
    let session: FestivalSession
    @State private var tab: Tab = .song
    @State private var rankBy: RivalRankMetric = .totalscore
    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    enum Tab: String, CaseIterable, Identifiable {
        case song = "Song"
        case leaderboard = "Leaderboard"
        var id: String { rawValue }
    }

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                hub
            }
        }
        .navigationTitle("Rivals")
        .festivalBackground(.carousel, session: session)
    }

    private var instruments: [Instrument] { visible.instruments }

    @ViewBuilder private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("fst.rivals.tab")

                if instruments.isEmpty {
                    FestivalFootnote(
                        "Enable at least one instrument in Settings to see rivals."
                    )
                    .padding(.horizontal, 16)
                } else if tab == .song {
                    ForEach(instruments) { instrument in
                        RivalInstrumentSongSection(session: session, instrument: instrument)
                    }
                } else {
                    rankByPicker
                    ForEach(instruments) { instrument in
                        RivalInstrumentLeaderboardSection(
                            session: session, instrument: instrument, rankBy: rankBy
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var rankByPicker: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(RivalRankMetric.allCases) { metric in
                    Button(metric.label) { rankBy = metric }
                }
            } label: {
                Label(rankBy.label, systemImage: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
            }
            .accessibilityIdentifier("fst.rivals.rankBy")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Per-instrument song section

/// One instrument's "shared songs" rivals, loaded independently of its siblings.
struct RivalInstrumentSongSection: View {
    let session: FestivalSession
    let instrument: Instrument
    @State private var state: RivalsLoadState<RivalsListResponse> = .loading

    private let previewCount = 3

    var body: some View {
        Group {
            switch state {
            case .loading:
                shell { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
            case let .failed(message):
                shell { RivalsSectionError(message: message) { Task { await load() } } }
            case let .loaded(response) where response.isEmpty:
                EmptyView()
            case let .loaded(response):
                shell {
                    ForEach(previewRows(response)) { row in
                        NavigationLink(
                            value: AppRoute.rivalDetail(rivalId: row.rival.accountId, name: row.rival.displayName)
                        ) {
                            RivalRowContent(rival: row.rival, direction: row.direction)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            RivalNavigationBridge.shared.stash(
                                .song(instruments: [instrument.rawValue]), forRivalId: row.rival.accountId
                            )
                        })
                    }
                    NavigationLink(
                        value: AppRoute.allRivals(
                            category: RivalAllCategory.song(instrument: instrument.rawValue).encoded
                        )
                    ) {
                        RivalViewAllRow(title: "View All Rivals")
                    }
                }
            }
        }
        .task(id: instrument) { await load() }
    }

    private struct Row: Identifiable {
        let rival: RivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ response: RivalsListResponse) -> [Row] {
        response.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + response.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection(instrument.label) { content() }
            .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.rivalsList(instrument: instrument))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Per-instrument leaderboard section

/// One instrument's global-leaderboard rivals, loaded independently of its siblings.
struct RivalInstrumentLeaderboardSection: View {
    let session: FestivalSession
    let instrument: Instrument
    let rankBy: RivalRankMetric
    @State private var state: RivalsLoadState<LeaderboardRivalsListResponse> = .loading

    private let previewCount = 3

    var body: some View {
        Group {
            switch state {
            case .loading:
                shell { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
            case let .failed(message):
                shell { RivalsSectionError(message: message) { Task { await load() } } }
            case let .loaded(response) where response.isEmpty:
                EmptyView()
            case let .loaded(response):
                shell {
                    ForEach(previewRows(response)) { row in
                        NavigationLink(
                            value: AppRoute.rivalDetail(rivalId: row.rival.accountId, name: row.rival.displayName)
                        ) {
                            RivalRowContent(rival: row.rival, direction: row.direction)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            RivalNavigationBridge.shared.stash(
                                .leaderboard(instrument: instrument.rawValue, rankBy: rankBy),
                                forRivalId: row.rival.accountId
                            )
                        })
                    }
                    NavigationLink(
                        value: AppRoute.allRivals(
                            category: RivalAllCategory.leaderboard(
                                instrument: instrument.rawValue, rankBy: rankBy
                            ).encoded
                        )
                    ) {
                        RivalViewAllRow(title: "View All Rivals")
                    }
                }
            }
        }
        .task(id: TaskKey(instrument: instrument, rankBy: rankBy)) { await load() }
    }

    private struct TaskKey: Equatable {
        let instrument: Instrument
        let rankBy: RivalRankMetric
    }

    private struct Row: Identifiable {
        let rival: LeaderboardRivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ response: LeaderboardRivalsListResponse) -> [Row] {
        response.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + response.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection(instrument.label) { content() }
            .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
