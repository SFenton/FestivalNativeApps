import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - ManualScreen

/// `/manual` — in-app guide.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct ManualScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Manual", symbol: "book")
            .festivalBackground(.carousel, session: session)
    }
}
