import Foundation

// MARK: - Reorderable settings keys

/// The five columns of the CHOpt Paths text table (`SongPathsSheet`, Lane S/SongDetail).
///
/// Settings owns the persisted column order (`fst.settings.pathColumnOrder`); the Paths
/// sheet is the consumer that should read it when rendering `PathActivationRow` cells.
/// See `.agents/pages/settings/ios.md` for the open consumer change.
public enum PathColumnKey: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case note
    case beat
    case time
    case od
    case score

    public var id: String { rawValue }

    /// Column header shared by the Paths text table and its Settings reorder row.
    public var label: String {
        switch self {
        case .note: "Note"
        case .beat: "Beat"
        case .time: "Time"
        case .od: "OD"
        case .score: "Score"
        }
    }
}

// MARK: - Order codec

/// Encode and decode a user-reorderable list of raw-string-backed cases as one
/// `@AppStorage` string, tolerating additions to the case list across app updates.
public enum SettingsOrder {
    /// Restore a persisted order, appending any case missing from the stored string
    /// (a case added after the value was first saved) and dropping unknown or
    /// duplicate tokens (a case removed, or corrupt data).
    ///
    /// - Parameter raw: Comma-joined raw values as `@AppStorage` last wrote them.
    /// - Returns: Every case exactly once, in the caller's preferred order first.
    public static func decode<T: RawRepresentable & CaseIterable & Hashable>(
        _ raw: String
    ) -> [T] where T.RawValue == String {
        var seen = Set<T>()
        var result: [T] = []
        for token in raw.split(separator: ",") {
            if let value = T(rawValue: String(token)), seen.insert(value).inserted {
                result.append(value)
            }
        }
        for value in T.allCases where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    /// Persist an order as the comma-joined string `decode` can restore.
    ///
    /// - Parameter values: Ordered, ideally duplicate-free case list.
    /// - Returns: Value to write to `@AppStorage`.
    public static func encode<T: RawRepresentable>(_ values: [T]) -> String where T.RawValue == String {
        values.map(\.rawValue).joined(separator: ",")
    }
}
