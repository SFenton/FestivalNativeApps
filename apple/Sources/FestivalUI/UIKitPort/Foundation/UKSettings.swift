#if os(iOS)
import FestivalCore
import Foundation

// MARK: - Settings reads

/// `@AppStorage` for UIKit: the app's settings live in `UserDefaults.standard` under the
/// same keys the SwiftUI screens declare (``SettingsRegistry``). Reads go through here;
/// a view that must follow a change observes ``didChange`` (one notification per
/// `UserDefaults` write, coalesced by the caller).
@MainActor
enum UKSettings {
    /// Posted (on the main queue) whenever `UserDefaults.standard` changes.
    static let didChange = UserDefaults.didChangeNotification

    /// A Boolean setting, falling back to its registered default (`@AppStorage`'s rule).
    ///
    /// - Parameters:
    ///   - key: The `fst.*` key.
    ///   - fallback: The value when nothing is stored.
    /// - Returns: The stored or default value.
    static func bool(_ key: String, default fallback: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard let stored = defaults.object(forKey: key) else { return fallback }
        // A launch argument (`-fst.settings.hideShop YES`) is a string in the argument domain;
        // `@AppStorage` reads it through `bool(forKey:)`, so do the same.
        return stored as? Bool ?? defaults.bool(forKey: key)
    }

    /// Chart instruments Settings shows, as `FestivalRootView.visibleInstruments`.
    ///
    /// - Returns: The instruments whose `fst.settings.show*` toggle is on.
    static func visibleInstruments() -> Set<Instrument> {
        let toggles: [(Instrument, String)] = [
            (.lead, "fst.settings.showLead"), (.bass, "fst.settings.showBass"),
            (.drums, "fst.settings.showDrums"), (.vocals, "fst.settings.showVocals"),
            (.proLead, "fst.settings.showProLead"), (.proBass, "fst.settings.showProBass"),
            (.karaoke, "fst.settings.showKaraoke"), (.proCymbals, "fst.settings.showProCymbals"),
            (.proDrums, "fst.settings.showProDrums"),
        ]
        return Set(toggles.filter { bool($0.1, default: true) }.map(\.0))
    }
}
#endif
