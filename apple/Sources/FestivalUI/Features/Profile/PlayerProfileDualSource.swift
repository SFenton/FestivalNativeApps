import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Player profile dual-source region

/// Player profile's (and Statistics') bottom region on the iPhone Duo inner display in
/// portrait: the viewed player's graphs as swipeable cards, while the overview and
/// per-instrument stats stay on top (`.agents/design/apple/duo.md`, "Dual-source
/// half-fold layouts"). `PlayerProfileContent` omits its inline graphs while split.
///
/// Cards, per Settings-visible instrument the player has played: Rank History (the
/// pure `GET /api/rankings/{instrument}/{accountId}/history` read), then Percentiles
/// (from the already-loaded profile) when any score has a placement.
struct PlayerChartsCarousel: View {
    let session: FestivalSession
    let accountId: String
    let payload: PlayerProfilePayload
    let instruments: [Instrument]

    /// One graph card.
    enum Card: Identifiable, Equatable {
        case rankHistory(Instrument)
        case percentiles(Instrument, [PlayerPercentileBucket])

        var id: String {
            switch self {
            case let .rankHistory(instrument): "rank:\(instrument.rawValue)"
            case let .percentiles(instrument, _): "percentiles:\(instrument.rawValue)"
            }
        }
    }

    /// Cards in order: each played instrument's rank history, then its percentiles.
    ///
    /// - Parameters:
    ///   - instruments: Settings-visible charts, in display order.
    ///   - songsPlayed: Songs played per instrument.
    ///   - buckets: Percentile buckets per instrument.
    /// - Returns: Carousel cards; instruments with no plays contribute none.
    nonisolated static func cards(
        instruments: [Instrument], songsPlayed: (Instrument) -> Int,
        buckets: (Instrument) -> [PlayerPercentileBucket]
    ) -> [Card] {
        instruments.filter { songsPlayed($0) > 0 }.flatMap { instrument -> [Card] in
            let percentile = buckets(instrument)
            return [.rankHistory(instrument)] + (percentile.isEmpty ? [] : [.percentiles(instrument, percentile)])
        }
    }

    private var cards: [Card] {
        Self.cards(
            instruments: instruments,
            songsPlayed: { payload.profile.instrumentStats($0).songsPlayed },
            buckets: { payload.profile.percentileBuckets($0) }
        )
    }

    var body: some View {
        DualSourcePane("Graphs", systemImage: "chart.xyaxis.line", identifier: "player.graphs") {
            let cards = cards
            if cards.isEmpty {
                DualSourceMessage(
                    "No Graphs Yet", systemImage: "chart.xyaxis.line",
                    message: "Graphs appear once this player has scores on a visible instrument."
                )
            } else {
                HorizontalCarousel("Graphs", items: cards, minimumCardWidth: 300) { card in
                    switch card {
                    case let .rankHistory(instrument):
                        PlayerRankHistoryPage(session: session, accountId: accountId, instrument: instrument)
                    case let .percentiles(instrument, buckets):
                        PlayerPercentilePage(buckets: buckets, instrument: instrument)
                    }
                }
            }
        }
    }
}

// MARK: - Graph pages

/// One instrument's 30-day rank history as a carousel card. Unlike the stacked page's
/// `PlayerRankHistoryCard`, it never renders empty: an unranked instrument says so.
struct PlayerRankHistoryPage: View {
    let session: FestivalSession
    let accountId: String
    let instrument: Instrument

    private enum Phase {
        case loading
        case failed(ServiceIssue)
        case loaded([PlayerRankHistorySnapshot])
    }

    private struct LoadKey: Hashable {
        let accountId: String
        let instrument: Instrument
        let retry: Int
        let publicationRevision: Int
    }

    @State private var phase = Phase.loading
    @State private var retryRevision = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    private var title: String { "\(instrument.label) Rank History" }

    var body: some View {
        FestivalGlassSection(title, subtitle: "Total Score rank over the last 30 days") {
            switch phase {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading \(title)")
                    .frame(maxWidth: .infinity, minHeight: 120)
            case let .failed(issue):
                ServiceStatusInline(issue, scope: "dual.rank-history.\(instrument.rawValue)") {
                    retryRevision += 1
                }
            case let .loaded(points) where points.isEmpty:
                Text("No ranked \(instrument.label) snapshots in the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .padding(.vertical, 8)
            case let .loaded(points):
                RankHistoryCharts(
                    points: points, instrument: instrument,
                    motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
                )
                .festivalFadeInOnAppear()
            }
        }
        .accessibilityIdentifier("fst.dual.rank-history.\(instrument.rawValue)")
        .task(id: LoadKey(
            accountId: accountId, instrument: instrument, retry: retryRevision,
            publicationRevision: session.publicationRevision
        )) {
            await load()
        }
    }

    /// Read the pure rank-history GET, never player-stats.
    private func load() async {
        phase = .loading
        do {
            let history = try await session.playerRankHistory(instrument: instrument, accountId: accountId)
            try Task.checkCancellation()
            phase = .loaded(history.rankedChronological)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(ServiceIssue(error))
        }
    }
}

/// One instrument's leaderboard-placement distribution as a carousel card.
struct PlayerPercentilePage: View {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    var body: some View {
        FestivalGlassSection("\(instrument.label) Percentiles", subtitle: "Songs by leaderboard placement") {
            PercentileBandsChart(
                buckets: buckets, instrument: instrument,
                motion: ChartMotion(system: systemReduceMotion, app: appReduceMotion)
            )
        }
        .accessibilityIdentifier("fst.dual.percentiles.\(instrument.rawValue)")
    }
}
