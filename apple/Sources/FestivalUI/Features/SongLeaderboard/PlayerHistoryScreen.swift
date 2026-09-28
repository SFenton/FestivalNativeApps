import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistoryScreen

/// `/songs/:songId/:instrument/history` — selected player's score history.
///
/// Placeholder until its feature lane lands; see `PROGRESS.md`.
struct PlayerHistoryScreen: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose history to show.
    ///   - instrument: Chart whose history to show.
    init(session: FestivalSession, song: Song, instrument: Instrument) {
        self.session = session
        self.song = song
        self.instrument = instrument
    }

    var body: some View {
        ComingSoonView("Score History", symbol: "clock.arrow.circlepath")
            .festivalBackground(.carousel, session: session)
    }
}
