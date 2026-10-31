import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalryScreen

/// `/rivals/:rivalId/rivalry?mode=` — full song list for one `RivalCategorization`
/// bucket (e.g. "Closest Battles"), reached from a `RivalDetailScreen` category's "View All".
///
/// `scope` is forwarded unchanged from the `.rivalDetail` push that reached this
/// screen (native `AppRoute` carries it directly; there is no bridge to re-stash).
///
/// The page is one flat list of songs, so it offers no Quick Links: a chooser with
/// one entry per row only repeats the list (owner, #545; pattern `quick-links` R3).
///
/// The page is titled with the section over the rival's name (owner, #604; pattern
/// `page-tools-and-nav-chrome` R23), as the list's first item (``InstrumentPageTitle``,
/// like Rival Detail and All Rivals), and that title pins to the bar once it scrolls away.
struct RivalryScreen: View {
    let session: FestivalSession
    let rivalId: String
    let mode: String
    let name: String?
    /// The scope the route carried (it may name an experimental metric).
    let routeScope: RivalScope?
    @AppStorage(ExperimentalRanks.storageKey) private var experimentalRanks = ExperimentalRanks.defaultValue
    @State private var state: RivalsLoadState<RivalDetailResponse> = .loading
    @State private var songsById: [String: Song] = [:]
    /// The in-list title has scrolled under the bar: the bar shows the compact title.
    @State private var titleHidden = false
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set where page tools float above the iPhone tab bar (issues #92, #632).
    @Environment(\.pageToolsRegistry) private var pageTools
    /// Pushes on the current tab: the floating tools are outside the navigation stack, so a
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
        self.routeScope = scope
    }

    /// The scope in effect: a leaderboard scope's experimental metric reads Total
    /// Score while Settings › Experimental Ranks is off (pattern `experimental-ranks`).
    private var scope: RivalScope? {
        routeScope?.coerced(experimentalRanks: experimentalRanks)
    }

    /// Section names by `RivalCategory.key`; `nonisolated` so ``title(for:)`` (also read by the UIKit port) can use it.
    private nonisolated static let modeTitles: [String: String] = [
        "closest_battles": "Closest Battles",
        "almost_passed": "Almost Passed",
        "slipping_away": "Slipping Away",
        "barely_winning": "Barely Winning",
        "pulling_forward": "Pulling Forward",
        "dominating_them": "Dominating Them",
    ]

    // MARK: - Title

    /// The page title: the section, e.g. "Closest Battles".
    ///
    /// - Parameter mode: `RivalCategory.key` from the route.
    /// - Returns: The section's name, or "Rivalry" for an unknown key.
    nonisolated static func title(for mode: String) -> String {
        modeTitles[mode] ?? "Rivalry"
    }

    /// The subtitle under the section (owner, #604): the rival's name, "Rival" until
    /// it is known.
    ///
    /// - Parameter rivalName: The rival's display name, if known.
    /// - Returns: The name, or "Rival".
    nonisolated static func subtitle(rivalName: String?) -> String {
        rivalName ?? "Rival"
    }

    private var title: String { Self.title(for: mode) }
    private var subtitle: String { Self.subtitle(rivalName: rivalName) }

    /// Whether the bar shows the compact title: once the in-list title has scrolled
    /// away, and in every state without an in-list title (loading, empty, failure,
    /// no profile), like All Rivals.
    private var showsPinnedTitle: Bool {
        guard session.selectedPlayer != nil, case let .loaded(detail) = state,
              RivalCategorization.categorize(detail.songs).contains(where: { $0.key == mode && !$0.songs.isEmpty })
        else { return true }
        return titleHidden
    }

    // MARK: - Body

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                content
            }
        }
        .festivalNavigationTitle(title)
        .festivalBackground(.carousel, session: session)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsPinnedTitle)
        .toolbar {
            #if os(iOS)
            // The iPhone Duo vertical bar keeps the system title instead (R14).
            if InstrumentPageTitleToolbarItem.pinsTitle(in: layout.sectionChrome) {
                InstrumentPageTitleToolbarItem(
                    instrument: nil, title: title, subtitle: subtitle,
                    isShown: showsPinnedTitle, identifier: "fst.rivalry.pinned-title"
                )
            }
            #endif
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) {
                    NavigationLink(value: AppRoute.player(accountId: rivalId, displayName: rivalName)) {
                        Label("View Profile", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("fst.rivalry.view-profile")
                }
            }
        }
        .festivalTitleDisplayMode(.inline)
        // iPhone floating page tools (issues #92, #632): View Profile is the page's only tool.
        .festivalPageTool(token: rivalName ?? "", order: PageToolOrder.primary) {
            Button {
                pushRoute?(.player(accountId: rivalId, displayName: rivalName))
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("fst.rivalry.view-profile")
        }
        // Mac and iPad menu bar: Profile › View Rival's Profile (issue #633).
        .macProfilePageCommands(MacProfilePageCommands(viewRivalProfile: {
            pushRoute?(.player(accountId: rivalId, displayName: rivalName))
        }))
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
            FestivalLoadingView(accessibilityLabel: "Loading rivalry", placement: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Rivals Unavailable") { Task { await load() } }
        case let .loaded(detail):
            let category = RivalCategorization.categorize(detail.songs).first { $0.key == mode }
            if let category, !category.songs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        InstrumentPageTitle(
                            instrument: nil, title: title, subtitle: subtitle, style: .header,
                            identifier: "fst.rivalry.title"
                        )
                        .padding(.horizontal, 16)
                        .festivalFadeInOnAppear()
                        .onGeometryChange(for: Bool.self) { proxy in
                            SongDetailPinnedTitlePolicy.isHeroHidden(
                                titleMaxY: proxy.frame(in: .scrollView).maxY
                            )
                        } action: { hidden in
                            titleHidden = hidden
                        }
                        FestivalGlassSection {
                            ForEach(category.songs) { song in
                                songRow(song, rivalName: detail.rival.displayName ?? name ?? "Rival")
                            }
                        }
                        .padding(.horizontal, 16)
                        .festivalFadeIn(isLoaded: true)
                    }
                    .padding(.vertical, 12)
                }
            } else {
                FestivalEmptyState(
                    "No Songs", systemImage: "music.note.list",
                    subtitle: "There are no songs in this category."
                )
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
