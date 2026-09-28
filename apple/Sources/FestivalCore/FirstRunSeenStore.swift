import Foundation

/// Bounded, validated persistence for first-run seen-state, backed by `UserDefaults` JSON —
/// the native analog of the web's `localStorage`-backed `loadSeenSlides`/`saveSeenSlides`.
///
/// Corrupt or oversized data never crashes or blocks the app: a fully-unparsable blob resets to
/// empty (matching the web's `catch { return {} }`), and individual malformed records are
/// dropped while the rest of the store is kept.
public final class FirstRunSeenStore: @unchecked Sendable {
    public static let storageKey = "fst.firstRun.seen.v1"

    /// Hard cap on persisted records so a runaway catalog (or a hand-edited default) can't grow
    /// the store unboundedly. Comfortably above the real slide count (~40) across all pages.
    public static let maxRecords = 500

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// Create a store over a `UserDefaults` suite.
    ///
    /// - Parameter defaults: Backing store; `.standard` in the app, an isolated suite in tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Read the current seen-state, silently recovering from any corruption.
    ///
    /// - Returns: A validated, bounded seen-state map (possibly empty).
    public func load() -> FirstRunSeenStorage {
        lock.lock()
        defer { lock.unlock() }
        return Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// Overwrite the persisted seen-state.
    ///
    /// - Parameter storage: New seen-state to persist (bounded before writing).
    public func save(_ storage: FirstRunSeenStorage) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(Self.encode(Self.bounded(storage)), forKey: Self.storageKey)
    }

    /// Mark a set of slides as seen, merging into the existing store.
    ///
    /// - Parameters:
    ///   - slides: Slides that were actually displayed to the user.
    ///   - now: Timestamp recorded for every slide (fixed for deterministic tests).
    public func markSeen(_ slides: [FirstRunSlide], at now: Date = Date()) {
        guard !slides.isEmpty else { return }
        lock.lock()
        var storage = Self.decode(defaults.data(forKey: Self.storageKey))
        for slide in slides {
            storage[slide.id] = FirstRunSlideEvaluator.seenRecord(for: slide, at: now)
        }
        defaults.set(Self.encode(Self.bounded(storage)), forKey: Self.storageKey)
        lock.unlock()
    }

    /// Clear seen-state for one page's slides only (used before a Settings replay so the
    /// replayed slides are freshly re-recorded on dismiss, matching the web's `resetPage`).
    ///
    /// - Parameter slideIDs: Ids belonging to the page being reset.
    public func resetPage(_ slideIDs: [String]) {
        guard !slideIDs.isEmpty else { return }
        lock.lock()
        var storage = Self.decode(defaults.data(forKey: Self.storageKey))
        for id in slideIDs { storage.removeValue(forKey: id) }
        defaults.set(Self.encode(storage), forKey: Self.storageKey)
        lock.unlock()
    }

    /// Clear all seen-state, matching the web's `resetAll`. Not currently wired to any UI
    /// (the web Settings page doesn't expose a "reset all" control either), but kept available
    /// and tested for a future Settings addition.
    public func resetAll() {
        lock.lock()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }

    // MARK: - Codec

    /// Decode persisted JSON, dropping individually malformed records and returning empty for
    /// any top-level parse failure or oversized payload.
    ///
    /// - Parameter data: Raw stored bytes, or nil when nothing has been saved yet.
    /// - Returns: A validated seen-state map.
    static func decode(_ data: Data?) -> FirstRunSeenStorage {
        guard let data, !data.isEmpty, data.count <= 256 * 1024 else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let raw = try? decoder.decode([String: FirstRunSeenRecord].self, from: data)
        else { return [:] }
        return raw.filter(isValid)
    }

    /// A record is valid when its fields are the shapes `markSeen` would ever have written.
    ///
    /// - Parameter entry: One decoded id/record pair.
    /// - Returns: Whether to keep it.
    private static func isValid(_ entry: (key: String, value: FirstRunSeenRecord)) -> Bool {
        !entry.key.isEmpty && entry.key.count <= 200
            && entry.value.version >= 0
            && !entry.value.hash.isEmpty && entry.value.hash.count <= 32
    }

    /// Encode a seen-state map with deterministic key order for stable diffs/tests.
    ///
    /// - Parameter storage: Seen-state to encode.
    /// - Returns: Encoded JSON, or nil on an (unexpected) encoder failure.
    static func encode(_ storage: FirstRunSeenStorage) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(storage)
    }

    /// Cap the store at `maxRecords`, dropping the oldest `seenAt` entries first.
    ///
    /// - Parameter storage: Candidate seen-state before persisting.
    /// - Returns: A storage map with at most `maxRecords` entries.
    private static func bounded(_ storage: FirstRunSeenStorage) -> FirstRunSeenStorage {
        guard storage.count > maxRecords else { return storage }
        let kept = storage.sorted { $0.value.seenAt > $1.value.seenAt }.prefix(maxRecords)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }
}
