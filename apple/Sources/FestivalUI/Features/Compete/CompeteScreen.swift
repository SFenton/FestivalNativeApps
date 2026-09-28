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
    @State private var quickLinks = QuickLinksController()
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
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
        .toolbar {
            QuickLinksToolbarItem(quickLinks)
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
    }

    @ViewBuilder private var hub: some View {
        // iPhone Duo inner display, portrait: leaderboards and rivals become two
        // swipeable sources stacked around the fold (`CompeteDualSource.swift`).
        DualSourceLayout {
            if DualSourcePolicy.isActive(layout) {
                CompeteLeaderboardsCarousel(session: session, instruments: visible.instruments)
            } else {
                stackedHub
            }
        } secondary: {
            CompeteRivalsCarousel(session: session, instruments: visible.instruments)
        }
        // Every section below loads for `session.selectedPlayer` but keys its
        // `task(id:)` only on instrument/scope; this hub survives a profile switch
        // (tab root, or pushed on a stack the switch does not reset), so key the
        // sections' state by the selected account or they keep the old account's
        // rivals (`.agents/platforms/apple/architecture.md`, "Per-entity screens").
        .id(session.selectedPlayer?.accountId)
    }

    private var stackedHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                leaderboardsSection
                rivalsSection
            }
            .padding(.vertical, 12)
        }
        .quickLinks(quickLinks, title: "Quick Links")
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
                        .foregroundStyle(FestivalText.deemphasized)
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
        .quickLinkSection(id: "leaderboards", title: "Leaderboards", symbol: "trophy.fill")
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
                    RivalInstrumentSongSection(
                        session: session, instrument: instrument, registersQuickLink: false,
                        emptyMessage: "No rivals found for \(instrument.label) yet."
                    )
                }
            }
        }
        .quickLinkSection(id: "rivals", title: "Rivals", symbol: "person.2.fill")
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
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "compete.\(instrument.rawValue)") { Task { await load() } }
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
            state = .failed(ServiceIssue(error))
        }
    }
}
