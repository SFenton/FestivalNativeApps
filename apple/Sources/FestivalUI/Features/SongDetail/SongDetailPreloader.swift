import Foundation
import FestivalCore

// MARK: - SongDetailPreloader

/// Reads every visible chart's top ten in parallel before Song Detail appears (web
/// `SongDetailPage` waits for `leaderboardsQuery`; operator batch 6.41). Each card then
/// adopts its result (`SongScorePreview(preloaded:)`); a failure stays on its own card
/// with Retry rather than failing the page.
@MainActor
enum SongDetailPreloader {
    private enum Result: Sendable {
        case loaded(Instrument, LeaderboardPayload)
        case failed(Instrument, String)
        case cancelled
    }

    /// Read the preview rows for each instrument at once.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - song: Song being shown.
    ///   - instruments: Visible charted instruments.
    ///   - leeway: Invalid-score leeway sent with the read (nil when filtering is off),
    ///     the same value the cards key on.
    /// - Returns: Each card's first state.
    static func previews(
        session: FestivalSession, song: Song, instruments: [Instrument], leeway: Double?
    ) async -> [Instrument: SongScorePreview.LoadState] {
        let songId = song.songId
        let results = await withTaskGroup(of: Result.self) { group in
            for instrument in instruments {
                group.addTask { await read(session: session, songId: songId, instrument: instrument, leeway: leeway) }
            }
            var collected: [Result] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var states: [Instrument: SongScorePreview.LoadState] = [:]
        for result in results {
            switch result {
            case let .loaded(instrument, payload): states[instrument] = .loaded(payload)
            case let .failed(instrument, message): states[instrument] = .failed(message)
            case .cancelled: break
            }
        }
        return states
    }

    private static func read(
        session: FestivalSession, songId: String, instrument: Instrument, leeway: Double?
    ) async -> Result {
        do {
            let payload = try await session.leaderboard(
                songId: songId, instrument: instrument, page: 1, top: 10, leeway: leeway
            )
            return .loaded(instrument, payload)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return .failed(instrument, error.localizedDescription)
        }
    }
}
