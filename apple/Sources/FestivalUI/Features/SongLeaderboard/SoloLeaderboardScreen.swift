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
    /// First staggered reveal of this page finished; recycled rows then appear instantly.
    @State private var staggerSettled = false
    /// The in-list song header has scrolled under the bar: show art, title and
    /// instrument in the navigation bar instead (operator batch 7.2, like Song Detail).
    @State private var headerHidden = false
    /// The song header's height, for when it has scrolled away.
    @State private var headerHeight: CGFloat = 0
    /// The chart's measured width, for the section's fitted columns (issue #37).
    @State private var chartWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    /// Row insets: two rows sit ``rowGap`` apart.
    nonisolated private static let rowInset: CGFloat = 4
    /// Space above the song header, at the top of the list.
    nonisolated private static let headerTopInset: CGFloat = 20
    /// Space between two rows, also kept above the pinned chrome (issue #293).
    nonisolated private static let rowGap: CGFloat = rowInset * 2

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
        // Page changes fade the rows out, show the spinner and fade the new page in
        // (web LoadGate, issue #71).
        FestivalReloadGate(key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading leaderboard") {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Leaderboard unavailable") {
                    Task { await loadPage() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    scoreBanner(payload)
                    ScrollViewReader { proxy in
                        List {
                            // The song header scrolls with the rows (no card behind it);
                            // once it passes under the bar the bar shows it instead.
                            scoreHeader(payload)
                                .listRowInsets(EdgeInsets(
                                    top: Self.headerTopInset, leading: 16, bottom: 8, trailing: 16
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(Array(payload.leaderboard.entries.enumerated()), id: \.element.id) { index, entry in
                                let isSelectedRow = isSelectedAccount(entry.accountId)
                                // One design with every leaderboard (web `entryRow`): each row
                                // its own material card, the player's purple, with the chevron
                                // inside the card. A button that pushes onto the tab's path
                                // rather than a NavigationLink, so the List draws no second
                                // disclosure indicator outside the card.
                                Button {
                                    path.append(playerRoute(for: entry))
                                } label: {
                                    HStack(spacing: 8) {
                                        SongLeaderboardEntryRow(
                                            entry: entry, isPlayer: isSelectedRow,
                                            currentSeason: session.catalogCurrentSeason
                                        )
                                        Image(systemName: "chevron.forward")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(FestivalText.deemphasized)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: LeaderboardRowMetrics.minHeight)
                                    .modifier(RankingRowSurface(isSelected: isSelectedRow))
                                    .contentShape(Rectangle())
                                }
                                .festivalRowButtonStyle()
                                // Accessibility grouping first, fade outermost: wrapping the
                                // link in the fade before `.contain` hid its score texts
                                // from the row's descendants.
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier(
                                    "fst.song-leaderboard.row.\(entry.accountId)"
                                )
                                .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                                .listRowInsets(EdgeInsets(
                                    top: Self.rowInset, leading: 16, bottom: Self.rowInset, trailing: 16
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        // Read from the List's offset: it recycles the header's row as
                        // it leaves the screen, before the header could report it.
                        .songHeaderScrollAway(headerBottom: Self.headerTopInset + headerHeight) {
                            headerHidden = $0
                        }
                        // Opened for the selected player's row: scroll it into view once
                        // (web `navToPlayer`, issue #307).
                        .task(id: focusPending) {
                            guard focusPending, let target = payload.leaderboard.entries.first(where: {
                                isSelectedAccount($0.accountId)
                            }) else {
                                focusPending = false
                                return
                            }
                            if await SelectedRowReveal.reveal(target.id, proxy: proxy, reduceMotion: reduceMotion) {
                                focusPending = false
                            }
                        }
                        .rankingsListRailClearance(layout)
                        // Rows fade out over up to 36 pt above the pinned footer and pager
                        // and are not drawn beneath them (web `useScrollFade`, issue #93),
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
                .task {
                    await FadeStagger.settle(afterRevealing: payload.leaderboard.entries.count) {
                        staggerSettled = true
                    }
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
        // season from 520 pt and stars from 768 pt of chart width.
        .leaderboardSectionColumns(sectionColumns(shownPayload))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            chartWidth = width
        }
        .coordinateSpace(.named(Self.pageSpace))
        // New rows stagger in again; the gate reveals them after its spinner, so the
        // settle timer runs from the reveal (inside the gated content).
        .onChange(of: loadedRowsKey) { _, _ in staggerSettled = false }
        .detailFadeTestSafe()
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle(song.title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: headerHidden)
        .toolbar {
            #if os(iOS)
            // The Mac keeps its leading window title: a centred toolbar item takes its
            // ideal width there and pushed trailing actions into overflow (song-header R4).
            SongBarTitleToolbarItem(
                song: song, session: session, caption: instrument.label, isShown: headerHidden,
                identifier: "fst.song-leaderboard.pinned-title"
            )
            if let shownPayload {
                RankingsPagerToolbarContent(
                    page: page, totalPages: shownPayload.leaderboard.pageCount,
                    idPrefix: "fst.song-leaderboard"
                ) { destination in
                    move(to: destination)
                }
            }
            #endif
        }
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

    // MARK: Pinned bottom chrome

    /// The current page's payload, nil while it loads or after a failure.
    private var loadedPayload: LeaderboardPayload? {
        if case let .loaded(payload) = state { return payload }
        return nil
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
            hasPager: shownPayload != nil && !layout.sectionChrome.isVerticalBar
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
    /// - Returns: Shared rank/score widths and the visible columns for `chartWidth`.
    private func sectionColumns(_ payload: LeaderboardPayload?) -> LeaderboardRowColumns {
        let rows = (payload?.leaderboard.entries ?? []) + [selectedPlayerEntry()].compactMap { $0 }
        return LeaderboardRowColumns.fit(
            .songLeaderboard, width: Double(chartWidth),
            ranks: rows.map(\.rank), scores: rows.map(\.score)
        )
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
    /// space). No card or band behind it, like Song Detail's (operator batch 7.2, issue
    /// #293): the shared dimmed song backdrop keeps the text legible.
    ///
    /// - Parameter payload: Current chart, including its optional totals disclosure.
    /// - Returns: The native song summary over the page backdrop.
    private func scoreHeader(_ payload: LeaderboardPayload) -> some View {
        SongHeaderRow(song: song, session: session, onHeightChange: { headerHeight = $0 }) {
            HStack(spacing: 6) {
                InstrumentIcon(instrument, size: 20)
                    .accessibilityHidden(true)
                MarqueeText(payload.leaderboard.showLeaderboardEntryTotals == true
                    ? "\(instrument.label) · \(payload.leaderboard.totalEntries.formatted()) entries"
                    : instrument.label)
                    .foregroundStyle(FestivalText.primary)
            }
        }
        .accessibilityIdentifier("fst.song-leaderboard.header")
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
