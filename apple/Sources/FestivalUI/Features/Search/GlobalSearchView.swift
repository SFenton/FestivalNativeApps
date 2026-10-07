import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Results

/// Global search results: a scope bar (All · Songs · Players · Bands) over song rows then
/// player rows, mirroring the web `SearchModal` (`.agents/controls/global-search/spec.md`).
/// No section titles (issue #299): the scope bar already names the scope.
///
/// The search field and scope bar sit on top; results, one centred spinner or a centred
/// message fill the rest. Every result is its own `List` row
/// holding one action (`.agents/platforms/apple/architecture.md`, "List rows hold one
/// action"). Placement per layout: `.agents/controls/global-search/ios.md`.
struct GlobalSearchResults: View {
    @Bindable var model: GlobalSearchModel
    let session: FestivalSession
    /// Navigate to a result (Song Detail, player profile or Statistics).
    let open: (AppRoute) -> Void
    /// Draw the sheet's own ``GlobalSearchField``; false where the Search tab's system
    /// `.searchable` field holds the query (issue #92) or its bottom field does (iPhone
    /// Duo inner display, issue #349).
    var showsField = true
    /// The Search tab shows ``BottomSearchField`` (iPhone Duo inner display, issue
    /// #349): the scope bar takes the field's column, so both share their edges (full
    /// width, or the trailing page across a book-pose fold), and result rows fade out
    /// above the field. False elsewhere: 16 pt margins, no bottom fade.
    var hasBottomField = false
    /// ``BottomSearchFieldPlacement/pageHinge(for:)`` for that column.
    var bottomFieldHinge: CGRect?
    /// The bottom field's top in ``bottomFieldSpace``, for the rows' fade.
    var bottomFieldTop: CGFloat?
    /// Coordinate space shared with the bottom field.
    var bottomFieldSpace = "fst.global-search.page"
    /// Result set whose staggered fade has finished: rows the List rebuilds after that
    /// (scrolled away and back) appear without a fade (issue #30).
    @State private var fadeSettledResults: [String]?

    var body: some View {
        VStack(spacing: 10) {
            if showsField {
                GlobalSearchField(
                    text: $model.query, prompt: GlobalSearch.prompt(for: model.scope),
                    submit: { model.submit() }
                )
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
            .modifier(GlobalSearchScopeColumn(
                alignsWithBottomField: hasBottomField, hinge: bottomFieldHinge
            ))
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

    /// The area below the scope bar: a centred hint, spinner or empty state, or the rows.
    @ViewBuilder private var results: some View {
        if !model.hasQuery {
            // Issue #299: the hint names what the scope searches, Bands included.
            centeredMessage(GlobalSearch.enterQueryHint(for: model.scope))
        } else if model.isSearching {
            // Issue #299: one spinner for the whole area, centred between the scope bar
            // and the field, keyboard or tab bar (HIG Progress indicators: "Display
            // progress indicators in a consistent location").
            searchingIndicator
        } else if isEmpty, let state = GlobalSearch.emptyState(scope: model.scope, query: model.query) {
            // Issue #99: a centred title and subtitle, not an inline row.
            GlobalSearchEmptyStateView(state: state)
        } else {
            resultList {
                if model.scope.sections.contains(.songs) { songRows }
                if model.scope.sections.contains(.players) { playerRows }
                if model.scope.sections.contains(.bands) { bandRows }
            }
        }
    }

    /// The one search spinner, centred in the results area.
    private var searchingIndicator: some View {
        FestivalLoadingView(accessibilityLabel: "Searching")
            .accessibilityIdentifier("fst.global-search.loading")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // iPhone Duo inner display: rows fade out above the bottom field and are not
        // drawn beneath it (scroll-edge R1, issue #349), as on Songs.
        .modifier(BottomSearchFieldFade(
            chromeTop: bottomFieldTop, enabled: hasBottomField, space: bottomFieldSpace
        ))
        // Each result set's fade window (web `SearchModal` `resetRush`): scrolling while
        // it staggers in fades the rest in together (#323).
        .festivalScrollFadeInScope(resetKey: resultFadeKey)
        .task(id: resultFadeKey) {
            let key = resultFadeKey
            await FadeStagger.settle(afterRevealing: key.count) { fadeSettledResults = key }
        }
    }

    /// Identity of the shown result set: each new set fades in once.
    private var resultFadeKey: [String] {
        model.songs.map(\.id) + model.players.map(\.accountId) + model.bands.map(\.id)
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
        let bandsEmpty = model.bandState == .ready && model.bands.isEmpty
        switch model.scope {
        case .all: return songsEmpty && playersEmpty && bandsEmpty
        case .songs: return songsEmpty
        case .players: return playersEmpty
        case .bands: return bandsEmpty
        }
    }

    // MARK: Songs

    /// Song rows, or why songs failed. Shown once every section the scope shows settled.
    @ViewBuilder private var songRows: some View {
        switch model.songState {
        case .idle, .loading:
            EmptyView()
        case let .failed(issue):
            failureRow(issue, section: .songs)
        case .ready where model.songs.isEmpty:
            // "All" hides an empty section (web parity); the Songs scope's empty state
            // is drawn centred by `results`.
            EmptyView()
        case .ready:
            Section {
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
                        .festivalCard(cornerRadius: 12)
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
            .modifier(ResultSectionChrome())
        }
    }

    // MARK: Players

    /// Player rows, or why players failed (a scrape freeze reads "Scores are updating",
    /// never "no players").
    @ViewBuilder private var playerRows: some View {
        switch model.playerState {
        case .idle, .loading:
            EmptyView()
        case let .failed(issue):
            failureRow(issue, section: .players)
        case .ready where model.players.isEmpty:
            // "All" hides an empty section, like the web (issue #99); the Players scope
            // and an all-empty "All" show the centred empty state instead.
            EmptyView()
        case .ready:
            Section {
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
                            .festivalCard(cornerRadius: 12)
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
            .modifier(ResultSectionChrome())
        }
    }

    /// A failed section's message without Retry (issue #299): the keyboard's Search key
    /// re-runs the query, and a scrape freeze still retries on its own countdown.
    ///
    /// - Parameters:
    ///   - issue: Classified failure.
    ///   - section: `.songs`, `.players` or `.bands`.
    private func failureRow(_ issue: ServiceIssue, section: GlobalSearchScope) -> some View {
        Section {
            ServiceStatusInline(
                issue, scope: "global-search.\(section.rawValue)", showsRetryButton: false,
                fallbackTitle: GlobalSearch.unavailableTitle(for: section)
            ) { model.retry() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fst.global-search.\(section.rawValue)-error")
            .listRowInsets(Self.cardInsets)
        }
        .modifier(ResultSectionChrome())
    }

    // MARK: Bands

    /// Band cards (web `PlayerBandCard`: member names, instruments, appearance count), or
    /// why bands failed (issue #320). A result opens that band's page; native apps have
    /// no selected band profile, so the web's "selected band opens Statistics" never applies.
    @ViewBuilder private var bandRows: some View {
        switch model.bandState {
        case .idle, .loading:
            EmptyView()
        case let .failed(issue):
            failureRow(issue, section: .bands)
        case .ready where model.bands.isEmpty:
            // "All" hides an empty section; the Bands scope shows the centred empty state.
            EmptyView()
        case .ready:
            Section {
                ForEach(Array(model.bands.enumerated()), id: \.element.id) { offset, band in
                    PlayerBandRow(
                        entry: band, open: open,
                        identifier: "fst.global-search.result.band"
                    )
                    .listRowInsets(Self.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .festivalFadeIn(
                        isLoaded: true,
                        index: resultFadeIndex(offset + model.songs.count + model.players.count)
                    )
                }
            }
            .modifier(ResultSectionChrome())
        }
    }

    // MARK: Building blocks

    /// "artist · year · duration", like a Songs row.
    static func subtitle(for song: Song) -> String {
        var text = song.artist
        if let year = song.year, year != 0 { text += " · \(year)" }
        if let duration = song.formattedDuration { text += " · \(duration)" }
        return text
    }

}

/// Clear, separator-free chrome for a run of result cards (no heading, issue #299).
private struct ResultSectionChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
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
///
/// Also the iPhone Duo bottom search field (``BottomSearchField``): Songs' "Filter
/// Songs" (issue #333), which floats over the list on the shared control capsule and
/// waits for a tap, and the Search tab's field on the inner display (issue #349).
struct GlobalSearchField: View {
    /// The field's backing.
    enum Surface {
        /// A faint capsule inside a sheet's header.
        case inline
        /// The shared floating-control capsule over scrolling rows (surface-materials R1).
        case floating
    }

    @Binding var text: String
    let prompt: String
    /// Spoken name of the field.
    var accessibilityLabel = "Search songs, players and bands"
    /// UI-test identifier of the text field.
    var identifier = "fst.global-search.field"
    /// UI-test identifier of the clear button.
    var clearIdentifier = "fst.global-search.clear"
    /// Focus the field (keyboard up) when it appears, and again whenever this turns on
    /// (the iPhone Duo Search tab passes its selection, so re-choosing the tab focuses it).
    var focusesOnAppear = true
    /// The field's backing.
    var surface = Surface.inline
    /// Return/Search was pressed (re-runs a failed or empty search, issue #299).
    var submit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(submit)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .foregroundStyle(FestivalText.primary)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(surface == .floating ? .isSearchField : [])
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FestivalText.deemphasized)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier(clearIdentifier)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .modifier(GlobalSearchFieldSurface(surface: surface))
        .onAppear {
            guard focusesOnAppear else { return }
            Task { @MainActor in focused = true }
        }
        .onChange(of: focusesOnAppear) { _, focuses in
            if focuses { focused = true }
        }
    }
}

/// The scope bar's horizontal margins: the standard 16 pt, or the iPhone Duo bottom
/// search field's column so the bar and the field share their edges (issue #349).
private struct GlobalSearchScopeColumn: ViewModifier {
    let alignsWithBottomField: Bool
    let hinge: CGRect?

    func body(content: Content) -> some View {
        if alignsWithBottomField {
            content.bottomSearchFieldColumn(hinge: hinge)
        } else {
            content.padding(.horizontal, 16)
        }
    }
}

/// The backing for a ``GlobalSearchField/Surface``.
private struct GlobalSearchFieldSurface: ViewModifier {
    let surface: GlobalSearchField.Surface

    func body(content: Content) -> some View {
        switch surface {
        case .inline:
            content.background(Color.white.opacity(0.1), in: Capsule())
        case .floating:
            content.festivalCardCapsule()
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
    /// (issue #92). With the iPhone tab-bar accessory only Profile is added; the bell is
    /// in the accessory (issue #300).
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
    /// Set where the tab-bar accessory draws the bell instead (issue #92); Profile stays
    /// in the bar (issue #300).
    @Environment(\.pageToolsRegistry) private var pageTools

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FestivalRootTrailingProvidedKey.self) { pageProvidesAccount = $0 }
            .toolbar {
                // The bell and profile stay top-right on every pushed page too (operator
                // batch 7, issue #92); root screens carry them in their own trailing items.
                // This outer modifier's items are laid out before the page's, so on iOS
                // they are the only `.primaryAction` items (pinned to the trailing edge),
                // in their own glass group after the page's tools (issue #85). With the
                // iPhone tab-bar accessory the bell is there and Profile stays here (#300).
                if let session, !pageProvidesAccount, !shellOwnsGlobalToolbar {
                    #if os(iOS)
                    if #available(iOS 26.0, *) {
                        if RootChromeTrailingGroups.separatesAccount(chrome: layout.sectionChrome) {
                            ToolbarSpacer(.fixed, placement: .primaryAction)
                        }
                    }
                    if session.selectedPlayer != nil, pageTools == nil {
                        ToolbarItem(placement: .primaryAction) {
                            NotificationsButton(session: session, pushRoute: pushRoute)
                        }
                    }
                    // The monogram hides its item's glass ring (issue #311).
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .primaryAction) {
                            RootProfileButton(session: session) { profileButtonAction() }
                        }
                        .profileItemBackground(.resolve(
                            displayName: session.selectedPlayer?.displayName,
                            chrome: layout.sectionChrome
                        ))
                    } else {
                        ToolbarItem(placement: .primaryAction) {
                            RootProfileButton(session: session) { profileButtonAction() }
                        }
                    }
                    #else
                    ToolbarItem(placement: .primaryAction) {
                        RootProfileButton(session: session) { profileButtonAction() }
                    }
                    #endif
                }
            }
    }
}
