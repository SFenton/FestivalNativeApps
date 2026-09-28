import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalryScreen

/// `/rivals/:rivalId/rivalry` — head-to-head breakdown.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct RivalryScreen: View {
    let session: FestivalSession
    let rivalId: String
    let mode: String
    let name: String?

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - rivalId: Rival account ID.
    ///   - mode: Comparison mode.
    ///   - name: Rival display name, if known.
    init(session: FestivalSession, rivalId: String, mode: String, name: String?) {
        self.session = session
        self.rivalId = rivalId
        self.mode = mode
        self.name = name
    }

    var body: some View {
        ComingSoonView("Rivalry", symbol: "person.2")
            .festivalBackground(.carousel, session: session)
    }
}
