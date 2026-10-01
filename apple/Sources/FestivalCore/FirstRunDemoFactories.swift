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
}
