import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Keep verified offline copy distinct from headerless, last-seen public bytes.
enum OfflineDisclosure {
    enum Content: Sendable {
        case songs
        case scores
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
        case (.songs, .some):
            "Offline - showing cached songs"
        case (.scores, .some):
            "Offline - showing cached scores"
        }
    }
}

/// Wrapping native text with a stable icon and explicit screen-reader label.
private struct FreshnessDisclosure: View {
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
private struct ServiceUnavailableView: View {
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
                isVisible: isVisible && path.isEmpty
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
    @State private var state: LoadState
    @Binding private var searchText: String
    @Binding private var settledSearch: String
    @Binding private var instrument: Instrument?
    @Binding private var navigationNotice: String?
    @State private var refreshFailure: String?
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
        highContrast: Bool = false, isVisible: Bool = true
    ) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        self.highContrast = highContrast
        self.isVisible = isVisible
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
                let visible = payload.catalog.songs.filter { song in
                    SongSearch.matches(song, query: settledSearch)
                        && (instrument.map(song.supports) ?? true)
                }.sorted { left, right in
                    let titleOrder = left.title.localizedCompare(right.title)
                    return titleOrder == .orderedSame
                        ? left.songId < right.songId
                        : titleOrder == .orderedAscending
                }
                if visible.isEmpty {
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
                                    ? (instrument == nil
                                        ? "No songs are available yet."
                                        : "No songs match your filters.")
                                    : "Try a different search."
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
                        ForEach(visible) { song in
                            NavigationLink(value: SongRoute.detail(song)) {
                                SongRowView(
                                    song: song, instrument: instrument,
                                    session: session, highContrast: highContrast
                                )
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("fst.songs.row.\(song.songId)")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await reload() }
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

    /// Avoid installing an empty accessibility node for an absent warning group.
    ///
    /// - Parameter payload: Catalogue state to check for visible disclosure.
    /// - Returns: True when at least one warning must appear above the rows.
    private func hasDisclosure(for payload: CatalogPayload) -> Bool {
        refreshFailure != nil || payload.isStale || payload.publicationId == nil
            || session.publicationId.map { $0 != payload.observedPublicationId } == true
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

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 44)
                .id(song.albumArt)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                Text(song.year.map { "\(song.artist) · \($0)" } ?? song.artist)
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
            }
            Spacer(minLength: 4)
            if let instrument, let difficulty = song.difficulty?.chartedValue(for: instrument) {
                DifficultyMeter(level: difficulty, raw: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    highContrast ? BrandTokens.textPrimary : BrandTokens.glassBorder,
                    lineWidth: highContrast ? 2 : 1
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

    private var charted: [Instrument] {
        Instrument.allCases.filter(song.supports)
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
                    }
                }
                .accessibilityElement(children: .combine)

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
                    ForEach(charted.filter(visibleInstruments.contains)) { instrument in
                        NavigationLink(value: SongRoute.leaderboard(song, instrument, 1)) {
                            Label(instrument.label, systemImage: "list.number")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12)
                                )
                        }
                        .accessibilityIdentifier(
                            "fst.song-detail.leaderboard.\(instrument.rawValue)"
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(ArtworkBackground(mode: .song(song.albumArt), session: session))
        .navigationTitle("")
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
                            scoreRow(entry)
                            .listRowBackground(BrandTokens.cardBackground)
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

    /// Keep score and accuracy whole when accessibility text is enlarged.
    ///
    /// - Parameter entry: Validated chart result in the current 25-row page.
    /// - Returns: Compact score columns or a wrapping stacked native row.
    private func scoreRow(_ entry: LeaderboardEntry) -> some View {
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
                accuracy(for: entry)
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }

    /// Announce accuracy as a percent independently of the raw chart value.
    ///
    /// - Parameter entry: Score row that may have no accuracy measurement.
    /// - Returns: Accessible, branded accuracy when present.
    @ViewBuilder
    private func accuracy(for entry: LeaderboardEntry) -> some View {
        if let value = entry.accuracy {
            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Accuracy \(ScoreFormatting.accuracy(value))%"
                    : "\(ScoreFormatting.accuracy(value))%"
            )
                .font(.body)
                .foregroundStyle(BrandTokens.gold)
        }
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

/// Preserve readable pager labels even when their native action is disabled.
private struct HighContrastPagerStyle: ButtonStyle {
    /// Render the label without the plain style's automatic disabled dimming.
    ///
    /// - Parameter configuration: Native press state and the button's label.
    /// - Returns: A readable label with pressed-state feedback.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
