import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerProfileScreen

/// `/player/:accountId` — a viewed player's profile (distinct from the selected
/// profile; ported from the web `PlayerPage` in "viewed" mode).
///
/// Shows the same content whether or not `accountId` is the currently selected
/// player: `PlayerProfileContent` offers Deselect when it is, and a
/// Select/Switch action (or an honest unverified/changed notice) otherwise.
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
        PlayerProfileContent(session: session, accountId: accountId, routeDisplayName: displayName)
            .festivalBackground(.carousel, session: session)
    }
}
