import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LicensesScreen

/// `/settings/licenses`.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct LicensesScreen: View {
    let session: FestivalSession


    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).

    init(session: FestivalSession) {
        self.session = session

    }

    var body: some View {
        ComingSoonView("Licenses", symbol: "doc.text")
            .festivalBackground(.carousel, session: session)
    }
}
