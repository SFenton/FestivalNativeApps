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
    /// Draw the sheet's own ``GlobalSearchField``; false where the Search tab's system
    /// `.searchable` field holds the query (issue #92).
    var showsField = true
    /// Result set whose staggered fade has finished: rows the List rebuilds after that
    /// (scrolled away and back) appear without a fade (issue #30).
    @State private var fadeSettledResults: [String]?

    var body: some View {
        VStack(spacing: 10) {
            if showsField {
                GlobalSearchField(text: $model.query, prompt: GlobalSearch.prompt(for: model.scope))
                    .padding(.horizontal, 16)
            }
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
        } else if isEmpty, let state = GlobalSearch.emptyState(scope: model.scope, query: model.query) {
            // Issue #99: a centred title, subtitle and Retry, not an inline row.
            GlobalSearchEmptyStateView(state: state) { model.retry() }
        } else {
            resultList {
                if model.scope.sections.contains(.songs) { songsSection }
                if model.scope.sections.contains(.players) { playersSection }
            }
        }
    }

    /// Web `SearchModal`: every result is its own frosted card, 4pt apart, on the
    /// sheet's standard 16pt margins (batch 6.4 / 6.5: no inset-grouped double inset).
    private func resultList<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        List {
            rows()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .task(id: resultFadeKey) {
            let key = resultFadeKey
            await FadeStagger.settle(afterRevealing: key.count) { fadeSettledResults = key }
        }
    }

    /// Identity of the shown result set: each new set fades in once.
    private var resultFadeKey: [String] {
        model.songs.map(\.id) + model.players.map(\.accountId)
    }

    /// Stagger index for a result row, or -1 (instant) once its result set has settled.
    ///
    /// - Parameter index: Row position across both sections, or nil when unknown.
    /// - Returns: Index to hand `festivalFadeIn(isLoaded:index:)`.
    private func resultFadeIndex(_ index: Int?) -> Int {
        FadeStagger.index(index ?? Int.max, settled: fadeSettledResults == resultFadeKey)
    }

    /// One result card's List row chrome.
    private static let cardInsets = EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)

    /// Vertically centred between the scope bar and the bottom safe area.
    private func centeredMessage(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(FestivalText.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("fst.global-search.hint")
    }

    /// Every section the scope shows finished with nothing to show.
    private var isEmpty: Bool {
        let songsEmpty = model.songState == .ready && model.songs.isEmpty
        let playersEmpty = model.playerState == .ready && model.players.isEmpty
        switch model.scope {
        case .all: return songsEmpty && playersEmpty
        case .songs: return songsEmpty
        case .players: return playersEmpty
        case .bands: return false
        }
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
            // "All" hides an empty section (web parity); the Songs scope's empty state
            // is drawn centred by `results`.
            EmptyView()
        case .ready:
            section("Songs", id: "songs") {
                ForEach(model.songs) { song in
                    Button {
                        open(.songDetail(song))
                    } label: {
                        // Same art, fonts and padding as a Songs row (batch 6.3).
                        HStack(spacing: 12) {
                            ArtworkTile(raw: song.albumArt, session: session, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                MarqueeText(song.title, font: .headline)
                                    .foregroundStyle(BrandTokens.textPrimary)
                                MarqueeText(Self.subtitle(for: song), font: .subheadline)
                                    .foregroundStyle(FestivalText.primary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .festivalGlass(.card, cornerRadius: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .listRowInsets(Self.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("fst.global-search.result.song")
                    // Each new result set fades in, staggered like the web list.
                    .festivalFadeIn(
                        isLoaded: true, index: resultFadeIndex(model.songs.firstIndex(of: song))
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
            // "All" hides an empty section, like the web (issue #99); the Players scope
            // and an all-empty "All" show the centred empty state with Retry instead.
            EmptyView()
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
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(.horizontal, 16)
                            .festivalGlass(.card, cornerRadius: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.displayName)
                    .listRowInsets(Self.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("fst.global-search.result.player")
                    .festivalFadeIn(
                        isLoaded: true,
                        index: resultFadeIndex(
                            model.players.firstIndex(of: player).map { $0 + model.songs.count }
                        )
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

    /// "artist · year · duration", like a Songs row.
    static func subtitle(for song: Song) -> String {
        var text = song.artist
        if let year = song.year, year != 0 { text += " · \(year)" }
        if let duration = song.formattedDuration { text += " · \(duration)" }
        return text
    }

    private func section<Rows: View>(
        _ title: String, id: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        Section {
            // Web: a small uppercase heading row, not a pinned header band. The
            // identifier sits on the heading (on the `Section` it would override rows').
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.global-search.section.\(id)")
                .listRowInsets(Self.cardInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            rows()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
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

/// Global search as a sheet, for the Mac shell (⌘K / ⌘F). A result dismisses the sheet,
/// then pushes on the presenting section. iOS uses the phone Search tab or the iPad
/// sidebar's Search row instead (``GlobalSearchTab``, issue #92), menu-bar shortcuts
/// included.
struct GlobalSearchSheet: View {
    let session: FestivalSession
    /// Pushes the chosen route on the presenting section (passed directly: environment
    /// actions do not reliably reach sheet content, see `ProfileSelectionSheet`).
    let open: (AppRoute) -> Void
    @State private var model = GlobalSearchModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FestivalModal("Search", closeIdentifier: "fst.global-search.close") {
            GlobalSearchResults(model: model, session: session) { route in
                dismiss()
                open(route)
            }
            .task(id: model.runKey) { await model.search(session: session) }
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
    /// Visible and spoken title ("Search"; the Mac toolbar says "Search Festival").
    var title = "Search"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "magnifyingglass")
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

// MARK: - Account items for pushed pages

extension View {
    /// Add the account group (bell when a profile is selected, then the profile button)
    /// to a pushed page's toolbar, so the persistent top bar matches its tab root
    /// (issue #92).
    ///
    /// - Returns: The page with the trailing account items.
    func pageTrailingItems() -> some View {
        modifier(PageTrailingItems())
    }
}

/// Implementation of `pageTrailingItems()`.
struct PageTrailingItems: ViewModifier {
    @Environment(\.profileButtonAction) private var profileButtonAction
    @Environment(\.festivalSession) private var session
    @Environment(\.pushRoute) private var pushRoute
    @Environment(\.deviceLayout) private var layout
    /// A root screen pushed as a page (Leaderboards from the drawer) already ends its
    /// toolbar with `FestivalRootTrailingItems`, whose bell and avatar would otherwise
    /// appear twice.
    @State private var pageProvidesAccount = false
    /// The macOS shell shows the account items once for the whole window.
    @Environment(\.shellOwnsGlobalToolbar) private var shellOwnsGlobalToolbar
    /// Set where the tab-bar accessory draws the account group instead (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FestivalRootTrailingProvidedKey.self) { pageProvidesAccount = $0 }
            .toolbar {
                // The bell and profile stay top-right on every pushed page too (operator
                // batch 7, issue #92); root screens carry them in their own trailing items.
                // This outer modifier's items are laid out before the page's, so on iOS
                // they are the only `.primaryAction` items (pinned to the trailing edge),
                // in their own glass group after the page's tools (issue #85).
                if let session, !pageProvidesAccount, !shellOwnsGlobalToolbar, pageTools == nil {
                    #if os(iOS)
                    if #available(iOS 26.0, *) {
                        if RootChromeTrailingGroups.separatesAccount(chrome: layout.sectionChrome) {
                            ToolbarSpacer(.fixed, placement: .primaryAction)
                        }
                    }
                    if session.selectedPlayer != nil {
                        ToolbarItem(placement: .primaryAction) {
                            NotificationsButton(session: session, pushRoute: pushRoute)
                        }
                    }
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        RootProfileButton(session: session) { profileButtonAction() }
                    }
                }
            }
    }
}
