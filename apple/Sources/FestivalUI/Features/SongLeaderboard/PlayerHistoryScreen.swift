import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistoryScreen

/// `/songs/:songId/:instrument/history`: every tracked score of the selected player on
/// one song and instrument, sortable. Native port of the web `PlayerHistoryPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/PlayerHistoryPage.tsx`).
///
/// Song Detail's Score History card previews the best five scores and its View All
/// Scores button opens this page (issue #324): pushed on iPhone, in the trailing pane
/// where Song Detail splits. Notifications and deep links open it too.
///
/// Like the song leaderboards it starts with the shared ``SongHeaderRow`` (song-header
/// R1), which hands off to the bar title once it scrolls under the bar. Rows reuse
/// Song Detail's ``ScoreHistoryListRow``; the best score is purple wherever the sort
/// puts it. Sort is a page tool (the iPhone tab accessory, the toolbar elsewhere) that
/// opens ``PlayerHistorySortSheet`` (a popover on the Mac, like Songs).
///
/// Reads only the allowlisted keyless song-history read (web
/// `playerHistoryQueryOptions(accountId, songId)`), filtered to the instrument.
struct PlayerHistoryScreen: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument

    @State private var state: LoadState = .loading
    @State private var lastRequest: RequestKey?
    @State private var sortMode = PlayerScoreHistorySort.defaultMode
    @State private var sortAscending = PlayerScoreHistorySort.defaultAscending
    @State private var sortPresented = false
    /// First staggered reveal finished; recycled rows then appear instantly.
    @State private var staggerSettled = false
    @State private var headerHidden = false
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openProfile) private var openProfile
    @Environment(\.pageToolsRegistry) private var pageTools
    @Environment(\.deviceLayout) private var layout
    /// The list page beside this page in a split (Song Detail drops the song header, #342).
    @Environment(\.splitDetailBesideList) private var besideList

    /// Scroll target at the top of the page (the song header).
    private static let topAnchor = "fst.history.top"
    /// Space above the song header, as on the song leaderboards.
    nonisolated private static let headerTopInset: CGFloat = 20

    enum LoadState {
        case loading
        case loaded(PlayerHistoryPayload)
        case failed(ServiceIssue)
    }

    private struct RequestKey: Hashable {
        let accountId: String
        let publicationRevision: Int
    }

    /// Create the page.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose history to show.
    ///   - instrument: Chart whose history to show.
    init(session: FestivalSession, song: Song, instrument: Instrument) {
        self.session = session
        self.song = song
        self.instrument = instrument
    }

    private var requestKey: RequestKey? {
        guard let accountId = session.selectedPlayer?.accountId else { return nil }
        return RequestKey(accountId: accountId, publicationRevision: session.publicationRevision)
    }

    /// The chart's scores, when loaded and available.
    private var entries: [ScoreHistoryEntry]? {
        guard session.selectedPlayer != nil, case let .loaded(payload) = state,
              payload.state == .available else { return nil }
        return payload.entries(songId: song.songId, instrument: instrument)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                header
                    .listRowInsets(EdgeInsets(top: Self.headerTopInset, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .id(Self.topAnchor)
                if let entries, !entries.isEmpty {
                    rows(entries)
                } else {
                    message
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(1, listHeight - headerHeight - Self.headerTopInset - 8))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                listHeight = size.height
                width = size.width
            }
            // Read from the List's offset (song-header R4), as the song leaderboards do.
            .songHeaderScrollAway(headerBottom: Self.headerTopInset + headerHeight) {
                headerHidden = $0
            }
            // Operator rule: changing the sort scrolls back to the top of the list.
            .onChange(of: PlayerHistorySortKey(mode: sortMode, ascending: sortAscending)) { _, _ in
                if reduceMotion {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                } else {
                    withAnimation { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                }
            }
            .rankingsListRailClearance(layout)
            // Loaded rows stagger in once; later recycling shows them instantly.
            .task(id: entries?.count) {
                staggerSettled = false
                guard let count = entries?.count, count > 0 else { return }
                await FadeStagger.settle(afterRevealing: count) { staggerSettled = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailFadeTestSafe()
        .festivalBackground(.song(song.albumArt), session: session)
        .festivalNavigationTitle(showsSongHeader ? song.title : caption)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: headerHidden)
        .toolbar {
            #if os(iOS)
            // iOS and iPadOS: the Mac keeps its window title (song-header R4).
            if showsSongHeader {
                SongBarTitleToolbarItem(
                    song: song, session: session, caption: caption, isShown: headerHidden,
                    identifier: "fst.history.pinned-title"
                )
            } else if !layout.sectionChrome.isVerticalBar {
                // Beside Song Detail: the chart's own title (#342), as the song board.
                InstrumentPageTitleToolbarItem(
                    instrument: instrument, title: caption, isShown: headerHidden,
                    identifier: "fst.history.pinned-title"
                )
            }
            #endif
            // With the iPhone tab-bar accessory, Sort is there instead.
            if pageTools == nil, sortAvailable {
                ToolbarItem(placement: .festivalPageAction) {
                    sortButton
                }
            }
        }
        .songBarTitleKeepsBarVisible(showsSongHeader)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // iPhone tab-bar accessory (issue #92): the page's one action.
        .festivalPageTool(
            token: ["sort", sortMode.rawValue, String(sortAscending)],
            order: PageToolOrder.primary, isEnabled: sortAvailable
        ) {
            sortButton
        }
        .macPageCommands(sortAvailable ? MacPageCommands(sort: { sortPresented = true }) : MacPageCommands())
        #if os(iOS)
        .sheet(isPresented: $sortPresented) { sortSheet }
        #endif
        .task(id: requestKey) {
            guard requestKey != nil else { return }
            if case .loading = state {
                await load()
            } else if let lastRequest, lastRequest != requestKey {
                await load()
            }
        }
        // The page root, as on Android and Windows (`fst.history`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.history")
    }

    // MARK: Header

    /// "Lead · Score History": the board line under the song title.
    private var caption: String { "\(instrument.label) · Score History" }

    /// The shared song header with the instrument and "Score History"; beside Song
    /// Detail in a split, the chart's own title instead (``InstrumentPageTitle``, #342).
    @ViewBuilder
    private var header: some View {
        if showsSongHeader {
            SongHeaderRow(song: song, session: session, onHeightChange: { headerHeight = $0 }) {
                HStack(spacing: 6) {
                    InstrumentIcon(instrument, size: 20)
                        .accessibilityHidden(true)
                    MarqueeText(caption)
                        .foregroundStyle(FestivalText.primary)
                }
            }
            .accessibilityIdentifier("fst.history.header")
        } else {
            InstrumentPageTitle(
                instrument: instrument, title: instrument.label, subtitle: "Score History",
                style: .header, identifier: "fst.history.board-title"
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
    }

    /// Whether the song header leads the page: not in a split beside Song Detail, where
    /// the song is on screen already (owner-approved variant, #342).
    private var showsSongHeader: Bool {
        SongLeaderboardBoardLine.showsSongHeader(besideList: besideList)
    }

    // MARK: Rows

    /// Every score in the chosen order, the best one highlighted.
    ///
    /// - Parameter entries: The chart's scores.
    /// - Returns: The list rows.
    @ViewBuilder
    private func rows(_ entries: [ScoreHistoryEntry]) -> some View {
        let sorted = PlayerScoreHistorySort.sorted(entries, mode: sortMode, ascending: sortAscending)
        let best = PlayerScoreHistorySort.highScoreIndex(in: sorted)
        let seasonColumn = ScoreRowSeasonPolicy.showsColumn(.historyList, width: Double(width))
        ForEach(Array(sorted.enumerated()), id: \.offset) { index, entry in
            ScoreHistoryListRow(
                entry: entry, isBest: index == best, seasonColumn: seasonColumn,
                currentSeason: session.catalogCurrentSeason
            )
            .accessibilityIdentifier("fst.history.row.\(index)")
            .detailStaggeredFadeIn(index: index, settled: staggerSettled)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: States

    /// The page's loading, empty and failure states below the header (web
    /// `PlayerHistoryPage`: select a player, spinner, not registered, syncing, empty).
    @ViewBuilder private var message: some View {
        if session.selectedPlayer == nil {
            FestivalEmptyState(
                "No Profile Selected", systemImage: "person.crop.circle",
                subtitle: "Select a player to view score history.",
                accessibilityIdentifier: "fst.history.no-player"
            ) {
                Button("Choose Profile") { openProfile() }
                    .festivalProminentButton()
                    .accessibilityIdentifier("fst.history.choose-profile")
            }
        } else {
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading Score History")
                    .accessibilityIdentifier("fst.history.loading")
            case let .failed(issue):
                ServiceStatusView(issue, title: "History Unavailable") {
                    Task { await load() }
                }
                .accessibilityIdentifier("fst.history.error")
            case let .loaded(payload):
                switch payload.state {
                case .unregistered:
                    // Unavailable, not empty: keeps its failure title and Retry (R1, R8).
                    ServiceUnavailableView(
                        title: "History Unavailable",
                        message: "Score history is only available for registered users.",
                        systemImage: "clock.badge.xmark",
                        retry: { Task { await load() } }
                    )
                    .accessibilityIdentifier("fst.history.unregistered")
                case .syncing:
                    ServiceUnavailableView(
                        title: "History Is Syncing",
                        message: "Score history is still syncing for this player. Check back soon.",
                        retry: { Task { await load() } }
                    )
                    .accessibilityIdentifier("fst.history.syncing")
                case .available:
                    FestivalEmptyState(
                        "No Score History", systemImage: "clock.arrow.circlepath",
                        subtitle: "No score history for this instrument.",
                        accessibilityIdentifier: "fst.history.empty"
                    )
                }
            }
        }
    }

    // MARK: Sort

    /// Sort is offered once there are scores to sort.
    private var sortAvailable: Bool { !(entries ?? []).isEmpty }

    /// The Sort page tool; gold while the sort differs from Score, descending.
    private var sortButton: some View {
        Button {
            sortPresented = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        #if os(macOS)
        .popover(isPresented: $sortPresented, arrowEdge: .bottom) {
            // The popover is its own chrome, as Songs' Sort (no title bar or Close).
            sortSheet
                .environment(\.festivalModalPreview, true)
                .formStyle(.grouped)
                .frame(width: 340, height: 420)
        }
        .help("Sort Scores")
        #endif
        .festivalBarItemAccessibility(
            label: "Sort", value: PlayerScoreHistorySort.spokenValue(mode: sortMode, ascending: sortAscending)
        )
        .accessibilityIdentifier("fst.history.sort.open")
        .tint(PlayerScoreHistorySort.isCustomized(mode: sortMode, ascending: sortAscending)
            ? BrandTokens.gold : BrandTokens.accentBlue)
    }

    /// The sort sheet (a popover on the Mac).
    private var sortSheet: some View {
        PlayerHistorySortSheet(mode: sortMode, ascending: sortAscending) { mode, ascending in
            sortMode = mode
            sortAscending = ascending
        }
    }

    // MARK: Load

    /// Load the selected player's history for this song and keep this chart's rows.
    private func load() async {
        guard let accountId = session.selectedPlayer?.accountId else { return }
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.songHistory(accountId: accountId, songId: song.songId)
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            state = .loaded(payload)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if requested == requestKey {
                state = .failed(ServiceIssue(error))
            }
        }
    }
}

/// Sort state compared as one value, so a mode or direction change scrolls to the top once.
struct PlayerHistorySortKey: Equatable {
    let mode: PlayerScoreSortMode
    let ascending: Bool
}
