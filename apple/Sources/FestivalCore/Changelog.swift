import Foundation

// MARK: - Model

/// One titled group of changelog bullets: a released app version and its notes.
public struct ChangelogSection: Sendable, Equatable, Identifiable {
    /// Heading, e.g. "Version 2610.01".
    public let title: String
    /// Bullet sentences, in release-note order.
    public let items: [String]

    public var id: String { title }

    /// Create a section.
    ///
    /// - Parameters:
    ///   - title: Heading.
    ///   - items: Bullet sentences.
    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }

    /// Native Title Case heading ("SONG DETAILS" → "Song Details").
    public var displayTitle: String { Changelog.titleCase(title) }
}

/// One app version's worth of changelog sections.
public struct ChangelogEntry: Sendable, Equatable {
    /// App version (`YYMM.NN`) the notes belong to; nil for ad-hoc entries.
    public let version: String?
    /// Whether that version had reached the App Store when this build was made (the built
    /// version itself is listed unreleased).
    public let released: Bool
    /// Sections in display order.
    public let sections: [ChangelogSection]

    /// Create an entry.
    ///
    /// - Parameters:
    ///   - version: App version the notes belong to.
    ///   - released: Whether that version was already released at build time.
    ///   - sections: Sections in display order.
    public init(version: String? = nil, released: Bool = true, sections: [ChangelogSection]) {
        self.version = version
        self.released = released
        self.sections = sections
    }
}

// MARK: - Catalog

/// The "What's New" changelog: one section per released app version, newest first.
///
/// Release builds generate `WhatsNew.json` (bundled from `apple/Apps/<platform>/`) with
/// `tools/release/versioning.py whats-new` from the platform's `Release-Note` commit trailers
/// and App Store Connect's released versions, so intermediate TestFlight builds fold into
/// the next released version. The checked-in file is a development placeholder. The card
/// shows whenever the content hash differs from the dismissed one (see `ChangelogSeenStore`).
public enum Changelog {
    /// Bundle resource name of the generated changelog.
    public static let resourceName = "WhatsNew"

    /// Most entries kept from the document (the generator writes at most 10).
    static let maxEntries = 20
    /// Most bullets kept per entry.
    static let maxItems = 40
    /// Longest bullet kept, in characters.
    static let maxItemLength = 600

    /// Entries bundled with the app (empty when the resource is missing or invalid).
    public static let entries: [ChangelogEntry] = load(bundle: .main)

    /// Content hash of the bundled entries; drives "show once per changelog".
    public static var currentHash: String { hash(entries) }

    /// Hash of an empty changelog; a store never shows the card for it.
    public static let emptyHash = hash([])

    /// Read `WhatsNew.json` from a bundle.
    ///
    /// - Parameter bundle: Bundle holding the resource (`.main` in the app).
    /// - Returns: Decoded entries, or an empty array when absent or invalid.
    public static func load(bundle: Bundle) -> [ChangelogEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? decode(data)) ?? []
    }

    /// Decode a `versioning.py whats-new` document
    /// (`{schema, platform, version, baseline, entries: [{version, released, items}]}`).
    ///
    /// - Parameter data: JSON document.
    /// - Returns: One entry per version with a single "Version <v>" section, bounded in size;
    ///   versions without notes are skipped.
    /// - Throws: `DecodingError` for malformed JSON.
    public static func decode(_ data: Data) throws -> [ChangelogEntry] {
        let document = try JSONDecoder().decode(WhatsNewDocument.self, from: data)
        return document.entries.prefix(maxEntries).compactMap { entry in
            let version = String(entry.version.prefix(32))
            let items = entry.items
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxItemLength)) }
                .filter { !$0.isEmpty }
                .prefix(maxItems)
            guard !version.isEmpty, !items.isEmpty else { return nil }
            return ChangelogEntry(
                version: version,
                released: entry.released ?? true,
                sections: [ChangelogSection(title: "Version \(version)", items: Array(items))]
            )
        }
    }

    /// Wire shape of the generated document (unknown keys ignored).
    private struct WhatsNewDocument: Decodable {
        struct Entry: Decodable {
            let version: String
            let released: Bool?
            let items: [String]
        }

        let entries: [Entry]
    }

    // MARK: Display

    /// Entries as natives display them: the deprecated Manual feature is never advertised, so
    /// any section titled Manual or bullet naming it is dropped, and empty sections removed.
    ///
    /// - Parameter entries: Bundled entries.
    /// - Returns: Entries safe to render natively.
    public static func displayEntries(_ entries: [ChangelogEntry] = entries) -> [ChangelogEntry] {
        entries.compactMap { entry in
            let sections = entry.sections.compactMap { section -> ChangelogSection? in
                guard !mentionsManual(section.title) else { return nil }
                let items = section.items.filter { !mentionsManual($0) }
                return items.isEmpty ? nil : ChangelogSection(title: section.title, items: items)
            }
            return sections.isEmpty
                ? nil : ChangelogEntry(version: entry.version, released: entry.released, sections: sections)
        }
    }

    /// Whether text refers to the deprecated in-app Manual.
    ///
    /// - Parameter text: Heading or bullet.
    /// - Returns: True when the word "manual" appears as a whole word, any case.
    static func mentionsManual(_ text: String) -> Bool {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .contains("manual")
    }

    /// Words kept lower case inside a Title Case heading (never the first word).
    private static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs",
    ]

    /// Convert a heading to Title Case.
    ///
    /// - Parameter text: Heading in any case.
    /// - Returns: Title Case heading with minor words lower-cased after the first word.
    public static func titleCase(_ text: String) -> String {
        text.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .enumerated()
            .map { index, word in
                let lower = String(word)
                if index > 0 && minorWords.contains(lower) { return lower }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    // MARK: Hash

    /// Content hash in the web's `calculateChangelogHash` form: a 32-bit
    /// `((h << 5) - h) + code` over the UTF-16 code units of `JSON.stringify(entries)`'s
    /// section shape, printed in base 36 with a sign. Section titles carry the version, so
    /// a newly released version always changes it.
    ///
    /// - Parameter entries: Entries to hash.
    /// - Returns: Short hash string.
    public static func hash(_ entries: [ChangelogEntry]) -> String {
        var value: Int32 = 0
        for unit in canonicalJSON(entries).utf16 {
            value = (value &<< 5) &- value &+ Int32(unit)
        }
        return String(value, radix: 36)
    }

    /// Reproduce `JSON.stringify` for the entry array (no whitespace, key order
    /// `sections` → `title`, `items`).
    ///
    /// - Parameter entries: Entries to serialize.
    /// - Returns: Compact JSON text.
    static func canonicalJSON(_ entries: [ChangelogEntry]) -> String {
        let body = entries.map { entry in
            let sections = entry.sections.map { section in
                let items = section.items.map(jsonString).joined(separator: ",")
                return "{\"title\":\(jsonString(section.title)),\"items\":[\(items)]}"
            }
            return "{\"sections\":[\(sections.joined(separator: ","))]}"
        }
        return "[\(body.joined(separator: ","))]"
    }

    /// Quote a string the way `JSON.stringify` does (escapes `"`, `\` and control characters;
    /// leaves other Unicode as-is).
    ///
    /// - Parameter text: Raw string.
    /// - Returns: Quoted JSON string literal.
    static func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - Seen state

/// What the user last dismissed, the web's `fst:changelog` `{ version, hash }` record.
public struct ChangelogSeenRecord: Codable, Sendable, Equatable {
    /// App version shown in the dismissed card's title.
    public let version: String
    /// Changelog content hash at dismissal.
    public let hash: String

    /// Create a record.
    ///
    /// - Parameters:
    ///   - version: App version at dismissal.
    ///   - hash: Changelog content hash at dismissal.
    public init(version: String, hash: String) {
        self.version = version
        self.hash = hash
    }
}

/// `UserDefaults`-backed "What's New" dismissal state, mirroring the web's
/// `localStorage['fst:changelog']` gate in `App.tsx`: the card shows when nothing valid is
/// stored or the stored hash differs from the current changelog hash.
public final class ChangelogSeenStore: @unchecked Sendable {
    /// Persisted key (JSON-encoded `ChangelogSeenRecord`).
    public static let storageKey = "fst.changelog.seen.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// Create a store.
    ///
    /// - Parameter defaults: Backing store; `.standard` in the app, a suite in tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last dismissal, or nil when absent, oversized or corrupt (the web treats a parse
    /// failure as "show again").
    ///
    /// - Returns: Validated record or nil.
    public func load() -> ChangelogSeenRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.storageKey), data.count <= 1024,
              let record = try? JSONDecoder().decode(ChangelogSeenRecord.self, from: data),
              !record.hash.isEmpty, record.hash.count <= 32, record.version.count <= 64
        else { return nil }
        return record
    }

    /// Whether the card should show for a changelog hash.
    ///
    /// - Parameter hash: Current changelog hash.
    /// - Returns: True when the changelog has content and was never dismissed or was
    ///   dismissed for different content.
    public func shouldShow(hash: String = Changelog.currentHash) -> Bool {
        hash != Changelog.emptyHash && load()?.hash != hash
    }

    /// Persist a dismissal.
    ///
    /// - Parameters:
    ///   - version: App version shown in the card.
    ///   - hash: Changelog hash that was shown.
    public func markSeen(version: String, hash: String = Changelog.currentHash) {
        let record = ChangelogSeenRecord(version: String(version.prefix(64)), hash: hash)
        guard let data = try? JSONEncoder().encode(record) else { return }
        lock.lock()
        defaults.set(data, forKey: Self.storageKey)
        lock.unlock()
    }

    /// Forget the dismissal so the card shows again on next launch.
    public func reset() {
        lock.lock()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }
}
