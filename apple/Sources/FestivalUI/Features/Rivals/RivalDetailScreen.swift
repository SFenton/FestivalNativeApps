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
/// React Router `location.state`. Native `AppRoute.rivalDetail` carries the same
/// information directly as a typed `RivalScope?` payload, so this screen (and any
/// other way of reaching this route — deep link, restored state, `DebugLaunchRoute`)
/// always sees the same scope a tap would have stashed. A `nil` scope (no context
/// at all) reads the web's Settings scopes with `allowLiveFallback=true`
/// (`RivalDetailScopes`), like the web's Find Rival.
struct RivalDetailScreen: View {
    let session: FestivalSession
    let rivalId: String
    let name: String?
    /// The scope the route carried (it may name an experimental metric).
    let routeScope: RivalScope?
    @AppStorage(ExperimentalRanks.storageKey) private var experimentalRanks = ExperimentalRanks.defaultValue
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
    ///   - name: Rival display name, if known.
    ///   - scope: Scope that produced the tapped row, or `nil` when reached
    ///     without one.
    init(session: FestivalSession, rivalId: String, name: String?, scope: RivalScope?) {
        self.session = session
        self.rivalId = rivalId
        self.name = name
        self.routeScope = scope
    }

    /// The scope in effect: a leaderboard scope's experimental metric reads Total
    /// Score while Settings › Experimental Ranks is off (pattern `experimental-ranks`).
    private var scope: RivalScope? {
        routeScope?.coerced(experimentalRanks: experimentalRanks)
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                content
            }
        }
        .festivalNavigationTitle(displayName ?? "Rival")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) {
                    NavigationLink(value: AppRoute.player(accountId: rivalId, displayName: displayName)) {
                        Label("View Profile", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("fst.rival-detail.view-profile")
                }
            }
            QuickLinksToolbarItem(quickLinks)
        }
        // iPhone tab-bar accessory (issue #92): View Profile before Quick Links.
        .festivalPageTool(token: displayName ?? "", order: PageToolOrder.primary) {
            Button {
                pushRoute?(.player(accountId: rivalId, displayName: displayName))
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("fst.rival-detail.view-profile")
        }
        .task(id: RivalDetailTaskKey(rivalId: rivalId, scope: scope)) { await load() }
        .task { await loadSongLookup() }
    }

    private var displayName: String? {
        if case let .loaded(detail) = state { return detail.rival.displayName ?? name }
        return name
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading rival detail")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Rivals Unavailable") { Task { await load() } }
        case let .loaded(detail):
            let categories = RivalCategorization.categorize(detail.songs)
            if categories.isEmpty {
                FestivalEmptyState(
                    "No Shared Songs", systemImage: "music.note.list",
                    subtitle: "You and this rival don't share any scored songs yet."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                            // The card ends with its "View All" inside it, like the Rivals
                            // hub's View All Rivals (view-all-cta R1; #321, #382).
                            FestivalGlassSection(category.title, subtitle: category.subtitle) {
                                ForEach(category.songs.prefix(5)) { song in
                                    songRow(song, rivalName: detail.rival.displayName ?? name ?? "Rival")
                                }
                            } action: {
                                PurpleActionLink(
                                    title: "View All",
                                    route: .rivalry(
                                        rivalId: rivalId, mode: category.key,
                                        name: detail.rival.displayName ?? name, scope: scope
                                    ),
                                    identifier: "fst.rival-detail.category.\(category.key).view-all",
                                    card: category.title
                                )
                            }
                            .padding(.horizontal, 16)
                            .quickLinkSection(
                                id: "rival-category:\(category.key)", title: category.title
                            )
                            .festivalFadeIn(isLoaded: true, index: index)
                        }
                    }
                    .padding(.vertical, 12)
                    // Scrolling or a Quick Links jump while the cards stagger in fades
                    // the rest in together (#323).
                    .festivalFadeInScope()
                }
                .quickLinks(quickLinks, title: "Quick Links")
            }
        }
    }

    @ViewBuilder
    private func songRow(_ song: RivalSongComparison, rivalName: String) -> some View {
        let match = songsById[song.songId]
        let row = RivalSongRowContent(
            song: song, albumArt: match?.albumArt, session: session,
            playerName: session.selectedPlayer?.displayName ?? "You", rivalName: rivalName
        )
        if let match {
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

/// Reload key for `RivalDetailScreen`'s detail read: both the rival and the
/// scope that should be queried for it.
private struct RivalDetailTaskKey: Equatable {
    let rivalId: String
    let scope: RivalScope?
}
