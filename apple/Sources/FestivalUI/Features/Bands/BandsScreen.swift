import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandsScreen

/// `/bands` — band lookup.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct BandsScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Bands", symbol: "person.3")
            .festivalBackground(.carousel, session: session)
    }
}
