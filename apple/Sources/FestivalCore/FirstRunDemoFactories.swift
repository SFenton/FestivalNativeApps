import Foundation

// MARK: - First-run demo factories

/// Public constructors the first-run demos use to feed the app's real Songs views with
/// fixed sample states (the web's demos use hardcoded pools the same way).
extension SongInstrumentBadge {
    /// One sample chip state for a first-run demo.
    ///
    /// - Parameters:
    ///   - instrument: Chart the chip represents.
    ///   - status: Status to show.
    /// - Returns: A badge for `SongInstrumentStatusChips`.
    public static func demo(_ instrument: Instrument, _ status: SongInstrumentStatus) -> SongInstrumentBadge {
        SongInstrumentBadge(instrument: instrument, status: status)
    }

    /// The web `SongIconsDemo` chip pattern for a song: each instrument's state comes from
    /// ``FirstRunDemoScorePattern/states(title:count:)``, so a rotated-in song shows a
    /// different mix.
    ///
    /// - Parameters:
    ///   - title: Song title seeding the pattern.
    ///   - instruments: Charts to show, in order.
    /// - Returns: One badge per instrument.
    public static func demoPattern(title: String, instruments: [Instrument]) -> [SongInstrumentBadge] {
        zip(instruments, FirstRunDemoScorePattern.states(title: title, count: instruments.count)).map { instrument, state in
            let status: SongInstrumentStatus = switch state {
            case .fullCombo: .fullCombo
            case .scored: .scored
            case .noScore: .noScore
            }
            return SongInstrumentBadge(instrument: instrument, status: status)
        }
    }
}
