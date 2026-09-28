import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalDetailScreen

/// `/rivals/:rivalId`.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct RivalDetailScreen: View {
    let session: FestivalSession
    let rivalId: String
    let name: String?

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - rivalId: Rival account ID.
    ///   - name: Rival display name, if known.
    init(session: FestivalSession, rivalId: String, name: String?) {
        self.session = session
        self.rivalId = rivalId
        self.name = name
    }

    var body: some View {
        ComingSoonView("Rival", symbol: "person.2")
            .festivalBackground(.carousel, session: session)
    }
}
