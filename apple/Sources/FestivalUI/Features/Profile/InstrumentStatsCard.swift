import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - InstrumentStatsCard

/// One played instrument's stat cards: the profile's tiles plus three global-rank
/// tiles (Global Rank, Total Score, Percentile) from the pure rankings-board read
/// `GET /api/rankings/{instrument}/{accountId}` (never player-stats; see
/// `.agents/pages/player-profile/ios.md`). Each tile is its own card (web `StatBox`);
/// there is no card around the grid.
///
/// The page normally reads the ranking before it shows anything (`preloaded`, web
/// `PlayerPage` waits for its ranking queries), so the tiles open final. Without a
/// preload, or on Retry, the rank tiles are redacted placeholders while the read is in
/// flight, so its arrival changes values, not the grid's height.
struct InstrumentStatsCard: View {
    let session: FestivalSession
    let accountId: String
    let instrument: Instrument
    /// Profile tiles, before the rank tiles.
    let tiles: [StatTile]
    /// The page's rule for which links may be drawn (see `PlayerProfileContent.tileLink`).
    let linkFilter: (PlayerStatLink?) -> PlayerStatLink?
    let onSelect: (PlayerStatLink) -> Void

    /// The ranking read's states (also the page's preload result).
    enum Phase {
        case loading
        case unranked
        case available(PlayerInstrumentRanking)
        case failed(String)

        /// Whether the read finished (a failure retries on the next appearance).
        var isFinished: Bool {
            switch self {
            case .unranked, .available: true
            case .loading, .failed: false
            }
        }
    }

    private struct LoadKey: Hashable {
        let accountId: String
        let instrument: Instrument
        let retry: Int
        let publicationRevision: Int
    }

    @State private var phase: Phase
    @State private var retryRevision = 0
    /// `LoadKey` whose read finished; a reappearance with the same key (Back from a
    /// pushed page restarts `.task(id:)`) keeps the shown ranks instead of reloading.
    @State private var loadedKey: LoadKey?
    /// The page already read this ranking: the first `.task` adopts it without a request.
    private let hasPreload: Bool

    /// Create the card.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instrument: Played, Settings-visible chart.
    ///   - tiles: Profile tiles before the rank tiles.
    ///   - preloaded: The page's finished ranking read, if any.
    ///   - linkFilter: The page's rule for drawable links.
    ///   - onSelect: Follows a tapped link.
    init(
        session: FestivalSession, accountId: String, instrument: Instrument, tiles: [StatTile],
        preloaded: Phase? = nil,
        linkFilter: @escaping (PlayerStatLink?) -> PlayerStatLink?,
        onSelect: @escaping (PlayerStatLink) -> Void
    ) {
        self.session = session
        self.accountId = accountId
        self.instrument = instrument
        self.tiles = tiles
        self.linkFilter = linkFilter
        self.onSelect = onSelect
        _phase = State(initialValue: preloaded ?? .loading)
        if case .loading? = preloaded { hasPreload = false } else { hasPreload = preloaded != nil }
    }

    private var loadKey: LoadKey {
        LoadKey(
            accountId: accountId, instrument: instrument, retry: retryRevision,
            publicationRevision: session.publicationRevision
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayerStatGrid(tiles: tiles + rankTiles, scope: instrument.rawValue, onSelect: onSelect)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).\(phaseIdentifier)")
            if case let .failed(message) = phase {
                HStack(spacing: 8) {
                    Text("Global rank unavailable: \(message)")
                        .font(.caption)
                        .foregroundStyle(FestivalText.primary)
                    Button("Retry") { retryRevision += 1 }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 4)
                .accessibilityIdentifier("fst.player.global-rank.\(instrument.rawValue).error")
            }
        }
        .task(id: loadKey) {
            guard loadedKey != loadKey else { return }
            let key = loadKey
            // The page's preload stands in for the first read (success or failure);
            // Retry and a new publication still read again.
            if hasPreload, loadedKey == nil, retryRevision == 0 {
                loadedKey = key
                return
            }
            await load(resetting: loadedKey?.accountId != key.accountId)
            if !Task.isCancelled, loadFinished { loadedKey = key }
        }
    }

    private var phaseIdentifier: String {
        switch phase {
        case .loading: "loading"
        case .unranked: "unranked"
        case .available: "available"
        case .failed: "failed"
        }
    }

    private var loadFinished: Bool { phase.isFinished }

    // MARK: Rank tiles

    /// Global Rank (links to the full Total Score rankings, like the web's rank card),
    /// Total Score and a rank-derived percentile; placeholders while loading and em
    /// dashes when unranked or failed, so the grid keeps its shape in every state.
    private var rankTiles: [StatTile] {
        switch phase {
        case .loading:
            [
                StatTile(id: "global-rank", label: "Global Rank", value: "#0,000", isPlaceholder: true),
                StatTile(id: "total-score", label: "Total Score", value: "000,000,000", isPlaceholder: true),
                StatTile(id: "percentile", label: "Percentile", value: "Top 00%", isPlaceholder: true),
            ]
        case .unranked:
            [
                StatTile(id: "global-rank", label: "Global Rank", value: "Unranked"),
                StatTile(id: "total-score", label: "Total Score", value: "\u{2014}"),
                StatTile(id: "percentile", label: "Percentile", value: "\u{2014}"),
            ]
        case .failed:
            [
                StatTile(id: "global-rank", label: "Global Rank", value: "\u{2014}"),
                StatTile(id: "total-score", label: "Total Score", value: "\u{2014}"),
                StatTile(id: "percentile", label: "Percentile", value: "\u{2014}"),
            ]
        case let .available(ranking):
            availableTiles(ranking)
        }
    }

    /// Tiles for a loaded ranking row.
    ///
    /// - Parameter ranking: Current validated single-account ranking row.
    /// - Returns: The three rank tiles.
    private func availableTiles(_ ranking: PlayerInstrumentRanking) -> [StatTile] {
        let rank = ranking.entry.rank(for: .totalscore)
        let percentile = ranking.percentile(for: .totalscore)
        return [
            StatTile(
                id: "global-rank", label: "Global Rank", value: "#\(rank.formatted())",
                link: linkFilter(PlayerStatLinks.globalRank(instrument, rank: rank))
            ),
            StatTile(
                id: "total-score", label: "Total Score",
                value: RankingFormatting.wholeNumber(ranking.entry.ratingValue(for: .totalscore))
            ),
            // "Top N%" from rank/field size: Total Score has no Bayesian percentile on
            // the wire. Gold for a top-5% placement.
            StatTile(
                id: "percentile", label: "Percentile",
                value: percentile.map(RankingFormatting.percentile) ?? "\u{2014}",
                tint: (percentile ?? 1) * 100 <= 5 ? BrandTokens.gold : nil
            ),
        ]
    }

    // MARK: Load

    /// Read the pure per-instrument rankings-board row, never player-stats.
    ///
    /// - Parameter resetting: Show placeholders first (a different account); a reload
    ///   for the same account (retry, new publication) keeps the old values until the
    ///   new ones arrive.
    private func load(resetting: Bool) async {
        if resetting || !loadFinished { phase = .loading }
        do {
            let payload = try await session.playerInstrumentRanking(instrument: instrument, accountId: accountId)
            try Task.checkCancellation()
            switch payload.state {
            case .available:
                phase = payload.ranking.map(Phase.available) ?? .unranked
            case .unranked:
                phase = .unranked
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
