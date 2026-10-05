import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SongBandLeaderboardScreen

/// `/songs/:songId/bands/:bandType` — per-song band leaderboard, matching the web
/// client's `SongBandLeaderboardPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx`).
///
/// `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=` is a pure read
/// (`MetaDatabase.GetSongBandLeaderboard`, only `SELECT`s).
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    @State private var bandType: BandType
    @State private var page = 1
    @State private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    /// The last loaded page count: keeps the pinned pager in place while the next page
    /// loads, so only the rows reload (Song Leaderboard, issue #93); cleared when the
    /// band size changes.
    @State private var shownPageCount: Int?
    /// Top edge of the pinned pager in ``pageSpace``; nil without one.
    @State private var bottomChromeTop: CGFloat?
    /// Height of the rows' bottom fade: the full 36 pt until the last row arrives
    /// above the pager, then shrinking to nothing (issues #293, #305).
    @State private var bottomFadeDistance = ScrollEdgeFade.distance
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    private struct RequestKey: Equatable {
        let bandType: BandType
        let page: Int
    }

    private var requestKey: RequestKey { RequestKey(bandType: bandType, page: page) }

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
                            SongBandPreviewRow(entry: entry, highlighted: false)
                                .accessibilityIdentifier("fst.song-band-leaderboard.row.\(entry.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, Self.rowGap)
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
        // Pinned outside the reload gate so the pager stays put while only the cards
        // reload, as a bottom safe-area inset for the same tab-bar reason as
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
            page = 1
            shownPageCount = nil
        }
        .task(id: requestKey) { await load() }
    }

    // MARK: Pinned bottom chrome

    /// The pager, floating over the page background with no band behind it. Built
    /// from the last loaded page count, so paging keeps it in place.
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            if let shownPageCount {
                RankingsPagerView(
                    page: page, totalPages: shownPageCount,
                    idPrefix: "fst.song-band-leaderboard", topPadding: chromeSpacing.pagerTop
                ) { destination in
                    page = destination
                }
            }
        }
        .reportsBottomChromeTop(in: Self.pageSpace) { bottomChromeTop = $0 }
    }

    /// Padding that rests the last card one row gap above the pager (issue #293).
    private var chromeSpacing: PinnedChromeSpacing {
        PinnedChromeSpacing.resolve(
            rowGap: Double(Self.rowGap), rowBottomInset: Double(Self.rowGap), edgePadding: 8,
            hasFooter: false, hasPager: !layout.sectionChrome.isVerticalBar
        )
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
                songId: song.songId, bandType: requested.bandType, page: requested.page, pageSize: 25
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = min(max(1, requested.page), payload.leaderboard.pageCount)
            if corrected != requested.page {
                page = corrected
                return
            }
            shownPageCount = payload.leaderboard.pageCount
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
