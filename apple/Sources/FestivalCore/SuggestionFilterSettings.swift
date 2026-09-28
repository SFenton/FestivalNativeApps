import Foundation

// MARK: - Suggestion filter settings

/// Persisted Suggestions filter draft (web `SuggestionsFilterDraft`): per-instrument
/// visibility plus global and per-instrument toggles for each `SuggestionCategoryType`.
///
/// Storage is minimal by construction: a toggle is only ever recorded when it differs
/// from the "on" default, so `isActive()` is exactly "is any key explicitly off" and an
/// untouched filter round-trips to empty JSON.
public struct SuggestionFilterSettings: Codable, Equatable, Sendable {
    public static let storageKey = "fst.suggestions.filter"

    /// Instrument key → false, only present when that instrument's suggestions are hidden.
    private var instrumentOff: Set<String>
    /// Type key → false, only present when a type's global toggle is off.
    private var globalTypeOff: Set<String>
    /// "instrument|type" → false, only present when that combination is off.
    private var perInstrumentTypeOff: Set<String>

    private enum CodingKeys: String, CodingKey {
        case instrumentOff, globalTypeOff, perInstrumentTypeOff
    }

    /// Start from an explicit set of overrides; prefer `defaults()` for a fresh filter.
    public init(
        instrumentOff: Set<String> = [], globalTypeOff: Set<String> = [],
        perInstrumentTypeOff: Set<String> = []
    ) {
        self.instrumentOff = instrumentOff
        self.globalTypeOff = globalTypeOff
        self.perInstrumentTypeOff = perInstrumentTypeOff
    }

    /// Every instrument and type enabled, matching a first launch.
    public static func defaults() -> SuggestionFilterSettings { SuggestionFilterSettings() }

    private static func perKey(_ instrument: Instrument, _ type: SuggestionCategoryType) -> String {
        "\(instrument.rawValue)|\(type.rawValue)"
    }

    // MARK: Reads

    /// Whether the player has asked to see this instrument's suggestions at all.
    public func isInstrumentEnabled(_ instrument: Instrument) -> Bool {
        !instrumentOff.contains(instrument.rawValue)
    }

    /// Whether a type is enabled globally, ignoring any per-instrument override.
    public func isGlobalEnabled(_ type: SuggestionCategoryType) -> Bool {
        !globalTypeOff.contains(type.rawValue)
    }

    /// Whether a type is enabled for a specific instrument-scoped category, falling back
    /// to the global toggle for a category with no per-instrument override.
    ///
    /// - Parameters:
    ///   - type: Category family being checked.
    ///   - instrument: The category's own instrument, or nil for a multi-instrument category.
    public func isTypeEnabled(_ type: SuggestionCategoryType, instrument: Instrument?) -> Bool {
        guard let instrument else { return isGlobalEnabled(type) }
        if perInstrumentTypeOff.contains(Self.perKey(instrument, type)) { return false }
        if !globalTypeOff.isEmpty, globalTypeOff.contains(type.rawValue) { return false }
        return true
    }

    /// True once any instrument or type toggle has been turned off from its default.
    public func isActive() -> Bool {
        !instrumentOff.isEmpty || !globalTypeOff.isEmpty || !perInstrumentTypeOff.isEmpty
    }

    /// Intersect the app's Settings-visible charts with this filter's own instrument toggles.
    ///
    /// - Parameter appVisible: Instruments currently enabled in Settings.
    /// - Returns: Instruments that should surface suggestions right now.
    public func effectiveInstruments(appVisible: Set<Instrument>) -> Set<Instrument> {
        appVisible.filter(isInstrumentEnabled)
    }

    // MARK: Mutations (filter sheet)

    /// Show or hide every suggestion for one instrument (independent of category type).
    public mutating func setInstrumentEnabled(_ instrument: Instrument, enabled: Bool) {
        if enabled { instrumentOff.remove(instrument.rawValue) }
        else { instrumentOff.insert(instrument.rawValue) }
    }

    /// Toggle a type globally, cascading the same value to every instrument's row so the
    /// per-instrument section stays consistent with the just-changed general switch.
    ///
    /// - Parameters:
    ///   - type: Category family being toggled.
    ///   - enabled: New value.
    ///   - instruments: Instruments to cascade to (Settings-visible charts).
    public mutating func setGlobalType(
        _ type: SuggestionCategoryType, enabled: Bool, instruments: [Instrument] = Instrument.allCases
    ) {
        setGlobalRaw(type, enabled)
        for instrument in instruments { setPerInstrumentRaw(type, instrument, enabled) }
    }

    /// Toggle one instrument's row for a type. Turning a row on re-enables the type's
    /// global switch if it was off; turning the last visible instrument's row off turns
    /// the global switch off too (mirrors the web filter modal).
    ///
    /// - Parameters:
    ///   - type: Category family being toggled.
    ///   - instrument: Row being toggled.
    ///   - enabled: New value.
    ///   - allInstruments: Every instrument shown in that section (Settings-visible charts).
    public mutating func setPerInstrumentType(
        _ type: SuggestionCategoryType, instrument: Instrument, enabled: Bool,
        allInstruments: [Instrument] = Instrument.allCases
    ) {
        setPerInstrumentRaw(type, instrument, enabled)
        if enabled {
            setGlobalRaw(type, true)
        } else if allInstruments.allSatisfy({ !isTypeEnabled(type, instrument: $0) }) {
            setGlobalRaw(type, false)
        }
    }

    /// Discard every override.
    public mutating func reset() { self = .defaults() }

    private mutating func setGlobalRaw(_ type: SuggestionCategoryType, _ enabled: Bool) {
        if enabled { globalTypeOff.remove(type.rawValue) } else { globalTypeOff.insert(type.rawValue) }
    }

    private mutating func setPerInstrumentRaw(
        _ type: SuggestionCategoryType, _ instrument: Instrument, _ enabled: Bool
    ) {
        let key = Self.perKey(instrument, type)
        if enabled { perInstrumentTypeOff.remove(key) } else { perInstrumentTypeOff.insert(key) }
    }

    // MARK: Persistence

    /// Encode to empty bytes for an unmodified filter, matching `SongPlayerScoreFilter`.
    ///
    /// - Returns: Sorted-key JSON, or empty `Data` when nothing was overridden.
    /// - Throws: Encoder failures, which must leave applied Settings unchanged.
    public func encoded() throws -> Data {
        guard isActive() else { return Data() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decode saved bytes, defaulting corrupt or empty data rather than crashing Settings.
    ///
    /// - Parameter data: Previously-encoded filter, or empty for defaults.
    /// - Returns: A valid filter; corrupt bytes fall back to `defaults()`.
    public static func decodeSaved(_ data: Data) -> SuggestionFilterSettings {
        guard !data.isEmpty, data.count <= 16_384 else { return .defaults() }
        return (try? JSONDecoder().decode(SuggestionFilterSettings.self, from: data)) ?? .defaults()
    }
}

// MARK: - Category filtering

/// Applies a `SuggestionFilterSettings` (and current instrument visibility) to already
/// generated categories, mirroring the web's `shouldShowCategory` / `filterCategoryForInstruments`
/// / `shouldShowCategoryType` / `filterCategoryForInstrumentTypes` pipeline in one pass.
public enum SuggestionCategoryFilter {
    /// Filter one category, dropping it entirely or trimming its songs.
    ///
    /// - Parameters:
    ///   - category: Already-generated category.
    ///   - effectiveInstruments: Settings-visible charts intersected with the filter's own toggles.
    ///   - filter: Saved Suggestions filter draft.
    /// - Returns: The category (unchanged or with hidden-instrument songs removed), or nil
    ///   when it should not be shown at all.
    public static func visible(
        _ category: SuggestionCategory, effectiveInstruments: Set<Instrument>,
        filter: SuggestionFilterSettings
    ) -> SuggestionCategory? {
        guard filter.isTypeEnabled(category.type, instrument: category.instrument) else { return nil }
        if let instrument = category.instrument {
            return effectiveInstruments.contains(instrument) ? category : nil
        }
        let keptSongs = category.songs.filter { item in
            guard let instrument = item.instrument else { return true }
            return effectiveInstruments.contains(instrument)
                && filter.isTypeEnabled(category.type, instrument: instrument)
        }
        guard !keptSongs.isEmpty else { return nil }
        guard keptSongs.count != category.songs.count else { return category }
        return SuggestionCategory(
            key: category.key, title: category.title, description: category.description,
            type: category.type, instrument: nil, songs: keptSongs
        )
    }
}
