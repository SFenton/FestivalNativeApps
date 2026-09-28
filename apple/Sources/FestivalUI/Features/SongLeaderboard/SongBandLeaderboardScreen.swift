import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SongBandLeaderboardScreen

/// `/songs/:songId/bands/:bandType` — per-song band leaderboard.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct SongBandLeaderboardScreen: View {
    let session: FestivalSession
    let song: Song
    let bandType: String

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose band leaderboard to show.
    ///   - bandType: Band size key.
    init(session: FestivalSession, song: Song, bandType: String) {
        self.session = session
        self.song = song
        self.bandType = bandType
    }

    var body: some View {
        ComingSoonView("Band Scores", symbol: "person.3")
            .festivalBackground(.carousel, session: session)
    }
}
