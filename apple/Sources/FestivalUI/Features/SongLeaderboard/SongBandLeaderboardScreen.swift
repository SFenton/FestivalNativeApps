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
/// issue #306).
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    @State private var bandType: BandType
    @State private var page = 1
    @State private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    /// The last loaded page and the request it answered: keeps the footer and pager in
    /// place while the next page loads, so only the rows reload (issue #93).
    @State private var shown: Shown?
    /// Top edge of the pinned footer and pager in ``pageSpace``; nil without chrome.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade, shrinking to 0 at the end of the list (#293).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    /// The page's measured width, for the footer's fitted columns.
    @State private var chartWidth: CGFloat = 0
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

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
    init(session: FestivalSession, song: Song, bandType: String) {
        self.session = session
        self.song = song
        _bandType = State(initialValue: BandType(rawValue: bandType) ?? .duets)
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
                ScrollView {
                    LazyVStack(spacing: Self.rowGap) {
                        if payload.leaderboard.entries.isEmpty {
                            Text("No \(bandType.label.lowercased()) scores yet.")
                                .foregroundStyle(FestivalText.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(payload.leaderboard.entries) { entry in
                            // The selected player's band gets the purple highlight
                            // (web `isSelected`).
                            SongBandPreviewRow(
                                entry: entry, highlighted: payload.leaderboard.isSelected(entry)
                            )
                            .accessibilityIdentifier("fst.song-band-leaderboard.row.\(entry.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, Self.rowGap)
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
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle("\(bandType.label) Scores")
        .toolbar {
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
        // iPhone tab-bar accessory (issue #92): Band Size.
        .festivalPageTool(token: bandType, order: PageToolOrder.primary) {
            bandTypeMenu
        }
        .onChange(of: bandType) { _, _ in
            page = 1
        }
        .task(id: requestKey) { await load() }
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

    /// The selected player's band as one Solo-style footer row: rank, the members'
    /// names (scrolling when long, still under Reduce Motion), score, stars on wide
    /// layouts and the accuracy/full-combo badge. Tapping opens the band, like the
    /// web's `getBandProfileRoute` for a selected player.
    ///
    /// - Parameter entry: The selected player's band row.
    /// - Returns: The pinned footer link.
    private func selectedBandFooter(_ entry: SongBandLeaderboardEntry) -> some View {
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: entry.membersLabel,
                bandType: entry.bandType, teamKey: entry.teamKey
            )
        ) {
            HStack(spacing: 8) {
                SongLeaderboardEntryRow(
                    entry: entry.footerLeaderboardEntry, isPlayer: true,
                    currentSeason: session.catalogCurrentSeason, starsAfterScore: true
                )
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: LeaderboardRowMetrics.minHeight)
            .modifier(RankingRowSurface(isSelected: true))
            // Floats over artwork with no band behind it: Reduce Transparency and
            // Increase Contrast get an opaque backing, as on the Solo footer.
            .background {
                if reduceTransparency || contrast == .increased {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandTokens.appBackground)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongBandPreviewText.spokenLabel(entry, selected: true))
        .accessibilityHint("Opens band")
        .accessibilityAddTraits(.isButton)
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
