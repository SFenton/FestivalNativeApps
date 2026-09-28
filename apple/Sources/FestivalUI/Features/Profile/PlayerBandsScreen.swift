import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerBandsScreen

/// `/bands/player/:accountId` — a player's Duo/Trio/Quad bands.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct PlayerBandsScreen: View {
    let session: FestivalSession
    let accountId: String
    let displayName: String?

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - accountId: Player whose bands to list.
    ///   - displayName: Player name for the title.
    init(session: FestivalSession, accountId: String, displayName: String?) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
    }

    var body: some View {
        ComingSoonView("Bands", symbol: "person.3")
            .festivalBackground(.carousel, session: session)
    }
}
