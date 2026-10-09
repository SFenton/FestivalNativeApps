import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandDetailScreen

/// `/bands/:bandId` — one band's page, matching the web client's `BandPage`
/// (`FortniteFestivalWeb/src/pages/band/BandPage.tsx`): the member names as the large
/// navigation title with a "type • N appearances" line under it (web `PageHeader`),
/// then Members cards, Band Summary and Band Statistics stat cards, the Band Rank
/// History chart, and Five Best / Five Worst Songs (#555).
///
/// Every read here is the same pure `GET /api/rankings/bands/{bandType}` board
/// `BandRankingsScreen` uses, filtered to one `teamKey` — never
/// `/api/bands/{bandId}`, whose handler has a write side effect from a GET (see
/// `BandDetail`'s documentation in `Bands.swift`). Because a bare `bandId` cannot
/// be resolved to a `bandType`/`teamKey` by any safe endpoint, this screen needs
/// both carried from the row that linked here; without them it shows an explicit
/// "open from a band list" state rather than guessing or calling the unsafe route.
///
/// There is no "Select Band Profile" action: `FestivalSession` has no user-facing
/// selected-band identity (only a debug one), so the web's Songs Played / Full Combos
/// band-filter links are plain tiles here; adding that identity is a cross-cutting
/// session change out of this screen's scope.
struct BandDetailScreen: View {
    let session: FestivalSession
    let bandId: String
    let name: String?
    let bandType: BandType?
    let teamKey: String?

    @State private var detailState: RankLoadState<BandDetail> = .loading
    /// The board's ranked-team count, colouring the history chart's bars.
    @State private var totalRankedTeams: Int?
    @State private var historyState: RankLoadState<BandRankHistoryResponse> = .loading
    @State private var songsState: RankLoadState<BandSongExtremesResponse> = .loading
    @State private var rankBy: BandRankingMetric = .adjusted
    @State private var songsById: [String: Song] = [:]
    @State private var quickLinks = QuickLinksController()
    /// History card width, so the chart opens on its final page size.
    @State private var historyCardWidth: CGFloat = 0
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools
    /// Pushes stat-tile targets (band rankings, Song Detail); nil in hosted tests.
    @Environment(\.playerStatNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - bandId: Band identifier from the originating link.
    ///   - name: Band member roster label known from the originating link, if any.
    ///   - bandType: Band size, when the originating row already knew it.
    ///   - teamKey: Stable member-account-id roster key, when already known.
    init(
        session: FestivalSession, bandId: String, name: String?,
        bandType: String? = nil, teamKey: String? = nil
    ) {
        self.session = session
        self.bandId = bandId
        self.name = name
        self.bandType = bandType.flatMap(BandType.init(rawValue:))
        self.teamKey = teamKey
    }

    private var isResolvable: Bool {
        bandType != nil && teamKey?.isEmpty == false
    }

    /// Rank By is offered once a resolvable band's detail has loaded.
    private var showsRankBy: Bool {
        guard isResolvable, case .loaded = detailState else { return false }
        return true
    }

    /// The page title: the loaded roster's names (web `formatBandTitle`), else the
    /// originating link's label.
    private var title: String {
        if case let .loaded(detail) = detailState {
            return BandPageFormatting.title(memberNames: detail.members.map(\.resolvedName))
        }
        return name.map { BandPageFormatting.title(memberNames: [$0]) } ?? "Band"
    }

    var body: some View {
        Group {
            if !isResolvable {
                unresolvedView
            } else {
                content
            }
        }
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle(title)
        #if os(iOS)
        // The band name as the large title, collapsing on scroll, whichever page
        // pushed it (HIG Toolbars; same as the Player profile, #555).
        .navigationBarTitleDisplayMode(.large)
        #endif
        // Mac: View › Rank By mirrors the toolbar menu.
        .macRankByCommands($rankBy)
        .toolbar {
            if pageTools == nil, showsRankBy {
                ToolbarItem(placement: .festivalPageAction) {
                    BandRankByMenu(selection: $rankBy)
                }
            }
            QuickLinksToolbarItem(quickLinks)
        }
        // iPhone tab-bar accessory (issue #92): Rank By before Quick Links.
        .festivalPageTool(token: rankBy, order: PageToolOrder.primary, isEnabled: showsRankBy) {
            BandRankByMenu(selection: $rankBy)
        }
        .task(id: teamKey) { await loadDetail() }
        .task { await loadSongLookup() }
    }

    // MARK: Unresolvable bandId

    /// Shown when only a bare `bandId` is known (e.g. a debug deep link): honest
    /// rather than silently broken, since resolving it needs the unsafe endpoint.
    private var unresolvedView: some View {
        FestivalEmptyState(
            "Band Not Available",
            systemImage: "person.3",
            subtitle: "Open this band from Player Bands, Band Rankings or a song's "
                + "Band Scores to see its details.",
            accessibilityIdentifier: "fst.band.unresolved"
        )
    }

    // MARK: Loaded content

    @ViewBuilder private var content: some View {
        switch detailState {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading band")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Band unavailable") {
                Task { await loadDetail() }
            }
        case let .loaded(detail):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Web `PageHeader` subtitle: the first line under the large title,
                    // as Band Rankings shows its ranked count (`RankingsCountHeader`).
                    if let bandType {
                        RankingsCountHeader(
                            text: BandPageFormatting.subtitle(bandType: bandType, appearances: detail.songsPlayed),
                            id: "fst.band.subtitle"
                        )
                        .padding(.horizontal, 4)
                        .padding(.bottom, -12)
                    }
                    // New content fades in as it loads (`Common/FadeInOnLoad.swift`).
                    membersSection(detail).festivalFadeIn(isLoaded: true, index: 0)
                    summarySection(detail).festivalFadeIn(isLoaded: true, index: 1)
                    statisticsSection(detail).festivalFadeIn(isLoaded: true, index: 2)
                    rankHistorySection(detail).festivalFadeIn(isLoaded: true, index: 3)
                    songsSection(detail).festivalFadeIn(isLoaded: true, index: 4)
                }
                .padding(16)
                // Scrolling or a Quick Links jump while the sections stagger in fades the
                // rest in together (#323).
                .festivalFadeInScope()
            }
            .quickLinks(quickLinks, title: "Quick Links")
            .festivalRefreshable {
                await loadDetail(force: true)
                await loadHistory()
                await loadSongs()
            }
        }
    }

    /// A white Title Case section heading above its cards (pattern `section-headers`;
    /// the Player profile's inset).
    private func heading(_ title: String, subtitle: String? = nil) -> some View {
        FestivalSectionHeader(title, subtitle: subtitle)
            .padding(.horizontal, 4)
    }

    // MARK: Members

    /// Web `MembersSection`: one card per member (name, instrument icons, chevron)
    /// opening the player's profile, in the web's auto-fit card grid.
    private func membersSection(_ detail: BandDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Members")
            HingeGrid(
                columns: [GridItem(.adaptive(minimum: BandMemberCard.minimumWidth), spacing: 8)],
                alignment: .leading, spacing: 8
            ) {
                ForEach(detail.members) { member in
                    BandMemberCard(member: member)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.members-section")
        .quickLinkSection(id: "members", title: "Members", symbol: "person.3.fill")
    }

    // MARK: Summary

    /// Web `BandSummarySection`: Type, Appearances and Members stat cards.
    private func summarySection(_ detail: BandDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Band Summary")
            PlayerStatGrid(
                tiles: Self.summaryTiles(detail, bandType: bandType),
                scope: "summary", identifierPrefix: Self.statIdentifierPrefix, onSelect: open
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.summary-section")
        .quickLinkSection(id: "summary", title: "Summary", symbol: "list.bullet")
    }

    /// Band Detail's stat-tile identifier prefix (`fst.band.stat.<scope>.<tile>`).
    static let statIdentifierPrefix = "fst.band.stat"

    /// Web `BandSummarySection` tiles.
    ///
    /// - Parameters:
    ///   - detail: The band's ranking row.
    ///   - bandType: The band's size.
    /// - Returns: Type, Appearances and Members tiles.
    static func summaryTiles(_ detail: BandDetail, bandType: BandType?) -> [StatTile] {
        [
            StatTile(id: "type", label: "Type", value: bandType?.label ?? "—"),
            StatTile(id: "appearances", label: "Appearances", value: detail.songsPlayed.formatted()),
            StatTile(id: "members", label: "Members", value: detail.members.count.formatted()),
        ]
    }

    // MARK: Statistics

    /// Web `BandStatisticsSection`: rank tiles open the band rankings at that metric and
    /// page, Best Song Rank opens the song.
    private func statisticsSection(_ detail: BandDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Band Statistics")
            PlayerStatGrid(
                tiles: Self.statisticsTiles(
                    detail, bandType: bandType, bestSongId: bestSongId, linkFilter: tileLink
                ),
                scope: "statistics", identifierPrefix: Self.statIdentifierPrefix, onSelect: open
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.statistics-section")
        .quickLinkSection(id: "statistics", title: "Statistics", symbol: "chart.bar.fill")
    }

    /// The best song's id once Five Best Songs has loaded (web `bestSongId`).
    private var bestSongId: String? {
        if case let .loaded(extremes) = songsState { return extremes.best.first?.songId }
        return nil
    }

    /// Web `BandStatisticsSection` tiles, in its order. The web shows the three
    /// percentile/FC rank tiles only behind its experimental-ranks setting; native shows
    /// them always, since Rank By offers those metrics here (agent decision, #555).
    ///
    /// - Parameters:
    ///   - detail: The band's ranking row.
    ///   - bandType: The band's size (rank links need it).
    ///   - bestSongId: Five Best Songs' first song, for the Best Song Rank link.
    ///   - linkFilter: Drops links that cannot be followed here (no navigator).
    /// - Returns: The statistics tiles.
    static func statisticsTiles(
        _ detail: BandDetail, bandType: BandType?, bestSongId: String?,
        linkFilter: (PlayerStatLink?) -> PlayerStatLink? = { $0 }
    ) -> [StatTile] {
        func rankLink(_ rank: Int, _ metric: BandRankingMetric) -> PlayerStatLink? {
            guard let bandType else { return nil }
            return linkFilter(PlayerStatLinks.bandRank(rank, metric: metric, bandType: bandType))
        }
        let total = detail.totalChartedSongs
        return [
            StatTile(
                id: "adjusted-rank", label: "Adjusted Percentile Rank",
                value: BandPageFormatting.rank(detail.adjustedSkillRank),
                link: rankLink(detail.adjustedSkillRank, .adjusted)
            ),
            StatTile(
                id: "weighted-rank", label: "Weighted Percentile Rank",
                value: BandPageFormatting.rank(detail.weightedRank),
                link: rankLink(detail.weightedRank, .weighted)
            ),
            StatTile(
                id: "fc-rate-rank", label: "FC Rate Rank",
                value: BandPageFormatting.rank(detail.fcRateRank),
                link: rankLink(detail.fcRateRank, .fcrate)
            ),
            StatTile(
                id: "total-score-rank", label: "Total Score Rank",
                value: BandPageFormatting.rank(detail.totalScoreRank),
                link: rankLink(detail.totalScoreRank, .totalscore)
            ),
            StatTile(
                id: "songs-played", label: "Songs Played",
                value: BandPageFormatting.ofTotal(detail.songsPlayed, total)
            ),
            StatTile(
                id: "full-combos", label: "Full Combos",
                value: BandPageFormatting.ofTotal(detail.fullComboCount, total),
                tint: total > 0 && detail.fullComboCount >= total ? BrandTokens.gold : nil
            ),
            StatTile(id: "total-score", label: "Total Score", value: detail.totalScore.formatted()),
            StatTile(id: "fc-rate", label: "FC Rate", value: BandPageFormatting.fcRate(detail.fcRate)),
            StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: BandPageFormatting.accuracy(detail.avgAccuracy)),
            StatTile(
                id: "avg-stars", label: "Avg Stars", value: BandPageFormatting.stars(detail.avgStars),
                goldStars: BandPageFormatting.isGoldStars(detail.avgStars)
            ),
            StatTile(
                id: "best-song-rank", label: "Best Song Rank",
                value: BandPageFormatting.rank(detail.bestRank),
                link: linkFilter(PlayerStatLinks.bandBestSong(bestRank: detail.bestRank, songId: bestSongId))
            ),
            StatTile(id: "avg-rank", label: "Avg Rank", value: BandPageFormatting.averageRank(detail.avgRank)),
        ]
    }

    /// A tile's link as drawn: nil (a plain tile) without the root navigator.
    private func tileLink(_ link: PlayerStatLink?) -> PlayerStatLink? {
        navigator == nil ? nil : link
    }

    /// Follow a tapped tile through the root navigator (web
    /// `onNavigateToBandLeaderboard` / `onNavigateToSongDetail`).
    ///
    /// - Parameter link: The tapped tile's link.
    private func open(_ link: PlayerStatLink) {
        guard let navigator else { return }
        switch link {
        case let .bandRankings(bandType, rankBy, page):
            navigator.push(.bandRankings(bandType: bandType.rawValue, rankBy: rankBy.rawValue, page: page))
        case let .bandSongDetail(songId), let .songDetail(songId, _):
            navigator.pushSongDetail(songId, session: session)
        case let .fullRankings(instrument, rankBy):
            navigator.push(.fullRankings(instrument: instrument, rankBy: rankBy))
        case let .songs(preset):
            navigator.showSongs(preset)
        }
    }

    // MARK: Rank history

    /// Web `BandRankHistoryChart`: the Player profile's rank-history chart plotting the
    /// Rank By metric, in its card with the 30-day hint and history status.
    @ViewBuilder
    private func rankHistorySection(_ detail: BandDetail) -> some View {
        VStack(spacing: 0) {
            switch historyState {
            case .loading:
                FestivalGlassSection("Band Rank History", subtitle: historySubtitle(nil)) {
                    RankHistoryPlaceholder(label: "Loading band rank history")
                }
            case let .failed(issue):
                FestivalGlassSection("Band Rank History", subtitle: historySubtitle(nil)) {
                    ServiceStatusInline(issue, scope: "band.history") { Task { await loadHistory() } }
                }
            case let .loaded(history):
                let ranked = history.rankedChronological(for: rankBy)
                FestivalGlassSection("Band Rank History", subtitle: historySubtitle(history)) {
                    if ranked.isEmpty {
                        FestivalFootnote("No band rank history yet.")
                            .accessibilityIdentifier("fst.band.history-empty")
                    } else {
                        RankHistoryCharts(
                            points: RankHistoryCharts.points(
                                ranked, metric: rankBy, totalRankedTeams: totalRankedTeams
                            ),
                            valueKind: .band(rankBy), title: "Band rank history",
                            identifierPrefix: "fst.band.rank-history",
                            motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion),
                            initialChartWidth: RankHistoryCharts.chartWidth(forCardWidth: historyCardWidth)
                        )
                        // A new metric is a new series: rebuild rather than morph paging.
                        .id(rankBy)
                    }
                }
                .festivalFadeIn(isLoaded: true)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { historyCardWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.history-section")
        .quickLinkSection(id: "rank-history", title: "Rank History", symbol: "chart.line.uptrend.xyaxis")
        .task(id: "\(detail.teamKey)|\(rankBy.rawValue)") { await loadHistory() }
    }

    private func historySubtitle(_ history: BandRankHistoryResponse?) -> String {
        BandPageFormatting.historySubtitle(
            days: history?.days ?? BandPageFormatting.historyDays,
            status: history?.historyStatus, message: history?.historyMessage
        )
    }

    // MARK: Songs

    /// Web `BandSongsSection`: Five Best Songs then Five Worst Songs, each under its
    /// heading and description, one card per song opening Song Detail.
    @ViewBuilder
    private func songsSection(_ detail: BandDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            songList(
                "Five Best Songs", description: BandPageFormatting.bestSongsDescription(title),
                empty: "No ranked band songs yet.", id: "best", entries: \.best
            )
            songList(
                "Five Worst Songs", description: BandPageFormatting.worstSongsDescription(title),
                empty: "No additional ranked band songs yet.", id: "worst", entries: \.worst
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.songs-section")
        .quickLinkSection(id: "songs", title: "Songs", symbol: "music.note")
        .task(id: detail.teamKey) { await loadSongs() }
    }

    /// One songs list: heading, description, then loading, failure, the in-card empty
    /// (web `InstrumentEmptySection`) or the song cards.
    @ViewBuilder
    private func songList(
        _ heading: String, description: String, empty: String, id: String,
        entries: KeyPath<BandSongExtremesResponse, [BandSongPerformanceEntry]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.heading(heading, subtitle: description)
            switch songsState {
            case .loading:
                FestivalGlassSection {
                    FestivalLoadingView(accessibilityLabel: "Loading \(heading)")
                        .frame(maxWidth: .infinity)
                }
            case let .failed(issue):
                FestivalGlassSection {
                    ServiceStatusInline(issue, scope: "band.songs.\(id)") { Task { await loadSongs() } }
                }
            case let .loaded(extremes):
                let rows = extremes[keyPath: entries]
                if rows.isEmpty {
                    FestivalGlassSection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(empty)
                                .font(.headline)
                                .foregroundStyle(BrandTokens.textPrimary)
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(FestivalText.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("fst.band.\(id)-songs-empty")
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { entry in
                            BandSongRow(entry: entry, song: songsById[entry.songId], session: session)
                        }
                    }
                    .festivalFadeIn(isLoaded: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.band.\(id)-songs")
    }

    // MARK: Loading

    /// Load the band's ranking row, then its history and songs.
    ///
    /// - Parameter force: Reissue every read (pull-to-refresh) rather than only
    ///   the first attempt.
    private func loadDetail(force: Bool = false) async {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        if force { detailState = .loading }
        do {
            let payload = try await session.bandProfile(bandType: bandType, teamKey: teamKey)
            totalRankedTeams = payload.totalRankedTeams
            detailState = .loaded(payload.detail)
        } catch {
            detailState = .failed(ServiceIssue(error))
        }
    }

    private func loadHistory() async {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        historyState = .loading
        do {
            let payload = try await session.bandRankHistory(bandType: bandType, teamKey: teamKey)
            historyState = .loaded(payload.response)
        } catch {
            historyState = .failed(ServiceIssue(error))
        }
    }

    private func loadSongs() async {
        guard let bandType, let teamKey, !teamKey.isEmpty else { return }
        songsState = .loading
        do {
            let payload = try await session.bandSongExtremes(bandType: bandType, teamKey: teamKey)
            songsState = .loaded(payload.response)
        } catch {
            songsState = .failed(ServiceIssue(error))
        }
    }

    /// Build the songId → catalog lookup used to enrich Best/Worst Songs rows.
    ///
    /// Best-effort: a failed or not-yet-loaded catalogue leaves rows on the raw
    /// `songId` fallback rather than blocking or erroring the rest of the page.
    private func loadSongLookup() async {
        guard let payload = try? await session.catalog() else { return }
        songsById = Dictionary(
            payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first }
        )
    }
}

// MARK: - BandMemberCard

/// Web `BandMemberCard`: the member's name over their instrument icons (32 pt) and a
/// chevron, on the shared band-row surface (``PlayerBandRow``), opening their profile.
struct BandMemberCard: View {
    /// Narrowest card before the grid drops a column (web `autoFitDetailCards`).
    static let minimumWidth: CGFloat = 240

    let member: BandMember
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(value: AppRoute.player(accountId: member.accountId, displayName: member.displayName)) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(member.resolvedName)
                        .font(.body.weight(.bold))
                        .foregroundStyle(BrandTokens.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    if !member.chartedInstruments.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(member.chartedInstruments) { instrument in
                                InstrumentIcon(instrument, size: 32)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: LeaderboardRowMetrics.minHeight, alignment: .leading)
            .modifier(RankingRowSurface(isSelected: false))
            .contentShape(Rectangle())
        }
        .festivalRowButtonStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(member))
        .accessibilityHint("Opens player profile")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fst.band.member.\(member.accountId)")
    }

    /// Web `aria-label` "View {name}", plus the instruments the card shows.
    ///
    /// - Parameter member: Band member.
    /// - Returns: For example "View SFentonX, Lead, Drums".
    static func spokenLabel(_ member: BandMember) -> String {
        ([ "View \(member.resolvedName)" ] + member.chartedInstruments.map(\.label)).joined(separator: ", ")
    }
}

// MARK: - BandSongRow

/// Web `PlayerSongRow` in `BandSongsSection`: album art, title, "artist · year" and the
/// percentile pill on its own Song row card (owner #381: song rows stay separate
/// cards), opening Song Detail. The pill drops under the song on a compact width or at
/// accessibility sizes, like the web's narrow two-row layout.
struct BandSongRow: View {
    let entry: BandSongPerformanceEntry
    /// The catalogue song, or nil before the catalogue answers or for an unknown id.
    let song: Song?
    let session: FestivalSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let song {
                NavigationLink(value: AppRoute.songDetail(song)) { card }
                    .festivalRowButtonStyle(cornerRadius: 12)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the song")
            } else {
                card
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(entry, song: song))
        .accessibilityIdentifier("fst.band.song-row.\(entry.songId)")
    }

    private var twoRow: Bool { sizeClass != .regular || dynamicTypeSize.isAccessibilitySize }

    private var card: some View {
        Group {
            if twoRow {
                VStack(alignment: .trailing, spacing: 6) {
                    songInfo
                    percentile
                }
            } else {
                HStack(spacing: 12) {
                    songInfo
                    percentile
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .festivalRowCard(cornerRadius: 12)
        .contentShape(Rectangle())
    }

    private var songInfo: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song?.albumArt, session: session, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(Self.title(song), font: .subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                if let subtitle = Self.subtitle(song) {
                    MarqueeText(subtitle, font: .caption)
                        .foregroundStyle(FestivalText.primary)
                }
            }
            .marqueeSync()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var percentile: some View {
        if let display = Self.percentileDisplay(entry) {
            SongMetadataFieldView(
                field: .percentile(display, tier: SuggestionSongRowView.tier(display)), songId: entry.songId
            )
        }
    }

    /// Web `band.unknownSong` when the catalogue has no such song.
    ///
    /// - Parameter song: Catalogue song, if known.
    /// - Returns: The row title.
    static func title(_ song: Song?) -> String { song?.title ?? "Unknown Song" }

    /// Web `SongInfo` subtitle: "artist · year".
    ///
    /// - Parameter song: Catalogue song, if known.
    /// - Returns: The subtitle, or nil without a song.
    static func subtitle(_ song: Song?) -> String? {
        guard let song else { return nil }
        let text = [song.artist, song.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
        return text.isEmpty ? nil : text
    }

    /// The pill's "Top N%" bucket (web `formatPercentileBucket`), from the row's rank in
    /// the song's band board. The service's `percentile` is a 0–1 fraction, which the
    /// web clamps to "Top 1%" for every row; rank over entries gives the true bucket
    /// (agent decision, #555), falling back to the fraction when the board size is unknown.
    ///
    /// - Parameter entry: Band song performance.
    /// - Returns: For example "Top 5%", or nil when neither is usable.
    static func percentileDisplay(_ entry: BandSongPerformanceEntry) -> String? {
        ScoreFormatting.percentileBucket(rank: entry.rank, totalEntries: entry.totalEntries)
            ?? ScoreFormatting.percentileBucket(percentile: entry.percentile * 100)
    }

    /// One spoken label: title, percentile and rank.
    ///
    /// - Parameters:
    ///   - entry: Band song performance.
    ///   - song: Catalogue song, if known.
    /// - Returns: For example "Song A, Top 5%, rank 12 of 340".
    static func spokenLabel(_ entry: BandSongPerformanceEntry, song: Song?) -> String {
        var parts = [title(song)]
        if let display = percentileDisplay(entry) { parts.append(display) }
        if entry.rank > 0 {
            let field = entry.totalEntries > 0 ? " of \(entry.totalEntries.formatted())" : ""
            parts.append("rank \(entry.rank.formatted())\(field)")
        }
        return parts.joined(separator: ", ")
    }
}
