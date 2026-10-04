import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandDetailScreen

/// `/bands/:bandId` — one band's members, per-member instrument assignments,
/// stats, rank history and best/worst songs, matching the web client's `BandPage`
/// (`FortniteFestivalWeb/src/pages/band/BandPage.tsx`).
///
/// Every read here is the same pure `GET /api/rankings/bands/{bandType}` board
/// `BandRankingsScreen` uses, filtered to one `teamKey` — never
/// `/api/bands/{bandId}`, whose handler has a write side effect from a GET (see
/// `BandDetail`'s documentation in `Bands.swift`). Because a bare `bandId` cannot
/// be resolved to a `bandType`/`teamKey` by any safe endpoint, this screen needs
/// both carried from the row that linked here; without them it shows an explicit
/// "open from a band list" state rather than guessing or calling the unsafe route.
///
/// There is no "select as band profile" action: `FestivalSession` only models a
/// selected *player* identity (`SelectedPlayerIdentity`); adding a parallel
/// selected-band concept is a cross-cutting session change out of this screen's
/// scope and is reported separately rather than half-built here.
struct BandDetailScreen: View {
    let session: FestivalSession
    let bandId: String
    let name: String?
    let bandType: BandType?
    let teamKey: String?

    @State private var detailState: RankLoadState<BandDetail> = .loading
    @State private var historyState: RankLoadState<BandRankHistoryResponse> = .loading
    @State private var songsState: RankLoadState<BandSongExtremesResponse> = .loading
    @State private var rankBy: BandRankingMetric = .adjusted
    @State private var songsById: [String: Song] = [:]
    @State private var quickLinks = QuickLinksController()
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

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

    var body: some View {
        Group {
            if !isResolvable {
                unresolvedView
            } else {
                content
            }
        }
        .festivalBackground(.carousel, session: session)
        .navigationTitle(name ?? "Band")
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
        ContentUnavailableView(
            "Band Not Available",
            systemImage: "person.3",
            description: Text(
                "Open this band from Player Bands, Band Rankings or a song's "
                    + "Band Scores to see its details."
            )
        )
        .accessibilityIdentifier("fst.band.unresolved")
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
                    // New content fades in as it loads (`Common/FadeInOnLoad.swift`).
                    membersSection(detail).festivalFadeIn(isLoaded: true, index: 0)
                    if summaryBesideStatistics {
                        // Mac regular-width column: the short Summary beside Statistics,
                        // like the web's auto-fit detail-card grid, instead of two
                        // window-wide tables with values far from their labels.
                        HStack(alignment: .top, spacing: 20) {
                            summarySection(detail).frame(maxWidth: .infinity)
                            statisticsSection(detail).frame(maxWidth: .infinity)
                        }
                        .festivalFadeIn(isLoaded: true, index: 1)
                    } else {
                        summarySection(detail).festivalFadeIn(isLoaded: true, index: 1)
                        statisticsSection(detail).festivalFadeIn(isLoaded: true, index: 2)
                    }
                    rankHistorySection(detail).festivalFadeIn(isLoaded: true, index: 3)
                    songsSection(detail).festivalFadeIn(isLoaded: true, index: 4)
                }
                .padding(16)
            }
            .quickLinks(quickLinks, title: "Quick Links")
            .festivalRefreshable {
                await loadDetail(force: true)
                await loadHistory()
                await loadSongs()
            }
        }
    }

    /// Summary and Statistics side by side: the Mac at regular column width only
    /// (iPhone, iPad and Duo keep their stacked sections).
    private var summaryBesideStatistics: Bool {
        #if os(macOS)
        layout.widthClass == .regular
        #else
        false
        #endif
    }

    // MARK: Members

    private func membersSection(_ detail: BandDetail) -> some View {
        FestivalGlassSection("Members") {
            ForEach(detail.members) { member in
                HStack(alignment: .top, spacing: 12) {
                    Text(member.resolvedName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if member.chartedInstruments.isEmpty {
                        Text("No observed instrument")
                            .font(.footnote)
                            .foregroundStyle(FestivalText.primary)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(member.chartedInstruments) { instrument in
                                InstrumentIcon(instrument, size: 24)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fst.band.member.\(member.accountId)")
            }
            if !detail.configurations.isEmpty {
                FestivalFootnote(
                    "Instrument assignments below reflect this team's most common "
                        + "\(detail.configurations.count == 1 ? "configuration" : "configurations")."
                )
            }
        }
        .accessibilityIdentifier("fst.band.members-section")
        .quickLinkSection(id: "members", title: "Members", symbol: "person.3.fill")
    }

    // MARK: Summary

    private func summarySection(_ detail: BandDetail) -> some View {
        FestivalGlassSection("Summary") {
            summaryRow("Rank", "#\(detail.rank(for: rankBy).formatted())")
            summaryRow(
                "Rating",
                RankingFormatting.rating(detail.ratingValue(for: rankBy), metric: rankBy.asRankingMetric)
            )
            summaryRow("Coverage", RankingFormatting.percentage(detail.coverage))
        }
        .accessibilityIdentifier("fst.band.summary-section")
        .quickLinkSection(id: "summary", title: "Summary", symbol: "list.bullet")
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(FestivalText.primary)
            Spacer()
            Text(value)
                .foregroundStyle(BrandTokens.textPrimary)
                .monospacedDigit()
        }
        .font(.body)
    }

    // MARK: Statistics

    private func statisticsSection(_ detail: BandDetail) -> some View {
        FestivalGlassSection("Statistics") {
            statRow(
                "Songs Played",
                "\(detail.songsPlayed.formatted()) / \(detail.totalChartedSongs.formatted())"
            )
            statRow(
                "Full Combos",
                "\(detail.fullComboCount.formatted()) / \(detail.totalChartedSongs.formatted())"
            )
            statRow("Average Accuracy", "\(ScoreFormatting.accuracy(detail.avgAccuracy))%")
            averageStarsRow(detail.avgStars)
            statRow("Best Rank", "#\(detail.bestRank.formatted())")
            statRow("Average Rank", "#\(detail.avgRank.formatted(.number.precision(.fractionLength(1))))")
        }
        .accessibilityIdentifier("fst.band.statistics-section")
        .quickLinkSection(id: "statistics", title: "Statistics", symbol: "chart.bar.fill")
    }

    /// Average stars, drawn as five gold stars at exactly six like the web's
    /// `BandPage.formatStars` (`GoldStars`), otherwise one decimal or an em dash.
    ///
    /// - Parameter average: Band's mean stars across played songs.
    /// - Returns: The labelled statistics row.
    @ViewBuilder
    private func averageStarsRow(_ average: Double) -> some View {
        if average >= 6 {
            HStack {
                Text("Average Stars").foregroundStyle(FestivalText.primary)
                Spacer()
                StarRating(stars: 6, size: 20)
            }
            .font(.body)
            .accessibilityElement(children: .combine)
        } else {
            statRow("Average Stars", average > 0 ? average.formatted(.number.precision(.fractionLength(1))) : "—")
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(FestivalText.primary)
            Spacer()
            Text(value).foregroundStyle(BrandTokens.textPrimary).monospacedDigit()
        }
        .font(.body)
    }

    // MARK: Rank history

    @ViewBuilder
    private func rankHistorySection(_ detail: BandDetail) -> some View {
        FestivalGlassSection("Rank History") {
            switch historyState {
            case .loading:
                RankingsSkeletonRows(count: 4)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "band.history") { Task { await loadHistory() } }
            case let .loaded(history):
                if history.history.isEmpty {
                    Text("No rank history yet.")
                        .font(.footnote)
                        .foregroundStyle(FestivalText.primary)
                } else {
                    ForEach(history.history.prefix(14)) { snapshot in
                        HStack {
                            Text(snapshot.snapshotDate)
                                .font(.footnote)
                                .foregroundStyle(FestivalText.deemphasized)
                            Spacer()
                            Text("#\(snapshot.rank(for: rankBy).formatted())")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(BrandTokens.textPrimary)
                        }
                        .accessibilityIdentifier("fst.band.history-row.\(snapshot.snapshotDate)")
                        .festivalFadeIn(isLoaded: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("fst.band.history-section")
        .quickLinkSection(id: "rank-history", title: "Rank History", symbol: "trophy.fill")
        .task(id: "\(detail.teamKey)|\(rankBy.rawValue)") { await loadHistory() }
    }

    // MARK: Songs

    @ViewBuilder
    private func songsSection(_ detail: BandDetail) -> some View {
        FestivalGlassSection("Best & Worst Songs") {
            switch songsState {
            case .loading:
                RankingsSkeletonRows(count: 4)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "band.songs") { Task { await loadSongs() } }
            case let .loaded(extremes):
                if extremes.best.isEmpty && extremes.worst.isEmpty {
                    Text("No scored songs yet.")
                        .font(.footnote)
                        .foregroundStyle(FestivalText.primary)
                } else {
                    songGroup("Best", entries: extremes.best)
                        .festivalFadeIn(isLoaded: true)
                    songGroup("Worst", entries: extremes.worst)
                        .festivalFadeIn(isLoaded: true)
                }
            }
        }
        .accessibilityIdentifier("fst.band.songs-section")
        .quickLinkSection(id: "songs", title: "Songs", symbol: "music.note")
        .task(id: detail.teamKey) { await loadSongs() }
    }

    private func songGroup(_ title: String, entries: [BandSongPerformanceEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
            ForEach(entries) { entry in
                songRow(entry)
            }
        }
    }

    /// Cross-reference the catalog for a title/artist/album-art row that links to
    /// `AppRoute.songDetail`; a raw `songId` (never navigable) is the defensive
    /// fallback for a song the catalog lookup hasn't loaded or no longer has.
    ///
    /// - Parameter entry: One best/worst performance row.
    @ViewBuilder
    private func songRow(_ entry: BandSongPerformanceEntry) -> some View {
        let row = songRowContent(entry)
        if let song = songsById[entry.songId] {
            NavigationLink(value: AppRoute.songDetail(song)) { row }
        } else {
            row
        }
    }

    private func songRowContent(_ entry: BandSongPerformanceEntry) -> some View {
        HStack(spacing: 10) {
            if let song = songsById[entry.songId] {
                ArtworkTile(raw: song.albumArt, session: session, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(song.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BrandTokens.textPrimary)
                        .lineLimit(1)
                    MarqueeText(song.artist)
                        .font(.caption2)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(1)
                }
            } else {
                Text(entry.songId)
                    .font(.footnote.monospaced())
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(entry.score.formatted())
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("fst.band.song-row.\(entry.songId)")
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
