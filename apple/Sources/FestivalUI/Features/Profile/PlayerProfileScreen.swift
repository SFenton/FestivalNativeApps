import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerProfileScreen

/// `/player/:accountId` — viewed player's profile (distinct from the selected profile).
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct PlayerProfileScreen: View {
    let session: FestivalSession
    let accountId: String
    let displayName: String?

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - accountId: Public Epic account ID of the viewed player.
    ///   - displayName: Display name known from the originating link, if any.
    init(session: FestivalSession, accountId: String, displayName: String?) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
    }

    var body: some View {
        ComingSoonView("Player", symbol: "person.crop.circle")
            .festivalBackground(.carousel, session: session)
    }
}
