import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - AllRivalsScreen

/// `/rivals/all` — full rival list for one category.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct AllRivalsScreen: View {
    let session: FestivalSession
    let category: String

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - category: Rival category key.
    init(session: FestivalSession, category: String) {
        self.session = session
        self.category = category
    }

    var body: some View {
        ComingSoonView("All Rivals", symbol: "person.2")
            .festivalBackground(.carousel, session: session)
    }
}
