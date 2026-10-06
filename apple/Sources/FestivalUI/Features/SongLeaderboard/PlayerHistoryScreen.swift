import SwiftUI
import FestivalCore

// MARK: - PlayerHistoryScreen

/// `/songs/:songId/:instrument/history`. Score history lives **on the song page**
/// (operator batch 6.39), so this route opens Song Detail scrolled to its Score History
/// section on `instrument`, with every score listed, instead of a separate page. It
/// keeps `AppRoute.playerHistory` deep links (notifications, older entry points) working.
///
/// In the trailing pane of a split Song Detail (`split-view.md`, operator 2026-10-04)
/// the song page is already beside it, so the route shows only the score history
/// (``SongScoreHistoryPage``), every score listed.
struct PlayerHistoryScreen: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true
    @Environment(\.splitPane) private var splitPane

    /// Create the redirecting route.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - song: Song whose history to show.
    ///   - instrument: Instrument to focus in the Score History section.
    init(session: FestivalSession, song: Song, instrument: Instrument) {
        self.session = session
        self.song = song
        self.instrument = instrument
    }

    /// Settings-visible solo charts, like the Songs tab's own policy.
    private var visibleInstruments: Set<Instrument> {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums), (.vocals, showVocals),
            (.proLead, showProLead), (.proBass, showProBass), (.karaoke, showKaraoke),
            (.proCymbals, showProCymbals), (.proDrums, showProDrums),
        ]
        return Set(preferences.compactMap { $0.1 ? $0.0 : nil })
    }

    var body: some View {
        if splitPane == .trailing {
            SongScoreHistoryPage(
                session: session, song: song, instrument: instrument, visibleInstruments: visibleInstruments
            )
        } else {
            SongDetailScreen(
                song: song, session: session, visibleInstruments: visibleInstruments, historyFocus: instrument
            )
        }
    }
}

// MARK: - Score history page (trailing pane)

/// The selected player's score history for one song on its own: the song page's
/// ``SongScoreHistorySection`` with every score listed, for the trailing pane of a split
/// Song Detail. Reads only the allowlisted song-history endpoint, like the song page.
struct SongScoreHistoryPage: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument
    let visibleInstruments: Set<Instrument>

    private enum Phase: Equatable {
        case loading
        case loaded([ScoreHistoryEntry])
        case unavailable
    }

    @State private var phase: Phase = .loading
    @State private var shown: Instrument?
    @State private var expanded = true
    @State private var width: CGFloat = 0

    /// Charted, Settings-visible instruments (the selector's pool).
    private var pool: [Instrument] {
        Instrument.allCases.filter { song.supports($0) && visibleInstruments.contains($0) }
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading score history")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(entries) where !entries.isEmpty:
                ScrollView {
                    SongScoreHistorySection(
                        entries: entries, pool: pool, keyboardIcon: song.usesKeyboardIcon,
                        instrument: Binding(get: { shown ?? instrument }, set: { shown = $0 }),
                        expanded: $expanded, viewportWidth: width,
                        currentSeason: session.catalogCurrentSeason
                    )
                    .padding(16)
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width = $0 }
            default:
                ContentUnavailableView(
                    "No Score History", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("No tracked scores for \(song.title) yet.")
                )
            }
        }
        .festivalNavigationTitle("Score History")
        .festivalBackground(.song(song.albumArt), session: session)
        .task(id: session.selectedPlayer?.accountId) { await load() }
        // The player-history page root, as on Android and Windows.
        .accessibilityIdentifier("fst.history")
    }

    private func load() async {
        guard let accountId = session.selectedPlayer?.accountId else {
            phase = .unavailable
            return
        }
        do {
            let payload = try await session.songHistory(accountId: accountId, songId: song.songId)
            try Task.checkCancellation()
            phase = payload.state == .available
                ? .loaded(payload.response.history.filter { $0.songId == song.songId }) : .unavailable
        } catch {
            guard !Task.isCancelled else { return }
            phase = .unavailable
        }
    }
}
