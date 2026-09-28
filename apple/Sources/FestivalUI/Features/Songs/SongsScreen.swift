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
    @State private var quickLinks = QuickLinksController()
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var deviceLayout
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

            Group {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading songs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
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
                let effectiveMode: SongSortMode = sortPausedMessage == nil ? sortMode : .title
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
                    return try SongCatalogSort.sorted(
                        filtered, mode: effectiveMode, ascending: sortAscending,
                        shopSongIds: membership
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
                            .foregroundStyle(BrandTokens.textPrimary)
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
                            .foregroundStyle(BrandTokens.textSecondary)
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
        // Library); global search is the search tab / toolbar button.
        .searchable(text: $searchText, prompt: Text("Filter Songs"))
        .toolbar {
            ToolbarItemGroup(placement: Self.pageActionPlacement) {
                sortAction
                if canPresentFilter {
                    filterAction
                }
            }
            QuickLinksToolbarItem(quickLinks)
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
        .festivalRootChrome(session: session, providesTrailingItems: true)
        .sheet(isPresented: $sortPresented) {
            SongsSortSheet(
                mode: sortMode, ascending: sortAscending,
                showShop: !hideShop, shopAvailable: shopOffersForCurrentSongs != nil
            ) { mode, order in
                sortMode = mode
                sortAscending = order
            }
        }
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
                    invalidScoreFilteringEnabled: filterInvalidScores
                ) { shop, player, instrumentChoice in
                    playerScoreFilterData = try player.encoded()
                    filterInShop = shop.inShop
                    filterLeavingTomorrow = shop.leavingTomorrow
                    instrument = instrumentChoice
                }
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

    /// Open a native Sort sheet while retaining the current instrument selection.
    private var sortAction: some View {
        Button {
            sortPresented = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
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
        let selected = (labels + [scoreLabel].compactMap { $0 })
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
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter Songs")
        .accessibilityValue(filterAccessibilityValue)
        .accessibilityIdentifier("fst.songs.filter")
        .tint(appliedShopFilter.isActive || appliedPlayerScoreFilter?.isActive == true
            ? BrandTokens.gold : BrandTokens.accentBlue)
    }

    /// Keep a saved Shop sort visible when its source is hidden or unavailable.
    private var sortPausedMessage: String? {
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
                .foregroundStyle(BrandTokens.textPrimary)
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
                    .foregroundStyle(BrandTokens.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(BrandTokens.textSecondary)
                Button {
                    playerScoreFilterData = Data()
                } label: {
                    Text("Reset saved score filters")
                        .font(.body)
                        .foregroundStyle(BrandTokens.textPrimary)
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
        22 + max(2, deviceLayout.cutoutInsets.trailing) + 8
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
        return ScrollViewReader { scrollProxy in
            ZStack(alignment: .trailing) {
                List {
                    if hasDisclosure(for: payload) {
                        disclosures(for: payload)
                    }
                    if let shopSections, shopSections.count > 1 {
                        ForEach(shopSections) { section in
                            Section {
                                ForEach(section.songs) { song in
                                    songLink(
                                        for: song, catalogueObservation: payload.observedPublicationId
                                    )
                                }
                            } header: {
                                shopSectionHeader(section)
                            }
                        }
                    } else if let durationSections, durationSections.count > 1 {
                        ForEach(durationSections) { section in
                            Section {
                                ForEach(section.songs) { song in
                                    songLink(
                                        for: song, catalogueObservation: payload.observedPublicationId
                                    )
                                }
                            } header: {
                                durationSectionHeader(section)
                            }
                        }
                    } else if showsIndex {
                        ForEach(indexSections) { section in
                            Section {
                                ForEach(section.songs) { song in
                                    songLink(
                                        for: song, catalogueObservation: payload.observedPublicationId
                                    )
                                }
                            } header: {
                                sectionIndexHeader(section)
                            }
                            .id(section.id)
                        }
                    } else {
                        ForEach(visible) { song in
                            songLink(
                                for: song, catalogueObservation: payload.observedPublicationId
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("fst.songs.list")
                .scrollContentBackground(.hidden)
                // Reserve room for the trailing section-index scrubber so its glass
                // capsule never overlaps a row's own trailing content (difficulty
                // meter, Shop badge, instrument-status chips) — the scrubber is an
                // overlay in this ZStack, not part of the List's own layout, so
                // without this a row's trailing edge sits directly underneath it.
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    Color.clear.frame(width: showsIndex ? scrubberTrailingReserve : 0)
                }
                .refreshable { await reload() }
                .quickLinks(
                    quickLinks, title: "\(effectiveMode.label) Quick Links",
                    sections: showsIndex ? [] : quickLinkSections(
                        shopSections: shopSections, durationSections: durationSections
                    )
                )
                if showsIndex {
                    SongSectionIndexScrubber(sections: indexSections) { id in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsIndex)
        }
    }

    /// Quick-link, the scrubber's counterpart for sorts it does not cover: Duration
    /// and Item Shop (`.agents/controls/quick-links/ios.md`). Title/Artist/Year
    /// return empty so the menu stays hidden while the scrubber is visible.
    ///
    /// - Parameters:
    ///   - shopSections: Grouped Shop buckets, when the current sort is `.shop`.
    ///   - durationSections: Grouped Duration buckets, when the current sort is `.duration`.
    /// - Returns: One quick-link section per visible, nonempty bucket.
    private func quickLinkSections(
        shopSections: [SongShopSection]?, durationSections: [SongDurationSection]?
    ) -> [QuickLinkSection] {
        if let shopSections, shopSections.count > 1 {
            return shopSections.map {
                QuickLinkSection(id: "shop:\($0.kind.rawValue)", title: $0.kind.label)
            }
        }
        if let durationSections, durationSections.count > 1 {
            return durationSections.map {
                QuickLinkSection(id: "duration:\($0.bucket.rawValue)", title: $0.bucket.label)
            }
        }
        return []
    }

    /// Shop bucket header, also the quick-link jump target for its section.
    ///
    /// Plain text on the List's own pinned-header material — matching
    /// ``sectionIndexHeader(_:)`` — rather than an opaque card `.background()`.
    /// This used to be inserted as an ordinary **row** (a sibling of the song rows
    /// in the same `ForEach`, not a real `Section` header), decorated with
    /// `.listRowBackground`/`.listRowInsets`/`.listRowSeparator`: modifiers that
    /// only mean something on a row. Once wrapped in a real `Section(header:)`
    /// (now the caller in `populatedList`), that leftover opaque rounded-rect
    /// background sat inside the List's own default pinned-header backing — which
    /// is not fully transparent — producing a visibly different "card" floating
    /// over a plain dark bar. Dropping the custom background and the row-only
    /// modifiers lets the header blend like the A–Z/Year headers already do.
    private func shopSectionHeader(_ section: SongShopSection) -> some View {
        Text(section.kind.label.uppercased())
            .font(.caption.bold())
            .foregroundStyle(BrandTokens.textSecondary)
            .accessibilityLabel(section.kind.label)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.songs.shop-section." + section.kind.rawValue)
            .quickLinkSection(id: "shop:\(section.kind.rawValue)", title: section.kind.label)
    }

    /// Duration bucket header, also the quick-link jump target for its section.
    ///
    /// See ``shopSectionHeader(_:)`` for why this is now plain text rather than a
    /// card-style `.background()`.
    private func durationSectionHeader(_ section: SongDurationSection) -> some View {
        Text(section.bucket.label.uppercased())
            .font(.caption.bold())
            .foregroundStyle(BrandTokens.textSecondary)
            .accessibilityLabel(section.bucket.label)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.songs.duration-section.\(section.bucket.rawValue)")
            .quickLinkSection(id: "duration:\(section.bucket.rawValue)", title: section.bucket.label)
    }

    /// Keep every grouped and ungrouped Song row on the same navigation path.
    ///
    /// - Parameters:
    ///   - song: Validated catalogue song to display.
    ///   - catalogueObservation: Observed generation of the retained catalogue.
    /// - Returns: One accessible Song Detail link with effective Shop highlighting.
    private func songLink(
        for song: Song, catalogueObservation: Int
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
                shopHighlight: highlight, profileChart: chart,
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

    /// Compact, tappable jump letter/year header for section-indexed sorts.
    ///
    /// - Parameter section: One nonempty bucket from `SongSectionIndex`.
    /// - Returns: A small, accessible List section header.
    private func sectionIndexHeader(_ section: SongSection) -> some View {
        Text(section.label)
            .font(.caption.bold())
            .foregroundStyle(BrandTokens.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.songs.section.\(section.id)")
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
            filtered, mode: sortMode == .shop ? .title : sortMode,
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
