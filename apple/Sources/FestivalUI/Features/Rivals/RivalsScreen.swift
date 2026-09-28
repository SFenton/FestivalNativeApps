import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalsScreen

/// `/rivals` — selected player's rivals hub.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct RivalsScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Rivals", symbol: "person.2")
            .festivalBackground(.carousel, session: session)
    }
}
