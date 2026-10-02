import Foundation

// MARK: - Model

/// One titled group of changelog bullets: a page category's notes ("Songs", "Other"), or an
/// unheaded list when none of an entry's notes has a category.
public struct ChangelogSection: Sendable, Equatable, Identifiable {
    /// Heading, e.g. "Song Details"; empty for an unheaded list.
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
    /// App version (`YYMM.DD.NN`) the notes belong to; nil for ad-hoc entries.
    public let version: String?
    /// Whether that version had reached the App Store when this build was made (the built
    /// version itself is listed unreleased).
    public let released: Bool
    /// Heading above the sections ("Version 2610.01.01"); nil for none.
    public let heading: String?
    /// Category sections in display order (`versioning.py` page order, "Other" last).
    public let sections: [ChangelogSection]
    /// Heading of the tester list ("Changes since release 2610.01.03"); nil without one.
    public let testerHeading: String?
    /// TestFlight category sections for the unreleased built version: every change since the
    /// latest release, the same list as TestFlight's "What to Test". Empty otherwise. Shown
    /// instead of `sections` to testers only.
    public let testerSections: [ChangelogSection]

    /// Create an entry.
    ///
    /// - Parameters:
    ///   - version: App version the notes belong to.
    ///   - released: Whether that version was already released at build time.
    ///   - heading: Heading above the sections.
    ///   - sections: Sections in display order.
    ///   - testerHeading: Heading of the tester list.
    ///   - testerSections: Tester-only replacement sections.
    public init(
        version: String? = nil, released: Bool = true, heading: String? = nil, sections: [ChangelogSection],
        testerHeading: String? = nil, testerSections: [ChangelogSection] = []
    ) {
        self.version = version
        self.released = released
        self.heading = heading
        self.sections = sections
        self.testerHeading = testerHeading
        self.testerSections = testerSections
    }

    /// Native Title Case heading, or nil.
    public var displayHeading: String? { heading.map(Changelog.titleCase) }
}

// MARK: - Catalog

/// The "What's New" changelog: one entry per released app version, newest first, its notes in
/// page-category sections.
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
    /// Most bullets kept in the tester list (every change since the latest release).
    static let maxTesterItems = 120
    /// Most category groups kept per list.
    static let maxGroups = 24
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
    /// (`{schema, platform, version, baseline, entries: [{version, released, items, groups?, testflight?}]}`).
    ///
    /// - Parameter data: JSON document.
    /// - Returns: One entry per version headed "Version <v>", its notes as category sections from
    ///   `groups` (`[{category, items}]`, already in page order with prefixes stripped; the apps never
    ///   re-classify), bounded in size; versions without notes are skipped. The unreleased built
    ///   version's optional `testflight.groups` becomes its `testerSections`.
    /// - Throws: `DecodingError` for malformed JSON.
    public static func decode(_ data: Data) throws -> [ChangelogEntry] {
        let document = try JSONDecoder().decode(WhatsNewDocument.self, from: data)
        return document.entries.prefix(maxEntries).compactMap { entry in
            let version = String(entry.version.prefix(32))
            let sections = categorySections(entry.groups, fallback: entry.items)
            guard !version.isEmpty, !sections.isEmpty else { return nil }
            let tester = entry.testflight.map { notes in
                categorySections(notes.groups, fallback: notes.vsRelease ?? [], limit: maxTesterItems)
            } ?? []
            return ChangelogEntry(
                version: version,
                released: entry.released ?? true,
                heading: "Version \(version)",
                sections: sections,
                testerHeading: tester.isEmpty ? nil : entry.testflight.map(testerHeading),
                testerSections: tester
            )
        }
    }

    /// Heading of the tester list, in `versioning.py testflight_notes` wording without the colon.
    ///
    /// - Parameter notes: Decoded `testflight` block.
    /// - Returns: "Changes since release <v>", or "Changes so far (no release yet)".
    static func testerHeading(_ notes: WhatsNewDocument.Tester) -> String {
        let release = notes.release.map { String($0.prefix(32)) }.flatMap { $0.isEmpty ? nil : $0 }
        return release.map { "Changes since release \($0)" } ?? "Changes so far (no release yet)"
    }

    /// Headed sections for `groups`, the way TestFlight's "What to Test" lays them out.
    ///
    /// A null category is "Other". When no group has a category the notes form one unheaded
    /// section (TestFlight shows no headings then). Older documents without `groups` show `fallback`
    /// as one unheaded section. At most `limit` bullets in total and ``maxGroups`` groups.
    ///
    /// - Parameters:
    ///   - groups: Decoded `groups`, or nil when absent.
    ///   - fallback: Flat notes for documents without `groups`.
    ///   - limit: Most bullets kept in total.
    /// - Returns: Non-empty sections in document order.
    static func categorySections(
        _ groups: [WhatsNewDocument.Group]?, fallback: [String], limit: Int = maxItems
    ) -> [ChangelogSection] {
        guard let all = groups, !all.isEmpty else {
            let items = clean(fallback, limit: limit)
            return items.isEmpty ? [] : [ChangelogSection(title: "", items: items)]
        }
        let groups = all.prefix(maxGroups)
        let headed = groups.contains { !($0.category ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        var budget = limit
        var sections: [ChangelogSection] = []
        for group in groups where budget > 0 {
            let items = clean(group.items, limit: budget)
            guard !items.isEmpty else { continue }
            budget -= items.count
            let category = String((group.category ?? "").trimmingCharacters(in: .whitespaces).prefix(32))
            let title = headed ? (category.isEmpty ? "Other" : category) : ""
            if let index = sections.firstIndex(where: { $0.title == title }) {
                sections[index] = ChangelogSection(title: title, items: sections[index].items + items)
            } else {
                sections.append(ChangelogSection(title: title, items: items))
            }
        }
        return sections
    }

    /// Trim, drop empty and bound bullet text.
    ///
    /// - Parameters:
    ///   - items: Raw bullets.
    ///   - limit: Most bullets kept.
    /// - Returns: At most `limit` non-empty bullets of at most ``maxItemLength`` characters.
    private static func clean(_ items: [String], limit: Int) -> [String] {
        Array(items
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxItemLength)) }
            .filter { !$0.isEmpty }
            .prefix(limit))
    }

    /// Wire shape of the generated document (unknown keys ignored).
    struct WhatsNewDocument: Decodable {
        struct Entry: Decodable {
            let version: String
            let released: Bool?
            let items: [String]
            let groups: [Group]?
            let testflight: Tester?
        }

        /// One `versioning.py groups_json` group: a page category (null = uncategorized) and its
        /// notes without the prefix.
        struct Group: Decodable {
            let category: String?
            let items: [String]
        }

        /// The `testflight` block: every note since the store release `release` (`vs_release`) and the
        /// same notes grouped by category (`groups`).
        struct Tester: Decodable {
            let release: String?
            let vsRelease: [String]?
            let groups: [Group]?

            enum CodingKeys: String, CodingKey {
                case release, groups
                case vsRelease = "vs_release"
            }
        }

        let entries: [Entry]
    }

    // MARK: Display

    /// Entries as natives display them: the deprecated Manual feature is never advertised, so
    /// any section titled Manual or bullet naming it is dropped, and empty sections removed.
    /// TestFlight and development installs see an entry's tester list (heading and sections) in
    /// place of its release notes.
    ///
    /// - Parameters:
    ///   - entries: Bundled entries.
    ///   - distribution: Install channel (`AppDistribution.current()`); App Store by default.
    /// - Returns: Entries safe to render natively.
    public static func displayEntries(
        _ entries: [ChangelogEntry] = entries, distribution: AppDistribution = .appStore
    ) -> [ChangelogEntry] {
        entries.compactMap { entry in
            let tester = distribution.showsTesterNotes && !entry.testerSections.isEmpty
            let source = tester ? entry.testerSections : entry.sections
            let sections = source.compactMap { section -> ChangelogSection? in
                guard !mentionsManual(section.title) else { return nil }
                let items = section.items.filter { !mentionsManual($0) }
                return items.isEmpty ? nil : ChangelogSection(title: section.title, items: items)
            }
            return sections.isEmpty
                ? nil : ChangelogEntry(version: entry.version, released: entry.released,
                                       heading: tester ? entry.testerHeading : entry.heading, sections: sections,
                                       testerHeading: entry.testerHeading, testerSections: entry.testerSections)
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
    /// - Returns: Title Case heading with minor words lower-cased after the first word; leading
    ///   punctuation is skipped ("(no" → "(No") and ignored when matching minor words ("vs.").
    public static func titleCase(_ text: String) -> String {
        text.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .enumerated()
            .map { index, word in
                let lower = String(word)
                let bare = lower.trimmingCharacters(in: .punctuationCharacters)
                if index > 0 && minorWords.contains(bare) { return lower }
                guard let first = lower.firstIndex(where: \.isLetter) else { return lower }
                return lower[..<first] + lower[first...].prefix(1).uppercased() + lower[first...].dropFirst()
            }
            .joined(separator: " ")
    }

    // MARK: Hash

    /// Content hash in the web's `calculateChangelogHash` form: a 32-bit
    /// `((h << 5) - h) + code` over the UTF-16 code units of `JSON.stringify(entries)`'s
    /// section shape, printed in base 36 with a sign. Entry headings carry the version, so
    /// a newly released version always changes it. Tester sections are not hashed.
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
    /// `title` (only when the entry has a heading) → `sections` → `title`, `items`).
    ///
    /// - Parameter entries: Entries to serialize.
    /// - Returns: Compact JSON text.
    static func canonicalJSON(_ entries: [ChangelogEntry]) -> String {
        let body = entries.map { entry in
            let sections = entry.sections.map { section in
                let items = section.items.map(jsonString).joined(separator: ",")
                return "{\"title\":\(jsonString(section.title)),\"items\":[\(items)]}"
            }
            let heading = entry.heading.map { "\"title\":\(jsonString($0))," } ?? ""
            return "{\(heading)\"sections\":[\(sections.joined(separator: ","))]}"
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
