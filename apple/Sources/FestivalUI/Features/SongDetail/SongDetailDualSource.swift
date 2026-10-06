import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Song Detail dual-source region

/// Song Detail's bottom region on the iPhone Duo inner display in portrait: the
/// selected player's score history for this song, one chart card per instrument they
/// have a score on (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// Reads only the allowlisted score-history endpoint (`FestivalSession.playerHistory`,
/// see `.agents/platforms/service-safety.md`), lazily per card, and never player stats.
/// Each card's "View All" (the shared `SectionViewAllLink`) opens the full Player History page for that chart.
struct SongHistoryCarouselPane: View {
    let session: FestivalSession
    let song: Song

    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    /// Create the pane.
    ///
    /// - Parameters:
    ///   - session: Shared app session (selected player and score index).
    ///   - song: The song Song Detail shows.
    init(session: FestivalSession, song: Song) {
        self.session = session
        self.song = song
    }

    /// Visible charts with a selected-player score on this song, in display order.
    ///
    /// - Parameters:
    ///   - visible: Settings-visible charts.
    ///   - scored: Charts the selected player has a score on.
    /// - Returns: Charts to show a history card for.
    nonisolated static func instruments(visible: [Instrument], scored: Set<Instrument>) -> [Instrument] {
        visible.filter(scored.contains)
    }

    private var instruments: [Instrument] {
        Self.instruments(
            visible: visible.instruments,
            scored: Set((session.selectedPlayerScores[song.songId] ?? [:]).keys)
        )
    }

    var body: some View {
        DualSourcePane("Your Score History", systemImage: "clock.arrow.circlepath", identifier: "song.history") {
            if session.selectedPlayer == nil {
                DualSourceMessage(
                    "No Profile Selected", systemImage: "person.crop.circle",
                    message: "Select a player to see their score history for this song."
                ) {
                    Button("Choose Profile") { openProfile() }
                        .festivalProminentButton()
                        .accessibilityIdentifier("fst.dual.song.history.choose-profile")
                }
            } else if session.playerLoadState == .syncing {
                DualSourceMessage(
                    "Scores Syncing", systemImage: "arrow.triangle.2.circlepath",
                    message: "This player's scores are still being published. Check back soon."
                )
            } else if instruments.isEmpty {
                DualSourceMessage(
                    "No Scores Yet", systemImage: "music.note",
                    message: "No scores on this song for your visible instruments yet."
                )
            } else {
                HorizontalCarousel("Your Score History", items: instruments, minimumCardWidth: 300) { instrument in
                    SongHistoryCard(session: session, song: song, instrument: instrument)
                }
            }
        }
    }
}

/// One chart's score history for the selected player as a carousel card.
private struct SongHistoryCard: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument

    private enum Phase {
        case loading
        case failed(ServiceIssue)
        case loaded(PlayerHistoryPayload)
    }

    private struct LoadKey: Hashable {
        let accountId: String?
        let publicationRevision: Int
        let retry: Int
    }

    @State private var phase = Phase.loading
    @State private var retryRevision = 0

    var body: some View {
        // Instrument header above the card, never inside it (operator rule).
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                InstrumentIcon(instrument, size: 20)
                FestivalSectionHeader(instrument.label)
                SectionViewAllLink(
                    route: .playerHistory(song, instrument),
                    identifier: "fst.dual.song.history.\(instrument.rawValue).view-all",
                    listName: "\(instrument.label) Score History"
                )
                .fixedSize()
            }
            .padding(.horizontal, 4)
            FestivalGlassSection {
                content
            }
        }
        // `.contain` keeps the header View All link's identifier reachable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.dual.song.history.\(instrument.rawValue)")
        .task(id: LoadKey(
            accountId: session.selectedPlayer?.accountId,
            publicationRevision: session.publicationRevision, retry: retryRevision
        )) {
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading \(instrument.label) history")
                .frame(maxWidth: .infinity, minHeight: 120)
        case let .failed(issue):
            ServiceStatusInline(issue, scope: "dual.song-history.\(instrument.rawValue)") { retryRevision += 1 }
        case let .loaded(payload):
            switch payload.state {
            case .syncing:
                note("Score history is still syncing for this player. Check back soon.")
            case .unregistered:
                note("Score history isn't tracked for this player yet.")
            case .available:
                let sorted = PlayerScoreHistorySort.sorted(
                    payload.entries(songId: song.songId, instrument: instrument), mode: .date, ascending: true
                )
                if sorted.isEmpty {
                    note("No tracked score changes on this chart yet.")
                } else {
                    let best = PlayerScoreHistorySort.highScoreIndex(in: sorted)
                    ForEach(Array(sorted.enumerated().suffix(3)), id: \.offset) { index, entry in
                        ScoreHistoryListRow(entry: entry, isBest: index == best)
                    }
                    .festivalFadeInOnAppear()
                    Text("\(sorted.count) score \(sorted.count == 1 ? "change" : "changes") tracked")
                        .font(.caption)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(BrandTokens.textSecondary)
            .padding(.vertical, 8)
    }

    /// Read the allowlisted score-history GET for the selected player.
    private func load() async {
        guard let accountId = session.selectedPlayer?.accountId else { return }
        phase = .loading
        do {
            let payload = try await session.playerHistory(
                accountId: accountId, songId: song.songId, instrument: instrument
            )
            try Task.checkCancellation()
            phase = .loaded(payload)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(ServiceIssue(error))
        }
    }
}
