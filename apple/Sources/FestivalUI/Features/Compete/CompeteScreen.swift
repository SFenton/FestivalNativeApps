import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - CompeteScreen

/// `/compete` — phone hub combining Leaderboards and Rivals; this is the phone
/// tab shown once a player is selected (see `FestivalRootView`).
///
/// Ports the web's `CompetePage`: a Leaderboards section (live Top-5 preview per
/// Settings-visible instrument, reusing Lane L's `AccountRankingRow`/`RankLoadState`
/// from `Features/Leaderboards/RankingsSupport.swift`) and a Rivals section
/// (reusing this lane's own `RivalInstrumentSongSection`). No player selected →
/// `RivalsChooseProfileState`. See `.agents/pages/compete/ios.md`.
struct CompeteScreen: View {
    let session: FestivalSession
    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

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
        .navigationTitle("Compete")
        .festivalBackground(.carousel, session: session)
    }

    @ViewBuilder private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                leaderboardsSection
                rivalsSection
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: Leaderboards

    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Leaderboards")
                .padding(.horizontal, 16)
            NavigationLink(value: AppRoute.leaderboards) {
                HStack {
                    Label("Leaderboards Overview", systemImage: "list.number")
                        .foregroundStyle(BrandTokens.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTokens.textMuted)
                }
                .contentShape(Rectangle())
                .padding(16)
                .festivalGlass(.card)
            }
            .padding(.horizontal, 16)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see leaderboards.")
                    .padding(.horizontal, 16)
            } else {
                ForEach(visible.instruments) { instrument in
                    CompeteInstrumentLeaderboardSection(session: session, instrument: instrument)
                }
            }
        }
    }

    // MARK: Rivals

    private var rivalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Rivals")
                .padding(.horizontal, 16)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see rivals.")
                    .padding(.horizontal, 16)
            } else {
                ForEach(visible.instruments) { instrument in
                    RivalInstrumentSongSection(session: session, instrument: instrument)
                }
            }
        }
    }
}

// MARK: - Per-instrument leaderboard preview

/// One instrument's Top-5 ranking preview, reusing Lane L's `RankLoadState`/
/// `AccountRankingRow`/`RankingsSkeletonRows` (`Features/Leaderboards/RankingsSupport.swift`)
/// so Compete's cards match `LeaderboardsScreen`'s own overview cards exactly.
struct CompeteInstrumentLeaderboardSection: View {
    let session: FestivalSession
    let instrument: Instrument
    @State private var state: RankLoadState<RankingsPayload> = .loading

    private let previewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                InstrumentIcon(instrument, size: 20)
                FestivalSectionHeader(instrument.label)
            }
            switch state {
            case .loading:
                RankingsSkeletonRows(count: previewCount)
            case let .failed(message):
                RivalsSectionError(message: message) { Task { await load() } }
            case let .loaded(payload) where payload.rankings.entries.isEmpty:
                FestivalFootnote("No ranked \(instrument.label) players yet.")
            case let .loaded(payload):
                VStack(spacing: 4) {
                    ForEach(payload.rankings.entries) { entry in
                        AccountRankingRow(entry: entry, metric: .totalscore)
                    }
                }
                NavigationLink(
                    value: AppRoute.fullRankings(instrument: instrument, rankBy: "totalscore")
                ) {
                    RivalViewAllRow(title: "View Full Leaderboard")
                }
            }
        }
        .padding(16)
        .festivalGlass(.card)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("fst.compete.leaderboard-card.\(instrument.rawValue)")
        .task(id: instrument) { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.rankings(
                instrument: instrument, rankBy: .totalscore, page: 1, pageSize: previewCount
            ))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
