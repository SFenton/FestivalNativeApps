import Foundation
import FestivalCore

// MARK: - LeaderboardsPreloader

/// Reads every Leaderboards card (visible instruments, band sizes, and the selected
/// player's own row where the top ten lacks it) in parallel, so the page can stay a
/// spinner until they settle and then fade in (operator batch 6.41; the web overview
/// waits for its ranking queries). Failures stay on their own cards.
@MainActor
enum LeaderboardsPreloader {
    /// Finished card states.
    struct Cards {
        var instruments: [Instrument: RankLoadState<RankingsPayload>] = [:]
        var bands: [BandType: RankLoadState<BandRankingsPayload>] = [:]
        var spotlights: [Instrument: RankLoadState<PlayerInstrumentRankingPayload>] = [:]
    }

    private enum Read: Sendable {
        case instrument(Instrument, Result<RankingsPayload, any Error>)
        case band(BandType, Result<BandRankingsPayload, any Error>)
        case spotlight(Instrument, Result<PlayerInstrumentRankingPayload, any Error>)
    }

    /// Read all cards at once, then the missing spotlights at once.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - instruments: Visible instruments.
    ///   - rankBy: Instrument metric.
    ///   - bandMetric: Band metric.
    /// - Returns: Every card's state.
    static func load(
        session: FestivalSession, instruments: [Instrument], rankBy: RankingMetric, bandMetric: BandRankingMetric
    ) async -> Cards {
        var cards = Cards()
        let first = await withTaskGroup(of: Read.self) { group in
            for instrument in instruments {
                group.addTask { await readInstrument(session, instrument, rankBy) }
            }
            for bandType in BandType.allCases {
                group.addTask { await readBand(session, bandType, bandMetric) }
            }
            var all: [Read] = []
            for await read in group { all.append(read) }
            return all
        }
        var needsSpotlight: [Instrument] = []
        let selected = session.selectedPlayer?.accountId
        for read in first {
            switch read {
            case let .instrument(instrument, .success(payload)):
                cards.instruments[instrument] = .loaded(payload)
                if let selected, !payload.rankings.entries.contains(where: {
                    $0.accountId.caseInsensitiveCompare(selected) == .orderedSame
                }) {
                    needsSpotlight.append(instrument)
                }
            case let .instrument(instrument, .failure(error)):
                cards.instruments[instrument] = .failed(ServiceIssue(error))
            case let .band(bandType, .success(payload)):
                cards.bands[bandType] = .loaded(payload)
            case let .band(bandType, .failure(error)):
                cards.bands[bandType] = .failed(ServiceIssue(error))
            case .spotlight:
                break
            }
        }
        guard let selected, !needsSpotlight.isEmpty else { return cards }
        let spotlights = await withTaskGroup(of: Read.self) { group in
            for instrument in needsSpotlight {
                group.addTask { await readSpotlight(session, instrument, selected) }
            }
            var all: [Read] = []
            for await read in group { all.append(read) }
            return all
        }
        for case let .spotlight(instrument, result) in spotlights {
            switch result {
            case let .success(payload): cards.spotlights[instrument] = .loaded(payload)
            case let .failure(error): cards.spotlights[instrument] = .failed(ServiceIssue(error))
            }
        }
        return cards
    }

    private static func readInstrument(_ session: FestivalSession, _ instrument: Instrument, _ rankBy: RankingMetric) async -> Read {
        do {
            return .instrument(instrument, .success(try await session.rankings(
                instrument: instrument, rankBy: rankBy, page: 1, pageSize: 10
            )))
        } catch {
            return .instrument(instrument, .failure(error))
        }
    }

    private static func readBand(_ session: FestivalSession, _ bandType: BandType, _ metric: BandRankingMetric) async -> Read {
        do {
            return .band(bandType, .success(try await session.bandRankings(
                bandType: bandType, rankBy: metric, page: 1, pageSize: 10
            )))
        } catch {
            return .band(bandType, .failure(error))
        }
    }

    private static func readSpotlight(_ session: FestivalSession, _ instrument: Instrument, _ accountId: String) async -> Read {
        do {
            return .spotlight(instrument, .success(try await session.playerInstrumentRanking(
                instrument: instrument, accountId: accountId
            )))
        } catch {
            return .spotlight(instrument, .failure(error))
        }
    }
}
