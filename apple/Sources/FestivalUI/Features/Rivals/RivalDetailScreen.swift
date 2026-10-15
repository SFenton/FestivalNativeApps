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
///
/// The page is titled with the rival's name over the list it belongs to (owner, #604;
/// pattern `page-tools-and-nav-chrome` R23): "Rivals", or the chart's icon and "Lead
/// Rivals" when it was opened from a single-instrument list. The title is the list's
/// first item (``InstrumentPageTitle``, as on All Rivals) and pins to the bar once it
/// scrolls away.
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

    // MARK: - Title

    /// The single chart the page's list is about, whose icon leads the subtitle: a
    /// single-instrument song or leaderboard scope (``AllRivalsScreen/titleInstrument(for:)``).
    ///
    /// - Parameter scope: The route's scope, or nil (Find Rival, deep links).
    /// - Returns: The scope's one instrument, or nil.
    nonisolated static func subtitleInstrument(for scope: RivalScope?) -> Instrument? {
        scope.flatMap(AllRivalsScreen.titleInstrument(for:))
    }

    /// The subtitle under the rival's name (owner, #604): "{Instrument} Rivals" for a
    /// single-chart list (song or leaderboard rivals alike, like Android and Windows),
    /// else "Rivals" (Common, Combo, Pro Drums Family, no scope).
    ///
    /// - Parameter scope: The route's scope, or nil.
    /// - Returns: e.g. "Lead Rivals" or "Rivals".
    nonisolated static func subtitle(for scope: RivalScope?) -> String {
        subtitleInstrument(for: scope).map { "\($0.label) Rivals" } ?? "Rivals"
    }

    /// The page title: the rival's name, "Rival" until it is known.
    private var title: String { displayName ?? "Rival" }

    /// Whether the bar shows the compact title: once the in-list title has scrolled
    /// away, and in every state without an in-list title (loading, empty, failure,
    /// no profile), like All Rivals.
    private var showsPinnedTitle: Bool {
        guard session.selectedPlayer != nil, case let .loaded(detail) = state,
              !RivalCategorization.categorize(detail.songs).isEmpty else { return true }
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
                    instrument: nil, title: title, subtitle: Self.subtitle(for: scope),
                    subtitleInstrument: Self.subtitleInstrument(for: scope),
                    isShown: showsPinnedTitle, identifier: "fst.rival-detail.pinned-title"
                )
            }
            #endif
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
        .festivalTitleDisplayMode(.inline)
        // iPhone floating page tools (issues #92, #632): View Profile before Quick Links.
        .festivalPageTool(token: displayName ?? "", order: PageToolOrder.primary) {
            Button {
                pushRoute?(.player(accountId: rivalId, displayName: displayName))
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("fst.rival-detail.view-profile")
        }
        // Mac and iPad menu bar: Profile › View Rival's Profile (issue #633).
        .macProfilePageCommands(MacProfilePageCommands(viewRivalProfile: {
            pushRoute?(.player(accountId: rivalId, displayName: displayName))
        }))
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
            FestivalLoadingView(accessibilityLabel: "Loading rival detail", placement: .fill)
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
                    // The title sits 12 pt above the first card, like All Rivals.
                    VStack(alignment: .leading, spacing: 12) {
                        InstrumentPageTitle(
                            instrument: nil, title: title, subtitle: Self.subtitle(for: scope),
                            subtitleInstrument: Self.subtitleInstrument(for: scope), style: .header,
                            identifier: "fst.rival-detail.title"
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
                                .quickLinkSection(category.quickLinkSection)
                                .festivalFadeIn(isLoaded: true, index: index)
                            }
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
