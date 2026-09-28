import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LeaderboardsScreen

/// `/leaderboards` — top-ten cards per instrument and band type.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct LeaderboardsScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Leaderboards", symbol: "trophy")
            .festivalBackground(.carousel, session: session)
    }
}
