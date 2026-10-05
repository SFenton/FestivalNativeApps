import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerBandsScreen

/// `/bands/player/:accountId` — a player's Duo/Trio/Quad bands, matching the web
/// client's `PlayerBandsPage`
/// (`FortniteFestivalWeb/src/pages/band/PlayerBandsPage.tsx`).
///
/// `GET /api/player/{accountId}/bands?group=&page=&pageSize=` is a pure read:
/// `GlobalLeaderboardPersistence.GetPlayerBandsList` returns an empty page when
/// the band-search projection is missing rather than rebuilding anything.
struct PlayerBandsScreen: View {
    let session: FestivalSession
    let accountId: String
    let displayName: String?

    @State private var group: PlayerBandGroup = .all
    @State private var page = 1
    @State private var state: RankLoadState<PlayerBandListPayload> = .loading
    /// The loaded page's first stagger finished: rows the List rebuilds after that
    /// (scrolled away and back) appear without a fade (issue #30).
    @State private var staggerSettled = false
    @Environment(\.deviceLayout) private var layout

    /// Includes `accountId` so a reused view identity can never keep, or accept a
    /// late response for, another player's bands.
    private struct RequestKey: Equatable {
        let accountId: String
        let group: PlayerBandGroup
        let page: Int
    }

    private var requestKey: RequestKey {
        RequestKey(accountId: accountId, group: group, page: page)
    }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - accountId: Player whose bands to list.
    ///   - displayName: Player name for the title.
    init(session: FestivalSession, accountId: String, displayName: String?) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Band Group", selection: $group) {
                ForEach(PlayerBandGroup.allCases) { group in
                    Text(group.label).tag(group)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            .accessibilityIdentifier("fst.player-bands.group-picker")
            // Group and page changes fade the bands out, show the spinner and fade the new
            // list in (web usePageTransition, issue #71).
            FestivalReloadGate(key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading bands") {
                switch state {
                case .loading:
                    EmptyView()
                case let .failed(issue):
                    ServiceStatusView(issue, title: "Bands unavailable") {
                        Task { await load() }
                    }
                case let .loaded(payload):
                    if payload.list.entries.isEmpty {
                        ContentUnavailableView(
                            "No Bands Yet",
                            systemImage: "person.3",
                            description: Text("No \(group.label.lowercased()) bands were found.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(Array(payload.list.entries.enumerated()), id: \.element.id) { index, entry in
                                PlayerBandRow(entry: entry)
                                    .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                                    .listRowBackground(BrandTokens.cardBackground)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                        .task(id: requestKey) {
                            await FadeStagger.settle(afterRevealing: payload.list.entries.count) {
                                staggerSettled = true
                            }
                        }
                        .rankingsListRailClearance(layout)
                        // Pinned below the rows (as the Solo leaderboard does): inside the
                        // reload gate's ZStack a sibling pager floated over mid-list rows.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            RankingsPagerView(
                                page: page,
                                totalPages: payload.list.pageCount(pageSize: 25),
                                idPrefix: "fst.player-bands"
                            ) { destination in
                                page = destination
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle(displayName.map { "\($0)'s Bands" } ?? "Bands")
        .toolbar {
            #if os(iOS)
            if case let .loaded(payload) = state {
                RankingsPagerToolbarContent(
                    page: page, totalPages: payload.list.pageCount(pageSize: 25),
                    idPrefix: "fst.player-bands"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        .onChange(of: group) { _, _ in page = 1 }
        .task(id: requestKey) { await load() }
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        state = .loading
        staggerSettled = false
        do {
            let payload = try await session.playerBands(
                accountId: accountId, group: requested.group, page: requested.page, pageSize: 25
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = min(max(1, requested.page), payload.list.pageCount(pageSize: 25))
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

// MARK: - Row

/// One player-band card: member names with their instrument icons and appearance
/// count, matching the web client's `PlayerBandCard`.
struct PlayerBandRow: View {
    let entry: PlayerBandEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: entry.membersLabel,
                bandType: entry.bandType, teamKey: entry.teamKey
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.members) { member in
                    HStack(spacing: 8) {
                        Text(member.resolvedName)
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(member.chartedInstruments) { instrument in
                                InstrumentIcon(instrument, size: 22)
                            }
                        }
                    }
                }
                Text("\(entry.appearanceCount.formatted()) songs together")
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fst.player-bands.row.\(entry.id)")
    }
}
