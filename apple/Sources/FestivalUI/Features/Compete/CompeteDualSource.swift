import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Compete dual-source regions

/// Compete on the iPhone Duo inner display in portrait: two swipeable sources stacked
/// around the fold (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// - Top: one Top-5 leaderboard card per Settings-visible instrument, then a card
///   linking to the full Leaderboards overview.
/// - Bottom: one rivals card per Settings-visible instrument.
///
/// Both reuse the phone hub's own sections (`CompeteInstrumentLeaderboardSection`,
/// `RivalInstrumentSongSection`), so the cards match the stacked page exactly.
struct CompeteLeaderboardsCarousel: View {
    let session: FestivalSession
    let instruments: [Instrument]

    /// One carousel card.
    private enum Card: Identifiable {
        case instrument(Instrument)
        case overview
        var id: String {
            switch self {
            case let .instrument(instrument): instrument.rawValue
            case .overview: "overview"
            }
        }
    }

    var body: some View {
        DualSourcePane(
            "Leaderboards", systemImage: "trophy.fill", seeAll: .leaderboards,
            identifier: "compete.leaderboards"
        ) {
            if instruments.isEmpty {
                DualSourceMessage(
                    "No Instruments", systemImage: "slider.horizontal.3",
                    message: "Enable at least one instrument in Settings to see leaderboards."
                )
            } else {
                HorizontalCarousel(
                    "Leaderboards", items: instruments.map(Card.instrument) + [.overview],
                    minimumCardWidth: 300
                ) { card in
                    switch card {
                    case let .instrument(instrument):
                        // The section pads itself 16 pt on each side for the stacked
                        // page; the carousel already insets its cards.
                        CompeteInstrumentLeaderboardSection(session: session, instrument: instrument)
                            .padding(.horizontal, -16)
                    case .overview:
                        overviewCard
                    }
                }
            }
        }
    }

    private var overviewCard: some View {
        NavigationLink(value: AppRoute.leaderboards) {
            VStack(spacing: 10) {
                Image(systemName: "list.number")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Leaderboards Overview")
                    .font(.headline)
                Text("Every instrument's top players and band rankings.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(BrandTokens.textPrimary)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 180)
            .contentShape(Rectangle())
            .festivalGlass(.card, cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fst.dual.compete.overview")
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
