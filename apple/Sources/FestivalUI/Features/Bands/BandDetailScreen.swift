import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandDetailScreen

/// `/bands/:bandId`.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct BandDetailScreen: View {
    let session: FestivalSession
    let bandId: String
    let name: String?

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - bandId: Band identifier.
    ///   - name: Band display name, if known.
    init(session: FestivalSession, bandId: String, name: String?) {
        self.session = session
        self.bandId = bandId
        self.name = name
    }

    var body: some View {
        ComingSoonView("Band", symbol: "person.3")
            .festivalBackground(.carousel, session: session)
    }
}
