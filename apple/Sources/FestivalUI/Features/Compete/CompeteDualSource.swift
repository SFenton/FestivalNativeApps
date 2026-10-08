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
/// Both reuse the phone hub's own cards (`CompeteInstrumentLeaderboardSection`,
/// `RivalInstrumentSongCard`) with the page's reads (``CompeteHubModel``), so the cards
/// match the stacked page exactly and appear only after the page's one spinner (#354).
/// Their pane headers and cards then fade in on the page's reading-order stagger
/// (``CompeteDualSourceEntrance``), and a swipe rushes the rest (load-transition R5).
struct CompeteLeaderboardsCarousel: View {
    let session: FestivalSession
    let instruments: [Instrument]
    let model: CompeteHubModel
    /// Reads again whatever failed.
    let retry: () -> Void

    var body: some View {
        DualSourcePane(
            "Leaderboards", systemImage: "trophy.fill", identifier: "compete.leaderboards",
            entranceIndex: CompeteDualSourceEntrance.leaderboardsHeader
        ) {
            if instruments.isEmpty {
                FestivalEmptyState(
                    "No Instruments", systemImage: "slider.horizontal.3",
                    subtitle: "Enable at least one instrument in Settings to see leaderboards."
                )
                .festivalFadeIn(staggerIndex: CompeteDualSourceEntrance.firstLeaderboardCard)
            } else {
                HorizontalCarousel(
                    "Leaderboards", items: instruments, minimumCardWidth: CompeteDualSourceEntrance.minimumCardWidth,
                    entranceIndex: CompeteDualSourceEntrance.firstLeaderboardCard
                ) { instrument in
                    // The section pads itself 16 pt on each side for the stacked
                    // page; the carousel already insets its cards.
                    CompeteInstrumentLeaderboardSection(
                        session: session, instrument: instrument,
                        state: model.boards[instrument] ?? .loading,
                        spotlight: model.spotlights[instrument], retry: retry
                    )
                    .padding(.horizontal, -16)
                }
            }
        }
    }
}

/// Compete's bottom region: one rivals card per Settings-visible instrument.
struct CompeteRivalsCarousel: View {
    let instruments: [Instrument]
    let model: CompeteHubModel
    /// Reads again whatever failed.
    let retry: () -> Void
    /// The regions' width, known before this pane is first built (the secondary region
    /// only appears once the layout measured itself), so the first scheduled entrances
    /// already follow the leaderboard cards on screen.
    @Environment(\.dualSourceRegionWidth) private var regionWidth

    var body: some View {
        let header = CompeteDualSourceEntrance.rivalsHeader(
            instrumentCount: instruments.count,
            leaderboardColumns: CompeteDualSourceEntrance.leaderboardColumns(regionWidth: regionWidth)
        )
        DualSourcePane(
            "Rivals", systemImage: "person.2.fill", seeAll: .rivals, identifier: "compete.rivals",
            entranceIndex: header
        ) {
            if instruments.isEmpty {
                FestivalEmptyState(
                    "No Instruments", systemImage: "slider.horizontal.3",
                    subtitle: "Enable at least one instrument in Settings to see rivals."
                )
                .festivalFadeIn(staggerIndex: header + 1)
            } else {
                HorizontalCarousel(
                    "Rivals", items: instruments, minimumCardWidth: CompeteDualSourceEntrance.minimumCardWidth,
                    entranceIndex: header + 1
                ) { instrument in
                    RivalInstrumentSongCard(
                        instrument: instrument, state: model.rivals[instrument] ?? .loading,
                        registersQuickLink: false,
                        emptyMessage: "No rivals found for \(instrument.label) yet.", retry: retry
                    )
                    .padding(.horizontal, -16)
                }
            }
        }
    }
}

// MARK: - Entrance order

/// Reading-order stagger positions for Compete's dual-source panes (web
/// `useStagger().next()`, load-transition R5): the Leaderboards header, the leaderboard
/// cards on screen, then the Rivals header and its cards. Leaderboard cards off screen
/// to the right only show after a swipe, which rushes the page's pending fades, so they
/// don't hold back the Rivals pane.
enum CompeteDualSourceEntrance {
    /// Narrowest Compete carousel card, in points.
    static let minimumCardWidth: CGFloat = 300
    /// The Leaderboards pane header.
    static let leaderboardsHeader = 0
    /// The first leaderboard card (or the pane's no-instruments message).
    static let firstLeaderboardCard = 1

    /// The Rivals pane header's stagger position.
    ///
    /// - Parameters:
    ///   - instrumentCount: Settings-visible instruments (one card per instrument).
    ///   - leaderboardColumns: Cards the Leaderboards carousel shows side by side
    ///     (``CarouselPaging/columns(width:minimumCardWidth:)``).
    /// - Returns: The position after the leaderboard cards on screen (or the pane's
    ///   message when there are no instruments).
    static func rivalsHeader(instrumentCount: Int, leaderboardColumns: Int) -> Int {
        firstLeaderboardCard + max(1, min(instrumentCount, leaderboardColumns))
    }

    /// Leaderboard cards the top carousel shows side by side: both carousels span the
    /// dual-source regions' width.
    ///
    /// - Parameter regionWidth: ``EnvironmentValues/dualSourceRegionWidth``, or nil
    ///   before the layout measured itself.
    /// - Returns: ``CarouselPaging/columns(width:minimumCardWidth:)`` at that width; the
    ///   most a carousel shows (``CarouselPaging/maximumColumns``) when the width is
    ///   unknown, so an unmeasured Rivals header never shares an entrance with a card.
    static func leaderboardColumns(regionWidth: CGFloat?) -> Int {
        guard let regionWidth else { return CarouselPaging.maximumColumns }
        return CarouselPaging.columns(width: regionWidth.rounded(), minimumCardWidth: minimumCardWidth)
    }
}
