import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Compete dual-source regions

/// Compete on the iPhone Duo inner display in portrait: two swipeable sources stacked
/// around the fold (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// - Top: one Top-5 leaderboard card per Settings-visible instrument. Like the web's
///   `CompetePage`, no link to the Leaderboards overview (no card, no header View All;
///   #36): each card's View Full Leaderboard opens that instrument's board.
/// - Bottom: one rivals card per Settings-visible instrument.
///
/// Both reuse the phone hub's own sections (`CompeteInstrumentLeaderboardSection`,
/// `RivalInstrumentSongSection`), so the cards match the stacked page exactly.
struct CompeteLeaderboardsCarousel: View {
    let session: FestivalSession
    let instruments: [Instrument]

    var body: some View {
        pane
            #if os(iOS)
            // The primary region no longer scrolls vertically, so a large title
            // would never collapse; keep the fold region for the cards.
            .toolbarTitleDisplayMode(.inline)
            #endif
    }

    private var pane: some View {
        DualSourcePane(
            "Leaderboards", systemImage: "trophy.fill", identifier: "compete.leaderboards"
        ) {
            if instruments.isEmpty {
                DualSourceMessage(
                    "No Instruments", systemImage: "slider.horizontal.3",
                    message: "Enable at least one instrument in Settings to see leaderboards."
                )
            } else {
                HorizontalCarousel("Leaderboards", items: instruments, minimumCardWidth: 300) { instrument in
                    // The section pads itself 16 pt on each side for the stacked
                    // page; the carousel already insets its cards.
                    CompeteInstrumentLeaderboardSection(session: session, instrument: instrument)
                        .padding(.horizontal, -16)
                }
            }
        }
    }
}

/// Compete's bottom region: one rivals card per Settings-visible instrument.
struct CompeteRivalsCarousel: View {
    let session: FestivalSession
    let instruments: [Instrument]

    var body: some View {
        DualSourcePane(
            "Rivals", systemImage: "person.2.fill", seeAll: .rivals, identifier: "compete.rivals"
        ) {
            if instruments.isEmpty {
                DualSourceMessage(
                    "No Instruments", systemImage: "slider.horizontal.3",
                    message: "Enable at least one instrument in Settings to see rivals."
                )
            } else {
                HorizontalCarousel("Rivals", items: instruments, minimumCardWidth: 300) { instrument in
                    RivalInstrumentSongSection(
                        session: session, instrument: instrument, registersQuickLink: false,
                        emptyMessage: "No rivals found for \(instrument.label) yet."
                    )
                    .padding(.horizontal, -16)
                }
            }
        }
    }
}
