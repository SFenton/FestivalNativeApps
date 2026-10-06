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

    @State private var group: PlayerBandGroup
    @State private var page = 1
    @State private var state: RankLoadState<PlayerBandListPayload> = .loading
    /// The loaded page's first stagger finished: cards the lazy stack rebuilds after that
    /// (scrolled away and back) appear without a fade (issue #30).
    @State private var staggerSettled = false
    /// Top edge of the pinned pager in ``pageSpace``; nil without one.
    @State private var bottomChromeTop: CGFloat?
    /// The cards' bottom fade height, shrinking as the last card arrives.
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    @Environment(\.deviceLayout) private var layout

    /// Coordinate space shared by the cards' fade and the pager.
    nonisolated private static let pageSpace = "fst.player-bands.page"
    /// Space between two band cards, and above the pager.
    nonisolated private static let rowGap: CGFloat = 8

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
    ///   - group: Band size the list opens on (the profile's per-group View All).
    init(session: FestivalSession, accountId: String, displayName: String?, group: PlayerBandGroup = .all) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
        _group = State(initialValue: group)
    }

    var body: some View {
        // Read here, not only inside the reload gate's content, so measuring the pager
        // always rebuilds the fade mask (issues #294, #305).
        let chromeTop = bottomChromeTop
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
                        // A `ScrollView` of band cards, not a `List`: the cards are
                        // `NavigationLink`s (a `List` would add a second chevron), and
                        // they share the leaderboard rows' card and bottom edge (issue #319).
                        ScrollView {
                            LazyVStack(spacing: Self.rowGap) {
                                ForEach(Array(payload.list.entries.enumerated()), id: \.element.id) { index, entry in
                                    PlayerBandRow(entry: entry)
                                        .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, Self.rowGap)
                        }
                        .task(id: requestKey) {
                            await FadeStagger.settle(afterRevealing: payload.list.entries.count) {
                                staggerSettled = true
                            }
                        }
                        .rankingsListRailClearance(layout)
                        // Cards fade out above the pager and are not drawn beneath it,
                        // like every paginated board (issue #305), so the pager's card
                        // surface never carries row text under its glyphs.
                        .bottomChromeFade(
                            chromeTop: chromeTop, distance: $bottomFadeDistance, in: Self.pageSpace
                        )
                        // Pinned below the rows (as the Solo leaderboard does): inside the
                        // reload gate's ZStack a sibling pager floated over mid-list rows.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            RankingsPagerView(
                                page: page,
                                totalPages: payload.list.pageCount(pageSize: 25),
                                idPrefix: "fst.player-bands",
                                topPadding: Self.rowGap
                            ) { destination in
                                page = destination
                            }
                            .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(.named(Self.pageSpace))
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
/// count, matching the web client's `PlayerBandCard` (`frostedCard`).
///
/// Player Bands and the profile's inline bands section (issue #312) both draw it on
/// the shared row card with an in-card chevron, like Song Detail's band previews
/// (``SongBandPreviewRow``) and the leaderboard rows beside the pager (issue #319).
struct PlayerBandRow: View {
    let entry: PlayerBandEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 8) {
                details
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: LeaderboardRowMetrics.minHeight, alignment: .leading)
            .modifier(RankingRowSurface(isSelected: false))
            .contentShape(Rectangle())
        }
        .festivalRowButtonStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlayerBandRow.spokenLabel(entry))
        .accessibilityHint("Opens band")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fst.player-bands.row.\(entry.id)")
    }

    private var route: AppRoute {
        .band(bandId: entry.bandId, name: entry.membersLabel, bandType: entry.bandType, teamKey: entry.teamKey)
    }

    private var details: some View {
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
    }

    /// One spoken label for a band card: its members and shared song count.
    ///
    /// - Parameter entry: Player band row.
    /// - Returns: For example "A + B, 12 songs together".
    static func spokenLabel(_ entry: PlayerBandEntry) -> String {
        let members = entry.membersLabel.isEmpty ? "Band" : entry.membersLabel
        return "\(members), \(entry.appearanceCount.formatted()) songs together"
    }
}
