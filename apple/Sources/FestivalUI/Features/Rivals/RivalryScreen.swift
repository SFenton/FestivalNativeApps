import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalryScreen

/// `/rivals/:rivalId/rivalry?mode=` — full song list for one `RivalCategorization`
/// bucket (e.g. "Closest Battles"), reached from `RivalDetailScreen`'s "See All".
struct RivalryScreen: View {
    let session: FestivalSession
    let rivalId: String
    let mode: String
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
    ///   - mode: `RivalCategory.key` selecting which bucket to show.
    ///   - name: Rival display name, if known.
    init(session: FestivalSession, rivalId: String, mode: String, name: String?) {
        self.session = session
        self.rivalId = rivalId
        self.mode = mode
        self.name = name
    }

    private static let modeTitles: [String: String] = [
        "closest_battles": "Closest Battles",
        "almost_passed": "Almost Passed",
        "slipping_away": "Slipping Away",
        "barely_winning": "Barely Winning",
        "pulling_forward": "Pulling Forward",
        "dominating_them": "Dominating Them",
    ]

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                content
            }
        }
        .navigationTitle(Self.modeTitles[mode] ?? "Rivalry")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppRoute.player(accountId: rivalId, displayName: rivalName)) {
                    Label("View Profile", systemImage: "person.crop.circle")
                }
            }
        }
        .task(id: RivalryTaskKey(rivalId: rivalId, mode: mode)) { await load() }
        .task { await loadSongLookup() }
    }

    private var rivalName: String? {
        if case let .loaded(detail) = state { return detail.rival.displayName ?? name }
        return name
    }

    private struct RivalryTaskKey: Equatable {
        let rivalId: String
        let mode: String
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
            let category = RivalCategorization.categorize(detail.songs).first { $0.key == mode }
            if let category, !category.songs.isEmpty {
                ScrollView {
                    FestivalGlassSection {
                        ForEach(category.songs) { song in
                            songRow(song, rivalName: detail.rival.displayName ?? name ?? "Rival")
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "No Songs", systemImage: "music.note.list",
                    description: Text("There are no songs in this category.")
                )
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
        // Re-stash immediately: `RivalDetailScreen` may still be on the stack and
        // will re-run its own `.task` (e.g. after a pop back and forward) expecting
        // the same context to still be available.
        if let context {
            RivalNavigationBridge.shared.stash(context, forRivalId: rivalId)
        }
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
