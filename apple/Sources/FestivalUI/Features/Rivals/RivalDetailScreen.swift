import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalDetailScreen

/// `/rivals/:rivalId` — themed breakdown of every shared song against one rival.
///
/// Ports the web's `RivalDetailPage`: songs are grouped into the same categories
/// as `categorizeRivalSongs` (Closest Battles, Almost Passed / Slipping Away,
/// Barely Winning / Pulling Forward / Dominating Them), each previewed here and
/// fully browsable via `RivalryScreen`.
///
/// The web learns which combo/leaderboard scope produced the tapped row from
/// React Router `location.state`; this app has no such side channel on its
/// value-typed `AppRoute`, so `RivalNavigationBridge` carries it for one push.
/// Reached without a stashed context (deep link, cold start) this screen falls
/// back to merging every Settings-visible instrument.
struct RivalDetailScreen: View {
    let session: FestivalSession
    let rivalId: String
    let name: String?
    @State private var state: RivalsLoadState<RivalDetailResponse> = .loading
    @State private var songsById: [String: Song] = [:]
    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - rivalId: Rival account ID.
    ///   - name: Rival display name, if known.
    init(session: FestivalSession, rivalId: String, name: String?) {
        self.session = session
        self.rivalId = rivalId
        self.name = name
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                content
            }
        }
        .navigationTitle(displayName ?? "Rival")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppRoute.player(accountId: rivalId, displayName: displayName)) {
                    Label("View Profile", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("fst.rivalDetail.viewProfile")
            }
        }
        .task(id: rivalId) { await load() }
        .task { await loadSongLookup() }
    }

    private var displayName: String? {
        if case let .loaded(detail) = state { return detail.rival.displayName ?? name }
        return name
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ServiceUnavailableView(
                title: "Rivals Unavailable", message: message
            ) { Task { await load() } }
        case let .loaded(detail):
            let categories = RivalCategorization.categorize(detail.songs)
            if categories.isEmpty {
                ContentUnavailableView(
                    "No Shared Songs", systemImage: "music.note.list",
                    description: Text("You and this rival don't share any scored songs yet.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(categories) { category in
                            FestivalGlassSection(category.title, subtitle: category.subtitle) {
                                ForEach(category.songs.prefix(5)) { song in
                                    songRow(song, rivalName: detail.rival.displayName ?? name ?? "Rival")
                                }
                                NavigationLink(
                                    value: AppRoute.rivalry(
                                        rivalId: rivalId, mode: category.key,
                                        name: detail.rival.displayName ?? name
                                    )
                                ) {
                                    RivalViewAllRow(title: "See All")
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func songRow(_ song: RivalSongComparison, rivalName: String) -> some View {
        let row = RivalSongRowContent(
            song: song, playerName: session.selectedPlayer?.displayName ?? "You", rivalName: rivalName
        )
        if let match = songsById[song.songId] {
            NavigationLink(value: AppRoute.songDetail(match)) { row }
        } else {
            row
        }
    }

    @MainActor
    private func load() async {
        state = .loading
        let context = RivalNavigationBridge.shared.consume(forRivalId: rivalId)
        do {
            let detail: RivalDetailResponse
            switch context?.source ?? .song {
            case .leaderboard:
                guard let raw = context?.instruments.first, let instrument = Instrument(rawValue: raw) else {
                    detail = try await fallbackSongDetail()
                    break
                }
                detail = try await session.leaderboardRivalDetail(
                    instrument: instrument, rivalId: rivalId, rankBy: context?.rankBy ?? .totalscore
                )
            case .song:
                let instruments = (context?.instruments ?? []).compactMap(Instrument.init(rawValue:))
                detail = instruments.isEmpty ? try await fallbackSongDetail()
                    : try await session.combinedRivalDetail(instruments: instruments, rivalId: rivalId)
            }
            state = .loaded(detail)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Merge every Settings-visible instrument when no navigation context was stashed.
    private func fallbackSongDetail() async throws -> RivalDetailResponse {
        let instruments = visible.instruments
        guard !instruments.isEmpty else {
            return .empty(rivalId: rivalId, displayName: name)
        }
        return try await session.combinedRivalDetail(instruments: instruments, rivalId: rivalId)
    }

    private func loadSongLookup() async {
        guard let payload = try? await session.catalog() else { return }
        songsById = Dictionary(
            payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first }
        )
    }
}
