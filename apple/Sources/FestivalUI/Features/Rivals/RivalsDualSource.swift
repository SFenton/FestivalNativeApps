import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Rivals dual-source region

/// The Rivals hub's and All Rivals' bottom region on the iPhone Duo inner display in
/// portrait: the rivalry detail for the rival selected in the list above
/// (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// Rows in the top region select instead of pushing (`dualSourceSelection`), so the
/// list stays put while this pane swaps rivals. Each themed category of shared songs
/// (Closest Battles, Almost Passed, …) is one swipeable card ending in its "View All"
/// button, as on `RivalDetailScreen`; the pane header's "View All" opens the full Rival
/// Detail page.
struct RivalDualDetailPane: View {
    let session: FestivalSession
    /// The selected `.rivalDetail` route, or nil before the first selection.
    let selection: AppRoute?

    private struct Selected: Equatable {
        let rivalId: String
        let name: String?
        let scope: RivalScope?
    }

    private var selected: Selected? {
        guard case let .rivalDetail(rivalId, name, scope) = selection else { return nil }
        return Selected(rivalId: rivalId, name: name, scope: scope)
    }

    var body: some View {
        if let selected, let selection {
            RivalDualDetailContent(
                session: session, rivalId: selected.rivalId, name: selected.name,
                scope: selected.scope, route: selection
            )
            .id(selection)
        } else {
            DualSourcePane("Rivalry", systemImage: "person.2.fill", identifier: "rivals.detail") {
                FestivalEmptyState(
                    "Select a Rival", systemImage: "hand.tap",
                    subtitle: "Choose a rival above to see where you're winning and losing."
                )
            }
            .accessibilityIdentifier("fst.dual.rivals.placeholder")
        }
    }
}

/// Loaded rivalry categories for one selected rival.
private struct RivalDualDetailContent: View {
    let session: FestivalSession
    let rivalId: String
    let name: String?
    let scope: RivalScope?
    let route: AppRoute

    @State private var state: RivalsLoadState<RivalDetailResponse> = .loading
    @State private var songsById: [String: Song] = [:]
    private var visible = VisibleInstrumentsReader()

    init(session: FestivalSession, rivalId: String, name: String?, scope: RivalScope?, route: AppRoute) {
        self.session = session
        self.rivalId = rivalId
        self.name = name
        self.scope = scope
        self.route = route
    }

    private var displayName: String {
        if case let .loaded(detail) = state, let loaded = detail.rival.displayName { return loaded }
        return name ?? "Rival"
    }

    var body: some View {
        DualSourcePane(displayName, systemImage: "person.2.fill", seeAll: route, identifier: "rivals.detail") {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading rival detail")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "dual.rival.\(rivalId)") { Task { await load() } }
                    .padding(.horizontal, 16)
            case let .loaded(detail):
                let categories = RivalCategorization.categorize(detail.songs)
                if categories.isEmpty {
                    FestivalEmptyState(
                        "No Shared Songs", systemImage: "music.note.list",
                        subtitle: "You and this rival don't share any scored songs yet."
                    )
                } else {
                    HorizontalCarousel("\(displayName) Rivalry", items: categories, minimumCardWidth: 300) { category in
                        RivalDualCategoryCard(
                            category: category, rivalId: rivalId, scope: scope,
                            rivalName: detail.rival.displayName ?? name ?? "Rival",
                            playerName: session.selectedPlayer?.displayName ?? "You",
                            songsById: songsById
                        )
                    }
                }
            }
        }
        .task { await load() }
        .task { await loadSongLookup() }
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

// MARK: - Category card

/// One themed rivalry category in the Duo pane: up to five song rows ending in the
/// shared purple "View All" CTA inside the card (`view-all-cta` R1–R4, #382), as on
/// `RivalDetailScreen`.
struct RivalDualCategoryCard: View {
    let category: RivalCategory
    let rivalId: String
    let scope: RivalScope?
    let rivalName: String
    let playerName: String
    let songsById: [String: Song]

    var body: some View {
        FestivalGlassSection(category.title, subtitle: category.subtitle) {
            ForEach(category.songs.prefix(5)) { song in
                let row = RivalSongRowContent(song: song, playerName: playerName, rivalName: rivalName)
                if let match = songsById[song.songId] {
                    NavigationLink(value: AppRoute.songDetail(match)) { row }
                } else {
                    row
                }
            }
        } action: {
            PurpleActionLink(
                title: "View All",
                route: .rivalry(rivalId: rivalId, mode: category.key, name: rivalName, scope: scope),
                identifier: "fst.dual.rivals.category.\(category.key).view-all",
                card: category.title
            )
        }
        // `.contain` keeps the rows' and the View All CTA's identifiers reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.dual.rivals.category.\(category.key)")
    }
}
