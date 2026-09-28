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
            Group {
                switch state {
                case .loading:
                    FestivalLoadingView(accessibilityLabel: "Loading bands")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            ForEach(payload.list.entries) { entry in
                                PlayerBandRow(entry: entry)
                                    .listRowBackground(BrandTokens.cardBackground)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                        .rankingsListRailClearance(layout)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .festivalBackground(.carousel, session: session)
        .navigationTitle(displayName.map { "\($0)'s Bands" } ?? "Bands")
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
                    .foregroundStyle(BrandTokens.textSecondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fst.player-bands.row.\(entry.id)")
    }
}
