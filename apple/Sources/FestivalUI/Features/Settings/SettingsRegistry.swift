import Foundation
import FestivalCore

// MARK: - Settings registry

/// A persisted setting's default value, in the representation `@AppStorage` writes.
enum SettingDefault: Sendable, Equatable {
    case bool(Bool)
    case double(Double)
    case string(String)
    /// A `Data`-backed `@AppStorage`, e.g. a Codable-JSON preference owned by
    /// another lane (`SuggestionFilterSettings.storageKey`). Its default is empty
    /// `Data()`, matching that type's own "untouched filter" contract.
    case data(Data)
}

/// Every app preference that Settings owns and "Reset App Settings" restores.
///
/// Keys must match the `@AppStorage` declarations in `SettingsScreen` (and any reader
/// elsewhere). Profile identity, Songs sort/filter state and navigation history are
/// deliberately **not** listed: reset keeps them.
enum SettingsRegistry {
    /// Key → default, in display order.
    static let defaults: [(key: String, value: SettingDefault)] = [
        ("fst.settings.showInstrumentIcons", .bool(true)),
        ("fst.settings.enableVisualOrder", .bool(false)),
        ("fst.settings.songRowVisualOrder", .string(SettingsOrder.encode(MetadataField.allCases))),
        ("fst.settings.pathColumnOrder", .string(SettingsOrder.encode(PathColumnKey.allCases))),
        ("fst.settings.filterInvalidScores", .bool(false)),
        ("fst.settings.leeway", .double(1)),
        ("fst.settings.pathDefaultView", .string(PathDisplayMode.image.rawValue)),
        ("fst.settings.pathUnavailableWarningDismissed", .bool(false)),
        ("fst.settings.experimentalRanks", .bool(false)),
        ("fst.settings.hideShop", .bool(false)),
        ("fst.settings.disableShopHighlighting", .bool(false)),
        (SuggestionFilterSettings.storageKey, .data(Data())),
        ("fst.settings.showLead", .bool(true)),
        ("fst.settings.showBass", .bool(true)),
        ("fst.settings.showDrums", .bool(true)),
        ("fst.settings.showVocals", .bool(true)),
        ("fst.settings.showProLead", .bool(true)),
        ("fst.settings.showProBass", .bool(true)),
        ("fst.settings.showKaraoke", .bool(true)),
        ("fst.settings.showProCymbals", .bool(true)),
        ("fst.settings.showProDrums", .bool(true)),
        ("fst.settings.metadataScore", .bool(true)),
        ("fst.settings.metadataPercentage", .bool(true)),
        ("fst.settings.metadataPercentile", .bool(true)),
        ("fst.settings.metadataSeason", .bool(true)),
        ("fst.settings.metadataIntensity", .bool(true)),
        ("fst.settings.metadataDifficulty", .bool(true)),
        ("fst.settings.metadataStars", .bool(true)),
        ("fst.settings.metadataLastPlayed", .bool(true)),
        ("fst.accessibility.reduceMotion", .bool(false)),
        ("fst.accessibility.disableAnimatedArtwork", .bool(false)),
        ("fst.accessibility.moreContrast", .bool(false)),
        ("fst.accessibility.lessTransparency", .bool(false)),
    ]

    /// Read a setting the way `@AppStorage` would, falling back to its default.
    ///
    /// - Parameters:
    ///   - key: Registered key.
    ///   - store: Defaults domain to read.
    /// - Returns: The stored value, or the registered default when absent.
    static func value(for key: String, in store: UserDefaults) -> SettingDefault? {
        guard let fallback = defaults.first(where: { $0.key == key })?.value else { return nil }
        guard store.object(forKey: key) != nil else { return fallback }
        switch fallback {
        case .bool: return .bool(store.bool(forKey: key))
        case .double: return .double(store.double(forKey: key))
        case .string: return store.string(forKey: key).map(SettingDefault.string) ?? fallback
        case .data: return .data(store.data(forKey: key) ?? Data())
        }
    }

    /// Write a value in the same representation `@AppStorage` uses.
    ///
    /// - Parameters:
    ///   - value: Value to persist.
    ///   - key: Registered key.
    ///   - store: Defaults domain to write.
    static func write(_ value: SettingDefault, for key: String, in store: UserDefaults) {
        switch value {
        case let .bool(flag): store.set(flag, forKey: key)
        case let .double(number): store.set(number, forKey: key)
        case let .string(text): store.set(text, forKey: key)
        case let .data(bytes): store.set(bytes, forKey: key)
        }
    }
}
