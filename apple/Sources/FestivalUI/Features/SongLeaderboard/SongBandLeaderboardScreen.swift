import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SongBandLeaderboardScreen

/// `/songs/:songId/bands/:bandType` — per-song band leaderboard, matching the web
/// client's `SongBandLeaderboardPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx`).
///
/// `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=[&accountId=]` is a pure
/// read (`MetaDatabase.GetSongBandLeaderboard`/`GetSongBandLeaderboardEntryForAccount`,
/// only `SELECT`s). With a selected player, `accountId` returns their best band
/// (`selectedPlayerEntry`), highlighted on its page and pinned above the pager.
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    @State private var bandType: BandType
    @State private var page: Int
    @State private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    /// The band whose row is highlighted and brought into view: Song Detail's selected
    /// band row opens this board at its page (issue #307, web `navToPlayer`).
    @State private var focus: SongBandRowFocus?
    /// The focused row still needs scrolling into view once its page loads.
    @State private var focusPending: Bool
    /// Width of the pinned footer, which decides its season/stars columns.
    @State private var footerWidth: CGFloat = 0
    /// The last loaded page: keeps the pinned footer and pager in place while the next
    /// page loads, so only the rows reload (Song Leaderboard, issue #93); cleared when
    /// the band size changes.
    @State private var shownLeaderboard: SongBandLeaderboardResponse?
    /// Top edge of the pinned footer and pager in ``pageSpace``; nil without either.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade: the full 36 pt until the last row arrives
    /// above the chrome, then shrinking to nothing (issues #293, #305).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    private struct RequestKey: Equatable {
        let bandType: BandType
        let page: Int
        /// Selected player for the footer's `accountId` query.
        let accountId: String?
    }

    private var requestKey: RequestKey {
        RequestKey(bandType: bandType, page: page, accountId: session.selectedPlayer?.accountId)
    }

    /// Coordinate space shared by the rows' fade mask and the pinned pager.
    nonisolated private static let pageSpace = "fst.song-band-leaderboard.page"
    /// Space between two band cards, and between the last card and the pager.
    nonisolated private static let rowGap: CGFloat = 6

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose band leaderboard to show.
    ///   - bandType: Band size key (`Band_Duets`, `Band_Trios`, `Band_Quad`).
    ///   - initialPage: One-based page to open.
    ///   - focus: Band row to highlight and bring into view on that page, if any.
    init(
        session: FestivalSession, song: Song, bandType: String,
        initialPage: Int = 1, focus: SongBandRowFocus? = nil
    ) {
        self.session = session
        self.song = song
        _bandType = State(initialValue: BandType(rawValue: bandType) ?? .duets)
        _page = State(initialValue: max(1, initialPage))
        _focus = State(initialValue: focus)
        _focusPending = State(initialValue: focus != nil)
    }

    /// Whether a row is the focused band's: the band Song Detail or the footer opened
    /// this page for.
    ///
    /// - Parameter entry: A page row.
    /// - Returns: True for the band to bring into view.
    private func isFocused(_ entry: SongBandLeaderboardEntry) -> Bool {
        focus?.matches(entry) == true
    }

    /// Whether a row gets the selected purple highlight: the focused band, or the
    /// selected player's band (web `isSameSongBandEntry` against `selectedEntry`).
    ///
    /// - Parameters:
    ///   - entry: A page row.
    ///   - leaderboard: The page's response.
    /// - Returns: True for the selected or focused band's row.
    private func isHighlighted(
        _ entry: SongBandLeaderboardEntry, in leaderboard: SongBandLeaderboardResponse
    ) -> Bool {
        isFocused(entry) || leaderboard.isSelected(entry)
    }

    /// Open the page holding a band's row, then highlight it and bring it into view: the
    /// selected-band footer's off-page action (``SongBandRowNavigation/footerAction(for:pageEntries:)``).
    ///
    /// - Parameters:
    ///   - destination: One-based page containing the band's rank.
    ///   - entry: The band's row.
    private func jump(to destination: Int, focusing entry: SongBandLeaderboardEntry) {
        focus = SongBandRowFocus(entry)
        focusPending = true
        page = max(1, destination)
    }

    var body: some View {
        // Read here, not only inside the reload gate's content or the mask's lazy
        // `GeometryReader`, so measuring the pinned chrome always rebuilds the mask:
        // otherwise the first page kept an opaque mask, and rows showed behind the
        // pager, until something else re-rendered the page (issues #294, #305).
        let chromeTop = bottomChromeTop
        // Band size and page changes fade the rows out, show the spinner and fade the
        // new page in (web usePageTransition, issue #71).
        FestivalReloadGate(key: requestKey, isLoading: state.isLoading, spinnerLabel: "Loading band scores") {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Band scores unavailable") {
                    Task { await load() }
                }
            case let .loaded(payload):
                // The same band card as the Song Detail previews (web `PlayerBandCard`
                // on both pages, issue #90), each row its own material card. A
                // `ScrollView`, not a `List`: the cards are `NavigationLink`s, and a
                // `List` would draw a second disclosure chevron outside each card.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Self.rowGap) {
                            if payload.leaderboard.entries.isEmpty {
                                Text("No \(bandType.label.lowercased()) scores yet.")
                                    .foregroundStyle(FestivalText.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(payload.leaderboard.entries) { entry in
                                SongBandPreviewRow(
                                    entry: entry, highlighted: isHighlighted(entry, in: payload.leaderboard)
                                )
                                    .accessibilityIdentifier("fst.song-band-leaderboard.row.\(entry.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, Self.rowGap)
                    }
                    // Opened for one band's row: scroll it into view once (web
                    // `navToPlayer`, issue #307).
                    .task(id: focusPending) {
                        guard focusPending,
                              let target = payload.leaderboard.entries.first(where: isFocused) else {
                            focusPending = false
                            return
                        }
                        if await SelectedRowReveal.reveal(target.id, proxy: proxy, reduceMotion: reduceMotion) {
                            focusPending = false
                        }
                    }
                }
                .rankingsListRailClearance(layout)
                // Cards fade out above the pinned pager like the solo board's rows
                // (issue #305): a sibling pager under the scroll view cut them off
                // with a hard edge.
                .bottomChromeFade(
                    chromeTop: chromeTop, distance: $bottomFadeDistance, in: Self.pageSpace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pinned outside the reload gate so the selected band's footer and the pager
        // stay put while only the cards reload, as a bottom safe-area inset for the same tab-bar reason as
        // `SoloLeaderboardScreen` (issue #93).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        .coordinateSpace(.named(Self.pageSpace))
        .festivalBackground(.carousel, session: session)
        .navigationTitle("\(bandType.label) Scores")
        .toolbar {
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) { bandTypeMenu }
            }
            #if os(iOS)
            if case let .loaded(payload) = state {
                RankingsPagerToolbarContent(
                    page: page, totalPages: payload.leaderboard.pageCount,
                    idPrefix: "fst.song-band-leaderboard"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        // iPhone tab-bar accessory (issue #92): Band Size.
        .festivalPageTool(token: bandType, order: PageToolOrder.primary) {
            bandTypeMenu
        }
        .onChange(of: bandType) { _, _ in
            focusPending = false
            page = 1
            shownLeaderboard = nil
        }
        .task(id: requestKey) { await load() }
    }

    // MARK: Pinned bottom chrome

    /// The selected band's footer and the pager, floating over the page background
    /// with no band behind them, like the Solo board's (issue #93). Built from the last
    /// loaded page, so paging keeps both in place while only the cards reload.
    private var bottomChrome: some View {
        let spacing = chromeSpacing
        return VStack(spacing: 0) {
            selectedBandFooter
                .padding(.top, spacing.footerTop)
                .padding(.bottom, spacing.footerBottom)
            if let shownLeaderboard {
                RankingsPagerView(
                    page: page, totalPages: shownLeaderboard.pageCount,
                    idPrefix: "fst.song-band-leaderboard", topPadding: spacing.pagerTop
                ) { destination in
                    page = destination
                }
            }
        }
        .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
    }

    /// Padding that rests the last card one row gap above the footer, or above the
    /// pager without a footer, and the footer one row gap above the pager (issue #293).
    private var chromeSpacing: PinnedChromeSpacing {
        PinnedChromeSpacing.resolve(
            rowGap: Double(Self.rowGap), rowBottomInset: Double(Self.rowGap), edgePadding: 8,
            hasFooter: shownLeaderboard?.selectedEntry != nil,
            hasPager: shownLeaderboard != nil && !layout.sectionChrome.isVerticalBar
        )
    }

    // MARK: Selected-band footer

    /// The footer's action. The loaded page's rows decide; while the next page loads,
    /// the band's rank against the requested page does, so the footer keeps its place
    /// and action (Solo board, issue #93).
    ///
    /// - Parameter entry: The selected player's band row.
    /// - Returns: Open Band Detail when the row is on this page, otherwise jump to it.
    private func footerAction(for entry: SongBandLeaderboardEntry) -> SelectedRowAction {
        if case let .loaded(payload) = state {
            return SongBandRowNavigation.footerAction(for: entry, pageEntries: payload.leaderboard.entries)
        }
        let pageSize = SongBandRowNavigation.pageSize
        return SelectedRowAction.footer(
            rank: entry.rank,
            isVisible: entry.rank > 0 && LeaderboardPaging.page(forRank: entry.rank, pageSize: pageSize) == page,
            pageSize: pageSize
        )
    }

    /// The selected player's band pinned above the pager (web `SongBandLeaderboardPage`
    /// `FixedLeaderboardPlayerFooter`), drawn like the Solo board's footer
    /// (``SelectedScoreFooterRow``) and following its rule (issue #307,
    /// ``SongBandRowNavigation/footerAction(for:pageEntries:)``): while the band's row
    /// is on this page it opens Band Detail; otherwise it jumps to the page holding
    /// the band's rank and brings the highlighted row into view.
    @ViewBuilder
    private var selectedBandFooter: some View {
        if let entry = shownLeaderboard?.selectedEntry {
            let action = footerAction(for: entry)
            let row = SelectedScoreFooterRow(
                entry: LeaderboardEntry(selectedBand: entry), currentSeason: session.catalogCurrentSeason
            )
            Group {
                switch action {
                case .openProfile:
                    NavigationLink(value: SongBandRowNavigation.bandRoute(entry)) { row }
                        .accessibilityLabel(action.footerLabel(for: .band, rank: entry.rank))
                        .accessibilityIdentifier("fst.song-band-leaderboard.spotlight-open")
                case let .jump(destination):
                    Button {
                        jump(to: destination, focusing: entry)
                    } label: {
                        row
                    }
                    .accessibilityLabel(action.footerLabel(for: .band, rank: entry.rank))
                    .accessibilityIdentifier("fst.song-band-leaderboard.spotlight-jump")
                }
            }
            .buttonStyle(.plain)
            // The footer's own columns, like the web's `computeRankWidth([rank])`, with
            // season from 520 pt and stars from 768 pt of footer width.
            .leaderboardSectionColumns(LeaderboardRowColumns.fit(
                .songLeaderboard, width: Double(footerWidth),
                ranks: [entry.rank], scores: [entry.score]
            ))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { footerWidth = $0 }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("fst.song-band-leaderboard.spotlight-footer")
        }
    }

    private var bandTypeMenu: some View {
        PageToolMenu("Band Size", choices: bandTypeChoices) {
            Picker("Band Size", selection: $bandType) {
                ForEach(BandType.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
        } label: {
            // A label (icon-only in bars) so the accessory can fill its 44 pt slot.
            Label("Band Size", systemImage: "person.3.fill")
        }
        .accessibilityIdentifier("fst.song-band-leaderboard.band-type-menu")
        .accessibilityLabel("Band size: \(bandType.label)")
    }

    /// The band sizes for the inline-accessory sheet (``PageToolMenu``).
    private func bandTypeChoices() -> [PageToolMenuChoice] {
        BandType.allCases.map { size in
            PageToolMenuChoice(
                id: "fst.song-band-leaderboard.band-type.\(size.rawValue)", label: AnyView(Text(size.label)),
                isSelected: size == bandType, action: { bandType = size }
            )
        }
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let payload = try await session.songBandLeaderboard(
                songId: song.songId, bandType: requested.bandType, page: requested.page, pageSize: 25,
                accountId: requested.accountId
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = min(max(1, requested.page), payload.leaderboard.pageCount)
            if corrected != requested.page {
                page = corrected
                return
            }
            shownLeaderboard = payload.leaderboard
            state = .loaded(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard requested == requestKey else { return }
            state = .failed(ServiceIssue(error))
        }
    }
}
