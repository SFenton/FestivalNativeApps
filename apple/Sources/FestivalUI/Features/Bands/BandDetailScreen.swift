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
        .toolbar {
            if isResolvable, case .loaded = detailState {
                ToolbarItem(placement: .primaryAction) {
                    BandRankByMenu(selection: $rankBy)
                }
            }
        }
        .task(id: teamKey) { await loadDetail() }
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
            ProgressView("Loading band")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Band unavailable") {
                Task { await loadDetail() }
            }
        case let .loaded(detail):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    membersSection(detail)
                    summarySection(detail)
                    statisticsSection(detail)
                    rankHistorySection(detail)
                    songsSection(detail)
                }
                .padding(16)
            }
            .refreshable {
                await loadDetail(force: true)
                await loadHistory()
                await loadSongs()
            }
        }
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
                            .foregroundStyle(BrandTokens.textSecondary)
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
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(BrandTokens.textSecondary)
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
            statRow("Average Stars", detail.avgStars.formatted(.number.precision(.fractionLength(1))))
            statRow("Best Rank", "#\(detail.bestRank.formatted())")
            statRow("Average Rank", "#\(detail.avgRank.formatted(.number.precision(.fractionLength(1))))")
        }
        .accessibilityIdentifier("fst.band.statistics-section")
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(BrandTokens.textSecondary)
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
                        .foregroundStyle(BrandTokens.textSecondary)
                } else {
                    ForEach(history.history.prefix(14)) { snapshot in
                        HStack {
                            Text(snapshot.snapshotDate)
                                .font(.footnote)
                                .foregroundStyle(BrandTokens.textSecondary)
                            Spacer()
                            Text("#\(snapshot.rank(for: rankBy).formatted())")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(BrandTokens.textPrimary)
                        }
                        .accessibilityIdentifier("fst.band.history-row.\(snapshot.snapshotDate)")
                    }
                }
            }
        }
        .accessibilityIdentifier("fst.band.history-section")
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
                        .foregroundStyle(BrandTokens.textSecondary)
                } else {
                    songGroup("Best", entries: extremes.best)
                    songGroup("Worst", entries: extremes.worst)
                }
            }
        }
        .accessibilityIdentifier("fst.band.songs-section")
        .task(id: detail.teamKey) { await loadSongs() }
    }

    private func songGroup(_ title: String, entries: [BandSongPerformanceEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandTokens.textSecondary)
            ForEach(entries) { entry in
                HStack {
                    Text(entry.songId)
                        .font(.footnote.monospaced())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(entry.score.formatted())
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(BrandTokens.textSecondary)
                }
                .accessibilityIdentifier("fst.band.song-row.\(entry.songId)")
            }
        }
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
}
