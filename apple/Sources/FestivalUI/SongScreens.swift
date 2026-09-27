import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Keep verified offline copy distinct from headerless, last-seen public bytes.
enum OfflineDisclosure {
    enum Content: Sendable {
        case songs
        case scores
        case paths
        case shop
    }

    /// Name the source of an offline page without promoting observed IDs to proof.
    ///
    /// - Parameters:
    ///   - content: Catalogue or solo chart being shown from process memory.
    ///   - publicationId: Response-proven generation, nil for headerless bytes.
    /// - Returns: A distinct, accessible freshness and provenance statement.
    static func label(_ content: Content, publicationId: Int?) -> String {
        switch (content, publicationId) {
        case (.songs, nil):
            "Offline - last seen songs (publication unverified)"
        case (.scores, nil):
            "Offline - last seen scores (publication unverified)"
        case (.paths, nil):
            "Offline - last seen paths (publication unverified)"
        case (.shop, nil):
            "Offline - last seen shop (publication unverified)"
        case (.songs, .some):
            "Offline - showing cached songs"
        case (.scores, .some):
            "Offline - showing cached scores"
        case (.paths, .some):
            "Offline - showing cached paths"
        case (.shop, .some):
            "Offline - showing cached shop"
        }
    }
}

/// Wrapping native text with a stable icon and explicit screen-reader label.
struct FreshnessDisclosure: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(BrandTokens.gold)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Scalable error content: the iOS 26 system unavailable view fails the Dynamic Type audit.
struct ServiceUnavailableView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(BrandTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: retry) {
                        Text("Retry")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 12)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Typed native navigation within the Songs tab, separate from other tab stacks.
enum SongRoute: Hashable {
    case detail(Song)
    case leaderboard(Song, Instrument, Int)
    case shop
}

/// Songs, Detail and solo scores share one scene-owned navigation path.
struct SongNavigationRoot: View {
    let session: FestivalSession
    @Binding var path: [SongRoute]
    @Binding var searchText: String
    @Binding var settledSearch: String
    @Binding var selectedInstrument: Instrument?
    @Binding var navigationNotice: String?
    let visibleInstruments: Set<Instrument>
    let highContrast: Bool
    let isVisible: Bool

    /// Retain a shared route and visibility policy across platform navigation.
    ///
    /// - Parameters:
    ///   - session: Shared process-lifetime service and artwork cache.
    ///   - path: Current Songs navigation stack.
    ///   - searchText: Live search entry.
    ///   - settledSearch: Debounced search query.
    ///   - selectedInstrument: Scene-owned chart filter surviving section switches.
    ///   - navigationNotice: Explanation for safe route or filter invalidation.
    ///   - visibleInstruments: Persisted chart visibility.
    ///   - highContrast: Effective system or in-app contrast override.
    ///   - isVisible: False when another tab or a nested route covers Songs.
    init(
        session: FestivalSession, path: Binding<[SongRoute]>,
        searchText: Binding<String>, settledSearch: Binding<String>,
        selectedInstrument: Binding<Instrument?> = .constant(nil),
        navigationNotice: Binding<String?> = .constant(nil),
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        highContrast: Bool = false, isVisible: Bool = true
    ) {
        self.session = session
        _path = path
        _searchText = searchText
        _settledSearch = settledSearch
        _selectedInstrument = selectedInstrument
        _navigationNotice = navigationNotice
        self.visibleInstruments = visibleInstruments
        self.highContrast = highContrast
        self.isVisible = isVisible
    }

    var body: some View {
        NavigationStack(path: $path) {
            SongsScreen(
                session: session, searchText: $searchText, settledSearch: $settledSearch,
                selectedInstrument: $selectedInstrument, navigationNotice: $navigationNotice,
                visibleInstruments: visibleInstruments, highContrast: highContrast,
                isVisible: isVisible && path.isEmpty,
                openShop: { path.append(.shop) }
            )
                .navigationDestination(for: SongRoute.self) { route in
                    switch route {
                    case let .detail(song):
                        SongDetailScreen(
                            song: song, session: session, visibleInstruments: visibleInstruments
                        )
                    case let .leaderboard(song, instrument, page):
                        SoloLeaderboardScreen(
                            song: song, instrument: instrument,
                            session: session, initialPage: page, path: $path
                        )
                    case .shop:
                        ShopScreen(
                            session: session, isVisible: isVisible && path.last == .shop
                        )
                    }
                }
        }
    }
}

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
    @State private var shopFilterPresented = false
    @State private var profilePresented = false
    @AppStorage("fst.songs.sortMode") private var sortMode = SongSortMode.title
    @AppStorage("fst.songs.sortAscending") private var sortAscending = true
    @AppStorage("fst.songs.filterInShop") private var filterInShop = false
    @AppStorage("fst.songs.filterLeavingTomorrow")
    private var filterLeavingTomorrow = false
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
    @FocusState private var searchFocused: Bool

    enum LoadState {
        case loading
        case loaded(CatalogPayload)
        case failed(String)
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

    private var canPresentFilter: Bool {
        (session.selectedPlayer != nil && session.playerLoadState == .available && !hideShop)
            || appliedShopFilter.isActive
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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                TextField(
                    "", text: $searchText,
                    prompt: Text("Search").foregroundStyle(BrandTokens.textSecondary)
                )
                .font(.body)
                .foregroundStyle(BrandTokens.textPrimary)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("Search songs")
                .accessibilityIdentifier("fst.songs.search")
            }
            .padding(12)
            .frame(minHeight: 50)
            .background(BrandTokens.cardBackground, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

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
                ProgressView("Loading songs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ServiceUnavailableView(title: "Songs unavailable", message: message) {
                    Task { await reload() }
                }
            case let .loaded(payload):
                let matching = payload.catalog.songs.filter { song in
                    SongSearch.matches(song, query: settledSearch)
                        && (instrument.map(song.supports) ?? true)
                }
                let effectiveMode: SongSortMode = sortPausedMessage == nil ? sortMode : .title
                let membership = shopOffersForCurrentSongs.map { offers in
                    Set(offers.keys)
                }
                let sorted: Result<[Song], Error> = Result {
                    let filtered = try effectiveShopFilter.filtered(
                        matching, offersById: shopOffersForCurrentSongs
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
                                        ? "Try a different search or filter."
                                        : "Try a different search.")
                            )
                            .foregroundStyle(BrandTokens.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    List {
                        if hasDisclosure(for: payload) {
                            disclosures(for: payload)
                        }
                        if effectiveMode == .shop, let shopOffersForCurrentSongs {
                            let sections = SongCatalogSort.shopSections(
                                visible, offersById: shopOffersForCurrentSongs
                            )
                            if sections.count > 1 {
                                ForEach(sections) { section in
                                    HStack {
                                        Text(section.kind.label.uppercased())
                                            .font(.headline)
                                            .foregroundStyle(BrandTokens.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .accessibilityLabel(section.kind.label)
                                            .accessibilityAddTraits(.isHeader)
                                            .accessibilityIdentifier(
                                                "fst.songs.shop-section.\(section.kind.rawValue)"
                                            )
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(
                                        BrandTokens.cardBackground,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    ForEach(section.songs) { song in
                                        songLink(for: song)
                                    }
                                }
                            } else {
                                ForEach(visible) { song in
                                    songLink(for: song)
                                }
                            }
                        } else {
                            ForEach(visible) { song in
                                songLink(for: song)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("fst.songs.list")
                    .scrollContentBackground(.hidden)
                    .refreshable { await reload() }
                }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ArtworkBackground(
            mode: .carousel, session: session, visible: isVisible
        ))
        .navigationTitle("Songs")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { profileAction }
            #else
            ToolbarItem(placement: .primaryAction) { profileAction }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("All instruments") { instrument = nil }
                    ForEach(Instrument.allCases.filter(visibleInstruments.contains)) { choice in
                        Button(choice.label) { instrument = choice }
                    }
                } label: {
                    Label(
                        instrument?.label ?? "All instruments",
                        systemImage: "slider.horizontal.3"
                    )
                }
                .accessibilityIdentifier("fst.songs.instrument-filter")
            }
            ToolbarItem(placement: .primaryAction) { sortAction }
            if canPresentFilter {
                ToolbarItem(placement: .primaryAction) { filterAction }
            }
            if !hideShop, let openShop {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openShop()
                    } label: {
                        Label("Item Shop", systemImage: "bag")
                    }
                    .accessibilityIdentifier("fst.songs.shop")
                }
            }
        }
        .sheet(isPresented: $sortPresented) {
            SongsSortSheet(
                mode: sortMode, ascending: sortAscending,
                showShop: !hideShop, shopAvailable: shopOffersForCurrentSongs != nil
            ) { mode, order in
                sortMode = mode
                sortAscending = order
            }
        }
        .sheet(isPresented: $shopFilterPresented) {
            SongsShopFilterSheet(
                applied: appliedShopFilter, showShop: !hideShop,
                shopAvailable: shopOffersForCurrentSongs != nil,
                profileAvailable: session.selectedPlayer != nil
                    && session.playerLoadState == .available
            ) { filter in
                filterInShop = filter.inShop
                filterLeavingTomorrow = filter.leavingTomorrow
            }
        }
        .sheet(isPresented: $profilePresented) {
            ProfileSelectionSheet(session: session)
        }
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
                state = .failed("Search could not finish: \(error.localizedDescription)")
            }
        }
    }

    /// Keep the profile search reachable ahead of Song sorting and Shop actions.
    private var profileAction: some View {
        ProfileActionButton(session: session) {
            profilePresented = true
        }
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

    private var shopFilterAccessibilityValue: String {
        let labels = [
            filterInShop ? "In Shop" : nil,
            filterLeavingTomorrow ? "Leaving Tomorrow" : nil,
        ].compactMap { $0 }
        let selected = labels.isEmpty ? "No filters" : labels.joined(separator: ", ")
        return selected + (shopFilterPausedMessage == nil
            ? "" : ", paused; showing all songs")
    }

    private var filterAction: some View {
        Button {
            shopFilterPresented = true
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter Songs")
        .accessibilityValue(shopFilterAccessibilityValue)
        .accessibilityIdentifier("fst.songs.filter")
        .tint(appliedShopFilter.isActive ? BrandTokens.gold : BrandTokens.accentBlue)
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
        refreshFailure != nil || payload.isStale || payload.publicationId == nil
            || session.publicationId.map { $0 != payload.observedPublicationId } == true
            || session.playerError != nil
            || (session.selectedPlayer != nil && session.playerLoadState != .available)
            || (!hideShop && (
                session.shopError != nil
                    || (session.currentShop == nil && shopRefreshFailure != nil)
                    || session.currentShop?.isStale == true
            ))
            || sortPausedMessage != nil || shopFilterPausedMessage != nil
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
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .songs, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
            .accessibilityIdentifier("fst.songs.offline")
        } else if payload.publicationId == nil {
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
            Button("Choose Profile") { profilePresented = true }
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
        } else if !hideShop, let shop = session.currentShop, shop.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .shop, publicationId: shop.publicationId
                ),
                symbol: "wifi.slash"
            )
            .accessibilityIdentifier("fst.songs.shop-offline")
        }
    }

    /// Offer a manual retry for a selected player after 202 syncing or a failed read.
    private var profileRetryButton: some View {
        Button("Retry Player Scores") {
            Task { await session.refreshSelectedPlayer() }
        }
        .accessibilityIdentifier("fst.songs.profile-retry")
    }

    /// Keep every grouped and ungrouped Song row on the same navigation path.
    ///
    /// - Parameter song: Validated catalogue song to display.
    /// - Returns: One accessible Song Detail link with effective Shop highlighting.
    private func songLink(for song: Song) -> some View {
        let highlight = ShopPresentationPolicy.highlight(
            for: shopOffersForCurrentSongs?[song.songId],
            hidden: hideShop,
            highlightingDisabled: disableShopHighlighting
        )
        let chart = instrument ?? Instrument.allCases.first(where: visibleInstruments.contains)
        return NavigationLink(value: SongRoute.detail(song)) {
            SongRowView(
                song: song, instrument: instrument,
                session: session, highContrast: highContrast,
                shopHighlight: highlight, profileChart: chart,
                metadata: metadataVisibility,
                filterInvalidScores: filterInvalidScores,
                showInstrumentIcons: showInstrumentIcons,
                visibleInstruments: visibleInstruments,
                currentSeason: currentSeason
            )
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("fst.songs.row.\(song.songId)")
    }

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
            state = .loaded(updated)
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
                state = .failed(error.localizedDescription)
            }
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
struct SongsSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draftMode: SongSortMode
    @State private var draftAscending: Bool
    @State private var discardPending = false
    let mode: SongSortMode
    let ascending: Bool
    let showShop: Bool
    let shopAvailable: Bool
    let onApply: (SongSortMode, Bool) -> Void

    /// Start every presentation from the currently applied sort preference.
    ///
    /// - Parameters:
    ///   - mode: Applied public catalogue or Shop sort mode.
    ///   - ascending: Applied direction.
    ///   - showShop: False when Settings hides the entire Shop feature.
    ///   - shopAvailable: True only after receiving a validated public feed.
    ///   - onApply: Commit both draft fields together after explicit confirmation.
    init(
        mode: SongSortMode, ascending: Bool,
        showShop: Bool = false, shopAvailable: Bool = false,
        onApply: @escaping (SongSortMode, Bool) -> Void
    ) {
        self.mode = mode
        self.ascending = ascending
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    private var hasChanges: Bool {
        draftMode != mode || draftAscending != ascending
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort by") {
                    Picker("Sort by", selection: $draftMode) {
                        ForEach(SongSortMode.allCases.filter {
                            showShop || $0 != .shop
                        }) { choice in
                            Text(choice.label).tag(choice)
                                .disabled(choice == .shop && !shopAvailable)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("fst.songs.sort.mode")
                    if showShop && !shopAvailable {
                        Text("Item Shop sorting requires matching public Songs and Shop data.")
                            .font(.footnote)
                            .foregroundStyle(BrandTokens.textSecondary)
                    } else if !showShop && mode == .shop {
                        Text("Item Shop sort is saved but hidden. Reset to Title A-Z "
                            + "to choose another mode.")
                            .font(.footnote)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
                Section("Direction") {
                    Picker("Direction", selection: $draftAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fst.songs.sort.direction")
                }
                Section {
                    Button("Reset to Title A-Z") {
                        draftMode = .title
                        draftAscending = true
                    }
                    .font(.body)
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.songs.sort.reset")
                }
            }
            .navigationTitle("Sort Songs")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionLayout {
                    Button {
                        if hasChanges { discardPending = true }
                        else { dismiss() }
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .accessibilityIdentifier("fst.songs.sort.cancel")
                    Button {
                        onApply(draftMode, draftAscending)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.body.bold())
                            .foregroundStyle(
                                hasChanges
                                    ? BrandTokens.textPrimary : BrandTokens.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .disabled(!hasChanges
                        || (draftMode == .shop && (!showShop || !shopAvailable)))
                    .accessibilityIdentifier("fst.songs.sort.apply")
                }
                .padding(12)
                .background(BrandTokens.cardBackground)
            }
        }
        .alert("Discard sort changes?", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("The song list will keep its current order.")
        }
        .interactiveDismissDisabled()
    }
}

/// Compact, announced refresh error that does not remove the current song list.
struct RefreshErrorBanner: View {
    let message: String

    var body: some View {
        Label("Update failed: \(message)", systemImage: "exclamationmark.triangle")
            .foregroundStyle(BrandTokens.gold)
            .accessibilityIdentifier("fst.songs.refresh-error")
    }
}

/// A row's text, artwork and charted meter remain one accessible navigation action.
struct SongRowView: View {
    let song: Song
    let instrument: Instrument?
    let session: FestivalSession
    let highContrast: Bool
    let shopHighlight: ShopHighlight?
    let profileChart: Instrument?
    let metadata: SongMetadataVisibility
    let filterInvalidScores: Bool
    let showInstrumentIcons: Bool
    let visibleInstruments: Set<Instrument>
    let currentSeason: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Decorate one real Shop offer without turning it into a new navigation action.
    ///
    /// - Parameters:
    ///   - song: Public catalogue row.
    ///   - instrument: Optional currently selected chart.
    ///   - session: Process-scoped artwork loader.
    ///   - highContrast: Explicit content contrast override.
    ///   - shopHighlight: Validated, effectively enabled Shop badge.
    ///   - profileChart: First visible chart or explicit Songs chart filter.
    ///   - metadata: Persisted score-field visibility switches.
    ///   - filterInvalidScores: Hide unsupported filtered-score details explicitly.
    ///   - showInstrumentIcons: Saved status-chip setting.
    ///   - visibleInstruments: Enabled charts independent of chart availability.
    ///   - currentSeason: Current catalogue season for the inverted season badge.
    init(
        song: Song, instrument: Instrument?, session: FestivalSession,
        highContrast: Bool, shopHighlight: ShopHighlight? = nil,
        profileChart: Instrument? = nil,
        metadata: SongMetadataVisibility = SongMetadataVisibility(),
        filterInvalidScores: Bool = false,
        showInstrumentIcons: Bool = true,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        currentSeason: Int? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        self.highContrast = highContrast
        self.shopHighlight = shopHighlight
        self.profileChart = profileChart
        self.metadata = metadata
        self.filterInvalidScores = filterInvalidScores
        self.showInstrumentIcons = showInstrumentIcons
        self.visibleInstruments = visibleInstruments
        self.currentSeason = currentSeason
    }

    private var trailingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private var usesInstrumentChips: Bool {
        SongInstrumentStatusPolicy.showsChips(
            hasSelectedPlayer: session.selectedPlayer != nil,
            scoresAvailable: session.playerLoadState == .available,
            iconsEnabled: showInstrumentIcons,
            instrumentFilter: instrument,
            filterInvalidScores: filterInvalidScores,
            visibleInstruments: visibleInstruments
        )
    }

    private var structuredScore: (chart: Instrument, score: PlayerScore)? {
        guard !usesInstrumentChips, !filterInvalidScores,
              session.selectedPlayer != nil, session.playerLoadState == .available,
              let chart = profileChart, song.supports(chart),
              let score = session.selectedPlayerScores[song.songId]?[chart],
              score.score > 0 else {
            return nil
        }
        return (chart, score)
    }

    private var structuredFields: Result<[SongMetadataField], Error>? {
        guard let structuredScore else { return nil }
        return Result {
            try SongProfileCardPolicy.fields(
                for: structuredScore.score, chart: structuredScore.chart,
                song: song, currentSeason: currentSeason, visibility: metadata
            )
        }
    }

    private var artworkTile: some View {
        ArtworkTile(raw: song.albumArt, session: session, size: 44)
            .id(song.albumArt)
            .accessibilityHidden(true)
    }

    private var songSubtitle: String {
        var subtitle = song.artist
        if let year = song.year, year != 0 {
            subtitle += " · \(year)"
        }
        if let duration = song.formattedDuration {
            subtitle += " · \(duration)"
        }
        return subtitle
    }

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.headline)
                .foregroundStyle(BrandTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(songSubtitle)
                .font(.subheadline)
                .foregroundStyle(BrandTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedChartInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            songInfo
            if let chart = structuredScore?.chart, chart != .lead {
                Text("\(chart.label) chart")
                    .font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityIdentifier("fst.songs.metadata.chart.\(song.songId)")
            }
        }
    }

    @ViewBuilder private var profileContent: some View {
        if let selected = session.selectedPlayer {
            if usesInstrumentChips {
                SongInstrumentStatusChips(
                    songId: song.songId,
                    badges: SongInstrumentStatusPolicy.badges(
                        for: song, visibleInstruments: visibleInstruments,
                        scores: session.selectedPlayerScores[song.songId] ?? [:]
                    )
                )
            } else {
                SongProfileSummary(
                    player: selected, chart: profileChart,
                    chartAvailable: profileChart.map(song.supports) ?? false,
                    score: profileChart.flatMap {
                        session.selectedPlayerScores[song.songId]?[$0]
                    },
                    state: session.playerLoadState, visibility: metadata,
                    filterInvalidScores: filterInvalidScores, songId: song.songId
                )
            }
        }
    }

    @ViewBuilder private var shopBadge: some View {
        if let shopHighlight {
            Image(systemName: shopHighlight == .leavingTomorrow
                ? "clock" : "sparkles")
                .font(.subheadline)
                .foregroundStyle(
                    shopHighlight == .leavingTomorrow
                        ? BrandTokens.textPrimary : BrandTokens.gold
                )
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    shopHighlight == .leavingTomorrow
                        ? BrandTokens.statusRed : BrandTokens.appBackground,
                    in: Circle()
                )
                .accessibilityLabel("Item Shop: \(shopHighlight.label)")
                .accessibilityIdentifier("fst.songs.shop-badge.\(song.songId)")
        }
    }

    private var trailingContent: some View {
        trailingLayout {
            if metadata.intensity, let instrument, structuredScore == nil,
               let difficulty = song.difficulty?.chartedValue(for: instrument) {
                DifficultyMeter(level: difficulty, raw: true)
            }
            shopBadge
        }
    }

    /// Keep a right-aligned primary field and a full-width wrapped secondary row.
    ///
    /// - Parameter fields: One validated, source-ordered selected-chart projection.
    /// - Returns: One opaque, noninteractive native Song card content layout.
    private func structuredMetadataRow(_ fields: [SongMetadataField]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artworkTile
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        selectedChartInfo.frame(minWidth: 150, alignment: .leading)
                        Spacer(minLength: 0)
                        if let primary = fields.first {
                            SongMetadataFieldView(field: primary, songId: song.songId)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        selectedChartInfo
                        if let primary = fields.first {
                            HStack {
                                Spacer(minLength: 0)
                                SongMetadataFieldView(field: primary, songId: song.songId)
                            }
                        }
                    }
                }
            }
            if fields.count > 1 {
                SongProfileMetadataPills(
                    fields: Array(fields.dropFirst()), songId: song.songId
                )
            }
            if shopHighlight != nil {
                HStack {
                    Spacer(minLength: 0)
                    shopBadge
                }
            }
        }
    }

    var body: some View {
        Group {
            if let structuredFields, case let .success(fields) = structuredFields {
                structuredMetadataRow(fields)
            } else if dynamicTypeSize.isAccessibilitySize && usesInstrumentChips {
                VStack(alignment: .leading, spacing: 12) {
                    songInfo
                    HStack(alignment: .top, spacing: 12) {
                        artworkTile
                        Spacer(minLength: 0)
                        trailingContent
                    }
                    profileContent
                }
            } else {
                HStack(spacing: 12) {
                    artworkTile
                    VStack(alignment: .leading, spacing: 4) {
                        songInfo
                        profileContent
                    }
                    Spacer(minLength: 4)
                    trailingContent
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    shopHighlight == .leavingTomorrow ? BrandTokens.statusRed
                        : shopHighlight == .new ? BrandTokens.gold
                        : highContrast ? BrandTokens.textPrimary : BrandTokens.glassBorder,
                    lineWidth: shopHighlight != nil || highContrast ? 2 : 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Song detail

/// Catalog detail retains source section order for currently available data.
struct SongDetailScreen: View {
    let song: Song
    let session: FestivalSession
    let visibleInstruments: Set<Instrument>
    @AppStorage("fst.settings.pathDefaultView") private var pathDefaultView = PathDisplayMode.image
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting")
    private var disableShopHighlighting = false
    @State private var pathsPresented = false
    @State private var shopRefreshFailure: String?

    private struct ShopDetailTaskKey: Equatable {
        let publicationRevision: Int
        let hidden: Bool
    }

    private var charted: [Instrument] {
        Instrument.allCases.filter(song.supports)
    }

    private var pathInstruments: [Instrument] {
        Instrument.allCases.filter {
            $0 != .karaoke && visibleInstruments.contains($0)
        }
    }

    private var shopOffer: ShopSong? {
        hideShop ? nil : session.shopOffersById[song.songId]
    }

    private var shopHighlight: ShopHighlight? {
        ShopPresentationPolicy.highlight(
            for: shopOffer, hidden: hideShop,
            highlightingDisabled: disableShopHighlighting
        )
    }

    /// Supply enabled chart links without hiding the PWA's full Intensity grid.
    ///
    /// - Parameters:
    ///   - song: Catalog record opened from the Songs route.
    ///   - session: Process-lifetime client and artwork state.
    ///   - visibleInstruments: Solo charts enabled in Settings.
    init(
        song: Song, session: FestivalSession,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases)
    ) {
        self.song = song
        self.session = session
        self.visibleInstruments = visibleInstruments
    }

    var body: some View {
        #if os(iOS)
        detailContent.navigationBarTitleDisplayMode(.inline)
        #else
        detailContent
        #endif
    }

    /// Branded detail beneath platform-owned compact back navigation.
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ArtworkTile(raw: song.albumArt, session: session, size: 96)
                        .id(song.albumArt)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(song.title)
                            .font(.title.bold())
                        Text(song.artist)
                            .foregroundStyle(BrandTokens.textSecondary)
                        if let year = song.year {
                            Text(year.formatted(.number.grouping(.never)))
                                .foregroundStyle(BrandTokens.textSecondary)
                        }
                        if let shopHighlight {
                            Label(
                                "Item Shop: \(shopHighlight.label)",
                                systemImage: shopHighlight == .leavingTomorrow
                                    ? "clock" : "sparkles"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(
                                shopHighlight == .leavingTomorrow
                                    ? BrandTokens.textPrimary : BrandTokens.gold
                            )
                            .padding(8)
                            .background(
                                shopHighlight == .leavingTomorrow
                                    ? BrandTokens.statusRed : BrandTokens.cardBackground,
                                in: Capsule()
                            )
                            .accessibilityIdentifier("fst.song-detail.shop-badge")
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if !hideShop, let error = session.shopError
                    ?? (session.currentShop == nil ? shopRefreshFailure : nil) {
                    FreshnessDisclosure(
                        message: "Item Shop status unavailable: \(error)",
                        symbol: "exclamationmark.triangle"
                    )
                    .accessibilityIdentifier("fst.song-detail.shop-error")
                } else if !hideShop, let shop = session.currentShop, shop.isStale {
                    FreshnessDisclosure(
                        message: OfflineDisclosure.label(
                            .shop, publicationId: shop.publicationId
                        ),
                        symbol: "wifi.slash"
                    )
                    .accessibilityIdentifier("fst.song-detail.shop-offline")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Intensity").font(.title2.bold())
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10
                    ) {
                        ForEach(charted) { instrument in
                            if let level = song.difficulty?.chartedValue(for: instrument) {
                                HStack(spacing: 6) {
                                    Text(instrument.label)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    DifficultyMeter(level: level, raw: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .accessibilityIdentifier("fst.song-detail.intensity")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Leaderboards").font(.title2.bold())
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360), spacing: 12)],
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(charted.filter(visibleInstruments.contains)) { instrument in
                            SongScorePreview(
                                song: song, instrument: instrument, session: session
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ArtworkBackground(mode: .song(song.albumArt), session: session))
        .navigationTitle("")
        .toolbar {
            if let offer = shopOffer {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: offer.shopUrl) {
                        Label("Item Shop", systemImage: "bag")
                    }
                    .accessibilityIdentifier("fst.song-detail.shop")
                }
            }
            if !pathInstruments.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pathsPresented = true
                    } label: {
                        Label("Paths", systemImage: "map")
                    }
                    .accessibilityIdentifier("fst.song-detail.paths")
                }
            }
        }
        .sheet(isPresented: $pathsPresented) {
            if let first = pathInstruments.first {
                SongPathsSheet(
                    song: song, session: session, instruments: pathInstruments,
                    firstInstrument: first, defaultDisplay: pathDefaultView,
                    warnAboutKaraoke: visibleInstruments.contains(.karaoke)
                )
            }
        }
        .task(id: ShopDetailTaskKey(
            publicationRevision: session.publicationRevision, hidden: hideShop
        )) {
            guard !hideShop, session.currentShop == nil,
                  session.shopError == nil else { return }
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
}

/// Load a visible chart's top ten via the same public, publication-aware API as Solo.
struct SongScorePreview: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @State private var state: LoadState
    private let usesLiveClient: Bool

    private struct RequestKey: Equatable {
        let publicationRevision: Int
        let leeway: Double?
    }

    private var requestKey: RequestKey {
        RequestKey(
            publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(String)
    }

    /// Use the live client except when hosted tests provide a fixed visual state.
    ///
    /// - Parameters:
    ///   - song: Catalog item whose score preview is requested.
    ///   - instrument: Chart displayed in this card.
    ///   - session: Publication-aware, process-scoped public service client.
    ///   - initialState: Optional fixture state that does not start network work.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialState: LoadState? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _state = State(initialValue: initialState ?? .loading)
        usesLiveClient = initialState == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(instrument.label)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            NavigationLink(value: SongRoute.leaderboard(song, instrument, 1)) {
                Label("View full \(instrument.label) leaderboard", systemImage: "arrow.right")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(
                        BrandTokens.appBackground,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "fst.song-detail.leaderboard.\(instrument.rawValue)"
            )
            switch state {
            case .loading:
                ProgressView("Loading \(instrument.label) scores")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            case let .failed(message):
                Text("Scores unavailable: \(message)")
                    .font(.body)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry \(instrument.label) scores") {
                    Task { await load() }
                }
                .frame(minHeight: 44)
            case let .loaded(payload):
                previewRows(payload)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .task(id: requestKey) {
            guard usesLiveClient else { return }
            await load()
        }
    }

    /// Keep every response's freshness separate from its visible score rows.
    ///
    /// - Parameter payload: Validated first ten scores and response provenance.
    /// - Returns: Empty, live or offline native row content.
    @ViewBuilder
    private func previewRows(_ payload: LeaderboardPayload) -> some View {
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .scores, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
        } else if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live scores without publication verification",
                symbol: "info.circle"
            )
        }
        if payload.leaderboard.showLeaderboardEntryTotals == true {
            Text("\(payload.leaderboard.totalEntries) \(instrument.label) entries")
                .font(.subheadline)
                .foregroundStyle(BrandTokens.textSecondary)
        }
        if payload.leaderboard.entries.isEmpty {
            Text("No \(instrument.label) scores yet")
                .foregroundStyle(BrandTokens.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            let displayed = Array(payload.leaderboard.entries.prefix(10))
            ForEach(Array(displayed.enumerated()), id: \.offset) { index, entry in
                SongLeaderboardEntryRow(entry: entry)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier(
                        "fst.song-detail.preview-row.\(instrument.rawValue).\(entry.accountId)"
                    )
                if index < displayed.count - 1 {
                    Divider()
                }
            }
        }
    }

    /// Refresh one chart only when visible or after an explicit retry.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let payload = try await session.leaderboard(
                songId: song.songId, instrument: instrument,
                page: 1, top: 10, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            state = .loaded(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

/// Scalable score row shared by the native preview and the paginated Solo chart.
private struct SongLeaderboardEntryRow: View {
    let entry: LeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var accuracyTextWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var accuracyPillHeight: CGFloat = 24

    var body: some View {
        let rank = Text("#\(entry.rank.formatted())")
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(BrandTokens.textSecondary)
        let name = Text(
            entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
        )
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        let score = Text(entry.score.formatted())
            .font(.body)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let valuesLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                rank
                name.frame(maxWidth: .infinity, alignment: .leading)
            }
            valuesLayout {
                score
                if let value = entry.accuracy {
                    let color: Result<ScoreAccuracyTint, Error> = Result {
                        try ScoreFormatting.accuracyTint(value)
                    }
                    switch color {
                    case let .failure(error):
                        Text("Accuracy unavailable: \(error.localizedDescription)")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
                    case let .success(tint):
                        let fullCombo = entry.isFullCombo == true
                        let percent = "\(ScoreFormatting.accuracy(value))%"
                        let spoken = fullCombo
                            ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
                        accuracyBadge(
                            text: dynamicTypeSize.isAccessibilitySize
                                ? spoken : fullCombo ? "FC \(percent)" : percent,
                            spoken: spoken,
                            fill: fullCombo ? BrandTokens.cardBackground
                                : Color(
                                    .sRGB,
                                    red: Double(tint.red) / 255,
                                    green: Double(tint.green) / 255,
                                    blue: Double(tint.blue) / 255,
                                    opacity: 0.25
                                ),
                            fullCombo: fullCombo
                        )
                    }
                } else if entry.isFullCombo == true {
                    accuracyBadge(
                        text: dynamicTypeSize.isAccessibilitySize ? "Full combo" : "FC",
                        spoken: "Full combo; accuracy unavailable",
                        fill: BrandTokens.cardBackground, fullCombo: true
                    )
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Color.clear
                        .frame(
                            width: accuracyTextWidth + 16,
                            height: accuracyPillHeight
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }

    /// Keep the compact and large-text accuracy states legible and independently spoken.
    ///
    /// - Parameters:
    ///   - text: Visible percentage with a full-combo prefix only when explicitly true.
    ///   - spoken: Expanded VoiceOver label that never infers a missing FC flag.
    ///   - fill: Opaque card for an FC, or graded 25%-opaque accuracy color otherwise.
    ///   - fullCombo: Whether to add the source's gold full-combo outline.
    /// - Returns: One scalable, accessible score-accuracy pill.
    private func accuracyBadge(
        text: String, spoken: String, fill: Color, fullCombo: Bool
    ) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(BrandTokens.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyTextWidth + 16,
                height: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyPillHeight
            )
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if fullCombo {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BrandTokens.gold, lineWidth: 2)
                }
            }
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
    }
}

// MARK: - Solo leaderboard

/// Loads one 25-row page and owns the native, one-based pagination controls.
struct SoloLeaderboardScreen: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var path: [SongRoute]
    @State private var page: Int
    @State private var state: LoadState
    @State private var lastRequest: RequestKey?

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(String)
    }

    private struct RequestKey: Hashable {
        let page: Int
        let publicationRevision: Int
        let leeway: Double?
    }

    private var requestKey: RequestKey {
        RequestKey(
            page: page, publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    /// Carry an explicit deep-link page into this screen before cached history.
    ///
    /// - Parameters:
    ///   - song: Current catalog song.
    ///   - instrument: Requested solo chart.
    ///   - session: Shared process-lifetime API and artwork session.
    ///   - initialPage: One-based page from navigation/deep link.
    ///   - path: Native tab's route descriptor to update on paging.
    ///   - initialState: Loading in production, fixture state in hosted UI tests.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialPage: Int, path: Binding<[SongRoute]>, initialState: LoadState = .loading
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _page = State(initialValue: max(1, initialPage))
        _path = path
        _state = State(initialValue: initialState)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading leaderboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ServiceUnavailableView(title: "Leaderboard unavailable", message: message) {
                    Task { await loadPage() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        scoreBanner(payload)
                        scoreHeader(payload)
                    }
                    List {
                        if dynamicTypeSize.isAccessibilitySize {
                            scoreBanner(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            scoreHeader(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.leaderboard.entries) { entry in
                            SongLeaderboardEntryRow(entry: entry)
                            .listRowBackground(BrandTokens.cardBackground)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(
                                "fst.song-leaderboard.row.\(entry.accountId)"
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    pagination(totalPages: payload.leaderboard.pageCount)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArtworkBackground(mode: .song(song.albumArt), session: session))
        .navigationTitle("\(song.title) - \(instrument.label)")
        .task(id: requestKey) {
            if case .loading = state {
                await loadPage()
            } else if let lastRequest, lastRequest != requestKey {
                await loadPage()
            }
        }
    }

    /// Keep score provenance in both the fixed and accessibility-scrolling layouts.
    ///
    /// - Parameter payload: Current chart response with freshness provenance.
    /// - Returns: A native disclosure when the chart is stale or unverified.
    @ViewBuilder
    private func scoreBanner(_ payload: LeaderboardPayload) -> some View {
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .scores, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
            .padding(.horizontal, 16)
        } else if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live scores without publication verification",
                symbol: "info.circle"
            )
            .padding(.horizontal, 16)
        }
    }

    /// Let the source-chart title and totals scroll above rows at large text sizes.
    ///
    /// - Parameter payload: Current chart, including its optional totals disclosure.
    /// - Returns: A wrapping, opaque native song summary.
    private func scoreHeader(_ payload: LeaderboardPayload) -> some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 80)
                .id(song.albumArt)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(song.artist)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if payload.leaderboard.showLeaderboardEntryTotals == true {
                    Text("\(payload.leaderboard.totalEntries) \(instrument.label) entries")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    /// Load a specific page and reject late responses from a previous selection.
    private func loadPage() async {
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.leaderboard(
                songId: song.songId, instrument: instrument,
                page: requested.page, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = LeaderboardPaging.corrected(
                requested: requested.page, totalPages: payload.leaderboard.pageCount
            )
            if corrected != requested.page {
                move(to: corrected)
                return
            }
            state = .loaded(payload)
        } catch is CancellationError {
            if requested == requestKey { state = .loading }
        } catch let error as URLError where error.code == .cancelled {
            if requested == requestKey { state = .loading }
        } catch {
            if requested == requestKey {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Change both the visible page and its native navigation descriptor.
    ///
    /// - Parameter destination: One-based page inside the loaded chart's bounds.
    private func move(to destination: Int) {
        state = .loading
        page = destination
        if !path.isEmpty {
            path[path.count - 1] = .leaderboard(song, instrument, destination)
        }
    }

    /// Render discoverable first/previous/next/last actions with an announced page.
    ///
    /// - Parameter totalPages: Number of pages computed from local entries.
    /// - Returns: Accessible native pagination control row.
    private func pagination(totalPages: Int) -> some View {
        let first = pagerButton("First", enabled: page > 1) { move(to: 1) }
            .accessibilityIdentifier("fst.song-leaderboard.page-first")
        let previous = pagerButton("Previous", enabled: page > 1) {
            move(to: page - 1)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-previous")
        let indicator = Text("\(page) / \(totalPages)")
            .monospacedDigit()
            .accessibilityIdentifier("fst.song-leaderboard.page-info")
        let next = pagerButton("Next", enabled: page < totalPages) {
            move(to: page + 1)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-next")
        let last = pagerButton("Last", enabled: page < totalPages) {
            move(to: totalPages)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-last")
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                first
                previous
                Spacer(minLength: 0)
            }
            indicator
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                next
                last
            }
        }
        .padding(12)
        .background(BrandTokens.cardBackground)
    }

    /// Keep native pager actions scalable and large enough to touch on every row.
    ///
    /// - Parameters:
    ///   - title: Visible First, Previous, Next or Last action name.
    ///   - enabled: Whether the current page can move in that direction.
    ///   - action: Page transition to run when activated.
    /// - Returns: A native Button with a Fluent opaque plate and Dynamic Type text.
    private func pagerButton(
        _ title: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(
                    enabled ? BrandTokens.textPrimary : BrandTokens.textSecondary
                )
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(
                    BrandTokens.cardBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
    }
}

/// Preserve readable control labels even when their native action is disabled.
struct HighContrastPagerStyle: ButtonStyle {
    /// Render the label without the plain style's automatic disabled dimming.
    ///
    /// - Parameter configuration: Native press state and the button's label.
    /// - Returns: A readable label with pressed-state feedback.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
