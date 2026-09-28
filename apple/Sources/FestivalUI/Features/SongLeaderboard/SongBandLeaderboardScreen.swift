import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SongBandLeaderboardScreen

/// `/songs/:songId/bands/:bandType` — per-song band leaderboard, matching the web
/// client's `SongBandLeaderboardPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx`).
///
/// `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=` is a pure read
/// (`MetaDatabase.GetSongBandLeaderboard`, only `SELECT`s).
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    @State private var bandType: BandType
    @State private var page = 1
    @State private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    @Environment(\.deviceLayout) private var layout

    private struct RequestKey: Equatable {
        let bandType: BandType
        let page: Int
    }

    private var requestKey: RequestKey { RequestKey(bandType: bandType, page: page) }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose band leaderboard to show.
    ///   - bandType: Band size key (`Band_Duets`, `Band_Trios`, `Band_Quad`).
    init(session: FestivalSession, song: Song, bandType: String) {
        self.session = session
        self.song = song
        _bandType = State(initialValue: BandType(rawValue: bandType) ?? .duets)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading band scores")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(issue):
                ServiceStatusView(issue, title: "Band scores unavailable") {
                    Task { await load() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    List {
                        if payload.leaderboard.entries.isEmpty {
                            Text("No \(bandType.label.lowercased()) scores yet.")
                                .foregroundStyle(FestivalText.primary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.leaderboard.entries) { entry in
                            SongBandLeaderboardRow(entry: entry)
                                .listRowBackground(BrandTokens.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .rankingsListRailClearance(layout)
                    RankingsPagerView(
                        page: page, totalPages: payload.leaderboard.pageCount,
                        idPrefix: "fst.song-band-leaderboard"
                    ) { destination in
                        page = destination
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .festivalBackground(.carousel, session: session)
        .navigationTitle("\(bandType.label) Scores")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { bandTypeMenu }
            #if os(iOS)
            if case let .loaded(payload) = state {
                RankingsPagerToolbarContent(
                    page: page, totalPages: payload.leaderboard.pageCount,
                    idPrefix: "fst.song-band-leaderboard"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        .onChange(of: bandType) { _, _ in page = 1 }
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
        .accessibilityIdentifier("fst.song-band-leaderboard.band-type-menu")
        .accessibilityLabel("Band size: \(bandType.label)")
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let payload = try await session.songBandLeaderboard(
                songId: song.songId, bandType: requested.bandType, page: requested.page, pageSize: 25
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = min(max(1, requested.page), payload.leaderboard.pageCount)
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

/// One band score row: rank, member names with instruments, and the team's score,
/// star count and accuracy, matching the web client's `SongBandScoreFooter`.
struct SongBandLeaderboardRow: View {
    let entry: SongBandLeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: entry.membersLabel,
                bandType: entry.bandType, teamKey: entry.teamKey
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text("#\(entry.rank.formatted())")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(FestivalText.primary)
                        .frame(minWidth: 32, alignment: .trailing)
                    Text(entry.membersLabel)
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.score.formatted())
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(FestivalText.primary)
                }
                HStack(spacing: 12) {
                    ForEach(entry.members) { member in
                        HStack(spacing: 4) {
                            ForEach(member.chartedInstruments) { instrument in
                                InstrumentIcon(instrument, size: 20)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if entry.isFullCombo {
                        Text("FC")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FestivalText.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).stroke(BrandTokens.gold, lineWidth: 1.5)
                            )
                    }
                    if entry.stars > 0 {
                        StarRating(stars: entry.stars)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fst.song-band-leaderboard.row.\(entry.id)")
    }
}
