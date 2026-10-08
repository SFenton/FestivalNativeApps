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

    /// `FST_DEBUG_SONG_BAND=<bandType>` (e.g. `Band_Duets`) with `FST_DEBUG_SONG`
    /// pushes that song's full band leaderboard instead of its Detail page, so
    /// screenshots of every device and pose reach it without scrolling (issue #306).
    static var songBandType: String? {
        let value = ProcessInfo.processInfo.environment["FST_DEBUG_SONG_BAND"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// `FST_DEBUG_SONG_INSTRUMENT=<instrument rawValue>` (e.g. `Solo_Guitar`) with
    /// `FST_DEBUG_SONG` pushes that song's solo Song Leaderboard (page 1) instead of its
    /// Detail page, so its song header can be captured directly (issue #315).
    static var songInstrument: Instrument? {
        ProcessInfo.processInfo.environment["FST_DEBUG_SONG_INSTRUMENT"].flatMap(Instrument.init(rawValue:))
    }
}
#endif

// MARK: - Song catalogue

/// Native virtualized catalogue with explicit loading, error and offline states.
struct SongsScreen: View, Equatable {
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
    /// The publication revision the list has been prepared for (``preparePublication(_:)``).
    @State private var shownRevision: Int
    @State private var quickLinks = QuickLinksController()
    /// Scroll-driven chrome state (scrolled away, passed section titles, section bar
    /// edge). Never read in `body`: only the section bar and row mask observe it, so
    /// scrolling does not re-render the whole screen (issue #8).
    @State private var scrollChrome = SongsScrollChrome()
    /// Far programmatic jumps teleport behind this fade (``ListJump``).
    @State private var jumpFade = ListJumpFade()
    /// The iPhone Duo bottom Filter field's top in ``pageSpace`` (issue #333).
    @State private var bottomFilterTop: CGFloat?
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var deviceLayout
    /// Song to scroll back to after an iPhone Duo fold/unfold rebuilt this list (`/duo` D6).
    /// The anchor this instance already scrolled to.
    @AppStorage("fst.songs.sortMode") private var sortMode = SongSortMode.title
    @AppStorage("fst.songs.sortAscending") private var sortAscending = true
    @AppStorage(SongGeneralFilter.storageKey) private var generalFilterData = Data()
    /// Older Item Shop toggles, read only to migrate into ``SongGeneralFilter``.
    @AppStorage(SongGeneralFilter.legacyInShopKey) private var legacyFilterInShop = false
    @AppStorage(SongGeneralFilter.legacyLeavingTomorrowKey)
    private var legacyFilterLeavingTomorrow = false
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

    private var generalFilterResult: Result<SongGeneralFilter, Error> {
        Result {
            try SongGeneralFilter.decodeSaved(
                generalFilterData, legacyInShop: legacyFilterInShop,
                legacyLeavingTomorrow: legacyFilterLeavingTomorrow
            )
        }
    }

    private var appliedGeneralFilter: SongGeneralFilter? {
        if case let .success(filter) = generalFilterResult { return filter }
        return nil
    }

    /// The first corrupt saved filter, which blocks the list until an explicit Reset.
    private var savedFilterError: Error? {
        if case let .failure(error) = generalFilterResult { return error }
        return playerScoreFilterError
    }

    private var appliedShopFilter: SongShopFilter {
        appliedGeneralFilter?.shop ?? SongShopFilter()
    }

    /// Loaded catalogue rows (the General filter's Year and Duration options).
    private var catalogueSongs: [Song] {
        if case let .loaded(payload) = state { return payload.catalog.songs }
        return []
    }

    /// Whether any saved General choice hides songs (Item Shop only while Shop is shown).
    private var generalFilterActive: Bool {
        appliedGeneralFilter?.isActive(shopVisible: !hideShop) == true
    }

    /// Store General choices and retire the migrated legacy Item Shop toggles.
    ///
    /// - Parameter filter: Validated General choices.
    /// - Throws: Encoder failure, leaving saved choices unchanged.
    private func saveGeneralFilter(_ filter: SongGeneralFilter) throws {
        let data = try filter.encoded()
        generalFilterData = data
        legacyFilterInShop = false
        legacyFilterLeavingTomorrow = false
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
        // Both categories off hides every song without classifying (web parity).
        guard appliedShopFilter.needsShopFeed else { return nil }
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

    /// Why saved score checks with a real cause cannot apply right now. Without a player
    /// there is no notice: a deselect resets them (web `resetSongSettingsForDeselect`,
    /// issue #359), and any left over stay inert like the web's.
    private var playerScoreFilterPausedMessage: String? {
        guard case .loaded = state, session.selectedPlayer != nil,
              let filter = appliedPlayerScoreFilter, filter.isActive else { return nil }
        if !filter.scoped(to: visibleInstruments).isActive {
            return "Player score filters paused while their charts are hidden in Settings. "
                + "Your choices are saved."
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
        session.selectedPlayer != nil && playerScoreFilterPausedMessage == nil
            ? (appliedPlayerScoreFilter?.scoped(to: visibleInstruments)
                ?? SongPlayerScoreFilter())
            : SongPlayerScoreFilter()
    }

    private var hiddenPlayerScoreChecks: Bool {
        guard session.selectedPlayer != nil, let filter = appliedPlayerScoreFilter else { return false }
        return filter.scoped(to: visibleInstruments) != filter
    }

    /// Tight, web-like row gutters: a small vertical gap keeps varied-height glass
    /// cards close together (web's virtualized list uses a 2pt row gap).
    private var songRowInsets: EdgeInsets {
        EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)
    }

    /// General filters need no player, so Filter is offered whenever saved filters
    /// decode (web: the Filter button is always shown on Songs).
    private var canPresentFilter: Bool {
        savedFilterError == nil
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
        _shownRevision = State(initialValue: session.publicationRevision)
        _refreshFailure = State(initialValue: initialRefreshError)
        _searchText = searchText
        _settledSearch = settledSearch
        _instrument = selectedInstrument
        _navigationNotice = navigationNotice
    }

    // MARK: - Re-render boundary

    /// Whether two Songs pages show the same thing, so a parent that re-creates the page
    /// without changing it skips its body (mounted with `.equatable()`).
    ///
    /// The iOS 26 tab bar minimizes as the list scrolls down and expands as it returns
    /// to the top, and each change re-runs the section's navigation stack, which builds
    /// a new `SongsScreen`. Its `openShop` closure made every copy compare unequal, so
    /// each pass re-ran the whole filter/sort pipeline and List on the main thread in the
    /// middle of the gesture, and the large title and first rows jumped (issue #325).
    /// `openShop` compares always-equal, like `SplitOpenReporter`: the parent re-creates
    /// it every pass and it only writes parent-owned navigation state. The bindings and
    /// the page's own state, environment and observed session update it directly.
    ///
    /// - Parameters:
    ///   - lhs: The page currently shown.
    ///   - rhs: The page the parent built now.
    /// - Returns: True when the session and every value input match.
    nonisolated static func == (lhs: SongsScreen, rhs: SongsScreen) -> Bool {
        lhs.session === rhs.session
            && lhs.visibleInstruments == rhs.visibleInstruments
            && lhs.highContrast == rhs.highContrast
            && lhs.isVisible == rhs.isVisible
            && (lhs.openShop == nil) == (rhs.openShop == nil)
    }

    var body: some View {
        // Read here, not only inside the reload gate's content, so measuring the Duo
        // bottom field always rebuilds the list's fade mask (issues #294, #333).
        let filterTop = bottomFilterTop
        let filterPlacement = self.filterPlacement
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

            // A new publication refreshes the list in place (issue #304, load-transition
            // R3/R9): the list fades out, the spinner holds while the new catalogue is
            // read, and the rebuilt list fades in. The search field, page tools and title
            // stay outside so they stay put and usable.
            PublicationRefreshBoundary(
                session: session, title: "Songs", retainsHiddenContent: false,
                prepare: { revision in await preparePublication(revision) },
                onReveal: revealList
            ) {
            // Sort, filter, instrument and search changes fade the list out, show the
            // spinner (also while a search is typed ahead of its debounce) and stagger the
            // new list in (web `SongsPage` `settingsKey`, issue #71).
            FestivalReloadGate(
                key: reloadKey, isLoading: state.isLoading || searchText != settledSearch,
                spinnerLabel: "Loading songs",
                onReveal: revealList
            ) {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Songs unavailable") {
                    Task { await reload() }
                }
            case let .loaded(payload):
                if let error = savedFilterError {
                    invalidPlayerFilterView(error.localizedDescription)
                } else {
                let general = appliedGeneralFilter ?? SongGeneralFilter()
                let matching = payload.catalog.songs.filter { song in
                    SongSearch.matches(song, query: settledSearch)
                        && (instrument.map(song.supports) ?? true)
                        && general.matchesMetadata(song)
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
                        || general.restrictsMetadata
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
                                        || general.restrictsMetadata
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
                    populatedList(
                        payload: payload, visible: visible, effectiveMode: effectiveMode,
                        bottomFieldTop: filterPlacement == .bottom ? filterTop : nil
                    )
                }
                }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // iPhone Duo: the Filter field sits at the bottom of the page, on the trailing
        // page across a book-pose fold (owner, issues #333, #349;
        // ``SongsFilterFieldPlacement``, ``BottomSearchField``). A bottom safe-area
        // inset, so the list's last rows and the A–Z scrubber end above it and the
        // keyboard lifts it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if filterPlacement == .bottom {
                BottomSearchField(
                    text: $searchText, prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
                    identifier: "fst.songs.filter-field", clearIdentifier: "fst.songs.filter-clear",
                    hinge: BottomSearchFieldPlacement.pageHinge(for: deviceLayout),
                    space: Self.pageSpace
                ) { top in
                    if top != bottomFilterTop { bottomFilterTop = top }
                }
            }
        }
        .coordinateSpace(.named(Self.pageSpace))
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .navigationTitle("Songs")
        // Filter this list: an inline field pinned above it (issue #92; HIG Search
        // fields: "Use an inline field when adjacency clarifies that it filters one view
        // rather than searches globally"). Global search is the Search tab. Not on
        // iPhone Duo, which shows its own field at the bottom (issue #333).
        .modifier(SongsSystemFilterField(
            text: $searchText, enabled: filterPlacement == .system
        ))
        // Sort, Filter and Quick Links, then the account group: in the iPhone tab-bar
        // accessory on iOS 26.1+, the navigation bar elsewhere (issue #92); Sort and
        // Filter fold into one menu where there is too little room.
        .modifier(SongsPageTools(
            session: session, quickLinks: quickLinks,
            canPresentFilter: canPresentFilter,
            sortCustomized: !(sortMode == .title && sortAscending),
            filterActive: generalFilterActive || appliedPlayerScoreFilter?.isActive == true,
            stateToken: [
                sortMode.label, String(sortAscending), sortPausedMessage ?? "",
                filterAccessibilityValue,
            ],
            sortAction: sortAction, filterAction: filterAction,
            presentSort: { sortPresented = true },
            presentFilter: { filterPresented = true }
        ))
        #if os(iOS)
        .sheet(isPresented: $sortPresented) { sortSheet }
        // iPad menu bar View › Sort… / Filter… (no-op on iPhone).
        .macPageCommands(macCommands)
        #else
        // Mac: Sort is a popover from its toolbar button (HIG Popovers: "a little
        // information or functionality"); View › Sort… opens it too.
        .macPageCommands(macCommands)
        #endif
        .sheet(isPresented: $filterPresented) {
            if let appliedPlayerScoreFilter, let appliedGeneralFilter {
                SongsFilterSheet(
                    appliedGeneral: appliedGeneralFilter, showShop: !hideShop,
                    shopAvailable: shopOffersForCurrentSongs != nil,
                    availableDecades: SongGeneralFilter.decades(in: catalogueSongs),
                    availableDurations: SongGeneralFilter.durationBuckets(in: catalogueSongs),
                    appliedPlayerFilter: appliedPlayerScoreFilter,
                    appliedInstrument: instrument,
                    visibleInstruments: visibleInstruments,
                    selectedPlayer: session.selectedPlayer != nil,
                    scoreAvailable: scoreFilterAvailable,
                    invalidScoreFilteringEnabled: filterInvalidScores,
                    availableSeasons: SongSeasonBucket.keys(in: session.selectedPlayerScores)
                ) { general, player, instrumentChoice in
                    let playerData = try player.encoded()
                    try saveGeneralFilter(general)
                    playerScoreFilterData = playerData
                    instrument = instrumentChoice
                }
                .macSheetFrame()
            } else {
                Text("Saved song filters are invalid. Reset them from Songs to continue.")
            }
        }
        #if DEBUG
        .navigationDestination(item: $debugPushedSong) { song in
            // Same pushed-page chrome (Search + avatar) as `FestivalTabStack` destinations.
            if let bandType = FestivalDebugLaunch.songBandType {
                SongBandLeaderboardScreen(session: session, song: song, bandType: bandType)
                    .pageTrailingItems()
            } else if let instrument = FestivalDebugLaunch.songInstrument {
                SoloLeaderboardScreen(
                    song: song, instrument: instrument, session: session,
                    initialPage: 1, path: .constant([])
                )
                .pageTrailingItems()
            } else {
                SongDetailScreen(song: song, session: session, visibleInstruments: visibleInstruments)
                    .pageTrailingItems()
            }
        }
        .task(id: FestivalDebugLaunch.songTitleOrId) {
            guard debugPushedSong == nil, let target = FestivalDebugLaunch.songTitleOrId
            else { return }
            // Up to 60 s: a live catalogue under screen recording can take longer than 10 s.
            for _ in 0..<1200 {
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
        // Keyed on the generation the list has prepared for, not the session's: a new
        // publication is read by the refresh boundary's `prepare`, once the old list has
        // faded out, so the fading list never draws new rows.
        .task(id: CatalogueTaskKey(
            publicationRevision: shownRevision, visible: isVisible
        )) {
            guard isVisible else { return }
            switch state {
            case .loading, .failed:
                await reload()
            case let .loaded(payload):
                if shownRevision == session.publicationRevision,
                   let current = session.publicationId,
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
            guard isVisible else { return }
            if session.selectedBand != nil {
                switch session.bandLoadState {
                case .loading, .failed:
                    await session.refreshSelectedBand()
                case .none, .available, .syncing:
                    break
                }
                return
            }
            guard session.selectedPlayer != nil else { return }
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

    /// Coordinate space shared by the Duo bottom Filter field and the faded list.
    static let pageSpace = "fst.songs.page"

    /// Where this window shows the Filter Songs field (issue #333): the system field
    /// everywhere but iPhone Duo, which has its own at the bottom of the page.
    private var filterPlacement: SongsFilterFieldPlacement {
        #if os(iOS)
        SongsFilterFieldPlacement.resolve(pose: deviceLayout.pose)
        #else
        .system
        #endif
    }

    /// Where the `.searchable` Filter Songs field sits.
    ///
    /// iOS (iPhone, iPad): the navigation-bar drawer, always displayed, so the
    /// field sits above the list and stays pinned while it scrolls (issue #92; HIG Search
    /// fields: "Put a top inline field above its list and consider pinning it to the top
    /// toolbar while scrolling"). The system placement elsewhere; there `.automatic`
    /// would collapse the field into a second magnifier that reads as global search
    /// (HIG Searching: "Show current scope with descriptive placeholder").
    static var filterFieldPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    /// Sort and Filter for View › Sort… / Filter… (Filter disabled when unavailable).
    private var macCommands: MacPageCommands {
        var commands = MacPageCommands()
        commands.sort = { sortPresented = true }
        if canPresentFilter { commands.filter = { filterPresented = true } }
        return commands
    }

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
        let general = appliedGeneralFilter ?? SongGeneralFilter()
        let labels = [
            general.restrictsYear ? "Year filter" : nil,
            general.restrictsDuration ? "Duration filter" : nil,
            !hideShop && general.shop.isActive ? "Item Shop filter" : nil,
            general.restrictsDoubleBass ? "Double Bass filter" : nil,
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
            return status + (effectivePlayerScoreFilter.isActive || general.restrictsMetadata
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
        .tint(generalFilterActive || appliedPlayerScoreFilter?.isActive == true
            ? BrandTokens.gold : BrandTokens.accentBlue)
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
        // No instrument: normalized to Title on appear / change, not a pause. No player:
        // a deselect reverts it to Title (issue #359); any left over shows Title silently.
        guard instrument != nil, session.selectedPlayer != nil else { return nil }
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
    /// player sort has no instrument or no player to order by.
    private var effectiveSortMode: SongSortMode {
        if sortPausedMessage != nil { return .title }
        if sortMode.isPlayerChartMode && (instrument == nil || session.selectedPlayer == nil) {
            return .title
        }
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
    /// - Returns: Accessible error and user-controlled reset of only the corrupt filters.
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
                    if case .failure = generalFilterResult {
                        try? saveGeneralFilter(SongGeneralFilter())
                    }
                    if playerScoreFilterError != nil { playerScoreFilterData = Data() }
                } label: {
                    Text("Reset saved filters")
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

    /// The loaded catalogue's list, section bar, A–Z scrubber and Quick Links.
    ///
    /// - Parameters:
    ///   - payload: The loaded catalogue.
    ///   - visible: Songs left after search and filters, in sort order.
    ///   - effectiveMode: The sort in force.
    ///   - bottomFieldTop: The iPhone Duo bottom Filter field's top in ``pageSpace``,
    ///     read in `body`; nil elsewhere (no bottom fade).
    /// - Returns: The list.
    private func populatedList(
        payload: CatalogPayload, visible: [Song], effectiveMode: SongSortMode,
        bottomFieldTop: CGFloat?
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
                            songRows(
                                group.songs, catalogueObservation: payload.observedPublicationId,
                                fadeOrder: fadeOrder
                            )
                        }
                    } else if let groups {
                        // Before iOS 26: sticky section titles (operator, 2026-09-28) on an
                        // opaque backing so rows never show through beneath them. The titles
                        // are the scrubber's and Quick Links' jump targets.
                        ForEach(groups) { group in
                            Section {
                                songRows(
                                    group.songs, catalogueObservation: payload.observedPublicationId,
                                    fadeOrder: fadeOrder
                                )
                            } header: {
                                groupHeader(group)
                            }
                        }
                    } else {
                        songRows(
                            visible, catalogueObservation: payload.observedPublicationId,
                            fadeOrder: fadeOrder
                        )
                    }
                }
                .listStyle(.plain)
                // The reveal's fade window: a scroll or section jump while the first rows
                // stagger in fades the rest in together (web `resetRush`, #323).
                .festivalScrollFadeInScope(resetKey: fadeLoadedAt)
                .modifier(ListJumpFadeEffect(fade: jumpFade))
                // Mac: ↑/↓ walk every song in list order, built or not.
                .macKeyboardRows((groups?.flatMap(\.songs) ?? visible).map {
                    MacKeyRow(id: $0.id, action: .route(.songDetail($0)))
                })
                // Before the section bar overlay: applied after it, this identifier
                // replaced the bar's own (`fst.songs.section-bar`) for UI tests.
                .accessibilityIdentifier("fst.songs.list")
                .modifier(SectionBarRowFade(
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
                ) { scrolled in
                    scrollChrome.setScrolled(scrolled)
                })
                .scrollContentBackground(.hidden)
                // iPhone Duo: rows fade out above the bottom Filter field and are not
                // drawn beneath it (scroll-edge R1, issue #333).
                .modifier(BottomSearchFieldFade(
                    chromeTop: bottomFieldTop, enabled: filterPlacement == .bottom,
                    space: Self.pageSpace
                ))
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
                    sections: showsIndex ? [] : (groups ?? []).compactMap(\.quickLink),
                    activationOffset: Double(SongsScrollChrome.landingOffset),
                    listNudger: scrollChrome.listNudger
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
                // Instant: an animated scroll back from deep in the old order would
                // build every row it passes (``ListJump``).
                var instant = Transaction()
                instant.disablesAnimations = true
                if let top { withTransaction(instant) { scrollProxy.scrollTo(top, anchor: .top) } }
            }
            .task {
                #if DEBUG
                // `FST_DEBUG_SONGS_SCROLL_STRESS=1`: replay a scroll stress pass in-app,
                // without XCUITest's accessibility snapshots (issue #8 measurements).
                guard SongsScrollStress.isRequested, let groups else { return }
                let ids = groups.map(\.id)
                let rows = SongsScrollStress.rowOffsets(sectionSizes: groups.map(\.songs.count))
                try? await Task.sleep(for: .seconds(3))
                // A list replaced while it waited (the Mac window measures its width
                // and swaps one column for the split) must not open the measured window:
                // its early start mark pulled launch work into the pass.
                guard !Task.isCancelled else { return }
                MainThreadStallMonitor.count(SongsScrollStress.startCounter)
                var current = 0
                for step in SongsScrollStress.plan(groupCount: ids.count) {
                    let target = ids[step.group]
                    if !SongsScrollStress.animatesFarJumps, jumpFade.isFar(rowDistance: rows[step.group] - rows[current]) {
                        MainThreadStallMonitor.count(SongsScrollStress.teleportCounter)
                        await jumpFade.teleport { scrollProxy.scrollTo(target, anchor: .top) }
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            scrollProxy.scrollTo(target, anchor: .top)
                        }
                    }
                    current = step.group
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
    /// The title lands where it pins under the section bar (issue #298), its first row
    /// right below it; the row fade under the bar stays out of that row
    /// (``SongsScrollChrome/fadeLimit(titleTop:barHeight:)``). A `List` honours `.top`, and
    /// ``SongsScrollChrome/settleLanding(on:generation:)`` corrects a far target placed from
    /// estimated row heights.
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
        let key = Self.headerKey(id)
        chrome.jump(to: key, in: keys)
        chrome.watchLanding(key)
        let generation = chrome.jumpGeneration
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(id, anchor: .top) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard chrome.jumpGeneration == generation else { return }
            withTransaction(instant) { proxy.scrollTo(id, anchor: .top) }
            await chrome.settleLanding(on: key, generation: generation)
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
        let generalFilter: Data
        let legacyShopFilter: [Bool]
        let playerScoreFilter: Data
        let instrument: Instrument?
        let search: String
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            sortMode: sortMode, sortAscending: sortAscending, generalFilter: generalFilterData,
            legacyShopFilter: [legacyFilterInShop, legacyFilterLeavingTomorrow],
            playerScoreFilter: playerScoreFilterData,
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
        let label = SongsInlineSectionTitle(
            key: Self.headerKey(group.id), label: group.label,
            spokenLabel: group.spokenLabel ?? group.label,
            accessibilityID: group.accessibilityID, chrome: scrollChrome
        )
        // The row traits go outside the anchor: under `QuickLinkSectionModifier` the
        // List no longer read them, so Duration, Year, Shop and score titles got the
        // default opaque row backing, separator and insets (issue #91).
        Group {
            if let link = group.quickLink {
                label.quickLinkSection(link)
            } else {
                label.id(group.id)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// A pinned section title: full-width, fully opaque backing (a flat surface with a
    /// hairline, matching the cards' border) so scrolling rows never show through,
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
    // MARK: Rows and the landscape grid

    /// Song cards per list row: two side by side under each section header in a
    /// landscape regular window (iPad, iPhone Duo inner display; operator 2026-10-04,
    /// `split-view.md`: Songs never splits, it uses the width instead), else one. With
    /// a player or band selected each song takes the full width so its row can put the
    /// profile's score cards on the right half (#340, `songs-profile-panel`). The Mac keeps one
    /// single-line row per song, like a table.
    private var songColumns: Int {
        #if os(macOS)
        1
        #else
        SongProfilePanelPolicy.gridColumns(
            layout: deviceLayout,
            hasSelectedProfile: session.selectedPlayer != nil || session.selectedBand != nil,
            filterInvalidScores: session.selectedBand == nil && filterInvalidScores
        )
        #endif
    }

    /// Rows may split into song | profile score cards: iPad and the iPhone Duo
    /// inner display (regular width *and* height; a large iPhone in landscape is
    /// compact height and keeps its rows) and the Mac.
    private var allowsProfilePanel: Bool {
        #if os(macOS)
        true
        #else
        deviceLayout.widthClass == .regular && deviceLayout.heightClass == .regular
        #endif
    }

    /// One section's songs as list rows: one card per row, or pairs in the landscape grid.
    ///
    /// - Parameters:
    ///   - songs: The section's songs, in order.
    ///   - catalogueObservation: Observed generation of the retained catalogue.
    ///   - fadeOrder: Stagger index per song id for rows that just loaded.
    /// - Returns: The rows.
    @ViewBuilder
    private func songRows(_ songs: [Song], catalogueObservation: Int, fadeOrder: [String: Int]) -> some View {
        let columns = songColumns
        if columns > 1 {
            ForEach(SongGridPolicy.rows(songs, columns: columns), id: \.first!.id) { pair in
                songGridRow(pair, columns: columns, catalogueObservation: catalogueObservation, fadeOrder: fadeOrder)
            }
        } else {
            ForEach(songs) { song in
                songLink(
                    for: song, catalogueObservation: catalogueObservation,
                    fadeIndex: Self.fadeIndex(song.songId, in: fadeOrder)
                )
            }
        }
    }

    /// A row's stagger index while the first rows are revealed: its place among them, or
    /// past the first screen for every other row, so rows a scroll or a section jump
    /// reaches during the reveal fade in with the rest instead of appearing opaque
    /// (load-transition R5, #323). Nil once the reveal is over (the plain row path).
    ///
    /// - Parameters:
    ///   - songId: The row's song.
    ///   - fadeOrder: Stagger index per first-screen song id; empty after the reveal.
    /// - Returns: The index to hand `festivalFadeIn(staggerIndex:)`.
    static func fadeIndex(_ songId: String, in fadeOrder: [String: Int]) -> Int? {
        guard !fadeOrder.isEmpty else { return nil }
        return fadeOrder[songId] ?? FestivalFadeIn.maxStaggeredItems
    }

    /// One grid row: up to `columns` cards of equal width (a short last row keeps its
    /// card at column width), each its own accessible link. On iPhone Duo the gutter sits
    /// on the hinge, flat or folded (``HingeRow`` page hinge, pattern `wide-columns` R3).
    private func songGridRow(
        _ songs: [Song], columns: Int, catalogueObservation: Int, fadeOrder: [String: Int]
    ) -> some View {
        HingeRow(spacing: SongGridPolicy.spacing) {
            ForEach(songs) { song in
                songCell(
                    for: song, catalogueObservation: catalogueObservation,
                    fadeIndex: Self.fadeIndex(song.songId, in: fadeOrder), windowMenu: false, gridCard: true
                )
                .frame(maxWidth: .infinity)
            }
            ForEach(songs.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
        // One menu for the row: a `List` row honours a single context menu.
        .openInNewWindowMenu(songs.map { (title: $0.title, route: FestivalWindowRoute.song(songId: $0.songId)) })
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(songRowInsets)
        .macKeyboardRow(songs[0].id)
    }

    /// One Songs list row (a single card).
    private func songLink(
        for song: Song, catalogueObservation: Int, fadeIndex: Int? = nil
    ) -> some View {
        songCell(for: song, catalogueObservation: catalogueObservation, fadeIndex: fadeIndex)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(songRowInsets)
            .macKeyboardRow(song.id)
    }

    /// A song card with its Song Detail link, context menu, fade, selected state and
    /// accessibility: one `fst.songs.row.<songId>` link, then any profile-card stops.
    ///
    /// - Parameters:
    ///   - song: Validated catalogue song to display.
    ///   - catalogueObservation: Observed generation of the retained catalogue.
    ///   - fadeIndex: Stagger index when the row just loaded, else nil.
    ///   - windowMenu: Attach this card's own "Open in New Window" menu.
    ///   - gridCard: The card shares its `List` row with another (landscape grid), so
    ///     it opens through its own borderless button (``SongGridCardLink``).
    /// - Returns: The decorated card.
    private func songCell(
        for song: Song, catalogueObservation: Int, fadeIndex: Int? = nil, windowMenu: Bool = true,
        gridCard: Bool = false
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
        // `ListDetailLink` is that link (Songs never splits, so it always pushes).
        let row = SongRowView(
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
        .environment(\.songRowsAllowProfilePanel, allowsProfilePanel)
        #if os(macOS)
        // On the Mac the row is the link's label, so its row button style draws the
        // hover tint and the keyboard focus ring on the card (an invisible link's
        // focus ring would be invisible too).
        let link = ListDetailLink(value: AppRoute.songDetail(song)) { row }
        #else
        let link = SongCardLink(route: AppRoute.songDetail(song), gridCard: gridCard) { row }
        #endif
        return link
        .contentShape(Rectangle())
        #if os(macOS)
        .contextMenu {
            MacSongRowMenu(song: song, chart: chart, hasPlayer: session.selectedPlayer != nil)
        }
        #else
        .modifier(SongCellWindowMenu(song: song, enabled: windowMenu))
        #endif
        // Rows arriving from a load fade in, staggered over the first screenful; rows
        // rebuilt later by scrolling appear instantly (nil index → no animation).
        .festivalFadeIn(staggerIndex: fadeIndex)
        .accessibilityElement(children: .combine)
        // `.combine` drops the invisible, `opacity(0)` `NavigationLink`'s own Button
        // trait (SwiftUI excludes fully transparent children from the merge), so the
        // row silently read as plain static text to VoiceOver and to `XCUIApplication
        // .buttons[...]` queries. Restore it explicitly rather than relying on the
        // link's own traits surviving the combine.
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fst.songs.row.\(song.songId)")
        #if !os(macOS)
        // The Mac's `ListDetailLink` already marks its label selected.
        .listDetailSelectable(AppRoute.songDetail(song))
        #endif
        // A wide row's profile cards follow the song link as their own VoiceOver stops
        // (`songs-profile-panel` R8); outside the link, which would collapse them.
        .songProfilePanelAccessibility(songId: song.songId)
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

    /// Reopen the row stagger window and reset the section headers as a new list is
    /// revealed (a reload or a publication refresh).
    private func revealList() {
        fadeLoadedAt = .now
        scrollChrome.resetHeaders()
    }

    /// Ready the list for a new publication while the refresh boundary hides it (issue
    /// #304): read the new catalogue. A failed read keeps the old rows with their paused
    /// notices (never an error page in their place), and the catalogue task retries when
    /// Songs is next shown. Shop and selected-player reads restart on their own; the
    /// publication guards keep them off rows from another publication.
    ///
    /// - Parameter revision: The session publication revision being prepared for.
    private func preparePublication(_ revision: Int) async {
        await reload(publicationRefresh: true)
        guard !Task.isCancelled else { return }
        shownRevision = revision
    }

    /// Refresh the public catalogue, preserving the last-viewed process cache.
    ///
    /// - Parameter publicationRefresh: The list is hidden behind the publication refresh
    ///   spinner: prime the first rows' artwork (the publication cleared it) and swap
    ///   without animation.
    private func reload(publicationRefresh: Bool = false) async {
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
            if prior == nil || publicationRefresh {
                await primeFirstArtwork(for: updated)
                try Task.checkCancellation()
            }
            if prior == nil { fadeLoadedAt = .now }
            withAnimation(publicationRefresh ? nil : .easeInOut(duration: 0.2)) {
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
/// before). ``ScrollAwayGate`` keeps the chrome this report moves from feeding back
/// into it (issue #5).
private struct ScrolledAwayTracker: ViewModifier {
    /// Receives the List's top content inset on every scroll geometry change.
    let topInsetChanged: (CGFloat) -> Void
    let changed: (Bool) -> Void
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
                changed(gate.isScrolled)
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
/// the List has scrolled. With ``SectionBarRowFade`` rows fade out just below its bottom
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
    @State private var top: CGFloat = 0
    @State private var height: CGFloat = 0

    var body: some View {
        // Always laid out (empty until scrolled), so the titles can measure against the
        // bar's top before it first shows a title. While scrolled it covers the bar's
        // height, so rows hidden under the bar never take a tap, even mid-push.
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: chrome.listScrolled ? height : 0)
                .contentShape(Rectangle())
            if chrome.listScrolled, let layout {
                if let previous = layout.previousY, let entry = entry(at: layout.current - 1) {
                    // Still leaving: the current title passed a little before the landing
                    // line. Hidden from VoiceOver, like any pushed-out header.
                    SongsSectionBarLabel(label: entry.label, spokenLabel: entry.spokenLabel)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .offset(y: previous)
                }
                if let current = layout.currentY, let entry = entry(at: layout.current) {
                    SongsSectionBarLabel(label: entry.label, spokenLabel: entry.spokenLabel)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            height = $0
                            chrome.setBarMetrics(top: top, height: $0)
                        }
                        .accessibilityIdentifier("fst.songs.section-bar")
                        .offset(y: current)
                }
                if let next = layout.nextY, let entry = entry(at: layout.current + 1) {
                    // The incoming title, drawn where its row is: the in-list copy hides
                    // while it is in the push band. VoiceOver reads the in-list title.
                    SongsSectionBarLabel(label: entry.label, spokenLabel: entry.spokenLabel)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .offset(y: next)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Titles pushed up leave at the bar's top edge, like pinned List headers; the
        // incoming title may sit below the bar's own frame.
        .clipShape(BelowTopShape())
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
            top = $0
            chrome.setBarMetrics(top: $0, height: height)
        }
    }

    /// Positions of the current and incoming titles (issue #288).
    private var layout: (current: Int, previousY: CGFloat?, currentY: CGFloat?, nextY: CGFloat?)? {
        let keys = sections.map(\.key)
        guard let index = chrome.currentSectionIndex(in: keys) else { return nil }
        let tops = chrome.titleTops
        let landing = SongsScrollChrome.landingOffset
        let height = chrome.barHeight.value
        let next = index + 1 < keys.count ? tops[keys[index + 1]] : nil
        let layout = SongsScrollChrome.sectionBarLayout(
            currentTop: tops[keys[index]],
            currentPassed: chrome.passedHeaders.contains(keys[index]),
            nextTop: next, landingOffset: landing, barHeight: height
        )
        // The title before the current one, only while the current one is pushing it out
        // (issue #297: never pinned under the current title).
        let previous = index > 0 && chrome.passedHeaders.contains(keys[index]) ?
            SongsScrollChrome.previousTitleY(
                currentTop: tops[keys[index]], landingOffset: landing, barHeight: height
            ) : nil
        return (index, previous, layout.currentY, layout.nextY)
    }

    private func entry(at index: Int) -> Entry? {
        sections.indices.contains(index) ? sections[index] : nil
    }
}

/// Everything from a frame's top edge down, reaching far past its bottom and sides.
private struct BelowTopShape: Shape {
    /// How far the path reaches past the frame, in points.
    private static let far: CGFloat = 10_000

    func path(in rect: CGRect) -> Path {
        let far = Self.far
        return Path(CGRect(
            x: rect.minX - far, y: rect.minY, width: rect.width + 2 * far, height: rect.height + far
        ))
    }
}

/// One floating section title.
private struct SongsSectionBarLabel: View {
    let label: String
    let spokenLabel: String

    var body: some View {
        Text(label)
            .font(.subheadline.bold())
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 20)
            .padding(.top, SongsScrollChrome.barTitleTopPadding)
            .padding(.bottom, SongsScrollChrome.barTitleBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section's in-list title (iOS 26): reports when it reaches the section bar's landing
/// line and blanks its text while the bar shows the same name (issues #286, #298).
///
/// A landed title rests exactly under the bar's copy of it. Clearing only the color
/// keeps the row's size, its jump target and its VoiceOver header. Observes
/// ``SongsScrollChrome/listScrolled`` itself, so only the title rows re-render when it
/// changes (issue #8). It also reports its top to a settling jump and how far the row
/// fade may reach near it (``SongsScrollChrome/fadeLimit(titleTop:barHeight:)``), and
/// hosts the locator that finds the List's scroll view for ``ListScrollNudger``.
private struct SongsInlineSectionTitle: View {
    let key: String
    let label: String
    let spokenLabel: String
    let accessibilityID: String
    let chrome: SongsScrollChrome
    /// This title has reached the landing line (its own geometry).
    @State private var passed = false
    /// The floating bar draws this title (it is pushing the pinned one, issue #288).
    @State private var inBand = false

    var body: some View {
        let topInset = chrome.listTopInset
        let line = SongsScrollChrome.landingOffset
        let barTop = chrome.barTop
        let barHeight = chrome.barHeight
        let blank = (passed || inBand) && chrome.listScrolled
        Text(label)
            .font(.subheadline.bold())
            .foregroundStyle(FestivalText.primary.opacity(blank ? 0 : 1))
            .padding(.horizontal, 20)
            .padding(.top, SongsScrollChrome.inlineTitleTopPadding)
            .padding(.bottom, SongsScrollChrome.inlineTitleBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(accessibilityID)
            .onGeometryChange(for: Bool.self) { proxy in
                SongsScrollChrome.headerPassed(
                    minY: proxy.frame(in: .scrollView).minY,
                    topInset: topInset.value, landingOffset: line
                )
            } action: { passed in
                self.passed = passed
                chrome.setHeader(key, passed: passed)
            }
            // Returning to the top forgets every passed title (issue #297); a built title
            // re-asserts its own answer, which its geometry repeats only when it changes.
            .onChange(of: chrome.listScrolled) {
                if passed { chrome.setHeader(key, passed: true) }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .scrollView).minY
            } action: { minY in
                chrome.recordTitleTop(key, minY: minY)
            }
            .onGeometryChange(for: CGFloat?.self) { proxy in
                SongsScrollChrome.pushBandTop(
                    titleTop: proxy.frame(in: .global).minY - barTop.value,
                    landingOffset: line, barHeight: barHeight.value
                )
            } action: { top in
                inBand = top != nil
                chrome.setTitleTop(key, top: top)
            }
            .onGeometryChange(for: CGFloat?.self) { proxy in
                SongsScrollChrome.fadeLimit(
                    titleTop: proxy.frame(in: .global).minY - barTop.value,
                    barHeight: barHeight.value
                )
            } action: { limit in
                chrome.setFadeLimit(key, limit: limit)
            }
            .onDisappear {
                chrome.setTitleTop(key, top: nil)
                chrome.setFadeLimit(key, limit: nil)
            }
            .background(ListScrollViewLocator(nudger: chrome.listNudger))
    }
}

/// Fades the List out under the floating section bar while scrolled (issue #10), with
/// the shared pinned-header fade (``PinnedHeaderEdgeFade``, issue #308). Inactive at the
/// top, where no row is under the bar and the large title shows. Near a section's start
/// the fade is only as deep as ``SongsScrollChrome/rowFadeLimit`` allows, so a landed
/// section's first row and an incoming title are never dimmed (issue #298).
///
/// Observes ``SongsScrollChrome`` here, so a scroll re-renders only this modifier, never
/// the List (issue #8).
private struct SectionBarRowFade: ViewModifier {
    let chrome: SongsScrollChrome
    /// False when the List has no sections or the OS has no section bar.
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.defaultMinListRowHeight, 0)
            .pinnedHeaderEdgeFadeMask(
                edge: chrome.sectionBarBottom, active: enabled && chrome.listScrolled,
                depthLimit: chrome.rowFadeLimit
            )
    }
}

/// Songs' page tools (issue #92): Sort, Filter and Quick Links, then the account group.
///
/// On iOS 26.1+ iPhone they sit in the tab-bar accessory (``PageToolsRegistry``); Sort
/// and Filter fold into one "Sort and Filter" menu when the inline accessory for this
/// window would be too narrow for every item, or at accessibility text sizes
/// (``PageToolsAccessoryFit``). The decision never follows the accessory's own width, so
/// the expanded and inline accessory show the same items (issue #300). Elsewhere they are
/// navigation-bar items, folding by ``SongsToolbarFold``. Either way Quick Links,
/// Notifications and Profile stay visible (HIG Toolbars, iOS: "Put only essential
/// actions in the main area; use More for the rest"). It measures its own width, so a
/// width change re-renders only this modifier.
private struct SongsPageTools<SortAction: View, FilterAction: View>: ViewModifier {
    let session: FestivalSession
    let quickLinks: QuickLinksController
    let canPresentFilter: Bool
    /// Sort differs from Title ascending (the folded menu is tinted gold, like Sort).
    let sortCustomized: Bool
    /// A filter is applied (the folded menu is tinted gold, like Filter).
    let filterActive: Bool
    /// Every value the Sort and Filter buttons display (accessibility values), so the
    /// accessory re-registers them when one changes.
    let stateToken: [String]
    let sortAction: SortAction
    let filterAction: FilterAction
    let presentSort: () -> Void
    let presentFilter: () -> Void
    @Environment(\.deviceLayout) private var layout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageToolsRegistry) private var pageTools
    @State private var width: CGFloat = 0

    private var folds: Bool {
        SongsToolbarFold.folds(
            width: width, dynamicTypeSize: dynamicTypeSize, chrome: layout.sectionChrome
        )
    }

    /// Whether Sort and Filter fold into one menu in the tab-bar accessory.
    private func foldsInAccessory(_ registry: PageToolsRegistry) -> Bool {
        PageToolsAccessoryFit.folds(
            windowWidth: registry.windowWidth,
            pageTools: (canPresentFilter ? 2 : 1) + (quickLinks.isAvailable ? 1 : 0),
            showsBell: session.selectedPlayer != nil,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    func body(content: Content) -> some View {
        let accessoryFolds = pageTools.map(foldsInAccessory) ?? false
        let highlighted = sortCustomized || filterActive
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .festivalPageTool(
                token: ["fold", String(highlighted), String(canPresentFilter)],
                order: PageToolOrder.primary, isEnabled: accessoryFolds
            ) {
                SongsSortFilterMenu(
                    canPresentFilter: canPresentFilter, highlighted: highlighted,
                    presentSort: presentSort, presentFilter: presentFilter
                )
            }
            .festivalPageTool(
                token: stateToken + [String(sortCustomized)],
                order: PageToolOrder.primary, isEnabled: !accessoryFolds
            ) {
                sortAction
            }
            .festivalPageTool(
                token: stateToken + [String(filterActive)],
                order: PageToolOrder.secondary, isEnabled: !accessoryFolds && canPresentFilter
            ) {
                filterAction
            }
            .toolbar {
                // With the tab-bar accessory, Sort and Filter are there instead.
                if pageTools == nil {
                    if folds {
                        ToolbarItem(placement: .festivalPageAction) {
                            SongsSortFilterMenu(
                                canPresentFilter: canPresentFilter,
                                highlighted: highlighted,
                                presentSort: presentSort, presentFilter: presentFilter
                            )
                        }
                    } else {
                        ToolbarItemGroup(placement: .festivalPageAction) {
                            sortAction
                            if canPresentFilter {
                                filterAction
                            }
                        }
                    }
                }
                QuickLinksToolbarItem(quickLinks)
                FestivalRootTrailingItems(session: session)
            }
            .festivalProvidesRootTrailingItems()
            .festivalRootChrome(session: session, providesTrailingItems: true)
    }
}

/// Sort and Filter folded into one menu for a narrow bar or large text (issue #92).
///
/// Not an ellipsis: HIG Designing for iPhone Duo, "reserve ellipsis for overflow"; the
/// filter-style symbol names what the menu holds.
private struct SongsSortFilterMenu: View {
    let canPresentFilter: Bool
    let highlighted: Bool
    let presentSort: () -> Void
    let presentFilter: () -> Void

    var body: some View {
        PageToolMenu("Sort and Filter", choices: choices) {
            Button(action: presentSort) {
                Label("Sort…", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("fst.songs.tools.sort")
            if canPresentFilter {
                Button(action: presentFilter) {
                    Label("Filter…", systemImage: "line.3.horizontal.decrease")
                }
                .accessibilityIdentifier("fst.songs.tools.filter")
            }
        } label: {
            Label("Sort and Filter", systemImage: "slider.horizontal.3")
        }
        .menuOrder(.fixed)
        .tint(highlighted ? BrandTokens.gold : BrandTokens.accentBlue)
        .accessibilityLabel("Sort and Filter")
        .accessibilityIdentifier("fst.songs.tools")
    }

    /// Sort and Filter for the inline-accessory sheet (``PageToolMenu``).
    private func choices() -> [PageToolMenuChoice] {
        var choices = [
            PageToolMenuChoice(
                id: "fst.songs.tools.sort",
                label: AnyView(Label("Sort…", systemImage: "arrow.up.arrow.down")), action: presentSort
            )
        ]
        if canPresentFilter {
            choices.append(PageToolMenuChoice(
                id: "fst.songs.tools.filter",
                label: AnyView(Label("Filter…", systemImage: "line.3.horizontal.decrease")),
                action: presentFilter
            ))
        }
        return choices
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


/// A Songs card's own Open in New Window menu (iPad), off inside a grid row, whose row
/// carries one menu for both cards.
#if !os(macOS)
// MARK: - Card links (iOS/iPadOS)

/// A Song card's Song Detail link on iOS/iPadOS.
///
/// A one-card row keeps the invisible ``ListDetailLink`` stretched over the card (the
/// `List` row is the tap target). A landscape grid row holds two cards, and a `List`
/// row fires every `NavigationLink` it contains on one tap, so both songs opened;
/// grid cards use ``SongGridCardLink`` instead.
private struct SongCardLink<Label: View>: View {
    let route: AppRoute
    let gridCard: Bool
    let label: Label

    /// Create a card link.
    ///
    /// - Parameters:
    ///   - route: Song Detail route.
    ///   - gridCard: The card shares its `List` row with another card.
    ///   - label: The card.
    init(route: AppRoute, gridCard: Bool, @ViewBuilder label: () -> Label) {
        self.route = route
        self.gridCard = gridCard
        self.label = label()
    }

    var body: some View {
        if gridCard {
            SongGridCardLink(route: route) { label }
        } else {
            ZStack {
                label
                ListDetailLink(value: route) { EmptyView() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0)
            }
        }
    }
}

/// One grid card's own Song Detail button: borderless, so the `List` row does not
/// claim the tap and only the touched card opens (HIG Lists and tables: each item is
/// its own target).
///
/// It routes like ``ListDetailLink``: the trailing pane when a split accepts the route,
/// else a push on the section's stack (`\.pushRoute`); outside the root shell (hosted
/// tests) a plain `NavigationLink`.
private struct SongGridCardLink<Label: View>: View {
    let route: AppRoute
    let label: Label
    @Environment(\.listDetailSelect) private var select
    @Environment(\.pushRoute) private var pushRoute

    /// Create a grid card link.
    ///
    /// - Parameters:
    ///   - route: Song Detail route.
    ///   - label: The card.
    init(route: AppRoute, @ViewBuilder label: () -> Label) {
        self.route = route
        self.label = label()
    }

    /// The action opening `route`, or nil when only a `NavigationLink` can.
    private var open: (@MainActor () -> Void)? {
        if let select, select.accepts(route) { return { select(route) } }
        if let pushRoute { return { pushRoute(route) } }
        return nil
    }

    var body: some View {
        Group {
            if let open {
                Button(action: open) { label }
                    .buttonStyle(.plain)
                    // VoiceOver's activate on the combined card runs this card's push.
                    .accessibilityAction(.default, open)
            } else {
                NavigationLink(value: route) { label }
                    .buttonStyle(.plain)
            }
        }
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverEffect(.highlight)
    }
}
#endif

private struct SongCellWindowMenu: ViewModifier {
    let song: Song
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.openInNewWindowMenu(.song(songId: song.songId))
        } else {
            content
        }
    }
}

// MARK: - Landscape grid policy

/// Pure rules for the Songs landscape grid (`.agents/design/apple/split-view.md`): the
/// app-wide ``WideColumns`` rule (pattern `wide-columns`, issue #350).
enum SongGridPolicy {
    /// Gap between the two cards of a grid row.
    static let spacing: CGFloat = WideColumns.spacing

    /// Cards per row: two in a landscape window that is regular in both dimensions (iPad
    /// landscape, iPhone Duo inner display in landscape), else one (iPhone, portrait,
    /// compact Split View windows, folded Duo).
    ///
    /// - Parameter layout: The page's device layout.
    /// - Returns: 1 or 2.
    static func columns(layout: DeviceLayout) -> Int {
        WideColumns.count(layout: layout)
    }

    /// Chunk a section's songs into rows of `columns`, keeping order (row-major).
    ///
    /// - Parameters:
    ///   - songs: The section's songs.
    ///   - columns: Cards per row (at least 1).
    /// - Returns: The rows; only the last may be short.
    static func rows<Item>(_ songs: [Item], columns: Int) -> [[Item]] {
        WideColumns.rows(songs, columns: columns)
    }
}
