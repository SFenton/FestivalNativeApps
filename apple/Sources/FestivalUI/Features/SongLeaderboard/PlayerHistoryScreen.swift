import SwiftUI
import FestivalCore

// MARK: - PlayerHistoryScreen

/// `/songs/:songId/:instrument/history`. Score history lives **on the song page**
/// (operator batch 6.39), so this route opens Song Detail scrolled to its Score History
/// section on `instrument`, with every score listed, instead of a separate page. It
/// keeps `AppRoute.playerHistory` deep links (notifications, older entry points) working.
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
        SongDetailScreen(
            song: song, session: session, visibleInstruments: visibleInstruments, historyFocus: instrument
        )
    }
}
