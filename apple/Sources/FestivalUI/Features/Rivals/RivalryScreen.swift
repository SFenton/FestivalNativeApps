import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalryScreen

/// `/rivals/:rivalId/rivalry?mode=` — full song list for one `RivalCategorization`
/// bucket (e.g. "Closest Battles"), reached from a `RivalDetailScreen` category's "View All".
///
/// `scope` is forwarded unchanged from the `.rivalDetail` push that reached this
/// screen (native `AppRoute` carries it directly; there is no bridge to re-stash).
struct RivalryScreen: View {
    let session: FestivalSession
    let rivalId: String
    let mode: String
    let name: String?
    let scope: RivalScope?
    @State private var state: RivalsLoadState<RivalDetailResponse> = .loading
    @State private var songsById: [String: Song] = [:]
    @State private var quickLinks = QuickLinksController()
    @Environment(\.openProfile) private var openProfile
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools
    /// Pushes on the current tab: the accessory is outside the navigation stack, so a
    /// `NavigationLink` there could not push.
    @Environment(\.pushRoute) private var pushRoute
    private var visible = VisibleInstrumentsReader()

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - rivalId: Rival account ID.
    ///   - mode: `RivalCategory.key` selecting which bucket to show.
    ///   - name: Rival display name, if known.
    ///   - scope: Scope forwarded from the originating `RivalDetailScreen`.
    init(session: FestivalSession, rivalId: String, mode: String, name: String?, scope: RivalScope?) {
        self.session = session
        self.rivalId = rivalId
        self.mode = mode
        self.name = name
        self.scope = scope
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
        .festivalNavigationTitle(Self.modeTitles[mode] ?? "Rivalry")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) {
                    NavigationLink(value: AppRoute.player(accountId: rivalId, displayName: rivalName)) {
                        Label("View Profile", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("fst.rivalry.view-profile")
                }
            }
            QuickLinksToolbarItem(quickLinks)
        }
        // iPhone tab-bar accessory (issue #92): View Profile before Quick Links.
        .festivalPageTool(token: rivalName ?? "", order: PageToolOrder.primary) {
            Button {
                pushRoute?(.player(accountId: rivalId, displayName: rivalName))
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("fst.rivalry.view-profile")
        }
        .task(id: RivalryTaskKey(rivalId: rivalId, mode: mode, scope: scope)) { await load() }
        .task { await loadSongLookup() }
    }

    private var rivalName: String? {
        if case let .loaded(detail) = state { return detail.rival.displayName ?? name }
        return name
    }

    private struct RivalryTaskKey: Equatable {
        let rivalId: String
        let mode: String
        let scope: RivalScope?
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading rivalry")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Rivals Unavailable") { Task { await load() } }
        case let .loaded(detail):
            let category = RivalCategorization.categorize(detail.songs).first { $0.key == mode }
            if let category, !category.songs.isEmpty {
                ScrollView {
                    FestivalGlassSection {
                        ForEach(Array(category.songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song, rivalName: detail.rival.displayName ?? name ?? "Rival")
                                .quickLinkSection(QuickLinkSection(
                                    id: "\(song.songId):\(song.instrument):\(index)",
                                    title: song.title ?? song.songId,
                                    icon: Instrument(rawValue: song.instrument).map(QuickLinkIcon.instrument)
                                ))
                        }
                    }
                    .padding(16)
                    .festivalFadeIn(isLoaded: true)
                }
                .quickLinks(quickLinks, title: "Quick Links")
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
        do {
            state = .loaded(try await session.rivalDetail(
                forScope: scope, rivalId: rivalId, visibleInstruments: visible.instruments
            ))
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }

    private func loadSongLookup() async {
        guard let payload = try? await session.catalog() else { return }
        songsById = Dictionary(
            payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first }
        )
    }
}
