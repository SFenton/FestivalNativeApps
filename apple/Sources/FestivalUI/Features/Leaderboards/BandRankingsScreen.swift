import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandRankingsScreen

/// `/leaderboards/bands/:bandType` — paginated band rankings.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct BandRankingsScreen: View {
    let session: FestivalSession
    let bandType: String

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - bandType: Band size key (Duets, Trios, Quad).
    init(session: FestivalSession, bandType: String) {
        self.session = session
        self.bandType = bandType
    }

    var body: some View {
        ComingSoonView("Band Rankings", symbol: "person.3")
            .festivalBackground(.carousel, session: session)
    }
}
