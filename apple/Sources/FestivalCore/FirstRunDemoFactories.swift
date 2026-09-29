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

extension Song {
    /// Offline stand-ins used until the live catalogue answers (no artwork, public-domain
    /// style names; never bundled album art).
    public static let firstRunFallback: [Song] = {
        let json = """
        [{"songId":"fre-neon","title":"Neon Skyline","artist":"The Voltage","year":2023,
          "durationSeconds":204,"difficulty":{"guitar":3,"bass":2,"vocals":2,"drums":4}},
         {"songId":"fre-midnight","title":"Midnight Runners","artist":"Echo Parade","year":2021,
          "durationSeconds":187,"difficulty":{"guitar":5,"bass":3,"vocals":4,"drums":5}},
         {"songId":"fre-static","title":"Static Bloom","artist":"Halcyon Drift","year":2024,
          "durationSeconds":231,"difficulty":{"guitar":1,"bass":1,"vocals":3,"drums":2}}]
        """
        return (try? JSONDecoder().decode([Song].self, from: Data(json.utf8))) ?? []
    }()
}
