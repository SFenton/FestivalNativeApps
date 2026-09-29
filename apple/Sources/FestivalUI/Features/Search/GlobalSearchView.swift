import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Results

/// Global search results: a scope bar (All · Songs · Players · Bands) over one section per
/// kind, mirroring the web `SearchModal` (`.agents/controls/global-search/spec.md`).
///
/// The search field and scope bar sit on top; results or a centred message fill the rest. Every result is its own `List` row
/// holding one action (`.agents/platforms/apple/architecture.md`, "List rows hold one
/// action"). Placement per layout: `.agents/controls/global-search/ios.md`.
struct GlobalSearchResults: View {
    @Bindable var model: GlobalSearchModel
    let session: FestivalSession
    /// Navigate to a result (Song Detail, player profile or Statistics).
    let open: (AppRoute) -> Void

    var body: some View {
        VStack(spacing: 10) {
            GlobalSearchField(text: $model.query, prompt: GlobalSearch.prompt(for: model.scope))
                .padding(.horizontal, 16)
            // HIG scope bar: a segmented control, broadest scope first.
            Picker("Search Scope", selection: $model.scope) {
                ForEach(GlobalSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .accessibilityIdentifier("fst.global-search.scope")
            results
        }
        .padding(.top, 8)
        // A container element, so the identifier does not replace its children's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.global-search.surface")
        // Speak the result count once results settle; a newer query or scope cancels a
        // pending announcement, so fast typing speaks only the last count.
        .task(id: model.resultAnnouncement) {
            guard let text = model.resultAnnouncement else { return }
            do {
                try await Task.sleep(for: Self.announcementDelay)
            } catch {
                return
            }
            AccessibilityNotification.Announcement(text).post()
        }
    }

    /// Quiet period before announcing, so typing or a second section settling does not
    /// speak intermediate counts.
    static let announcementDelay: Duration = .milliseconds(700)

    /// The area below the scope bar: a centred message, or the result sections.
    @ViewBuilder private var results: some View {
        if model.scope == .bands {
            resultList { bandsUnavailable }
        } else if !model.hasQuery {
            centeredMessage("Enter at least two characters to search.")
        } else if model.scope == .all && allEmpty {
            centeredMessage("No results found.")
        } else {
            resultList {
                if model.scope.sections.contains(.songs) { songsSection }
                if model.scope.sections.contains(.players) { playersSection }
            }
        }
    }

    private func resultList<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        List {
            rows()
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// Vertically centred between the scope bar and the bottom safe area.
    private func centeredMessage(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(FestivalText.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("fst.global-search.hint")
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
                                MarqueeText(song.title)
                                    .foregroundStyle(BrandTokens.textPrimary)
                                    .lineLimit(1)
                                MarqueeText(song.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(FestivalText.primary)
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
                    // Each new result set fades in, staggered like the web list.
                    .festivalFadeIn(
                        isLoaded: true, index: model.songs.firstIndex(of: song) ?? Int.max
                    )
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
                            .foregroundStyle(FestivalText.primary)
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
                    .festivalFadeIn(
                        isLoaded: true,
                        index: model.players.firstIndex(of: player).map { $0 + model.songs.count }
                            ?? Int.max
                    )
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
                .foregroundStyle(FestivalText.primary)
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
                .foregroundStyle(FestivalText.primary)
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

/// Global search as a sheet: opened from the header Search button, ⌘K or ⌘F. A result dismisses the
/// sheet, then pushes on the presenting section.
struct GlobalSearchSheet: View {
    let session: FestivalSession
    /// Pushes the chosen route on the presenting section (passed directly: environment
    /// actions do not reliably reach sheet content, see `ProfileSelectionSheet`).
    let open: (AppRoute) -> Void
    @State private var model = GlobalSearchModel()
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
            #endif
            .task(id: model.runKey) { await model.search(session: session) }
            .toolbar {
                // Dismiss-only modal: trailing (modal standard, operator 2026-09-28).
                FestivalSheetCloseItem(identifier: "fst.global-search.close") { dismiss() }
            }
        }
    }
}

/// The sheet's own search field (not `.searchable`, whose active state hid the sheet's
/// title and Close and added a second X beside the field): magnifier, text, and a clear
/// button inside the field. Focused when the sheet opens.
struct GlobalSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .foregroundStyle(FestivalText.primary)
                .accessibilityLabel("Search songs, players and bands")
                .accessibilityIdentifier("fst.global-search.field")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FestivalText.deemphasized)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("fst.global-search.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.1), in: Capsule())
        .onAppear {
            Task { @MainActor in focused = true }
        }
    }
}

// MARK: - Toolbar button

/// The header Search button (every layout; operator 2026-09-28: search lives in the header).
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
    /// Add the header Search button to a pushed page's toolbar.
    ///
    /// - Returns: The page with a trailing Search item.
    func globalSearchToolbarItem() -> some View {
        modifier(GlobalSearchToolbarItem())
    }
}

/// Implementation of `globalSearchToolbarItem()`.
struct GlobalSearchToolbarItem: ViewModifier {
    @Environment(\.openGlobalSearch) private var openGlobalSearch
    @Environment(\.openProfile) private var openProfile
    @Environment(\.festivalSession) private var session
    /// A root screen pushed as a page (Leaderboards from the drawer) already ends its
    /// toolbar with `FestivalRootTrailingItems`, whose Search and avatar would otherwise
    /// appear twice.
    @State private var pageProvidesSearch = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FestivalRootTrailingProvidedKey.self) { pageProvidesSearch = $0 }
            .toolbar {
                if let openGlobalSearch, !pageProvidesSearch {
                    ToolbarItem(placement: .primaryAction) {
                        GlobalSearchButton { openGlobalSearch() }
                    }
                }
                // The profile avatar stays top-right on every pushed page too (operator
                // batch 7), after Search; root screens carry it in their own trailing items.
                if let session, !pageProvidesSearch {
                    ToolbarItem(placement: .primaryAction) {
                        RootProfileButton(session: session) { openProfile() }
                    }
                }
            }
    }
}
