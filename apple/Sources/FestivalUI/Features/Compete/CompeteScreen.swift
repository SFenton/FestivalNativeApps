import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - CompeteScreen

/// `/compete` — phone hub combining Leaderboards and Rivals.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct CompeteScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Compete", symbol: "trophy")
            .festivalBackground(.carousel, session: session)
    }
}
