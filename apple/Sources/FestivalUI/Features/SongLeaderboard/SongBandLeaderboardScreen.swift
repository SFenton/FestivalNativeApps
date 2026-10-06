import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SongBandLeaderboardScreen

/// `/songs/:songId/bands/:bandType` — per-song band leaderboard, matching the web
/// client's `SongBandLeaderboardPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx`).
///
/// `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=[&accountId=]` is a pure
/// read (`MetaDatabase.GetSongBandLeaderboard` and, with `accountId`,
/// `GetSongBandLeaderboardEntryForAccount`, only `SELECT`s).
///
/// With a selected player who has a band score here, the band's row is pinned above
/// the pager like the Solo chart's player footer (web `FixedLeaderboardPlayerFooter`,
/// issue #306) and follows the Solo footer's rule (issue #307): off-page it jumps to
/// the band's row, on-page it opens the band.
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    @State private var bandType: BandType
    @State private var page: Int
    @State private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    /// The last loaded page and the request it answered: keeps the footer and pager in
    /// place while the next page loads, so only the rows reload (issue #93).
    @State private var shown: Shown?
    /// The band whose row is highlighted and brought into view: Song Detail's selected
    /// band row and the footer's jump open this board at its page (issue #307, web
    /// `navToPlayer`).
    @State private var focus: SongBandRowFocus?
    /// The focused row still needs scrolling into view once its page loads.
    @State private var focusPending: Bool
    /// Top edge of the pinned footer and pager in ``pageSpace``; nil without chrome.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade, shrinking to 0 at the end of the list (#293).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    /// The page's measured width, for the footer's fitted columns.
    @State private var chartWidth: CGFloat = 0
    /// The in-page song header has scrolled under the bar: show art, title and band
    /// size in the navigation bar instead, like the Solo board (issue #315).
    @State private var headerHidden = false
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    /// Space between two band cards, between the last card and the footer or pager,
    /// and below the last card in the list (issues #293, #305).
    nonisolated private static let rowGap: CGFloat = 6
    /// Coordinate space shared by the rows' fade mask and the pinned chrome.
    nonisolated private static let pageSpace = "fst.song-band-leaderboard.page"

    private struct RequestKey: Equatable {
        let bandType: BandType
        let page: Int
        /// Selected player sent as the `accountId` query, so a selection change reloads.
        let accountId: String?
    }

    /// A loaded page together with the request it answered.
    private struct Shown {
        let key: RequestKey
        let payload: SongBandLeaderboardPayload
    }

    private var requestKey: RequestKey {
        RequestKey(bandType: bandType, page: page, accountId: session.selectedPlayer?.accountId)
    }

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
                        VStack(spacing: 0) {
                            // The song header scrolls with the cards, like the Solo
                            // board's; once it passes under the bar the bar shows it.
                            songHeader(payload.leaderboard)
                                .padding(.top, 20)
                                .padding(.bottom, 12)
                            LazyVStack(spacing: Self.rowGap) {
                                if payload.leaderboard.entries.isEmpty {
                                    Text("No \(bandType.label.lowercased()) scores yet.")
                                        .foregroundStyle(FestivalText.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(payload.leaderboard.entries) { entry in
                                    // The selected player's band, or the band this page was
                                    // opened for, gets the purple highlight (web `isSelected`).
                                    SongBandPreviewRow(
                                        entry: entry, highlighted: isHighlighted(entry, in: payload.leaderboard)
                                    )
                                    .accessibilityIdentifier("fst.song-band-leaderboard.row.\(entry.id)")
                                }
                            }
                        }
                        .padding(.horizontal, 16)
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
                // Cards fade out above the pinned footer and pager like the solo
                // board's rows (issues #305, #306): a sibling pager under the scroll
                // view cut them off with a hard edge.
                .bottomChromeFade(
                    chromeTop: chromeTop, distance: $bottomFadeDistance, in: Self.pageSpace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pinned outside the reload gate, as a bottom safe-area inset like the Solo
        // chart's: the footer and pager stay put while another page loads, and the
        // scroll view keeps its frame while only its content inset changes.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        .leaderboardSectionColumns(footerColumns)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            chartWidth = width
        }
        .coordinateSpace(.named(Self.pageSpace))
        // The song's dimmed cover behind its header, like the Solo board and the web
        // page's `PageBackground` (Android and Windows switch to it too).
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle("\(bandType.label) Scores")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: headerHidden)
        .toolbar {
            SongBarTitleToolbarItem(
                song: song, session: session, caption: bandType.label, isShown: headerHidden,
                identifier: "fst.song-band-leaderboard.pinned-title"
            )
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) { bandTypeMenu }
            }
            #if os(iOS)
            if let payload = chromePayload {
                RankingsPagerToolbarContent(
                    page: page, totalPages: payload.leaderboard.pageCount,
                    idPrefix: "fst.song-band-leaderboard"
                ) { destination in
                    page = destination
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // iPhone tab-bar accessory (issue #92): Band Size.
        .festivalPageTool(token: bandType, order: PageToolOrder.primary) {
            bandTypeMenu
        }
        .onChange(of: bandType) { _, _ in
            focusPending = false
            page = 1
        }
        .task(id: requestKey) { await load() }
    }

    // MARK: Song header

    /// The song header: art beside the title, artist and band size (with the entry
    /// total when the service allows it), on one full-width marqueeing line each, like
    /// the web's `SongInfoHeader` on this page (``SongHeaderRow``, issue #315).
    ///
    /// - Parameter leaderboard: The loaded page.
    /// - Returns: The header over the song backdrop.
    private func songHeader(_ leaderboard: SongBandLeaderboardResponse) -> some View {
        SongHeaderRow(song: song, session: session, onScrolledAway: { headerHidden = $0 }) {
            MarqueeText(leaderboard.headerDetail(label: bandType.label))
                .foregroundStyle(FestivalText.primary)
        }
        .accessibilityIdentifier("fst.song-band-leaderboard.header")
    }

    // MARK: Pinned bottom chrome

    /// The last loaded page while it still answers the current band size and selected
    /// player: paging keeps the footer and pager, while a band-size or player change
    /// drops them until the new page arrives, so a Duos footer never sits on Trios.
    private var chromePayload: SongBandLeaderboardPayload? {
        guard let shown, shown.key.bandType == requestKey.bandType,
              shown.key.accountId == requestKey.accountId else { return nil }
        return shown.payload
    }

    /// The selected player's band row for the footer; nil without a selected player
    /// or a band score of this size on this song.
    private var footerEntry: SongBandLeaderboardEntry? {
        guard session.selectedPlayer != nil else { return nil }
        return chromePayload?.leaderboard.selectedEntry
    }

    /// The footer's columns: rank and score fitted to the footer row (web
    /// `selectedFooterRankWidth`), season from 520 pt and stars from 768 pt of width,
    /// matching the web footer's desktop-only season/stars.
    private var footerColumns: LeaderboardRowColumns {
        let row = footerEntry.map { [$0] } ?? []
        return LeaderboardRowColumns.fit(
            .songLeaderboard, width: Double(chartWidth),
            ranks: row.map(\.rank), scores: row.map(\.score)
        )
    }

    /// The player's band footer and the pager, floating over the page background with
    /// no band behind them, like the Solo chart (HIG Materials: "Let content scroll and
    /// peek through while preserving control and navigation legibility").
    private var bottomChrome: some View {
        let spacing = chromeSpacing
        return VStack(spacing: 0) {
            if let entry = footerEntry {
                selectedBandFooter(entry)
                    .padding(.top, spacing.footerTop)
                    .padding(.bottom, spacing.footerBottom)
            }
            if let payload = chromePayload {
                RankingsPagerView(
                    page: page, totalPages: payload.leaderboard.pageCount,
                    idPrefix: "fst.song-band-leaderboard", topPadding: spacing.pagerTop
                ) { destination in
                    page = destination
                }
            }
        }
        .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
    }

    /// Padding that rests the last card one gap above the footer (or the pager without
    /// one) and the footer one gap above the pager (issue #293).
    private var chromeSpacing: PinnedChromeSpacing {
        PinnedChromeSpacing.resolve(
            rowGap: Double(Self.rowGap), rowBottomInset: Double(Self.rowGap), edgePadding: 8,
            hasFooter: footerEntry != nil,
            hasPager: chromePayload != nil && !layout.sectionChrome.isVerticalBar
        )
    }

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

    /// The selected player's band as one Solo-style footer row (the shared
    /// ``SelectedScoreFooterRow``: rank, the members' names scrolling when long, score,
    /// stars on wide layouts and the accuracy/full-combo badge), following the Solo
    /// footer's rule (issue #307, ``SongBandRowNavigation/footerAction(for:pageEntries:)``):
    /// while the band's row is on this page it opens Band Detail (web
    /// `getBandProfileRoute`); otherwise it jumps to the page holding the band's rank
    /// and brings the highlighted row into view.
    ///
    /// - Parameter entry: The selected player's band row.
    /// - Returns: The pinned footer button or link.
    private func selectedBandFooter(_ entry: SongBandLeaderboardEntry) -> some View {
        let action = footerAction(for: entry)
        let row = SelectedScoreFooterRow(
            entry: entry.footerLeaderboardEntry, currentSeason: session.catalogCurrentSeason,
            starsAfterScore: true
        )
        return Group {
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
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.song-band-leaderboard.spotlight-footer")
    }

    // MARK: Band size

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
            shown = Shown(key: requested, payload: payload)
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
