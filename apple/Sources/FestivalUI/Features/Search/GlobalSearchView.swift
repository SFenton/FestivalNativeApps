import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Results

/// Global search results: a scope bar (All · Songs · Players · Bands) over one section per
/// kind, mirroring the web `SearchModal` (`.agents/controls/global-search/spec.md`).
///
/// The search field belongs to ``GlobalSearchSheet``. Every result is its own `List` row
/// holding one action (`.agents/platforms/apple/architecture.md`, "List rows hold one
/// action"). Placement per layout: `.agents/controls/global-search/ios.md`.
struct GlobalSearchResults: View {
    @Bindable var model: GlobalSearchModel
    let session: FestivalSession
    /// Navigate to a result (Song Detail, player profile or Statistics).
    let open: (AppRoute) -> Void

    var body: some View {
        List {
            Section {
                // HIG scope bar: a segmented control, broadest scope first.
                Picker("Search Scope", selection: $model.scope) {
                    ForEach(GlobalSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("fst.global-search.scope")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if model.scope == .bands {
                bandsUnavailable
            } else if !model.hasQuery {
                messageSection("Enter at least two characters to search.")
            } else {
                if model.scope.sections.contains(.songs) { songsSection }
                if model.scope.sections.contains(.players) { playersSection }
                if model.scope == .all && allEmpty {
                    messageSection("No results found.")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("fst.global-search.surface")
    }

    /// Both live sections finished with nothing to show.
    private var allEmpty: Bool {
        model.songState == .ready && model.songs.isEmpty
            && model.playerState == .ready && model.players.isEmpty
    }

    // MARK: Songs

    /// Songs appear as soon as the catalogue filter runs; they never wait for players.
    @ViewBuilder private var songsSection: some View {
        let single = model.scope == .songs
        switch model.songState {
        case .idle, .loading:
            if single { section("Songs", id: "songs") { loadingRow("Searching Songs") } }
        case let .failed(issue):
            section("Songs", id: "songs") {
                ServiceStatusInline(issue, scope: "global-search.songs") { model.retry() }
                    .accessibilityIdentifier("fst.global-search.retry")
            }
        case .ready where model.songs.isEmpty:
            if single { messageSection("No songs found.") }
        case .ready:
            section("Songs", id: "songs") {
                ForEach(model.songs) { song in
                    Button {
                        open(.songDetail(song))
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkTile(raw: song.albumArt, session: session, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .foregroundStyle(BrandTokens.textPrimary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(BrandTokens.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("fst.global-search.result.song")
                }
            }
        }
    }

    // MARK: Players

    @ViewBuilder private var playersSection: some View {
        switch model.playerState {
        case .idle, .loading:
            section("Players", id: "players") {
                loadingRow("Searching Players")
                    .accessibilityIdentifier("fst.global-search.players-loading")
            }
        case let .failed(issue):
            // A scrape freeze reads "Scores are updating", never "no players".
            section("Players", id: "players") {
                ServiceStatusInline(issue, scope: "global-search.players") { model.retry() }
                    .accessibilityIdentifier("fst.global-search.retry")
            }
        case .ready where model.players.isEmpty:
            // An empty envelope can be a server timeout, so it offers Retry too.
            section("Players", id: "players") {
                Button {
                    model.retry()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No players found.")
                            .foregroundStyle(BrandTokens.textSecondary)
                        Text("Retry")
                            .foregroundStyle(BrandTokens.accentBlue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("No players found. Retry")
                .accessibilityIdentifier("fst.global-search.retry")
            }
        case .ready:
            section("Players", id: "players") {
                PlayerSearchResultRows(model.players) { player in
                    Button {
                        // Web: the selected profile opens Statistics, others their page.
                        if session.selectedPlayer?.accountId == player.accountId {
                            open(.statistics)
                        } else {
                            open(.player(accountId: player.accountId, displayName: player.displayName))
                        }
                    } label: {
                        Label(player.displayName, systemImage: "person.crop.circle")
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.displayName)
                    .accessibilityIdentifier("fst.global-search.result.player")
                }
            }
        }
    }

    // MARK: Bands

    /// Band search is never sent (its GET writes); the scope explains that instead.
    private var bandsUnavailable: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.3")
                        .accessibilityHidden(true)
                    Text("Band search isn't available in the app yet. The service's band search "
                        + "can change stored band data, so the app won't call it until a "
                        + "read-only version exists. Browse bands in Leaderboards → Band "
                        + "Rankings, or from a player's Bands.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(BrandTokens.textSecondary)
                Button("Band Rankings") {
                    open(.bandRankings(bandType: "Band_Duets"))
                }
                .buttonStyle(.borderless)
                .tint(BrandTokens.accentBlue)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.global-search.bands-unavailable")
        } header: {
            FestivalSectionHeader("Bands")
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    // MARK: Building blocks

    private func section<Rows: View>(
        _ title: String, id: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        Section {
            rows()
        } header: {
            // On the heading: an identifier on the `Section` would override its rows'.
            FestivalSectionHeader(title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.global-search.section.\(id)")
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func messageSection(_ text: String) -> some View {
        Section {
            Text(text)
                .foregroundStyle(BrandTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fst.global-search.hint")
        }
        .listRowBackground(Color.clear)
    }

    private func loadingRow(_ label: String) -> some View {
        HStack {
            Spacer(minLength: 0)
            FestivalLoadingView(accessibilityLabel: label)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Sheet

/// Global search as a sheet: opened from the tab-bar accessory's Search pill (iOS 26.1+
/// iPhone), the toolbar Search button (other layouts), ⌘K or ⌘F. A result dismisses the
/// sheet, then pushes on the presenting section.
struct GlobalSearchSheet: View {
    let session: FestivalSession
    /// Pushes the chosen route on the presenting section (passed directly: environment
    /// actions do not reliably reach sheet content, see `ProfileSelectionSheet`).
    let open: (AppRoute) -> Void
    @State private var model = GlobalSearchModel()
    @State private var fieldPresented = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GlobalSearchResults(model: model, session: session) { route in
                dismiss()
                open(route)
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.query, isPresented: $fieldPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(GlobalSearch.prompt(for: model.scope))
            )
            #else
            .searchable(
                text: $model.query, isPresented: $fieldPresented,
                prompt: Text(GlobalSearch.prompt(for: model.scope))
            )
            #endif
            .task(id: model.runKey) { await model.search(session: session) }
            .toolbar {
                // Dismiss-only modal: trailing (modal standard, operator 2026-09-28).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("fst.global-search.close")
                }
            }
        }
    }
}

// MARK: - Toolbar button

/// Toolbar Search button where the tab accessory is unavailable (iOS 17–26.0, iPhone Duo
/// rail, iPad, Mac).
struct GlobalSearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Search", systemImage: "magnifyingglass")
        }
        .tint(BrandTokens.textPrimary)
        .accessibilityHint("Searches songs, players and bands")
        .accessibilityIdentifier("fst.global-search.open")
    }
}

/// Environment action that opens the global search sheet (set by `FestivalRootView`).
struct OpenGlobalSearchAction {
    let handler: @MainActor () -> Void

    /// Present global search.
    @MainActor func callAsFunction() { handler() }
}

extension EnvironmentValues {
    /// Opens the global search sheet; nil outside the app shell (previews, hosted tests).
    @Entry var openGlobalSearch: OpenGlobalSearchAction? = nil
}

// MARK: - Toolbar item for pushed pages

extension View {
    /// Add the Search button to a pushed page's toolbar where the tab accessory (which
    /// already offers Search on every page) is unavailable.
    ///
    /// - Returns: The page with a trailing Search item when needed.
    func globalSearchToolbarItem() -> some View {
        modifier(GlobalSearchToolbarItem())
    }
}

/// Implementation of `globalSearchToolbarItem()`.
struct GlobalSearchToolbarItem: ViewModifier {
    @Environment(\.openGlobalSearch) private var openGlobalSearch
    @Environment(\.isTabAccessoryAvailable) private var accessoryAvailable

    func body(content: Content) -> some View {
        content.toolbar {
            if let openGlobalSearch, !accessoryAvailable {
                ToolbarItem(placement: .primaryAction) {
                    GlobalSearchButton { openGlobalSearch() }
                }
            }
        }
    }
}
