import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - FullRankingsScreen

/// `/leaderboards/all` — paginated global rankings for one instrument and metric.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct FullRankingsScreen: View {
    let session: FestivalSession
    let instrument: Instrument
    let rankBy: String

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - instrument: Chart being ranked.
    ///   - rankBy: Ranking metric (e.g. `adjusted`, `totalscore`).
    init(session: FestivalSession, instrument: Instrument, rankBy: String) {
        self.session = session
        self.instrument = instrument
        self.rankBy = rankBy
    }

    var body: some View {
        ComingSoonView("Rankings", symbol: "list.number")
            .festivalBackground(.carousel, session: session)
    }
}
