import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - StatisticsScreen

/// `/statistics` — selected profile statistics hub.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct StatisticsScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Statistics", symbol: "chart.bar")
            .festivalBackground(.carousel, session: session)
    }
}
