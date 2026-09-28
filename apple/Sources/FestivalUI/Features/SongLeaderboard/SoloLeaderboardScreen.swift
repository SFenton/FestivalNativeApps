import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Solo leaderboard

/// Loads one 25-row page and owns the native, one-based pagination controls.
struct SoloLeaderboardScreen: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var path: [AppRoute]
    @State private var page: Int
    @State private var state: LoadState
    @State private var lastRequest: RequestKey?

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(ServiceIssue)
    }

    private struct RequestKey: Hashable {
        let page: Int
        let publicationRevision: Int
        let leeway: Double?
    }

    private var requestKey: RequestKey {
        RequestKey(
            page: page, publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    /// Carry an explicit deep-link page into this screen before cached history.
    ///
    /// - Parameters:
    ///   - song: Current catalog song.
    ///   - instrument: Requested solo chart.
    ///   - session: Shared process-lifetime API and artwork session.
    ///   - initialPage: One-based page from navigation/deep link.
    ///   - path: Native tab's route descriptor to update on paging.
    ///   - initialState: Loading in production, fixture state in hosted UI tests.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialPage: Int, path: Binding<[AppRoute]>, initialState: LoadState = .loading
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _page = State(initialValue: max(1, initialPage))
        _path = path
        _state = State(initialValue: initialState)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading leaderboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(issue):
                ServiceStatusView(issue, title: "Leaderboard unavailable") {
                    Task { await loadPage() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        scoreBanner(payload)
                        scoreHeader(payload)
                    }
                    List {
                        if dynamicTypeSize.isAccessibilitySize {
                            scoreBanner(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            scoreHeader(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.leaderboard.entries) { entry in
                            let isSelectedRow = isSelectedAccount(entry.accountId)
                            NavigationLink(value: playerRoute(for: entry)) {
                                SongLeaderboardEntryRow(entry: entry)
                                    .padding(12)
                                    .festivalGlass(.card)
                                    .overlay {
                                        if isSelectedRow {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(BrandTokens.accentPurple, lineWidth: 2)
                                        }
                                    }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(
                                "fst.song-leaderboard.row.\(entry.accountId)"
                            )
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    selectedPlayerFooter(payload)
                    RankingsPagerView(
                        page: page, totalPages: payload.leaderboard.pageCount,
                        idPrefix: "fst.song-leaderboard"
                    ) { destination in
                        move(to: destination)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle(song.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    InstrumentIcon(instrument, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(instrument.label)
                            .font(.caption)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: requestKey) {
            if case .loading = state {
                await loadPage()
            } else if let lastRequest, lastRequest != requestKey {
                await loadPage()
            }
        }
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

    /// The selected player's own score footer for this song/instrument, built from
    /// the score index already loaded for their profile (`FestivalSession.selectedPlayerScores`)
    /// — no extra network read, matching the web client's `playerData.scores` lookup
    /// (`LeaderboardPage.tsx:88-91`). Shown whenever they have a score here, since the
    /// paginated board may or may not currently show their row.
    ///
    /// Tapping the row opens Statistics, matching the web client's footer
    /// (`LeaderboardPage.tsx:476-500`, `navigate('/statistics')`); a trailing jump
    /// control — a native addition beyond web — moves straight to their page when
    /// they are not visible on the current one.
    ///
    /// - Parameter payload: Current page's loaded leaderboard.
    @ViewBuilder
    private func selectedPlayerFooter(_ payload: LeaderboardPayload) -> some View {
        if let selected = session.selectedPlayer,
           let score = session.selectedPlayerScores[song.songId]?[instrument],
           let rank = score.rank {
            let entry = LeaderboardEntry(
                accountId: selected.accountId, displayName: selected.displayName,
                score: score.score, rank: rank, localRank: nil,
                accuracy: score.accuracy, isFullCombo: score.isFullCombo,
                stars: score.stars, season: score.season, difficulty: score.difficulty
            )
            let isVisible = payload.leaderboard.entries.contains {
                $0.accountId.caseInsensitiveCompare(selected.accountId) == .orderedSame
            }
            HStack(spacing: 8) {
                NavigationLink(value: AppRoute.statistics) {
                    SongLeaderboardEntryRow(entry: entry)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your rank, \(RankingFormatting.ordinal(rank)).")
                if !isVisible {
                    Button {
                        move(to: LeaderboardPaging.page(forRank: rank, pageSize: 25))
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(BrandTokens.accentPurple)
                    }
                    .accessibilityLabel("Jump to your page")
                    .accessibilityIdentifier("fst.song-leaderboard.spotlight-jump")
                }
            }
            .padding(.horizontal, 4)
            .background(BrandTokens.accentPurple.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BrandTokens.accentPurple, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.song-leaderboard.spotlight-footer")
        }
    }

    /// Send a row to the shared Statistics tab when it is the selected player,
    /// otherwise to the viewed player's profile — matching the source's
    /// `navToPlayer` (`FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx`).
    ///
    /// - Parameter entry: Tapped chart row.
    /// - Returns: `.statistics` for the signed-in selected player, else `.player`.
    private func playerRoute(for entry: LeaderboardEntry) -> AppRoute {
        if let selected = session.selectedPlayer, selected.accountId == entry.accountId {
            return .statistics
        }
        return .player(accountId: entry.accountId, displayName: entry.displayName)
    }

    /// Keep score provenance in both the fixed and accessibility-scrolling layouts.
    ///
    /// - Parameter payload: Current chart response with freshness provenance.
    /// - Returns: A native disclosure when the chart is stale or unverified.
    @ViewBuilder
    private func scoreBanner(_ payload: LeaderboardPayload) -> some View {
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .scores, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
            .padding(.horizontal, 16)
        } else if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live scores without publication verification",
                symbol: "info.circle"
            )
            .padding(.horizontal, 16)
        }
    }

    /// Let the source-chart title and totals scroll above rows at large text sizes.
    ///
    /// - Parameter payload: Current chart, including its optional totals disclosure.
    /// - Returns: A wrapping, opaque native song summary.
    private func scoreHeader(_ payload: LeaderboardPayload) -> some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 80)
                .id(song.albumArt)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(song.artist)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if payload.leaderboard.showLeaderboardEntryTotals == true {
                    Text("\(payload.leaderboard.totalEntries) \(instrument.label) entries")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    /// Load a specific page and reject late responses from a previous selection.
    private func loadPage() async {
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.leaderboard(
                songId: song.songId, instrument: instrument,
                page: requested.page, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = LeaderboardPaging.corrected(
                requested: requested.page, totalPages: payload.leaderboard.pageCount
            )
            if corrected != requested.page {
                move(to: corrected)
                return
            }
            state = .loaded(payload)
        } catch is CancellationError {
            if requested == requestKey { state = .loading }
        } catch let error as URLError where error.code == .cancelled {
            if requested == requestKey { state = .loading }
        } catch {
            if requested == requestKey {
                state = .failed(ServiceIssue(error))
            }
        }
    }

    /// Change both the visible page and its native navigation descriptor.
    ///
    /// - Parameter destination: One-based page inside the loaded chart's bounds.
    private func move(to destination: Int) {
        state = .loading
        page = destination
        if !path.isEmpty {
            path[path.count - 1] = .songLeaderboard(song, instrument, destination)
        }
    }

}
