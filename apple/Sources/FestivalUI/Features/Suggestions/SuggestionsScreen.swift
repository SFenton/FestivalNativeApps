import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SuggestionsScreen

/// `/suggestions` — score-driven song suggestions.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct SuggestionsScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Suggestions", symbol: "sparkles")
            .festivalBackground(.carousel, session: session)
    }
}
