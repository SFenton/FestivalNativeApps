import Foundation
import FestivalCore

// MARK: - ProfileExtrasLoader

/// Reads every played instrument's ranking row and rank history in parallel, so the
/// player page can wait for them before it appears (web `PlayerPage` waits for its
/// ranking queries; operator batch 6.41: no partial pages).
///
/// Both endpoints are pure reads (`.agents/platforms/service-safety.md`): the
/// rankings-board row `GET /api/rankings/{instrument}/{accountId}` and
/// `GET /api/rankings/{instrument}/{accountId}/history`. A failure is kept per card
/// (each card shows its own Retry) rather than failing the page.
@MainActor
enum ProfileExtrasLoader {
    /// The finished reads, keyed by instrument.
    struct Extras {
        var ranks: [Instrument: InstrumentStatsCard.Phase] = [:]
        var histories: [Instrument: PlayerRankHistoryCard.Phase] = [:]
    }

    /// One finished read (Sendable, so it can leave a child task).
    private enum Result: Sendable {
        case rank(Instrument, Swift.Result<PlayerInstrumentRankingPayload, any Error>)
        case history(Instrument, Swift.Result<PlayerRankHistory, any Error>)
    }

    /// Read both extras for every instrument at once.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instruments: Played, Settings-visible charts.
    /// - Returns: Per-instrument phases; cancellation leaves the missing ones out.
    static func load(session: FestivalSession, accountId: String, instruments: [Instrument]) async -> Extras {
        let results = await withTaskGroup(of: Result.self) { group in
            for instrument in instruments {
                group.addTask { await readRank(session: session, accountId: accountId, instrument: instrument) }
                group.addTask { await readHistory(session: session, accountId: accountId, instrument: instrument) }
            }
            var collected: [Result] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var extras = Extras()
        for result in results {
            switch result {
            case let .rank(instrument, outcome):
                extras.ranks[instrument] = rankPhase(outcome)
            case let .history(instrument, outcome):
                extras.histories[instrument] = historyPhase(outcome)
            }
        }
        return extras
    }

    /// One ranking read as a Sendable result.
    private static func readRank(session: FestivalSession, accountId: String, instrument: Instrument) async -> Result {
        let outcome: Swift.Result<PlayerInstrumentRankingPayload, any Error>
        do {
            outcome = .success(try await session.playerInstrumentRanking(instrument: instrument, accountId: accountId))
        } catch {
            outcome = .failure(error)
        }
        return .rank(instrument, outcome)
    }

    /// One rank-history read as a Sendable result.
    private static func readHistory(session: FestivalSession, accountId: String, instrument: Instrument) async -> Result {
        let outcome: Swift.Result<PlayerRankHistory, any Error>
        do {
            outcome = .success(try await session.playerRankHistory(instrument: instrument, accountId: accountId))
        } catch {
            outcome = .failure(error)
        }
        return .history(instrument, outcome)
    }

    /// The ranking card's phase for a finished read.
    ///
    /// - Parameter outcome: Read result.
    /// - Returns: Available, unranked or failed; nil when the read was cancelled.
    static func rankPhase(_ outcome: Swift.Result<PlayerInstrumentRankingPayload, any Error>) -> InstrumentStatsCard.Phase? {
        switch outcome {
        case let .success(payload):
            switch payload.state {
            case .available: return payload.ranking.map(InstrumentStatsCard.Phase.available) ?? .unranked
            case .unranked: return .unranked
            }
        case let .failure(error):
            return isCancellation(error) ? nil : .failed(error.localizedDescription)
        }
    }

    /// The rank-history card's phase for a finished read.
    ///
    /// - Parameter outcome: Read result.
    /// - Returns: Loaded snapshots or failed; nil when the read was cancelled.
    static func historyPhase(_ outcome: Swift.Result<PlayerRankHistory, any Error>) -> PlayerRankHistoryCard.Phase? {
        switch outcome {
        case let .success(history): return .loaded(history.rankedChronological)
        case let .failure(error): return isCancellation(error) ? nil : .failed(ServiceIssue(error))
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}
