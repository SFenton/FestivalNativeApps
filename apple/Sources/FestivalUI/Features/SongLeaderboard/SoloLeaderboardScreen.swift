import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Solo leaderboard

/// Loads one 25-row page and owns the native, one-based pagination controls.
struct SoloLeaderboardScreen: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.deviceLayout) private var layout
    @Binding var path: [AppRoute]
    @State private var page: Int
    @State private var state: LoadState
    @State private var lastRequest: RequestKey?
    /// The rows' first-load fade window: a scroll rushes their stagger (issue #323), rows
    /// the selected-row scroll realizes fade in with it, and once it closes recycled rows
    /// appear without a fade (R5). The selected-row reveal reads whether the reader
    /// scrolled first.
    @State private var fadeScope = FestivalFadeInScope()
    /// The song header has scrolled under the bar: the bar shows art, title and
    /// instrument instead (operator batch 7.2, like Song Detail).
    @State private var headerHidden = false
    /// Laid-out height of the song header, for the scrolled-away threshold.
    @State private var headerHeight: CGFloat = 0
    /// The chart's measured width, for the section's fitted columns (issue #37).
    @State private var chartWidth: CGFloat = 0
    /// Columns of rows: two on a full-width page in wide landscape, never beside Song
    /// Detail in a split (pattern `wide-columns`, issue #353).
    @State private var columns = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The list page beside this board in a split (Song Detail drops the song header, #342).
    @Environment(\.splitDetailBesideList) private var besideList
    /// The last loaded page: keeps the pager's page count and the footer's columns
    /// while the next page loads, so neither disappears (issue #93).
    @State private var shownPayload: LeaderboardPayload?
    /// Top edge of the pinned footer and pager in ``pageSpace``; nil without chrome.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade: full mid-list (and before iOS 18 / macOS 15),
    /// shrinking to 0 as the list reaches its end (issue #293).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    /// The selected player's row still needs scrolling into view once its page loads:
    /// opened from Song Detail's spotlight row or after a footer jump (web
    /// `navToPlayer`, issue #307).
    @State private var focusPending: Bool
    /// The rows' visible height: the result area under the header (spinner placeholder
    /// or error) fills it, so a page change never lets the List clamp the header back
    /// into view (issue #316).
    @State private var listHeight: CGFloat = 0

    /// The group card's inset above its first row and below its last (rows inside it
    /// abut); the pinned chrome still rests ``rowGap`` below the card.
    nonisolated private static let rowInset: CGFloat = 4
    /// Space between two rows, also kept above the pinned chrome (issue #293).
    nonisolated private static let rowGap: CGFloat = rowInset * 2
    /// Space between the bar and the song header row.
    nonisolated private static let headerTopInset: CGFloat = 20
    /// Scroll anchors of the song header and of the result area that replaces the rows
    /// while a page loads or after it failed.
    nonisolated private static let headerAnchor = "fst.song-leaderboard.header-anchor"
    nonisolated private static let resultAnchor = "fst.song-leaderboard.result-anchor"

    /// Coordinate space shared by the rows' fade mask and the pinned chrome.
    nonisolated private static let pageSpace = "fst.song-leaderboard.page"

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(ServiceIssue)

        /// Whether the page is still loading (drives ``FestivalReloadGate``).
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// Identity of a pending selected-row reveal: re-runs when the request or the
    /// revealed rows change.
    private struct FocusRequest: Equatable {
        let pending: Bool
        let rows: String?
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

    /// Identity of the rows currently shown (page + first row), for the stagger gate.
    private var loadedRowsKey: String? {
        guard case let .loaded(payload) = state else { return nil }
        return "\(page):\(payload.leaderboard.entries.first?.accountId ?? "")"
    }

    /// Carry an explicit deep-link page into this screen before cached history.
    ///
    /// - Parameters:
    ///   - song: Current catalog song.
    ///   - instrument: Requested solo chart.
    ///   - session: Shared process-lifetime API and artwork session.
    ///   - initialPage: One-based page from navigation/deep link.
    ///   - path: Native tab's route descriptor to update on paging.
    ///   - focusSelected: Bring the selected player's row into view once the page loads.
    ///   - initialState: Loading in production, fixture state in hosted UI tests.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialPage: Int, path: Binding<[AppRoute]>, focusSelected: Bool = false,
        initialState: LoadState = .loading
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _page = State(initialValue: max(1, initialPage))
        _focusPending = State(initialValue: focusSelected)
        _path = path
        _state = State(initialValue: initialState)
        if case let .loaded(payload) = initialState {
            _shownPayload = State(initialValue: payload)
        }
    }

    var body: some View {
        // Read here, not only inside the reload gate's content or the mask's lazy
        // `GeometryReader`, so measuring the pinned chrome always rebuilds the mask:
        // otherwise the first page kept an opaque mask, and rows showed behind the
        // pager, until something else re-rendered the page (issues #294, #305).
        let chromeTop = bottomChromeTop
        // Page changes remove the rows, show the spinner and fade the new page in (web
        // LoadGate, issue #71). The song header and its list stay from the first load on
        // and only the rows swap, for a failed page too (web keeps `SongInfoHeader`
        // outside its LoadGate and skips its stagger on 'paginate', issue #316).
        FestivalReloadGate(
            key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading leaderboard",
            spinnerIdentifier: "fst.song-leaderboard.loading"
        ) { reveal in
            if let shownPayload {
                // The rows of the page being revealed; nil while the next page loads or
                // after it failed.
                let rows = reveal.showsResult ? loadedPayload : nil
                let revealedRowsKey = reveal.showsResult ? loadedRowsKey : nil
                VStack(spacing: 0) {
                    scoreBanner(shownPayload)
                    ScrollViewReader { proxy in
                        List {
                            // The song header scrolls with the rows (no card behind it);
                            // once it passes under the bar the bar shows it instead.
                            scoreHeader(shownPayload)
                                .listRowInsets(EdgeInsets(
                                    top: Self.headerTopInset, leading: 16, bottom: 8, trailing: 16
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .id(Self.headerAnchor)
                            if rows == nil {
                                // A failed page's error, or nothing under the spinner,
                                // in the rows' place below the header (song-leaderboard-
                                // header R5, issue #316).
                                resultArea(reveal.showsResult ? failedIssue : nil)
                            }
                            // Row-major pairs in wide landscape (wide-columns R2, #353),
                            // the page's rows segments of one group card per column
                            // (leaderboard-row R10, owner #543): rows abut, and only
                            // the card's ends keep the row inset.
                            let entries = rows?.leaderboard.entries ?? []
                            ForEach(WideColumns.indexedRows(entries, columns: columns)) { row in
                                WideColumnsRow(columns: columns, count: row.items.count, matchesHeights: true) {
                                    ForEach(row.indexed, id: \.item.id) { index, entry in
                                        entryRow(entry, index: index)
                                            .festivalGroupSegment(
                                                .position(index: index, count: entries.count, columns: columns),
                                                separatorInset: SongLeaderboardRowCard.horizontalPadding
                                            )
                                    }
                                }
                                // The card's top inset is content padding: a lone top
                                // List row inset also left a gap under the first row
                                // on macOS.
                                .padding(.top, row.start == 0 ? Self.rowInset : 0)
                                .listRowInsets(EdgeInsets(
                                    top: 0, leading: 16,
                                    bottom: row.start + columns >= entries.count ? Self.rowInset : 0, trailing: 16
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        // Rows set their own 48 pt height (R2): the system minimum
                        // (about 52 pt on iOS 26) would open a strip of page between
                        // a group card's segments (#543).
                        .environment(\.defaultMinListRowHeight, 0)
                        .scrollContentBackground(.hidden)
                        // One fade window per revealed page (web `resetRush` on
                        // paginate): scrolling while its rows stagger in, or the
                        // selected-row scroll, fades the rest in together (#323).
                        .festivalScrollFadeInScope(fadeScope, resetKey: revealedRowsKey)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            listHeight = height
                        }
                        // Read from the List's offset (song-header R4): it recycles the
                        // header's row as it leaves the screen, before the header could
                        // report itself under the bar (#315, #316).
                        .songHeaderScrollAway(headerBottom: Self.headerTopInset + headerHeight) {
                            headerHidden = $0
                        }
                        // A page change under a collapsed header starts the new page at
                        // its first row and keeps the header under the bar; otherwise
                        // it returns to the top (web `goToPage('paginate')`, #316).
                        .onChange(of: requestKey) { _, _ in
                            let target = LeaderboardPaging.reloadScroll(
                                headerUnderBar: headerHidden, boardChanged: false
                            )
                            // After the List has swapped the rows for the result area.
                            Task { @MainActor in
                                switch target {
                                case .top: proxy.scrollTo(Self.headerAnchor, anchor: .top)
                                case .firstRow: proxy.scrollTo(Self.resultAnchor, anchor: .top)
                                }
                            }
                        }
                        // Opened for the selected player's row: scroll it into view once
                        // its page is revealed (web `navToPlayer`, issue #307).
                        .task(id: FocusRequest(pending: focusPending, rows: revealedRowsKey)) {
                            guard focusPending, let rows else { return }
                            guard let targetIndex = rows.leaderboard.entries.firstIndex(where: {
                                isSelectedAccount($0.accountId)
                            }) else {
                                focusPending = false
                                return
                            }
                            // After the row's own entrance (web `navToPlayer`, #323).
                            // A pair's identity is its first row's (wide-columns, #353).
                            let rowStart = WideColumns.rowStart(of: targetIndex, columns: columns)
                            if await SelectedRowReveal.reveal(
                                rows.leaderboard.entries[rowStart].id, proxy: proxy,
                                reduceMotion: reduceMotion, staggerIndex: targetIndex, scope: fadeScope
                            ) {
                                focusPending = false
                            }
                        }
                        .rankingsListRailClearance(layout)
                        // Rows fade out over up to 40 pt above the pinned footer and pager
                        // and are not drawn beneath them (web board `useScrollMask`, #93, #329),
                        // so the chrome floats over the page background with no opaque
                        // band, and no row text sits under its text (the contrast audit
                        // that once required the band). The fade shrinks away as the last
                        // row arrives, so the list ends one row gap above the chrome with
                        // no reserved margin (issue #293). Shared with every paginated
                        // board, with or without a footer (issue #305).
                        .bottomChromeFade(
                            chromeTop: chromeTop, distance: $bottomFadeDistance, in: Self.pageSpace
                        )
                    }
                }
            } else if case let .failed(issue) = state, reveal.showsResult {
                // The first page failed: no header to keep yet.
                ServiceStatusView(issue, title: "Leaderboard unavailable") {
                    Task { await loadPage() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pinned outside the reload gate so the player's footer and the pager stay put
        // while another page loads and only the rows fade (web portals both outside
        // its LoadGate, issue #93). A bottom safe-area inset, not a VStack sibling: the
        // tab bar minimizes on scroll down, and a sibling made the List's own frame grow
        // and shrink at the end of the page, which read as a bounce. As an inset the
        // List keeps its frame and only its content inset changes.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        // One set of columns for the page's rows and the pinned footer (web
        // `LeaderboardPage` `rankWidth`/`scoreWidth`, operator batch 7.3), with
        // season from 520 pt and stars from 768 pt of chart width. In the trailing
        // pane, every row becomes a multi-row card when any name would scroll (#364).
        .songLeaderboardSectionColumns(
            sectionColumns(shownPayload), names: sectionNames(shownPayload),
            template: shownPayload?.leaderboard.entries.first ?? selectedPlayerEntry(),
            currentSeason: session.catalogCurrentSeason,
            rowInset: WideColumns.rowMargins + layout.cutoutInsets.trailing
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            chartWidth = width
        }
        .wideColumnsCount($columns)
        .coordinateSpace(.named(Self.pageSpace))
        .detailFadeTestSafe()
        .festivalBackground(.song(song.albumArt), session: session)
        .festivalNavigationTitle(showsSongHeader ? song.title : instrument.label)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: headerHidden)
        .toolbar {
            #if os(iOS)
            // iOS and iPadOS: the Mac keeps its window title (song-header R4).
            if showsSongHeader {
                SongBarTitleToolbarItem(
                    song: song, session: session, caption: instrument.label,
                    captionInstrument: instrument, isShown: headerHidden,
                    identifier: "fst.song-leaderboard.pinned-title"
                )
            } else if !layout.sectionChrome.isVerticalBar {
                // Beside Song Detail: the board's own title (#342); the Duo rail draws
                // the system inline title instead, as on Full Rankings.
                InstrumentPageTitleToolbarItem(
                    instrument: instrument, title: instrument.label, isShown: headerHidden,
                    identifier: "fst.song-leaderboard.pinned-title"
                )
            }
            #endif
        }
        .songBarTitleKeepsBarVisible(showsSongHeader)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: requestKey) {
            if case .loading = state {
                await loadPage()
            } else if let lastRequest, lastRequest != requestKey {
                await loadPage()
            }
        }
    }

    // MARK: Rows

    /// One leaderboard row: a row of the page's group card (the player's purple band)
    /// with the chevron inside, as a button that pushes the player's page. One design
    /// with every leaderboard (web `entryRow`); a button that pushes onto the tab's path
    /// rather than a NavigationLink, so the List draws no second disclosure indicator
    /// outside it.
    ///
    /// - Parameters:
    ///   - entry: The row's entry.
    ///   - index: Its position on the page (fade stagger).
    /// - Returns: The row, filling its column.
    private func entryRow(_ entry: LeaderboardEntry, index: Int) -> some View {
        let isSelectedRow = isSelectedAccount(entry.accountId)
        return Button {
            path.append(playerRoute(for: entry))
        } label: {
            SongLeaderboardRowCard(
                entry: entry, isPlayer: isSelectedRow,
                currentSeason: session.catalogCurrentSeason
            )
            .contentShape(Rectangle())
        }
        .festivalRowButtonStyle()
        // Accessibility grouping first, fade outermost: wrapping the link in the fade
        // before `.contain` hid its score texts from the row's descendants.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.song-leaderboard.row.\(entry.accountId)")
        // The page scope decides whether it still fades (R5).
        .festivalFadeIn(staggerIndex: index)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pinned bottom chrome

    /// The current page's payload, nil while it loads or after a failure.
    private var loadedPayload: LeaderboardPayload? {
        if case let .loaded(payload) = state { return payload }
        return nil
    }

    /// The current page's failure, nil while it loads or once it loaded.
    private var failedIssue: ServiceIssue? {
        if case let .failed(issue) = state { return issue }
        return nil
    }

    /// What stands in for the rows below the kept song header: a failed page's status
    /// and Retry, or an empty, unspoken area while the next page loads under the gate's
    /// spinner (load-transition R4, issue #316). It is as tall as the visible rows, so
    /// the List keeps a collapsed header under the bar instead of clamping it back.
    ///
    /// - Parameter issue: The failure to show; nil while loading.
    /// - Returns: A full-width List row.
    private func resultArea(_ issue: ServiceIssue?) -> some View {
        Group {
            if let issue {
                ServiceStatusView(issue, title: "Leaderboard unavailable") {
                    Task { await loadPage() }
                }
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(1, listHeight))
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(Self.resultAnchor)
    }

    /// The player's footer and the pager, floating over the page background with no
    /// band behind them (issue #93, HIG Materials: "Let content scroll and peek
    /// through while preserving control and navigation legibility"). Built from the
    /// last loaded page, so paging keeps both in place while only the rows reload.
    private var bottomChrome: some View {
        let spacing = chromeSpacing
        return VStack(spacing: 0) {
            selectedPlayerFooter
                .padding(.top, spacing.footerTop)
                .padding(.bottom, spacing.footerBottom)
            if let shownPayload {
                RankingsPagerView(
                    page: page, totalPages: shownPayload.leaderboard.pageCount,
                    idPrefix: "fst.song-leaderboard", topPadding: spacing.pagerTop
                ) { destination in
                    move(to: destination)
                }
            }
        }
        .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
    }

    /// Padding that rests the last row one row gap above the footer, or above the
    /// pager when there is no footer (no selected player or no score here), and the
    /// footer one row gap above the pager (issue #293).
    private var chromeSpacing: PinnedChromeSpacing {
        PinnedChromeSpacing.resolve(
            rowGap: Double(Self.rowGap), rowBottomInset: Double(Self.rowInset), edgePadding: 8,
            hasFooter: session.selectedPlayer != nil && selectedPlayerEntry() != nil,
            hasPager: shownPayload != nil
        )
    }

    // MARK: Selected-player spotlight

    /// Whether `accountId` is the currently selected player, matching case-insensitively.
    ///
    /// - Parameter accountId: Row's account id.
    /// - Returns: True only when a player is selected and it is this account.
    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    /// The selected player's own score footer for this song/instrument, built from
    /// the score index already loaded for their profile (`FestivalSession.selectedPlayerScores`)
    /// — no extra network read, matching the web client's `playerData.scores` lookup
    /// (`LeaderboardPage.tsx:88-91`). Shown whenever they have a score here, since the
    /// paginated board may or may not currently show their row.
    ///
    /// Tapping the row opens Statistics, matching the web client's footer
    /// (`LeaderboardPage.tsx:476-500`, `navigate('/statistics')`), while their row is
    /// on the shown page; otherwise it jumps to their page and brings the row into view
    /// (a native addition beyond web). The band board's footer follows the same rule
    /// (``SelectedRowAction``, issue #307).
    @ViewBuilder
    private var selectedPlayerFooter: some View {
        if let selected = session.selectedPlayer, let entry = selectedPlayerEntry() {
            let rank = entry.rank
            // While the next page loads, its rank decides, so the footer keeps its
            // place and action (issue #93).
            let isVisible = LeaderboardPaging.isSelectedOnPage(
                accountId: selected.accountId, rank: rank, page: page, pageSize: 25,
                entries: loadedPayload?.leaderboard.entries.map(\.accountId)
            )
            // Same row design and columns as the list rows (operator batch 7.3). Off
            // this page, tapping jumps to the player's page; on it, opens Statistics.
            Group {
                let action = SelectedRowAction.footer(rank: rank, isVisible: isVisible, pageSize: 25)
                switch action {
                case .openProfile:
                    NavigationLink(value: AppRoute.statistics) {
                        footerRow(entry)
                    }
                    .accessibilityLabel(action.footerLabel(for: .player, rank: rank))
                    .accessibilityIdentifier("fst.song-leaderboard.spotlight-open")
                case let .jump(destination):
                    Button {
                        move(to: destination, focusSelected: true)
                    } label: {
                        footerRow(entry)
                    }
                    .accessibilityLabel(action.footerLabel(for: .player, rank: rank))
                    .accessibilityIdentifier("fst.song-leaderboard.spotlight-jump")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.song-leaderboard.spotlight-footer")
        }
    }

    /// The selected player's own score on this chart as a row, from the already-loaded
    /// score index; nil without a selected player or a ranked score here.
    private func selectedPlayerEntry() -> LeaderboardEntry? {
        guard let selected = session.selectedPlayer,
              let score = session.selectedPlayerScores[song.songId]?[instrument],
              let rank = score.rank else { return nil }
        return LeaderboardEntry(
            accountId: selected.accountId, displayName: selected.displayName,
            score: score.score, rank: rank, localRank: nil,
            accuracy: score.accuracy, isFullCombo: score.isFullCombo,
            stars: score.stars, season: score.season, difficulty: score.difficulty
        )
    }

    /// The page's fitted columns, measured over its rows and the pinned footer row.
    ///
    /// - Parameter payload: The last loaded page, kept while the next one loads.
    /// - Returns: Shared rank/score widths and the visible columns for one column of
    ///   `chartWidth`.
    private func sectionColumns(_ payload: LeaderboardPayload?) -> LeaderboardRowColumns {
        let rows = (payload?.leaderboard.entries ?? []) + [selectedPlayerEntry()].compactMap { $0 }
        return LeaderboardRowColumns.fit(
            // One column's page-equivalent width (wide-columns, #353).
            .songLeaderboard, width: Double(WideColumns.columnPageWidth(chartWidth, columns: columns)),
            ranks: rows.map(\.rank), scores: rows.map(\.score)
        )
    }

    /// Every name the page's rows and pinned footer row show, bold for the selected
    /// player, for the trailing pane's multi-row card decision (#364).
    ///
    /// - Parameter payload: The last loaded page, kept while the next one loads.
    /// - Returns: The section's names as the rows draw them.
    private func sectionNames(_ payload: LeaderboardPayload?) -> [RankingRowName] {
        let rows = (payload?.leaderboard.entries ?? []).map { entry in
            RankingRowName(
                name: SongLeaderboardEntryRow.displayName(entry),
                emphasized: isSelectedAccount(entry.accountId)
            )
        }
        let footer = selectedPlayerEntry().map {
            RankingRowName(name: SongLeaderboardEntryRow.displayName($0), emphasized: true)
        }
        return rows + [footer].compactMap { $0 }
    }

    /// The player's footer row, drawn exactly like a list row (shared with the band
    /// board's footer, ``SelectedScoreFooterRow``).
    private func footerRow(_ entry: LeaderboardEntry) -> some View {
        SelectedScoreFooterRow(entry: entry, currentSeason: session.catalogCurrentSeason)
    }

    /// Send a row to the shared Statistics tab when it is the selected player,
    /// otherwise to the viewed player's profile — matching the source's
    /// `navToPlayer` (`FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx`).
    ///
    /// - Parameter entry: Tapped chart row.
    /// - Returns: `.statistics` for the signed-in selected player, else `.player`.
    private func playerRoute(for entry: LeaderboardEntry) -> AppRoute {
        if let selected = session.selectedPlayer, selected.accountId == entry.accountId {
            return .statistics
        }
        return .player(accountId: entry.accountId, displayName: entry.displayName)
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

    /// The song header: art beside the title, artist and instrument (with the entry
    /// total), scrolling above rows so large text sizes keep a usable list.
    ///
    /// The title and artist fill the width beside the art on one marqueeing line each
    /// (the shared ``SongHeaderRow``, issue #315: the title used to wrap beside empty
    /// space).
    ///
    /// Beside Song Detail in a split it is the board's own title instead
    /// (``InstrumentPageTitle``: instrument artwork and name, the entry total under it).
    ///
    /// - Parameter payload: Current chart, including its optional totals disclosure.
    /// - Returns: The shared song header with the instrument's board line.
    @ViewBuilder
    private func scoreHeader(_ payload: LeaderboardPayload) -> some View {
        if showsSongHeader {
            SongHeaderRow(song: song, session: session, onHeightChange: { headerHeight = $0 }) {
                SongBoardLine(instrument: instrument, text: SongLeaderboardBoardLine.text(
                    name: instrument.label, totalEntries: payload.leaderboard.totalEntries,
                    showsTotals: payload.leaderboard.showLeaderboardEntryTotals
                ))
            }
            .accessibilityIdentifier("fst.song-leaderboard.header")
        } else {
            // Beside Song Detail the song is already on screen: the board's title only.
            InstrumentPageTitle(
                instrument: instrument, title: instrument.label,
                subtitle: SongLeaderboardBoardLine.totalText(
                    totalEntries: payload.leaderboard.totalEntries,
                    showsTotals: payload.leaderboard.showLeaderboardEntryTotals
                ),
                style: .header, identifier: "fst.song-leaderboard.board-title"
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
    }

    /// Whether the song header leads the board: not in a split beside Song Detail,
    /// where the song is on screen already (owner-approved variant, #342).
    private var showsSongHeader: Bool {
        SongLeaderboardBoardLine.showsSongHeader(besideList: besideList)
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
            shownPayload = payload
            state = .loaded(payload)
        } catch is CancellationError {
            if requested == requestKey { state = .loading }
        } catch let error as URLError where error.code == .cancelled {
            if requested == requestKey { state = .loading }
        } catch {
            if requested == requestKey {
                state = .failed(ServiceIssue(error))
            }
        }
    }

    /// Change both the visible page and its native navigation descriptor.
    ///
    /// - Parameters:
    ///   - destination: One-based page inside the loaded chart's bounds.
    ///   - focusSelected: Bring the selected player's row into view once it loads.
    private func move(to destination: Int, focusSelected: Bool = false) {
        state = .loading
        focusPending = focusSelected
        page = destination
        if !path.isEmpty {
            path[path.count - 1] = .songLeaderboard(song, instrument, destination, focusSelected: focusSelected)
        }
    }

}
