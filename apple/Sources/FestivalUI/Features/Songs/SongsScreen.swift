import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

#if DEBUG
/// Screenshot-only hook: `FST_DEBUG_SONG=<title or songId>` auto-pushes that
/// song's Detail once the catalogue loads, so `tools/ios_sim.py shot` can
/// capture Song Detail without manual navigation. Never compiled into Release.
enum FestivalDebugLaunch {
    static var songTitleOrId: String? {
        let value = ProcessInfo.processInfo.environment["FST_DEBUG_SONG"]
        return (value?.isEmpty ?? true) ? nil : value
    }
}
#endif

// MARK: - Song catalogue

/// Native virtualized catalogue with explicit loading, error and offline states.
struct SongsScreen: View {
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    let highContrast: Bool
    let isVisible: Bool
    let openShop: (() -> Void)?
    @State private var state: LoadState
    @Binding private var searchText: String
    @Binding private var settledSearch: String
    @Binding private var instrument: Instrument?
    @Binding private var navigationNotice: String?
    @State private var refreshFailure: String?
    @State private var shopRefreshFailure: String?
    @State private var shopRetryRevision = 0
    @State private var sortPresented = false
    @State private var filterPresented = false
    @State private var debugPushedSong: Song?
    /// When the catalogue first arrived; rows fade in only shortly after it.
    @State private var fadeLoadedAt: Date?
    @State private var quickLinks = QuickLinksController()
    /// Scroll-driven chrome state (scrolled away, tools in the bar, passed section
    /// titles, section bar edge). Never read in `body`: only the section bar, row mask
    /// and page-tools modifier observe it, so scrolling does not re-render the whole
    /// screen (issue #8).
    @State private var scrollChrome = SongsScrollChrome()
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var deviceLayout
    /// True where Filter/Sort live in the iPhone bottom dock instead of the toolbar.
    @Environment(\.isTabAccessoryAvailable) private var actionsInDock
    @AppStorage("fst.songs.sortMode") private var sortMode = SongSortMode.title
    @AppStorage("fst.songs.sortAscending") private var sortAscending = true
    @AppStorage("fst.songs.filterInShop") private var filterInShop = false
    @AppStorage("fst.songs.filterLeavingTomorrow")
    private var filterLeavingTomorrow = false
    @AppStorage(SongPlayerScoreFilter.storageKey)
    private var playerScoreFilterData = Data()
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting")
    private var disableShopHighlighting = false
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.showInstrumentIcons") private var showInstrumentIcons = true
    @AppStorage("fst.settings.metadataScore") private var metadataScore = true
    @AppStorage("fst.settings.metadataPercentage") private var metadataPercentage = true
    @AppStorage("fst.settings.metadataPercentile") private var metadataPercentile = true
    @AppStorage("fst.settings.metadataSeason") private var metadataSeason = true
    @AppStorage("fst.settings.metadataIntensity") private var metadataIntensity = true
    @AppStorage("fst.settings.metadataDifficulty") private var metadataDifficulty = true
    @AppStorage("fst.settings.metadataStars") private var metadataStars = true
    @AppStorage("fst.settings.metadataLastPlayed") private var metadataLastPlayed = true

    enum LoadState {
        case loading
        case loaded(CatalogPayload)
        case failed(ServiceIssue)

        /// Whether the catalogue is still loading (drives ``FestivalReloadGate``).
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// Restart a single catalogue task on publication or tab/route visibility changes.
    private struct CatalogueTaskKey: Equatable {
        let publicationRevision: Int
        let visible: Bool
    }

    private struct ShopTaskKey: Equatable {
        let publicationRevision: Int
        let visible: Bool
        let hidden: Bool
        let retryRevision: Int
    }

    private struct ProfileTaskKey: Equatable {
        let selectionRevision: Int
        let publicationRevision: Int
        let visible: Bool
    }

    private var currentSeason: Int? {
        if case let .loaded(payload) = state {
            return payload.catalog.currentSeason
        }
        return nil
    }

    /// Share one set of Settings switches across lazy row renderers.
    private var metadataVisibility: SongMetadataVisibility {
        SongMetadataVisibility(
            score: metadataScore, percentage: metadataPercentage,
            percentile: metadataPercentile, season: metadataSeason,
            intensity: metadataIntensity, difficulty: metadataDifficulty,
            stars: metadataStars, lastPlayed: metadataLastPlayed
        )
    }

    private var appliedShopFilter: SongShopFilter {
        SongShopFilter(inShop: filterInShop, leavingTomorrow: filterLeavingTomorrow)
    }

    private var playerScoreFilterResult: Result<SongPlayerScoreFilter, Error> {
        Result { try SongPlayerScoreFilter.decodeSaved(playerScoreFilterData) }
    }

    private var appliedPlayerScoreFilter: SongPlayerScoreFilter? {
        if case let .success(filter) = playerScoreFilterResult { return filter }
        return nil
    }

    private var playerScoreFilterError: Error? {
        if case let .failure(error) = playerScoreFilterResult { return error }
        return nil
    }

    private var shopPublicationMismatch: Bool {
        guard case let .loaded(payload) = state,
              let current = session.publicationId else { return false }
        return payload.observedPublicationId != current
            || session.currentShop.map {
                $0.observedPublicationId != current
            } == true
    }

    private var shopOffersForCurrentSongs: [String: ShopSong]? {
        guard !hideShop, case let .loaded(payload) = state,
              SongShopPublicationPolicy.matches(
                catalogue: payload.observedPublicationId,
                shop: session.currentShop?.observedPublicationId,
                current: session.publicationId
              ) else { return nil }
        return session.shopOffersById
    }

    private var profilePublicationMismatch: Bool {
        guard case let .loaded(payload) = state,
              session.selectedPlayer != nil,
              session.playerLoadState == .available else { return false }
        return !session.hasCurrentPlayerScores(
            forCatalogue: payload.observedPublicationId
        )
    }

    private var scoreFilterAvailable: Bool {
        guard case let .loaded(payload) = state else { return false }
        return session.hasCurrentPlayerScores(
            forCatalogue: payload.observedPublicationId
        )
    }

    private var shopFilterPausedMessage: String? {
        guard appliedShopFilter.isActive else { return nil }
        if hideShop {
            return "Item Shop filters paused while Shop is hidden. Showing all songs; "
                + "your choices are saved."
        }
        if session.selectedPlayer == nil {
            return "Item Shop filters paused until a selected player is available. "
                + "Showing all songs; your choices are saved."
        }
        if shopPublicationMismatch {
            return "Item Shop filters paused while songs and Shop publications differ. "
                + "Showing songs without Shop filters; your choices are saved."
        }
        if shopOffersForCurrentSongs == nil {
            return "Item Shop filters paused until public Shop data loads. "
                + "Showing all songs; retry Item Shop status if unavailable."
        }
        return nil
    }

    private var effectiveShopFilter: SongShopFilter {
        shopFilterPausedMessage == nil ? appliedShopFilter : SongShopFilter()
    }

    private var playerScoreFilterPausedMessage: String? {
        guard case .loaded = state,
              let filter = appliedPlayerScoreFilter, filter.isActive else { return nil }
        if !filter.scoped(to: visibleInstruments).isActive {
            return "Player score filters paused while their charts are hidden in Settings. "
                + "Your choices are saved."
        }
        if session.selectedPlayer == nil {
            return "Player score filters paused until a player is selected. "
                + "Showing songs without score filters."
        }
        if filterInvalidScores {
            return "Player score filters paused while Filter Invalid Scores is enabled. "
                + "Published raw scores cannot replace validated score variants."
        }
        if !scoreFilterAvailable {
            return "Player score filters paused until selected scores and songs "
                + "share the current publication. Showing songs without score filters."
        }
        return nil
    }

    private var effectivePlayerScoreFilter: SongPlayerScoreFilter {
        playerScoreFilterPausedMessage == nil
            ? (appliedPlayerScoreFilter?.scoped(to: visibleInstruments)
                ?? SongPlayerScoreFilter())
            : SongPlayerScoreFilter()
    }

    private var hiddenPlayerScoreChecks: Bool {
        guard let filter = appliedPlayerScoreFilter else { return false }
        return filter.scoped(to: visibleInstruments) != filter
    }

    /// Tight, web-like row gutters: a small vertical gap keeps varied-height glass
    /// cards close together (web's virtualized list uses a 2pt row gap).
    private var songRowInsets: EdgeInsets {
        EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)
    }

    private var canPresentFilter: Bool {
        playerScoreFilterError == nil
            && ((session.selectedPlayer != nil && session.playerLoadState == .available)
                || appliedShopFilter.isActive
                || appliedPlayerScoreFilter?.isActive == true)
    }

    /// Create a catalogue screen with a fixture state for hosted visual tests.
    ///
    /// - Parameters:
    ///   - session: Process-scoped data and artwork cache.
    ///   - initialState: Loading in production, or a fixture for state snapshots.
    ///   - initialRefreshError: An actionable last-update failure for snapshot tests.
    ///   - searchText: Tab-owned text retained across native section switching.
    ///   - settledSearch: Tab-owned 250 ms debounced query.
    ///   - selectedInstrument: Scene-owned filter retained when a split view switches sections.
    ///   - navigationNotice: Explicit route/filter invalidation announcement.
    init(
        session: FestivalSession, initialState: LoadState = .loading,
        initialRefreshError: String? = nil,
        searchText: Binding<String> = .constant(""),
        settledSearch: Binding<String> = .constant(""),
        selectedInstrument: Binding<Instrument?> = .constant(nil),
        navigationNotice: Binding<String?> = .constant(nil),
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        highContrast: Bool = false, isVisible: Bool = true,
        openShop: (() -> Void)? = nil
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        self.highContrast = highContrast
        self.isVisible = isVisible
        self.openShop = openShop
        _state = State(initialValue: initialState)
        _refreshFailure = State(initialValue: initialRefreshError)
        _searchText = searchText
        _settledSearch = settledSearch
        _instrument = selectedInstrument
        _navigationNotice = navigationNotice
    }

    var body: some View {
        VStack(spacing: 0) {
            let _ = MainThreadStallMonitor.count("songs.body")
            if let navigationNotice {
                HStack(spacing: 8) {
                    Text(navigationNotice)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss") { self.navigationNotice = nil }
                }
                .font(.footnote)
                .foregroundStyle(BrandTokens.gold)
                .padding(12)
                .background(
                    BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12)
                )
                .padding(.horizontal, 16)
                .accessibilityIdentifier("fst.songs.navigation-notice")
            }

            // Sort, filter, instrument and search changes fade the list out, show the
            // spinner (also while a search is typed ahead of its debounce) and stagger the
            // new list in (web `SongsPage` `settingsKey`, issue #71).
            FestivalReloadGate(
                key: reloadKey, isLoading: state.isLoading || searchText != settledSearch,
                spinnerLabel: "Loading songs",
                onReveal: {
                    fadeLoadedAt = .now
                    scrollChrome.resetHeaders()
                }
            ) {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Songs unavailable") {
                    Task { await reload() }
                }
            case let .loaded(payload):
                if let error = playerScoreFilterError {
                    invalidPlayerFilterView(error.localizedDescription)
                } else {
                let matching = payload.catalog.songs.filter { song in
                    SongSearch.matches(song, query: settledSearch)
                        && (instrument.map(song.supports) ?? true)
                }
                let effectiveMode = effectiveSortMode
                let membership = shopOffersForCurrentSongs.map { offers in
                    Set(offers.keys)
                }
                let sorted: Result<[Song], Error> = Result {
                    let publicFiltered = try effectiveShopFilter.filtered(
                        matching, offersById: shopOffersForCurrentSongs
                    )
                    let filtered = try effectivePlayerScoreFilter.filtered(
                        publicFiltered,
                        scoresBySong: session.hasCurrentPlayerScores(
                            forCatalogue: payload.observedPublicationId
                        ) ? session.selectedPlayerScores : nil,
                        visibleInstruments: visibleInstruments,
                        selectedInstrument: instrument
                    )
                    MainThreadStallMonitor.count("songs.sort")
                    return try SongCatalogSort.sorted(
                        filtered, mode: effectiveMode, ascending: sortAscending,
                        shopSongIds: membership,
                        chartScores: effectiveMode.isPlayerChartMode
                            ? chartScores(for: payload) : nil
                    )
                }
                switch sorted {
                case let .failure(error):
                    ServiceUnavailableView(
                        title: "Song sort unavailable", message: error.localizedDescription
                    ) {
                        shopRetryRevision += 1
                    }
                case let .success(visible):
                if visible.isEmpty {
                    let filtersApplied = instrument != nil || effectiveShopFilter.isActive
                        || effectivePlayerScoreFilter.isActive
                    VStack(spacing: 8) {
                        if hasDisclosure(for: payload) {
                            disclosures(for: payload)
                                .padding(.horizontal, 16)
                        }
                        ContentUnavailableView {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .accessibilityHidden(true)
                                Text(
                                    settledSearch.isEmpty
                                        ? "No Results" : "No Results for \"\(settledSearch)\""
                                )
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(FestivalText.primary)
                        } description: {
                            Text(
                                settledSearch.isEmpty
                                    ? (filtersApplied
                                        ? "No songs match your filters."
                                        : "No songs are available yet.")
                                    : (effectiveShopFilter.isActive
                                        || effectivePlayerScoreFilter.isActive
                                        ? "Try a different search or filter."
                                        : "Try a different search.")
                            )
                            .foregroundStyle(FestivalText.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    populatedList(payload: payload, visible: visible, effectiveMode: effectiveMode)
                }
                }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .navigationTitle("Songs")
        // Inline filter of this list (HIG "search as an inline field", like Music's
        // Library); global search is in the toolbar. On iPhone it stays pinned under
        // the bar while scrolled, beside the tools that rise into it (issue #13; HIG
        // Search fields: "consider pinning it to the top toolbar while scrolling").
        .searchable(
            text: $searchText, placement: Self.filterFieldPlacement(
                actionsInDock: actionsInDock, sidebarShell: deviceLayout.sectionChrome == .sidebar
            ),
            prompt: Text("Filter Songs")
        )
        // iPhone: Filter and Sort sit in the bottom dock beside Search, like the web's
        // FAB dock (operator, 2026-09-28); toolbar items elsewhere (Duo rail, iPad, Mac).
        .modifier(SongsPageTools(
            chrome: scrollChrome, session: session, quickLinks: quickLinks,
            filterDockToken: filterDockToken, sortDockToken: sortDockToken,
            canPresentFilter: canPresentFilter, actionsInDock: actionsInDock,
            placement: Self.pageActionPlacement,
            sortAction: sortAction, filterAction: filterAction
        ))
        #if os(iOS)
        .sheet(isPresented: $sortPresented) { sortSheet }
        #else
        // Mac: Sort is a popover from its toolbar button (HIG Popovers: "a little
        // information or functionality"); View › Sort… opens it too.
        .macPageCommands(macCommands)
        #endif
        .sheet(isPresented: $filterPresented) {
            if let appliedPlayerScoreFilter {
                SongsFilterSheet(
                    applied: appliedShopFilter, showShop: !hideShop,
                    shopAvailable: shopOffersForCurrentSongs != nil,
                    profileAvailable: session.selectedPlayer != nil
                        && session.playerLoadState == .available,
                    appliedPlayerFilter: appliedPlayerScoreFilter,
                    appliedInstrument: instrument,
                    visibleInstruments: visibleInstruments,
                    selectedPlayer: session.selectedPlayer != nil,
                    scoreAvailable: scoreFilterAvailable,
                    invalidScoreFilteringEnabled: filterInvalidScores,
                    availableSeasons: SongSeasonBucket.keys(in: session.selectedPlayerScores)
                ) { shop, player, instrumentChoice in
                    playerScoreFilterData = try player.encoded()
                    filterInShop = shop.inShop
                    filterLeavingTomorrow = shop.leavingTomorrow
                    instrument = instrumentChoice
                }
                .macSheetFrame()
            } else {
                Text("Saved song filters are invalid. Reset them from Songs to continue.")
            }
        }
        #if DEBUG
        .navigationDestination(item: $debugPushedSong) { song in
            SongDetailScreen(song: song, session: session, visibleInstruments: visibleInstruments)
        }
        .task(id: FestivalDebugLaunch.songTitleOrId) {
            guard debugPushedSong == nil, let target = FestivalDebugLaunch.songTitleOrId
            else { return }
            for _ in 0..<200 {
                if case let .loaded(payload) = state,
                   let match = payload.catalog.songs.first(where: {
                       $0.songId == target
                           || $0.title.localizedCaseInsensitiveCompare(target) == .orderedSame
                   }) {
                    debugPushedSong = match
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #endif
        .task(id: CatalogueTaskKey(
            publicationRevision: session.publicationRevision, visible: isVisible
        )) {
            guard isVisible else { return }
            switch state {
            case .loading, .failed:
                await reload()
            case let .loaded(payload):
                if let current = session.publicationId,
                   payload.observedPublicationId != current {
                    await reload()
                }
            }
        }
        .task(id: ShopTaskKey(
            publicationRevision: session.publicationRevision,
            visible: isVisible, hidden: hideShop, retryRevision: shopRetryRevision
        )) {
            guard isVisible && !hideShop else { return }
            await reloadShop()
        }
        .task(id: ProfileTaskKey(
            selectionRevision: session.selectionRevision,
            publicationRevision: session.publicationRevision,
            visible: isVisible
        )) {
            guard isVisible, session.selectedPlayer != nil else { return }
            switch session.playerLoadState {
            case .loading, .failed:
                await session.refreshSelectedPlayer()
            case .none, .available, .syncing:
                break
            }
        }
        .onChange(of: visibleInstruments) { _, updated in
            if let instrument, !updated.contains(instrument) {
                self.instrument = nil
            }
        }
        // Player sorts need one instrument: without one the web resets to Title A–Z
        // (`normalizeSongSettings`). The Songs instrument is not saved across launches,
        // so a saved player sort is normalized on appear too.
        .onChange(of: instrument) { _, _ in normalizePlayerSort() }
        .onAppear { normalizePlayerSort() }
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(250))
                settledSearch = searchText
            } catch is CancellationError {
                return
            } catch {
                state = .failed(.other(message: "Search could not finish: \(error.localizedDescription)"))
            }
        }
    }

    /// Tab-root page actions must precede the shared bell/avatar capsule; iOS pins
    /// `.primaryAction` to the trailing edge, so use `.topBarTrailing` there.
    private static var pageActionPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// Where the Filter Songs field sits.
    ///
    /// - Parameters:
    ///   - actionsInDock: The page tools float above an iPhone tab bar at the top.
    ///   - sidebarShell: The iPad sections sidebar shell.
    /// - Returns: On iPhone, the navigation-bar drawer kept visible while scrolling, so the
    ///   field stays with the tools that rise into the bar (issue #13). On iPad too: the
    ///   system placement there collapses the field into a second magnifier beside global
    ///   Search, two identical buttons with different scopes (HIG Searching: "Show current
    ///   scope with descriptive placeholder"). The system placement elsewhere.
    static func filterFieldPlacement(actionsInDock: Bool, sidebarShell: Bool = false) -> SearchFieldPlacement {
        #if os(iOS)
        actionsInDock || sidebarShell ? .navigationBarDrawer(displayMode: .always) : .automatic
        #else
        .automatic
        #endif
    }

    #if os(macOS)
    /// Sort and Filter for View › Sort… / Filter… (Filter disabled when unavailable).
    private var macCommands: MacPageCommands {
        var commands = MacPageCommands()
        commands.sort = { sortPresented = true }
        if canPresentFilter { commands.filter = { filterPresented = true } }
        return commands
    }
    #endif

    /// Sort options (a sheet on iPhone/iPad, a popover on the Mac).
    private var sortSheet: some View {
        SongsSortSheet(
            mode: sortMode, ascending: sortAscending,
            showShop: !hideShop, shopAvailable: shopOffersForCurrentSongs != nil,
            playerModes: playerSortModesOffered
        ) { mode, order in
            sortMode = mode
            sortAscending = order
        }
    }

    /// Open a native Sort sheet while retaining the current instrument selection.
    private var sortAction: some View {
        Button {
            sortPresented = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        #if os(macOS)
        .popover(isPresented: $sortPresented, arrowEdge: .bottom) {
            // The popover is its own chrome: no modal stack, title bar or Close (which
            // would otherwise join the window toolbar); it closes on an outside click.
            sortSheet
                .environment(\.festivalModalPreview, true)
                .formStyle(.grouped)
                .frame(width: 340, height: 470)
        }
        .help("Sort Songs")
        #endif
        .accessibilityValue(
            "\(sortMode.label), \(sortAscending ? "ascending" : "descending")"
                + (sortPausedMessage == nil ? "" : ", paused; showing Title order")
        )
        .accessibilityIdentifier("fst.songs.sort")
        .tint(sortMode == .title && sortAscending
            ? BrandTokens.accentBlue : BrandTokens.gold)
    }

    private var filterAccessibilityValue: String {
        let labels = [
            filterInShop ? "In Shop" : nil,
            filterLeavingTomorrow ? "Leaving Tomorrow" : nil,
        ].compactMap { $0 }
        let scoreCount = appliedPlayerScoreFilter.map { filter in
            SongScoreFilterKind.allCases.reduce(0) { count, kind in
                count + Instrument.allCases.filter {
                    filter.contains(kind, for: $0)
                }.count
            }
        } ?? 0
        let scoreLabel = scoreCount > 0
            ? "\(scoreCount) player score \(scoreCount == 1 ? "check" : "checks")"
            : nil
        let bucketLabels = SongBucketKind.allCases.compactMap { kind in
            appliedPlayerScoreFilter?.excluded(kind).isEmpty == false
                ? "\(kind.rawValue.capitalized) filter" : nil
        }
        let selected = (labels + [scoreLabel].compactMap { $0 } + bucketLabels)
            .joined(separator: ", ")
        let status = selected.isEmpty ? "No filters" : selected
        if shopFilterPausedMessage != nil {
            return status + (effectivePlayerScoreFilter.isActive
                ? ", Item Shop filters paused" : ", paused; showing all songs")
        }
        return status + (playerScoreFilterPausedMessage == nil
            ? "" : ", player score filters paused")
    }

    private var filterAction: some View {
        Button {
            filterPresented = true
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Filter Songs")
        #if os(macOS)
        .help("Filter Songs")
        #endif
        .accessibilityValue(filterAccessibilityValue)
        .accessibilityIdentifier("fst.songs.filter")
        .tint(appliedShopFilter.isActive || appliedPlayerScoreFilter?.isActive == true
            ? BrandTokens.gold : BrandTokens.accentBlue)
    }

    /// Everything the dock's Sort button shows; a change re-registers it.
    private var sortDockToken: [String] {
        [sortMode.rawValue, String(sortAscending), sortPausedMessage ?? ""]
    }

    /// Everything the dock's Filter button shows; a change re-registers it.
    private var filterDockToken: [String] {
        [filterAccessibilityValue, String(appliedShopFilter.isActive),
         String(appliedPlayerScoreFilter?.isActive == true)]
    }

    /// Keep a saved Shop or player sort visible when its source is hidden or unavailable.
    private var sortPausedMessage: String? {
        if sortMode.isPlayerChartMode { return playerSortPausedMessage }
        guard sortMode == .shop else { return nil }
        if hideShop {
            return "Item Shop sort paused while Shop is hidden. Showing title order; "
                + "your preference is saved."
        }
        if shopPublicationMismatch {
            return "Item Shop sort paused while songs and Shop publications differ. "
                + "Showing title order; your preference is saved."
        }
        if shopOffersForCurrentSongs == nil {
            return "Item Shop sort paused until public Shop data loads. "
                + "Showing title order; retry Item Shop status if unavailable."
        }
        return nil
    }

    /// Why a saved Score/Percentile/Stars sort cannot order the rows right now (never
    /// by treating an unavailable or mismatched score index as "no scores").
    private var playerSortPausedMessage: String? {
        let name = sortMode.label
        // No instrument: normalized to Title on appear / change, not a pause.
        guard instrument != nil else { return nil }
        if session.selectedPlayer == nil {
            return "\(name) sort paused until a player is selected. "
                + "Showing title order; your preference is saved."
        }
        if filterInvalidScores {
            return "\(name) sort paused while Filter Invalid Scores is enabled. "
                + "Published raw scores cannot replace validated score variants."
        }
        if !scoreFilterAvailable {
            return "\(name) sort paused until selected scores and songs share the current "
                + "publication. Showing title order; your preference is saved."
        }
        return nil
    }

    /// The sort actually applied: Title while the saved sort is paused, or while a
    /// player sort waits for its normalization without an instrument.
    private var effectiveSortMode: SongSortMode {
        if sortPausedMessage != nil { return .title }
        if sortMode.isPlayerChartMode && instrument == nil { return .title }
        return sortMode
    }

    /// Selected-player sorts the Sort sheet offers: only with a selected player and
    /// one Songs instrument, and only those whose row metadata Settings shows (web
    /// `SortModal` hides a mode whose metadata is hidden).
    private var playerSortModesOffered: [SongSortMode] {
        guard instrument != nil, session.selectedPlayer != nil else { return [] }
        return SongSortMode.playerChartModes.filter { mode in
            switch mode {
            case .score: metadataScore
            case .percentile: metadataPercentile
            case .stars: metadataStars
            default: false
            }
        }
    }

    /// The selected player's scores on the Songs instrument, only from an available
    /// score index observed with this catalogue (nil otherwise: never a newer index).
    ///
    /// - Parameter payload: The retained catalogue.
    /// - Returns: Scores by song ID, or nil without one instrument or a matching index.
    private func chartScores(for payload: CatalogPayload) -> [String: PlayerScore]? {
        guard let instrument,
              session.hasCurrentPlayerScores(forCatalogue: payload.observedPublicationId)
        else { return nil }
        return session.selectedPlayerScores.compactMapValues { $0[instrument] }
    }

    /// Reset a player sort to Title A–Z once Songs shows every instrument.
    private func normalizePlayerSort() {
        guard instrument == nil, sortMode.isPlayerChartMode else { return }
        sortMode = .title
        sortAscending = true
    }

    /// Avoid installing an empty accessibility node for an absent warning group.
    ///
    /// - Parameter payload: Catalogue state to check for visible disclosure.
    /// - Returns: True when at least one warning must appear above the rows.
    private func hasDisclosure(for payload: CatalogPayload) -> Bool {
        refreshFailure != nil || payload.publicationId == nil
            || session.publicationId.map { $0 != payload.observedPublicationId } == true
            || profilePublicationMismatch
            || session.playerError != nil
            || (session.selectedPlayer != nil && session.playerLoadState != .available)
            || (!hideShop && (
                session.shopError != nil
                    || (session.currentShop == nil && shopRefreshFailure != nil)
            ))
            || sortPausedMessage != nil || shopFilterPausedMessage != nil
            || playerScoreFilterPausedMessage != nil
            || hiddenPlayerScoreChecks
    }

    /// Show freshness and update errors even when search finds no matching rows.
    ///
    /// - Parameter payload: Current catalogue with response and observation provenance.
    /// - Returns: Any visible, accessible warning that applies to these songs.
    @ViewBuilder
    private func disclosures(for payload: CatalogPayload) -> some View {
        if let refreshFailure {
            RefreshErrorBanner(message: refreshFailure)
        }
        if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live songs without publication verification",
                symbol: "info.circle"
            )
        }
        if let current = session.publicationId,
           payload.observedPublicationId != current {
            FreshnessDisclosure(
                message: "Publication changed - updating songs",
                symbol: "arrow.clockwise"
            )
        }
        if profilePublicationMismatch {
            FreshnessDisclosure(
                message: "Player scores paused until songs and player data share "
                    + "the current observed publication. Showing songs without player scores.",
                symbol: "pause.circle"
            )
            .accessibilityIdentifier("fst.songs.profile-paused")
        }
        if let playerScoreFilterPausedMessage {
            FreshnessDisclosure(
                message: playerScoreFilterPausedMessage,
                symbol: "line.3.horizontal.decrease.circle"
            )
            .accessibilityIdentifier("fst.songs.score-filter-paused")
        } else if hiddenPlayerScoreChecks {
            FreshnessDisclosure(
                message: "Player score checks for hidden charts are inactive. "
                    + "Visible chart checks still apply.",
                symbol: "eye.slash"
            )
            .accessibilityIdentifier("fst.songs.score-filter-hidden")
        }
        if let sortPausedMessage {
            FreshnessDisclosure(message: sortPausedMessage, symbol: "arrow.up.arrow.down")
                .accessibilityIdentifier("fst.songs.sort-paused")
        }
        if let shopFilterPausedMessage {
            FreshnessDisclosure(
                message: shopFilterPausedMessage,
                symbol: "line.3.horizontal.decrease.circle"
            )
            .accessibilityIdentifier("fst.songs.filter-paused")
        }
        if let selected = session.selectedPlayer {
            switch session.playerLoadState {
            case .loading:
                FreshnessDisclosure(
                    message: "Loading public scores for \(selected.displayName)",
                    symbol: "hourglass"
                )
                .accessibilityIdentifier("fst.songs.profile-status")
            case .syncing:
                FreshnessDisclosure(
                    message: "Player scores are syncing. No published score cards yet.",
                    symbol: "arrow.triangle.2.circlepath"
                )
                .accessibilityIdentifier("fst.songs.profile-status")
                profileRetryButton
            case .failed, .none:
                FreshnessDisclosure(
                    message: "Player scores unavailable: \(session.playerError ?? "Not loaded")",
                    symbol: "exclamationmark.triangle"
                )
                .accessibilityIdentifier("fst.songs.profile-status")
                profileRetryButton
            case .available:
                EmptyView()
            }
        } else if let playerError = session.playerError {
            FreshnessDisclosure(
                message: playerError, symbol: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("fst.songs.profile-status")
            Button("Choose Profile") { openProfile() }
                .accessibilityIdentifier("fst.songs.profile-retry")
        }
        if !hideShop, let shopFailure = session.shopError
            ?? (session.currentShop == nil ? shopRefreshFailure : nil) {
            FreshnessDisclosure(
                message: "Item Shop status unavailable: \(shopFailure)",
                symbol: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("fst.songs.shop-error")
            Button("Retry Item Shop status") { shopRetryRevision += 1 }
                .font(.body)
                .foregroundStyle(FestivalText.primary)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(
                    BrandTokens.cardBackground,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .buttonStyle(HighContrastPagerStyle())
                .accessibilityIdentifier("fst.songs.shop-retry")
        }
    }

    /// Offer a manual retry for a selected player after 202 syncing or a failed read.
    private var profileRetryButton: some View {
        Button("Retry Player Scores") {
            Task { await session.refreshSelectedPlayer() }
        }
        .accessibilityIdentifier("fst.songs.profile-retry")
    }

    /// Block corrupt saved filters with an explicit reset, never show unfiltered success.
    ///
    /// - Parameter message: Validated local-preference decode failure.
    /// - Returns: Accessible error and user-controlled reset of only score filters.
    private func invalidPlayerFilterView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Saved song filters unavailable")
                    .font(.title2.bold())
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(FestivalText.primary)
                Button {
                    playerScoreFilterData = Data()
                } label: {
                    Text("Reset saved score filters")
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(
                            BrandTokens.cardBackground,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(HighContrastPagerStyle())
                .accessibilityIdentifier("fst.songs.filter-reset-invalid")
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("fst.songs.filter-invalid")
    }

    /// Render the non-empty catalogue List with Item Shop or A-Z/Year sections.
    ///
    /// Extracted from `body` so the section-index scrubber's own layout does not
    /// deepen an already large `switch`/`if` expression the type checker must solve.
    ///
    /// - Parameters:
    ///   - payload: Currently loaded catalogue and its observed publication.
    ///   - visible: Songs after search, filters and sort have been applied.
    ///   - effectiveMode: Sort mode actually in effect (paused sorts fall back to Title).
    /// - Returns: A scrollable List, with a trailing jump scrubber when applicable.
    /// Width to keep clear of the trailing `SongSectionIndexScrubber`: its own
    /// 22pt-wide capsule, the same Duo vertical-bar margin it insets by
    /// (`.agents/design/apple/duo.md`'s B4), and a small visual gap so a row's
    /// trailing content doesn't sit flush against the capsule's edge.
    private var scrubberTrailingReserve: CGFloat {
        22 + max(2, deviceLayout.cutoutInsets.trailing) + 6
    }

    /// Extra trailing safe area while the rail shows: the rows already keep their
    /// standard 16pt margin, so only the part of the reserve beyond it is added
    /// (operator: recover the empty strip; card edge 48 → 30pt from the screen edge).
    /// Nothing is reserved without the rail (Year, Duration, Shop and player sorts).
    private var scrubberExtraInset: CGFloat {
        max(0, scrubberTrailingReserve - songRowInsets.trailing)
    }

    private func populatedList(
        payload: CatalogPayload, visible: [Song], effectiveMode: SongSortMode
    ) -> some View {
        let indexSections = SongSectionIndex.sections(visible, mode: effectiveMode)
        let showsIndex = indexSections.count > 1
        let shopSections = effectiveMode == .shop
            ? shopOffersForCurrentSongs.map { SongCatalogSort.shopSections(visible, offersById: $0) }
            : nil
        let durationSections = effectiveMode == .duration
            ? SongCatalogSort.durationSections(visible) : nil
        let yearSections = effectiveMode == .year
            ? SongCatalogSort.yearSections(visible) : nil
        let scoreSections = effectiveMode.isPlayerChartMode
            ? chartScores(for: payload).map {
                SongCatalogSort.scoreSections(visible, mode: effectiveMode, chartScores: $0)
            }
            : nil
        // Stagger only while the rows that just loaded first appear.
        let fadeOrder: [String: Int] = fadeWindowOpen
            ? Dictionary(
                visible.prefix(FestivalFadeIn.maxStaggeredItems).enumerated()
                    .map { ($1.songId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            : [:]
        let groups = listGroups(
            indexSections: showsIndex ? indexSections : nil, shopSections: shopSections,
            durationSections: durationSections, yearSections: yearSections,
            scoreSections: scoreSections
        )
        let headerKeys = (groups ?? []).map { Self.headerKey($0.id) }
        return ScrollViewReader { scrollProxy in
            ZStack(alignment: .trailing) {
                List {
                    if hasDisclosure(for: payload) {
                        disclosures(for: payload)
                    }
                    if let groups, Self.usesSectionBar {
                        // iOS 26: the current section title sits in a bar above the List
                        // (`SongsSectionBar`); rows fade out just below its edge, like the
                        // system's soft scroll-edge effect under the bar (issue #10), with
                        // no opaque backing (operator batch 7).
                        // The in-list titles are ordinary rows marking where each section
                        // starts; the first section's title is the bar itself.
                        // Flat rows, no `Section`: iOS 26 plain Lists draw an opaque band
                        // for a header-less section.
                        ForEach(groups) { group in
                            inlineGroupHeader(group)
                            ForEach(group.songs) { song in
                                songLink(
                                    for: song, catalogueObservation: payload.observedPublicationId,
                                    fadeIndex: fadeOrder[song.songId]
                                )
                            }
                        }
                    } else if let groups {
                        // Before iOS 26: sticky section titles (operator, 2026-09-28) on an
                        // opaque backing so rows never show through beneath them. The titles
                        // are the scrubber's and Quick Links' jump targets.
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.songs) { song in
                                    songLink(
                                        for: song, catalogueObservation: payload.observedPublicationId,
                                        fadeIndex: fadeOrder[song.songId]
                                    )
                                }
                            } header: {
                                groupHeader(group)
                            }
                        }
                    } else {
                        ForEach(visible) { song in
                            songLink(
                                for: song, catalogueObservation: payload.observedPublicationId,
                                fadeIndex: fadeOrder[song.songId]
                            )
                        }
                    }
                }
                .listStyle(.plain)
                // Before the section bar overlay: applied after it, this identifier
                // replaced the bar's own (`fst.songs.section-bar`) for UI tests.
                .accessibilityIdentifier("fst.songs.list")
                .modifier(SectionBarRowMask(
                    chrome: scrollChrome, enabled: groups != nil && Self.usesSectionBar
                ))
                .overlay(alignment: .top) {
                    // Once scrolled, the current section's title floats just below the
                    // navigation bar and the rows fade out at its bottom edge. An
                    // overlay, not a safeAreaBar: a top bar hid the iOS 26 large title.
                    if Self.usesSectionBar, let groups {
                        SongsSectionBar(
                            chrome: scrollChrome,
                            sections: groups.map {
                                SongsSectionBar.Entry(
                                    key: Self.headerKey($0.id), label: $0.label,
                                    spokenLabel: $0.spokenLabel ?? $0.label
                                )
                            }
                        )
                    }
                }
                .modifier(ScrolledAwayTracker(
                    topInsetChanged: scrollChrome.setListTopInset
                ) { scrolled, style in
                    scrollChrome.setScrolled(scrolled)
                    let moved = PageToolsHandOff.toolsInBar(
                        scrolled: scrolled, actionsInDock: actionsInDock
                    )
                    guard moved != scrollChrome.toolsInBar else { return }
                    // The floating dock animates its half with the same timing.
                    withAnimation(PageToolsHandOff.animation(style)) {
                        scrollChrome.setToolsInBar(moved)
                        quickLinks.prefersToolbar = moved
                    }
                })
                .scrollContentBackground(.hidden)
                // Reserve room for the trailing section-index scrubber so its glass
                // capsule never overlaps a row's own trailing content (difficulty
                // meter, Shop badge, instrument-status chips) — the scrubber is an
                // overlay in this ZStack, not part of the List's own layout, so
                // without this a row's trailing edge sits directly underneath it.
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    Color.clear.frame(width: showsIndex ? scrubberExtraInset : 0)
                }
                .festivalRefreshable { await reload() }
                .quickLinks(
                    quickLinks, title: "\(effectiveMode.label) Quick Links",
                    sections: showsIndex ? [] : (groups ?? []).compactMap(\.quickLink)
                )
                .modifier(QuickLinksJumpHeaderSync(
                    quickLinks: quickLinks, chrome: scrollChrome, keys: headerKeys
                ))
                if showsIndex {
                    SongSectionIndexScrubber(sections: indexSections) { id in
                        jumpToSection(AnyHashable(id), keys: headerKeys, proxy: scrollProxy)
                    }
                    // Centered between a *fixed* top (status bar + collapsed inline bar)
                    // and the bottom safe area (tab bar + floating tools), so it neither
                    // jumps when the large title and filter field collapse nor overlaps
                    // the floating Filter/Sort buttons.
                    .frame(maxHeight: .infinity)
                    .padding(.top, deviceLayout.overlayInsets.top + 52)
                    .padding(.bottom, 8)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsIndex)

            // Any reordering (sort mode, direction, filters) starts at the top of the new
            // order (operator, 2026-09-28).
            .onChange(of: reorderKey) { _, _ in
                scrollChrome.resetHeaders()
                let top: AnyHashable? = groups?.first?.id ?? visible.first.map { AnyHashable($0.id) }
                if let top { scrollProxy.scrollTo(top, anchor: .top) }
            }
            .task {
                #if DEBUG
                // `FST_DEBUG_SONGS_SCROLL_STRESS=1`: replay a scroll stress pass in-app,
                // without XCUITest's accessibility snapshots (issue #8 measurements).
                guard SongsScrollStress.isRequested, let groups else { return }
                let ids = groups.map(\.id)
                try? await Task.sleep(for: .seconds(3))
                MainThreadStallMonitor.count(SongsScrollStress.startCounter)
                for step in SongsScrollStress.plan(groupCount: ids.count) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy.scrollTo(ids[step.group], anchor: .top)
                    }
                    try? await Task.sleep(for: .seconds(step.pause))
                    if Task.isCancelled { return }
                }
                MainThreadStallMonitor.count(SongsScrollStress.endCounter)
                #endif
            }
        }
    }

    /// Jump instantly to a section's title from the A–Z rail (like Contacts and the Quick
    /// Links jumps) and name it in the section bar at once.
    ///
    /// A far target's rows have never been laid out, so the first scroll places it from
    /// estimated row heights; once they exist a second scroll lands it exactly (as Quick
    /// Links does), unless a newer jump has replaced it while scrubbing.
    ///
    /// - Parameters:
    ///   - id: The section's scroll target.
    ///   - keys: Section title keys in list order.
    ///   - proxy: Reader proxy for the Songs List.
    private func jumpToSection(_ id: AnyHashable, keys: [String], proxy: ScrollViewProxy) {
        let chrome = scrollChrome
        chrome.jump(to: Self.headerKey(id), in: keys)
        let generation = chrome.jumpGeneration
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(id, anchor: .top) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard chrome.jumpGeneration == generation else { return }
            withTransaction(instant) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    /// True for a moment after the catalogue loads, while its first rows are revealed.
    private var fadeWindowOpen: Bool {
        guard let fadeLoadedAt else { return false }
        return Date.now.timeIntervalSince(fadeLoadedAt)
            < FestivalFadeIn.completionDelay(itemCount: FestivalFadeIn.maxStaggeredItems)
    }

    /// The list settings whose change replays the load sequence (web `settingsKey`):
    /// sort, direction, filters, instrument and the settled search.
    private struct ReloadKey: Equatable {
        let sortMode: SongSortMode
        let sortAscending: Bool
        let filterInShop: Bool
        let filterLeavingTomorrow: Bool
        let playerScoreFilter: Data
        let instrument: Instrument?
        let search: String
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            sortMode: sortMode, sortAscending: sortAscending, filterInShop: filterInShop,
            filterLeavingTomorrow: filterLeavingTomorrow, playerScoreFilter: playerScoreFilterData,
            instrument: instrument, search: settledSearch
        )
    }

    /// Changes whenever the list is re-sorted or re-filtered.
    private var reorderKey: [String] {
        [sortMode.rawValue, String(sortAscending), filterAccessibilityValue,
         instrument?.rawValue ?? ""]
    }

    /// One labelled run of songs: an A–Z letter, a decade, a duration or Shop bucket.
    private struct SongListGroup: Identifiable {
        /// Scroll target: the scrubber's `Int` section id, or the quick-link id.
        let id: AnyHashable
        let label: String
        /// VoiceOver label when it differs from `label` ("5 stars" for "5★").
        var spokenLabel: String?
        let accessibilityID: String
        /// Quick Links entry for sorts without the scrubber (Year, Duration, Shop).
        let quickLink: QuickLinkSection?
        let songs: [Song]
    }

    /// Group the sorted rows for the active sort (nil: an ungrouped list).
    ///
    /// Title/Artist use the A–Z scrubber; Year (decades), Duration (one-minute buckets),
    /// Item Shop and the Score/Percentile/Stars sorts use Quick Links
    /// (`.agents/controls/quick-links/ios.md`).
    private func listGroups(
        indexSections: [SongSection]?, shopSections: [SongShopSection]?,
        durationSections: [SongDurationSection]?, yearSections: [SongYearSection]?,
        scoreSections: [SongScoreSection]? = nil
    ) -> [SongListGroup]? {
        if let indexSections {
            return indexSections.map {
                SongListGroup(
                    id: AnyHashable($0.id), label: $0.label,
                    accessibilityID: "fst.songs.section.\($0.id)", quickLink: nil, songs: $0.songs
                )
            }
        }
        func bucketed(_ kind: String, _ key: String, _ label: String, _ songs: [Song]) -> SongListGroup {
            let link = QuickLinkSection(id: "\(kind):\(key)", title: label)
            return SongListGroup(
                id: AnyHashable(link.id), label: label,
                accessibilityID: "fst.songs.\(kind)-section.\(key)", quickLink: link, songs: songs
            )
        }
        if let shopSections, shopSections.count > 1 {
            return shopSections.map { bucketed("shop", $0.kind.rawValue, $0.kind.label, $0.songs) }
        }
        if let durationSections, durationSections.count > 1 {
            return durationSections.map {
                bucketed("duration", $0.bucket.rawValue, $0.bucket.label, $0.songs)
            }
        }
        if let yearSections, yearSections.count > 1 {
            return yearSections.map { bucketed("year", $0.id, $0.label, $0.songs) }
        }
        if let scoreSections, scoreSections.count > 1 {
            return scoreSections.map { section in
                var group = bucketed("score", section.key, section.label, section.songs)
                group.spokenLabel = section.spokenLabel == section.label ? nil : section.spokenLabel
                return group
            }
        }
        return nil
    }

    /// Whether the section title lives in a bar above the List (iOS 26 scroll-edge
    /// effect) instead of opaque pinned List headers.
    static var usesSectionBar: Bool {
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        return false
    }

    /// Stable key for a group's in-list title, from the group's scroll target.
    static func headerKey(_ id: AnyHashable) -> String { "\(id)" }

    /// A section's in-list title (iOS 26): a plain row, no backing, carrying the jump
    /// target and Quick Links tracking.
    @ViewBuilder private func inlineGroupHeader(_ group: SongListGroup) -> some View {
        let key = Self.headerKey(group.id)
        let topInset = scrollChrome.listTopInset
        let label = Text(group.label)
            .font(.subheadline.bold())
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(group.spokenLabel ?? group.label)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(group.accessibilityID)
            .onGeometryChange(for: Bool.self) { proxy in
                SongsScrollChrome.headerPassed(
                    minY: proxy.frame(in: .scrollView).minY,
                    topInset: topInset.value
                )
            } action: { passed in
                scrollChrome.setHeader(key, passed: passed)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        if let link = group.quickLink {
            label.quickLinkSection(link)
        } else {
            label.id(group.id)
        }
    }

    /// A pinned section title: full-width, fully opaque backing (a flat surface with a
    /// hairline, matching the glass cards' border) so scrolling rows never show through,
    /// and the jump target for the scrubber or Quick Links.
    @ViewBuilder private func groupHeader(_ group: SongListGroup) -> some View {
        let label = Text(group.label)
            .font(.subheadline.bold())
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PinnedHeaderBacking())
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(group.spokenLabel ?? group.label)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(group.accessibilityID)
        if let link = group.quickLink {
            label.quickLinkSection(link)
        } else {
            label.id(group.id)
        }
    }

    /// Keep every grouped and ungrouped Song row on the same navigation path.
    ///
    /// - Parameters:
    ///   - song: Validated catalogue song to display.
    ///   - catalogueObservation: Observed generation of the retained catalogue.
    /// - Returns: One accessible Song Detail link with effective Shop highlighting.
    private func songLink(
        for song: Song, catalogueObservation: Int, fadeIndex: Int? = nil
    ) -> some View {
        let highlight = ShopPresentationPolicy.highlight(
            for: shopOffersForCurrentSongs?[song.songId],
            hidden: hideShop,
            highlightingDisabled: disableShopHighlighting
        )
        let chart = instrument ?? Instrument.allCases.first(where: visibleInstruments.contains)
        // Apple HIG: a card-style row is itself the tap target and drops the
        // trailing disclosure chevron. `NavigationLink` still owns the push (kept
        // invisible and stretched to the card's bounds) so the row remains one
        // accessible, combined VoiceOver stop with the standard Link action.
        // `ListDetailLink` is that link, or a button filling the detail column in an
        // iPhone Duo list/detail split.
        return ZStack {
            SongRowView(
                song: song, instrument: instrument,
                session: session, highContrast: highContrast,
                shopHighlight: highlight,
                inShop: !hideShop && !disableShopHighlighting
                    && shopOffersForCurrentSongs?[song.songId] != nil,
                profileChart: chart,
                catalogueObservation: catalogueObservation,
                metadata: metadataVisibility,
                filterInvalidScores: filterInvalidScores,
                showInstrumentIcons: showInstrumentIcons,
                visibleInstruments: visibleInstruments,
                currentSeason: currentSeason
            )
            ListDetailLink(value: AppRoute.songDetail(song)) { EmptyView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0)
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .contextMenu {
            MacSongRowMenu(song: song, chart: chart, hasPlayer: session.selectedPlayer != nil)
        }
        #endif
        // Rows arriving from a load fade in, staggered over the first screenful; rows
        // rebuilt later by scrolling appear instantly (nil index → no animation).
        .festivalFadeIn(isLoaded: true, index: fadeIndex ?? Int.max)
        .accessibilityElement(children: .combine)
        // `.combine` drops the invisible, `opacity(0)` `NavigationLink`'s own Button
        // trait (SwiftUI excludes fully transparent children from the merge), so the
        // row silently read as plain static text to VoiceOver and to `XCUIApplication
        // .buttons[...]` queries. Restore it explicitly rather than relying on the
        // link's own traits surviving the combine.
        .accessibilityAddTraits(.isButton)
        .listDetailSelectable(AppRoute.songDetail(song))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(songRowInsets)
        .accessibilityIdentifier("fst.songs.row.\(song.songId)")
    }

    /// Rows primed before the very first reveal, and how long priming may block it.
    ///
    /// Native-only addition (2026-09-28): the web app has no equivalent gate — its
    /// `SongsPage` reveals rows as soon as the catalogue/player data queries settle
    /// and fades each row's `<img>` in independently once it loads (`AlbumArt.tsx`).
    /// On a virtualized native `List`, that per-row fade instead reads as a page of
    /// spinning-placeholder art that pops in piecemeal while scrolling settles, so
    /// natives hold the loading state a little longer and prime the first visible
    /// slice's artwork before the first reveal, then cross-fade in once.
    private static let artworkPrimeCount = 12
    private static let artworkPrimeTimeout = Duration.milliseconds(900)

    /// Refresh the public catalogue, preserving the last-viewed process cache.
    private func reload() async {
        let prior: CatalogPayload?
        if case let .loaded(payload) = state {
            prior = payload
        } else {
            prior = nil
            state = .loading
        }
        do {
            let updated = try await session.catalog()
            try Task.checkCancellation()
            if prior == nil {
                await primeFirstArtwork(for: updated)
                try Task.checkCancellation()
            }
            if prior == nil { fadeLoadedAt = .now }
            withAnimation(.easeInOut(duration: 0.2)) {
                state = .loaded(updated)
            }
            refreshFailure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if let prior {
                state = .loaded(prior)
                refreshFailure = error.localizedDescription
            } else {
                state = .failed(ServiceIssue(error))
            }
        }
    }

    /// Decode the first visible rows' artwork before the very first reveal.
    ///
    /// Approximates the row order the just-loaded catalogue will render in (current
    /// instrument filter and sort/direction; search is always empty this early) and
    /// warms ``FestivalSession/preparedArtwork(raw:maxPixels:)`` for its first
    /// ``artworkPrimeCount`` rows at the same `maxPixels` ``ArtworkTile`` requests, so
    /// those rows hit the in-memory cache instantly once shown — no spinner flash.
    /// Bounded by ``artworkPrimeTimeout`` so slow or unreachable art can never block
    /// the reveal; whichever rows haven't decoded yet just show their own placeholder.
    ///
    /// - Parameter payload: Just-fetched catalogue, not yet published to `state`.
    private func primeFirstArtwork(for payload: CatalogPayload) async {
        let filtered = payload.catalog.songs.filter { song in
            instrument.map(song.supports) ?? true
        }
        let ordered = (try? SongCatalogSort.sorted(
            filtered, mode: sortMode == .shop || sortMode.isPlayerChartMode ? .title : sortMode,
            ascending: sortAscending
        )) ?? filtered
        let artworkPaths = ordered.prefix(Self.artworkPrimeCount)
            .compactMap { $0.albumArt?.isEmpty == false ? $0.albumArt : nil }
        guard !artworkPaths.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskGroup(of: Void.self) { downloads in
                    for raw in artworkPaths {
                        downloads.addTask {
                            _ = try? await session.preparedArtwork(raw: raw, maxPixels: 132)
                        }
                    }
                    await downloads.waitForAll()
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.artworkPrimeTimeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Keep Shop status distinct from Songs while revealing a usable retry on failure.
    private func reloadShop() async {
        do {
            _ = try await session.shop()
            try Task.checkCancellation()
            shopRefreshFailure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            shopRefreshFailure = error.localizedDescription
        }
    }
}

private extension SongShopSectionKind {
    var label: String {
        switch self {
        case .leavingTomorrow: "Leaving Tomorrow"
        case .inShop: "In Shop"
        case .notInShop: "Not In Shop"
        }
    }
}

/// Keep anonymous catalogue and Shop sorting as an Apply/Reset/Discard draft.

/// Reports whether a scroll view has moved away from its top (iOS 18+; always false
/// before, so older systems keep the floating tools), with the hand-off style the
/// current Reduce Motion settings call for. ``ScrollAwayGate`` keeps the chrome this
/// report moves from feeding back into it (issue #5).
private struct ScrolledAwayTracker: ViewModifier {
    /// Receives the List's top content inset on every scroll geometry change.
    let topInsetChanged: (CGFloat) -> Void
    let changed: (Bool, PageToolsHandOff.Style) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @State private var gate = ScrollAwayGate()
    /// The last value sent to `changed`; nil until the first decision is reported.
    @State private var reported: Bool?

    /// The geometry values the gate needs.
    private struct Sample: Equatable {
        let offsetY: CGFloat
        let topInset: CGFloat
        let width: CGFloat
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: Sample.self) { geometry in
                Sample(
                    offsetY: geometry.contentOffset.y, topInset: geometry.contentInsets.top,
                    width: geometry.containerSize.width
                )
            } action: { _, sample in
                topInsetChanged(sample.topInset)
                gate.update(
                    offsetY: sample.offsetY, topInset: sample.topInset,
                    containerWidth: sample.width
                )
                guard reported != gate.isScrolled else { return }
                reported = gate.isScrolled
                changed(gate.isScrolled, PageToolsHandOff.style(
                    systemReduceMotion: systemReduceMotion, appReduceMotion: appReduceMotion
                ))
            }
        } else {
            content
        }
    }
}

/// Names a Quick Links jump's target in the section bar at once (issue #9), like an A–Z
/// rail jump: the in-list titles cannot report an instant jump themselves.
///
/// Observes the jump serial itself, so a jump re-renders only this modifier, never the
/// List (issue #8).
private struct QuickLinksJumpHeaderSync: ViewModifier {
    let quickLinks: QuickLinksController
    let chrome: SongsScrollChrome
    /// Section title keys in list order.
    let keys: [String]

    func body(content: Content) -> some View {
        content.onChange(of: quickLinks.jumpSerial) {
            guard let target = quickLinks.jumpTarget else { return }
            chrome.jump(to: target, in: keys)
        }
    }
}

/// iOS 26: the current Songs section title, floating just below the navigation bar once
/// the List has scrolled. With ``SectionBarRowMask`` rows fade out just below its bottom
/// edge (issue #10), with no backing behind the title (operator batch 7).
///
/// Observes ``SongsScrollChrome`` itself, so a passed title or a scroll-away change
/// re-renders only this bar, never the List (issue #8).
private struct SongsSectionBar: View {
    /// One section title in list order.
    struct Entry: Equatable {
        let key: String
        let label: String
        let spokenLabel: String
    }

    let chrome: SongsScrollChrome
    let sections: [Entry]

    var body: some View {
        if chrome.listScrolled,
           let index = chrome.currentSectionIndex(in: sections.map(\.key)) {
            SongsSectionBarLabel(
                label: sections[index].label, spokenLabel: sections[index].spokenLabel
            ) { chrome.setSectionBarBottom($0) }
        }
    }
}

/// The floating section title itself.
private struct SongsSectionBarLabel: View {
    let label: String
    let spokenLabel: String
    /// Reports the label's bottom edge (global).
    let bottomChanged: (CGFloat) -> Void

    var body: some View {
        Text(label)
            .font(.subheadline.bold())
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                bottomChanged($0)
            }
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.songs.section-bar")
    }
}

/// Masks the List above the section bar's bottom edge while scrolled, so rows fade out
/// under the bar (issue #10, ``SectionBarEdgeFade``). Inactive at the top, where no row
/// is under the bar and the large title shows.
///
/// The mask is a shape whose path may extend past its frame: inactive it covers far
/// beyond every edge (a mask laid out inside the safe area hid the iOS 26 large title,
/// and `ignoresSafeArea` on the mask stalled the scroll view), active it starts at the
/// end of the fade below the bar's bottom edge, measured against the mask's own global
/// top. A gradient band fills the fade between the bar's edge and the shape; it sits
/// under the opaque shape when inactive, so it changes nothing there. The structure is
/// the same in every state, so toggling a setting never rebuilds the List.
private struct SectionBarRowMask: ViewModifier {
    /// Observed here, not by `SongsScreen` (issue #8).
    let chrome: SongsScrollChrome
    /// False when the List has no sections or the OS has no section bar.
    let enabled: Bool
    @State private var maskTop: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    func body(content: Content) -> some View {
        let active = enabled && chrome.listScrolled
        let fade = SectionBarEdgeFade.height(
            reduceTransparency: systemReduceTransparency || lessTransparency,
            increaseContrast: moreContrast || systemContrast == .increased
        )
        let cut = max(0, chrome.sectionBarBottom - maskTop)
        content
            .environment(\.defaultMinListRowHeight, 0)
            .mask {
                ZStack(alignment: .top) {
                    LinearGradient(
                        stops: SectionBarEdgeFade.gradientStops, startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: fade)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, -RowMaskShape.far)
                    .offset(y: cut)
                    RowMaskShape(cut: active ? cut + fade : nil)
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    maskTop = $0
                }
            }
    }
}

/// Everything below `cut` (local points), or everything when `cut` is nil.
private struct RowMaskShape: Shape {
    /// How far the path reaches past the frame, in points.
    static let far: CGFloat = 10_000

    let cut: CGFloat?

    func path(in rect: CGRect) -> Path {
        let far = Self.far
        let top = cut.map { rect.minY + max(0, $0) } ?? (rect.minY - far)
        return Path(CGRect(x: rect.minX - far, y: top, width: rect.width + 2 * far, height: rect.maxY + far - top))
    }
}

/// Songs' Filter/Sort/Quick Links placement: the iPhone bottom dock, or the navigation
/// bar (elsewhere, and on iPhone once scrolled), plus the root trailing items and, on
/// iPhone, an empty inline title.
///
/// Observes ``SongsScrollChrome/toolsInBar`` itself, so moving the tools re-renders only
/// this toolbar and dock, never the List (issue #8).
private struct SongsPageTools<SortAction: View, FilterAction: View>: ViewModifier {
    let chrome: SongsScrollChrome
    let session: FestivalSession
    let quickLinks: QuickLinksController
    let filterDockToken: [String]
    let sortDockToken: [String]
    let canPresentFilter: Bool
    let actionsInDock: Bool
    let placement: ToolbarItemPlacement
    let sortAction: SortAction
    let filterAction: FilterAction

    func body(content: Content) -> some View {
        let toolsInBar = chrome.toolsInBar
        content
            .festivalTabAccessory(
                token: filterDockToken, order: DockOrder.filter,
                accessibilityID: "fst.songs.filter",
                isEnabled: canPresentFilter && !toolsInBar
            ) {
                filterAction.frame(minWidth: 44, minHeight: 44)
            }
            .festivalTabAccessory(
                token: sortDockToken, order: DockOrder.sort, accessibilityID: "fst.songs.sort",
                isEnabled: !toolsInBar
            ) {
                sortAction.frame(minWidth: 44, minHeight: 44)
            }
            .toolbar {
                if !actionsInDock || toolsInBar {
                    ToolbarItemGroup(placement: placement) {
                        sortAction
                        if canPresentFilter {
                            filterAction
                        }
                    }
                }
                QuickLinksToolbarItem(quickLinks)
                FestivalRootTrailingItems(session: session)
                #if os(iOS)
                if actionsInDock {
                    // With Filter/Sort/Quick Links in the bar the inline title had no room
                    // and read "…"; the section bar names the place instead (Back still
                    // says "Songs"). A permanent empty title view, never a toggled
                    // `toolbar(removing: .title)`: removing the title also removed the
                    // large title, so the list jumped by its height on every hand-off and
                    // the title reappeared late back at the top (issue #13).
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                }
                #endif
            }
            .festivalProvidesRootTrailingItems()
            .festivalRootChrome(session: session, providesTrailingItems: true)
    }
}

/// Pinned Songs section title backing: none on iOS 26, where the system draws the plain
/// List's pinned header treatment (EXPERIMENT); the opaque band with a hairline before.
private struct PinnedHeaderBacking: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
        } else {
            content
                .background(BrandTokens.appBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(BrandTokens.glassBorder).frame(height: 1)
                }
        }
    }
}
